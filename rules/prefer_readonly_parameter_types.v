module rules

import json2
import time
import tsgo
import treesitter { Ident, has_child_kind, named_children, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `prefer-readonly-parameter-types` rule of typescript-eslint 8.62.0, with its
// options.

const prpt_messages = {
	'shouldBeReadonly': 'Parameter should be a read only type.'
}

// ArrowFunctionExpression, FunctionDeclaration, FunctionExpression, TSCallSignatureDeclaration,
// TSConstructSignatureDeclaration, TSDeclareFunction, TSEmptyBodyFunctionExpression,
// TSFunctionType and TSMethodSignature (not TSConstructorType).
const prpt_function_kinds = ['arrow_function', 'function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'method_definition', 'call_signature',
	'construct_signature', 'function_signature', 'method_signature', 'abstract_method_signature',
	'function_type']

struct PrptOptions {
	readonlyness               ReadonlynessOptions
	check_parameter_properties bool
	ignore_inferred_types      bool
}

fn prpt_options(options []json2.Any) !PrptOptions {
	o := option_object(prefer_readonly_parameter_types, options, ['allow', 'checkParameterProperties',
		'ignoreInferredTypes', 'treatMethodsAsReadonly'])!
	return PrptOptions{
		readonlyness:               ReadonlynessOptions{
			allow:                     o.specifiers('allow')!
			treat_methods_as_readonly: o.bool_value('treatMethodsAsReadonly')!
		}
		check_parameter_properties: o.bool_value('checkParameterProperties')!
		ignore_inferred_types:      o.bool_value('ignoreInferredTypes')!
	}
}

// PrptParameter is a parameter to check: where it is reported (the ESTree parameter, without the
// modifiers of a parameter property) and the node its type is that of (its type annotation, or
// the whole parameter when it has none or it has a default value).
struct PrptParameter {
	report    C.TSNode
	type_node C.TSNode
	is_type   bool
}

fn (mut c Checker) lint_prefer_readonly_parameter_types(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := prpt_options(c.rule_options(prefer_readonly_parameter_types))!
	mut sw := time.new_stopwatch()
	mut parameters := []PrptParameter{}
	mut spans := []Span{}
	for function in c.nodes_of_kinds(root, prpt_function_kinds, []string{}) {
		for parameter in prpt_parameters(function, options) {
			parameters << parameter
			// A parameter that is only its name has the range of that name, whose type is the
			// same.
			spans << if parameter.is_type {
				c.type_node_span(parameter.type_node)
			} else {
				node_span(parameter.type_node)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for parameter in parameters {
		t := c.node_type(parameter.type_node) or { continue }
		if !c.is_type_readonly(t, options.readonlyness, c.prpt_annotation(parameter))!
			&& !c.is_type_branded_literal_like(t)! {
			findings << Finding{
				stmt:       c.prpt_place(parameter.report)
				message_id: 'shouldBeReadonly'
			}
		}
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += parameters.len
	return findings
}

// prpt_annotation is the handle of the type annotation the type of a parameter comes from: the
// node whose type was asked, or the annotation of the parameter when the type asked is that of
// the parameter (the same type, with `undefined` if it is optional). '' without one.
fn (c &Checker) prpt_annotation(parameter PrptParameter) string {
	handle := c.node_handles[node_key(parameter.type_node)] or { return '' }
	if parameter.is_type {
		return handle
	}
	if tsgo.handle_kind(handle) != syntax_kind_parameter {
		return ''
	}
	annotation := c.ast.tree.node_child(tsgo.handle_index(handle), 'type')
	return if annotation == 0 { '' } else { c.ast.tree.node_handle(annotation) }
}

// prpt_parameters are the parameters of a function the options have the rule check.
fn prpt_parameters(function C.TSNode, options PrptOptions) []PrptParameter {
	mut out := []PrptParameter{}
	list := node_field(function, 'parameters') or {
		// The only parameter of an arrow function, without parentheses: it has no type annotation.
		parameter := node_field(function, 'parameter') or { return out }
		if !options.ignore_inferred_types {
			out << PrptParameter{
				report:    parameter
				type_node: parameter
			}
		}
		return out
	}
	for parameter in named_children(list) {
		if node_kind(parameter) !in ['required_parameter', 'optional_parameter'] {
			continue
		}
		// TSParameterProperty: a parameter with an accessibility modifier, `readonly` or `override`.
		is_property := has_child_kind(parameter, 'accessibility_modifier')
			|| has_child_kind(parameter, 'readonly') || has_child_kind(parameter, 'override_modifier')
		if is_property && !options.check_parameter_properties {
			continue
		}
		pattern := node_field(parameter, 'pattern') or { continue }
		// A parameter with a default value is an AssignmentPattern, which has no type annotation
		// of its own: its type is that of the parameter.
		mut annotation := ?C.TSNode(none)
		if _ := node_field(parameter, 'value') {
		} else if type_annotation := node_field(parameter, 'type') {
			annotation = first_named(type_annotation)
		}
		if type_node := annotation {
			out << PrptParameter{
				report:    pattern
				type_node: unwrap_type_parens(type_node)
				is_type:   true
			}
		} else if !options.ignore_inferred_types {
			out << PrptParameter{
				report:    pattern
				type_node: parameter
			}
		}
	}
	return out
}

// prpt_place is where a parameter is reported: its ESTree node, an AssignmentPattern to its
// default value, or the name or pattern with its type annotation.
fn (c &Checker) prpt_place(report C.TSNode) Ident {
	if parent := node_parent(report) {
		if node_kind(parent) in ['required_parameter', 'optional_parameter'] {
			if _ := node_field(parent, 'value') {
				return c.position_range(node_start(report), c.es_end(parent))
			}
		}
	}
	return c.es_binding_position(report)
}
