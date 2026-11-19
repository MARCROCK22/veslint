module rules

import estree
import json2
import time
import treesitter { node_end, node_kind, node_parent, node_start }

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
	// A TSAnyKeyword is the text `any`: without it a TypeScript file needs no ESTree for this rule
	// (built on first use). The code of a .vue or .svelte file has more than its text.
	if !c.is_vue() && !c.is_svelte() && !c.svelte_module.on && !c.src.contains('any') {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	// Most TypeScript files need no ESTree either: see nea_plain_anys.
	if !c.is_vue() && !c.is_svelte() && !c.svelte_module.on {
		if anys := nea_plain_anys(root, &c.node_index, o.ignore_rest_args) {
			for any in anys {
				stats.checked++
				start, end := node_start(any.node), node_end(any.node)
				unknown := fix_replace_range(start, end, if any.rest_type {
					'unknown[]'
				} else {
					'unknown'
				})
				findings << Finding{
					stmt:        c.position_range(start, end)
					message_id:  'unexpectedAny'
					has_fix:     o.fix_to_unknown
					fix:         if o.fix_to_unknown { unknown } else { Fix{} }
					suggestions: [
						Suggestion{
							message_id: 'suggestUnknown'
							fix:        unknown
						},
						Suggestion{
							message_id: 'suggestNever'
							fix:        fix_replace_range(start, end, 'never')
						},
					]
				}
			}
			stats.eval_ms += ms(sw.elapsed())
			return findings
		}
	}
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

// NeaAny is a TSAnyKeyword the rule reports with the `unknown` and `never` suggestions: `rest_type`
// when it is the type of a rest parameter (`...a: any`), whose fix is `unknown[]`.
struct NeaAny {
	node      C.TSNode
	rest_type bool
}

// nea_plain_anys gives the TSAnyKeyword nodes of a TypeScript file's tree (the root of its tree)
// from tree-sitter's: the `any` predefined types, which are the nodes typescript-estree makes
// TSAnyKeyword; or none, and the rule reads the ESTree, when one of them is under `keyof` (the
// PropertyKey suggestion) or, with ignoreRestArgs, in the type of a rest parameter. A tree with
// syntax errors has no ESTree, so no TSAnyKeyword.
fn nea_plain_anys(root C.TSNode, index &treesitter.NodeIndex, ignore_rest_args bool) ?[]NeaAny {
	if C.ts_node_has_error(root) {
		return []NeaAny{}
	}
	mut anys := []NeaAny{}
	for node in index.of_kind(root, 'predefined_type') {
		if node_end(node) - node_start(node) != 3 || node_kind(C.ts_node_child(node, 0)) != 'any' {
			continue
		}
		// The ESTree parent, without the parentheses.
		mut parent := node_parent(node) or { return none }
		for node_kind(parent) == 'parenthesized_type' {
			parent = node_parent(parent) or { return none }
		}
		if node_kind(parent) == 'index_type_query' {
			return none
		}
		if ignore_rest_args {
			mut ancestor := parent
			for {
				if nea_is_rest_parameter(ancestor) {
					return none
				}
				ancestor = node_parent(ancestor) or { break }
			}
		}
		// The TSTypeAnnotation of a RestElement in a function (isNodeRestElementInFunction).
		rest_type := node_kind(parent) == 'type_annotation'
			&& nea_is_rest_parameter(node_parent(parent) or { parent })
		anys << NeaAny{node, rest_type}
	}
	return anys
}

// nea_is_rest_parameter: `n` is a rest parameter of a function or a signature (a RestElement in
// one of them for typescript-estree), not of a named tuple member.
fn nea_is_rest_parameter(n C.TSNode) bool {
	if node_kind(n) !in ['required_parameter', 'optional_parameter']
		|| !treesitter.has_child_kind(n, 'rest_pattern') {
		return false
	}
	parent := node_parent(n) or { return false }
	return node_kind(parent) == 'formal_parameters'
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
