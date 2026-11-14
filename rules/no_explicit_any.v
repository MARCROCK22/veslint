module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/no-explicit-any` rule of typescript-eslint 8.72.2, with its
// options `fixToUnknown` and `ignoreRestArgs`, its fix and its suggestions.

const nea_messages = {
	'suggestNever':       "Use `never` instead, this is useful when instantiating generic type parameters that you don't need to know the type of."
	'suggestPropertyKey': 'Use `PropertyKey` instead, this is more explicit than `keyof any`.'
	'suggestUnknown':     'Use `unknown` instead, this will force you to explicitly, and safely assert the type is correct.'
	'unexpectedAny':      'Unexpected any. Specify a different type.'
}

struct NeaOptions {
	fix_to_unknown   bool
	ignore_rest_args bool
}

fn nea_options(options []json2.Any) !NeaOptions {
	o := option_object(no_explicit_any, options, ['fixToUnknown', 'ignoreRestArgs'])!
	return NeaOptions{
		fix_to_unknown:   o.bool_value('fixToUnknown') or { false }
		ignore_rest_args: o.bool_value('ignoreRestArgs') or { false }
	}
}

fn (mut c Checker) lint_no_explicit_any(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nea_options(c.rule_options(no_explicit_any))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .ts_any_keyword {
			continue
		}
		stats.checked++
		if o.ignore_rest_args && nea_is_descendant_of_rest_element_in_function(t, node) {
			continue
		}
		parent := t.nodes[node].parent
		is_keyof_any := t.typ(parent) == .ts_type_operator
			&& (t.string_of(parent, .operator) or { '' }) == 'keyof'
		property_key := fix_replace_range(t.nodes[parent].start, t.nodes[parent].end, 'PropertyKey')
		// createUnknownFixer: `unknown[]` for the annotation of a rest parameter.
		unknown_text := if t.typ(parent) == .ts_type_annotation
			&& nea_is_rest_element_in_function(t, t.nodes[parent].parent) {
			'unknown[]'
		} else {
			'unknown'
		}
		unknown := fix_replace_range(t.nodes[node].start, t.nodes[node].end, unknown_text)
		suggestions := if is_keyof_any {
			[Suggestion{
				message_id: 'suggestPropertyKey'
				fix:        property_key
			}]
		} else {
			[
				Suggestion{
					message_id: 'suggestUnknown'
					fix:        unknown
				},
				Suggestion{
					message_id: 'suggestNever'
					fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'never')
				},
			]
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, node)
			message_id:  'unexpectedAny'
			has_fix:     o.fix_to_unknown
			fix:         if !o.fix_to_unknown {
				Fix{}
			} else if is_keyof_any {
				property_key
			} else {
				unknown
			}
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nea_is_valid_function ports isNodeValidFunction: the functions and signatures a rest parameter
// belongs to.
fn nea_is_valid_function(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.arrow_function_expression, .function_declaration,
		.function_expression, .ts_call_signature_declaration, .ts_constructor_type,
		.ts_construct_signature_declaration, .ts_declare_function, .ts_empty_body_function_expression,
		.ts_function_type, .ts_method_signature]
}

// nea_is_rest_element_in_function ports isNodeRestElementInFunction.
fn nea_is_rest_element_in_function(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .rest_element
		&& nea_is_valid_function(t, t.nodes[node].parent)
}

// nea_is_valid_ts_type ports isNodeValidTSType: `readonly` or Array/ReadonlyArray.
fn nea_is_valid_ts_type(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.ts_type_operator {
			return (t.string_of(node, .operator) or { '' }) == 'readonly'
		}
		.ts_type_reference {
			name := t.node(node, .type_name) or { return false }
			return t.typ(name) == .identifier
				&& (t.string_of(name, .name) or { '' }) in ['Array', 'ReadonlyArray']
		}
		else {
			return false
		}
	}
}

// nea_ancestor is the ancestor `n` levels up, -1 when there is none.
fn nea_ancestor(t &estree.EsTree, node int, n int) int {
	mut current := node
	for _ in 0 .. n {
		if current < 0 {
			return -1
		}
		current = t.nodes[current].parent
	}
	return current
}

// nea_is_descendant_of_rest_element_in_function ports isNodeDescendantOfRestElementInFunction.
fn nea_is_descendant_of_rest_element_in_function(t &estree.EsTree, node int) bool {
	great_grandparent := nea_ancestor(t, node, 3)
	if great_grandparent >= 0 && nea_is_rest_element_in_function(t, great_grandparent) {
		return true
	}
	grandparent := nea_ancestor(t, node, 2)
	great_great_grandparent := nea_ancestor(t, node, 4)
	return great_great_grandparent >= 0 && nea_is_valid_ts_type(t, grandparent)
		&& nea_is_rest_element_in_function(t, great_great_grandparent)
}
