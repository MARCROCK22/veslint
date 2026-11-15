module rules

import estree
import time
import x.json2

// Port of the `@stylistic/type-annotation-spacing` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`before` and `after`, and their `overrides` for `colon`, `arrow` (or `"ignore"`),
// `variable`, `parameter`, `property` and `returnType`) and its fixes.

const stas_messages = {
	'expectedSpaceAfter':     "Expected a space after the '{{type}}'."
	'expectedSpaceBefore':    "Expected a space before the '{{type}}'."
	'unexpectedSpaceAfter':   "Unexpected space after the '{{type}}'."
	'unexpectedSpaceBefore':  "Unexpected space before the '{{type}}'."
	'unexpectedSpaceBetween': "Unexpected space between the '{{previousToken}}' and the '{{type}}'."
}

// StasSpacing is a spacing config of createRules; `ignore` is the `"ignore"` of `arrow`.
struct StasSpacing {
	ignore bool
	before bool
	after  bool
}

struct StasOptions {
	colon       StasSpacing
	arrow       StasSpacing
	variable    StasSpacing
	property    StasSpacing
	parameter   StasSpacing
	return_type StasSpacing
}

// stas_merge is `{ ...base, ...object }` for the keys `before` and `after`.
fn stas_merge(base StasSpacing, object map[string]json2.Any) StasSpacing {
	return StasSpacing{
		before: sty_option_bool(object, 'before') or { base.before }
		after:  sty_option_bool(object, 'after') or { base.after }
	}
}

// stas_override is `override[key]` when it is an object, else an empty one.
fn stas_override(override map[string]json2.Any, key string) map[string]json2.Any {
	value := override[key] or { return map[string]json2.Any{} }
	if value is map[string]json2.Any {
		return value
	}
	return map[string]json2.Any{}
}

// stas_options ports createRules.
fn stas_options(given []json2.Any) !StasOptions {
	options := sty_options(given, [json2.Any(map[string]json2.Any{})])
	config := sty_option_object(options, 0)
	override := stas_override(config, 'overrides')
	colon := stas_merge(stas_merge(StasSpacing{
		before: false
		after:  true
	}, config), stas_override(override, 'colon'))
	arrow_value := override['arrow'] or { json2.Any(json2.Null{}) }
	arrow := if arrow_value is string {
		StasSpacing{
			ignore: true
		}
	} else {
		stas_merge(stas_merge(StasSpacing{
			before: true
			after:  true
		}, config), stas_override(override, 'arrow'))
	}
	return StasOptions{
		colon:       colon
		arrow:       arrow
		variable:    stas_merge(colon, stas_override(override, 'variable'))
		property:    stas_merge(colon, stas_override(override, 'property'))
		parameter:   stas_merge(colon, stas_override(override, 'parameter'))
		return_type: stas_merge(colon, stas_override(override, 'returnType'))
	}
}

fn (mut c Checker) lint_stylistic_type_annotation_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := stas_options(c.rule_options(stylistic_type_annotation_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if t.typ(node) !in [.ts_mapped_type, .ts_type_annotation] {
			continue
		}
		type_annotation := t.node(node, .type_annotation) or { continue }
		stats.checked++
		c.stas_check(t, tokens, type_annotation, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

const stas_function_types = [estree.NodeType.arrow_function_expression, .function_declaration,
	.function_expression]

const stas_function_or_function_types = [estree.NodeType.arrow_function_expression,
	.function_declaration, .function_expression, .ts_call_signature_declaration,
	.ts_constructor_type, .ts_construct_signature_declaration, .ts_declare_function,
	.ts_empty_body_function_expression, .ts_function_type, .ts_method_signature]

// isClassOrTypeElement of @typescript-eslint/utils.
const stas_class_or_type_elements = [estree.NodeType.property_definition, .function_expression,
	.method_definition, .ts_abstract_property_definition, .ts_abstract_method_definition,
	.ts_empty_body_function_expression, .ts_index_signature, .ts_call_signature_declaration,
	.ts_construct_signature_declaration, .ts_method_signature, .ts_property_signature]

// stas_rules ports getRules (and getIdentifierRules) for the type node `node`.
fn stas_rules(t &estree.EsTree, options StasOptions, node int) StasSpacing {
	parent := t.nodes[node].parent
	scope := if parent >= 0 { t.nodes[parent].parent } else { -1 }
	if scope < 0 {
		return options.colon
	}
	typ := t.typ(scope)
	if typ in [.ts_function_type, .ts_constructor_type] {
		return options.arrow
	}
	if typ == .identifier {
		identifier_parent := t.nodes[scope].parent
		if identifier_parent >= 0 {
			if t.typ(identifier_parent) == .variable_declarator {
				return options.variable
			}
			if t.typ(identifier_parent) in stas_function_or_function_types {
				return options.parameter
			}
		}
		return options.colon
	}
	if typ in stas_class_or_type_elements {
		return options.property
	}
	if typ in stas_function_types {
		return options.return_type
	}
	return options.colon
}

// stas_check ports checkTypeAnnotationSpacing.
fn (c &Checker) stas_check(t &estree.EsTree, tokens &SourceTokens, type_annotation int, options StasOptions, mut findings []Finding) {
	annotation_start := t.nodes[type_annotation].start
	// getTokenBefore(typeAnnotation, isNotOpeningParenToken)
	mut punctuator_end := tokens.before(annotation_start, false) or { return }
	for c.token_is(punctuator_end, '(') {
		punctuator_end = tokens.before(punctuator_end.start, false) or { return }
	}
	mut punctuator_start := punctuator_end
	mut previous := tokens.before(punctuator_end.start, false) or { return }
	mut typ := c.token_text(punctuator_end)
	if typ !in [':', '=>'] {
		return
	}
	config := stas_rules(t, options, type_annotation)
	if config.ignore {
		return
	}
	if typ == ':' && c.token_text(previous) == '?' {
		// space between ? and :
		if tokens.is_space_between(previous.end, punctuator_start.start) {
			findings << c.stas_report(punctuator_start, 'unexpectedSpaceBetween', {
				'type':          typ
				'previousToken': c.token_text(previous)
			}, fix_remove_range(previous.end, punctuator_start.start))
		}
		// shift the start to the ?
		typ = '?:'
		punctuator_start = previous
		previous = tokens.before(previous.start, false) or { return }
		// handle the +/- modifiers for optional modification operators
		previous_text := c.token_text(previous)
		if previous_text in ['+', '-'] {
			typ = '${previous_text}?:'
			punctuator_start = previous
			previous = tokens.before(previous.start, false) or { return }
		}
	}
	has_next_space := tokens.is_space_between(punctuator_end.end, annotation_start)
	if config.after && !has_next_space {
		findings << c.stas_report(punctuator_end, 'expectedSpaceAfter', {
			'type': typ
		}, fix_replace_range(punctuator_end.end, punctuator_end.end, ' '))
	} else if !config.after && has_next_space {
		findings << c.stas_report(punctuator_end, 'unexpectedSpaceAfter', {
			'type': typ
		}, fix_remove_range(punctuator_end.end, annotation_start))
	}
	has_previous_space := tokens.is_space_between(previous.end, punctuator_start.start)
	if config.before && !has_previous_space {
		findings << c.stas_report(punctuator_start, 'expectedSpaceBefore', {
			'type': typ
		}, fix_replace_range(previous.end, previous.end, ' '))
	} else if !config.before && has_previous_space {
		findings << c.stas_report(punctuator_start, 'unexpectedSpaceBefore', {
			'type': typ
		}, fix_remove_range(previous.end, punctuator_start.start))
	}
}

fn (c &Checker) stas_report(token SourceToken, message_id string, data map[string]string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(token.start, token.end)
		message_id: message_id
		data:       data
		has_fix:    true
		fix:        fix
	}
}
