module rules

import json2
import time
import treesitter { Ident, has_child_kind, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-inferrable-types` rule of typescript-eslint 8.62.0, with its options
// `ignoreParameters` and `ignoreProperties`, and its fix.

const nit_messages = {
	'noInferrableType': 'Type {{type}} trivially inferred from a {{type}} literal, remove type annotation.'
}

struct NitOptions {
	ignore_parameters bool
	ignore_properties bool
}

fn nit_options(options []json2.Any) !NitOptions {
	o := option_object(no_inferrable_types, options, ['ignoreParameters', 'ignoreProperties'])!
	return NitOptions{
		ignore_parameters: o.bool_value('ignoreParameters')!
		ignore_properties: o.bool_value('ignoreProperties')!
	}
}

// The functions whose parameters the rule checks: ArrowFunctionExpression, FunctionDeclaration
// and FunctionExpression (a method's value), not a TSDeclareFunction nor a method without body.
const nit_function_kinds = ['arrow_function', 'function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'method_definition']

fn (mut c Checker) lint_no_inferrable_types(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nit_options(c.rule_options(no_inferrable_types))!
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['variable_declarator', 'public_field_definition',
		'required_parameter', 'optional_parameter'], []) {
		annotation := node_field(node, 'type') or { continue }
		init := node_field(node, 'value') or { continue }
		match node_kind(node) {
			'variable_declarator' {
				// VariableDeclarator: the annotation of its id and its init.
				checked++
				c.nit_check(c.position_range(node_start(node), c.es_end(node)), annotation, init, false, mut
					findings)!
			}
			'public_field_definition' {
				// PropertyDefinition and AccessorProperty (not the abstract ones), neither readonly
				// nor optional; the `!` of a PropertyDefinition goes with the annotation.
				if o.ignore_properties || has_child_kind(node, 'abstract')
					|| has_child_kind(node, 'readonly') || has_child_kind(node, '?') {
					continue
				}
				checked++
				definite := has_child_kind(node, '!') && !has_child_kind(node, 'accessor')
				c.nit_check(c.position_range(node_start(node), c.es_member_end(node)), annotation,
					init, definite, mut findings)!
			}
			else {
				// A parameter with a default (an AssignmentPattern, also inside a
				// TSParameterProperty); the `?` of an optional one goes with the annotation.
				if o.ignore_parameters {
					continue
				}
				list := node_parent(node) or { continue }
				function := node_parent(list) or { continue }
				if node_kind(list) != 'formal_parameters'
					|| node_kind(function) !in nit_function_kinds {
					continue
				}
				checked++
				c.nit_check(c.position_range(nit_assignment_start(node), c.es_end(node)), annotation, init, node_kind(node) == 'optional_parameter', mut
					findings)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nit_assignment_start is where the AssignmentPattern of a parameter starts: at its name (or
// pattern), after its decorators and modifiers.
fn nit_assignment_start(parameter C.TSNode) int {
	if pattern := node_field(parameter, 'pattern') {
		return node_start(pattern)
	}
	if pattern := node_field(parameter, 'name') {
		return node_start(pattern)
	}
	return node_start(parameter)
}

// nit_check ports reportInferrableType for a type annotation (the TSTypeAnnotation, from its `:`)
// and an initial value. The fix removes the annotation and, with `remove_before`, the token
// before it.
fn (mut c Checker) nit_check(at Ident, annotation C.TSNode, init_node C.TSNode, remove_before bool, mut findings []Finding) ! {
	type_node := unwrap_type_parens(first_named(annotation) or { return })
	type_name := c.nit_inferrable(type_node, unwrap_parens(init_node)) or { return }
	mut fixes := []Fix{}
	if remove_before {
		if token := c.source_tokens(annotation).before(node_start(annotation), false) {
			fixes << fix_remove_range(token.start, token.end)
		}
	}
	fixes << fix_remove(annotation)
	findings << c.with_fixes(Finding{
		stmt:       at
		message_id: 'noInferrableType'
		data:       {
			'type': type_name
		}
	}, fixes)!
}

// nit_inferrable ports isInferrable: the type the annotation names (keywordMap, or `RegExp`) if
// the value is one the rule takes as inferred.
fn (c &Checker) nit_inferrable(annotation C.TSNode, init C.TSNode) ?string {
	match c.nit_keyword(annotation) {
		'bigint' {
			// Any Literal, or a call to BigInt, also after a `-`.
			value := nit_unary_argument(init, ['-']) or { init }
			if c.nit_is_call(value, 'BigInt') || estree_type(value) == 'Literal' {
				return 'bigint'
			}
		}
		'boolean' {
			if nit_has_unary(init, ['!']) || c.nit_is_call(init, 'Boolean')
				|| node_kind(init) in ['true', 'false'] {
				return 'boolean'
			}
		}
		'number' {
			value := nit_unary_argument(init, ['+', '-']) or { init }
			if c.nit_is_identifier(value, ['Infinity', 'NaN']) || c.nit_is_call(value, 'Number')
				|| c.nit_is_number(value) {
				return 'number'
			}
		}
		'null' {
			if node_kind(init) == 'null' {
				return 'null'
			}
		}
		'string' {
			if c.nit_is_call(init, 'String') || node_kind(init) in ['string', 'template_string'] {
				return 'string'
			}
		}
		'symbol' {
			if c.nit_is_call(init, 'Symbol') {
				return 'symbol'
			}
		}
		'undefined' {
			if nit_has_unary(init, ['void']) || c.nit_is_identifier(init, ['undefined']) {
				return 'undefined'
			}
		}
		else {}
	}
	// A TSTypeReference whose name is the identifier RegExp: a regular expression literal, or a
	// call or a `new` of RegExp.
	name := if node_kind(annotation) == 'generic_type' {
		node_field(annotation, 'name') or { return none }
	} else {
		annotation
	}
	if node_kind(name) != 'type_identifier' || c.identifier_name(name) != 'RegExp' {
		return none
	}
	if node_kind(init) == 'regex' || c.nit_is_call(init, 'RegExp') {
		return 'RegExp'
	}
	if node_kind(init) == 'new_expression' {
		callee := unwrap_parens(node_field(init, 'constructor') or { return none })
		if node_kind(callee) == 'identifier' && c.identifier_name(callee) == 'RegExp' {
			return 'RegExp'
		}
	}
	return none
}

// nit_keyword is the keyword type an annotation is (TSBigIntKeyword, TSNullKeyword…), or ''.
// tree-sitter has no `bigint` keyword: TypeScript reads a type name `bigint` as one.
fn (c &Checker) nit_keyword(annotation C.TSNode) string {
	match node_kind(annotation) {
		'predefined_type' {
			return c.text(annotation)
		}
		'type_identifier' {
			if c.text(annotation) == 'bigint' {
				return 'bigint'
			}
		}
		'literal_type' {
			keyword := first_named(annotation) or { return '' }
			if node_kind(keyword) in ['null', 'undefined'] {
				return node_kind(keyword)
			}
		}
		else {}
	}
	return ''
}

// nit_unary_argument is the argument of a UnaryExpression with one of these operators
// (hasUnaryPrefix), without parentheses.
fn nit_unary_argument(init C.TSNode, operators []string) ?C.TSNode {
	if node_kind(init) != 'unary_expression' || operator_of(init) !in operators {
		return none
	}
	return unwrap_parens(node_field(init, 'argument')?)
}

// nit_has_unary ports hasUnaryPrefix: a UnaryExpression with one of these operators.
fn nit_has_unary(init C.TSNode, operators []string) bool {
	return node_kind(init) == 'unary_expression' && operator_of(init) in operators
}

// nit_is_call ports isFunctionCall: a CallExpression (in an optional chain or not) whose callee
// is the identifier `name`.
fn (c &Checker) nit_is_call(init C.TSNode, name string) bool {
	if node_kind(init) != 'call_expression' || precedence_is_import_call(init) {
		return false
	}
	call_arguments(init) or { return false }
	callee := unwrap_parens(node_field(init, 'function') or { return false })
	return node_kind(callee) == 'identifier' && c.identifier_name(callee) == name
}

// nit_is_identifier ports isIdentifier: an Identifier with one of the names.
fn (c &Checker) nit_is_identifier(init C.TSNode, names []string) bool {
	return node_kind(init) in ['identifier', 'undefined'] && c.identifier_name(init) in names
}

// nit_is_number: a Literal whose value is a number (not a BigInt).
fn (c &Checker) nit_is_number(init C.TSNode) bool {
	return node_kind(init) == 'number' && !c.text(init).ends_with('n')
}
