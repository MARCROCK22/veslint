module rules

import estree
import json2
import math
import time

// Port of the `unicorn/explicit-length-check` rule of eslint-plugin-unicorn 64.0.0, with its option,
// fix and suggestion.

const uelc_messages = {
	'non-zero':   'Use `.{{property}} {{code}}` when checking {{property}} is not zero.'
	'zero':       'Use `.{{property}} {{code}}` when checking {{property}} is zero.'
	'suggestion': 'Replace `.{{property}}` with `.{{property}} {{code}}`.'
}

fn uelc_options(options []json2.Any) !string {
	o := option_object(unicorn_explicit_length_check, options, ['non-zero'])!
	style := o.string_value('non-zero', ['greater-than', 'not-equal'])!
	return if style == '' { 'greater-than' } else { style }
}

fn uelc_compare(t &estree.EsTree, node int, operator string, value f64, right bool) bool {
	return node >= 0 && t.typ(node) == .binary_expression
		&& (t.string_of(node, .operator) or { '' }) == operator
		&& un_is_numeric_literal_of(t, t.node(node, if right { estree.Key.right } else { .left }) or {
		-1
	}, value)
}

// uelc_length_check ports getLengthCheckNode: the comparison of the length with 0 or 1 around it,
// and whether it checks for zero.
fn uelc_length_check(t &estree.EsTree, length int) ?(int, bool) {
	node := t.nodes[length].parent
	if uelc_compare(t, node, '===', 0, true) || uelc_compare(t, node, '==', 0, true)
		|| uelc_compare(t, node, '<', 1, true) || uelc_compare(t, node, '===', 0, false)
		|| uelc_compare(t, node, '==', 0, false) || uelc_compare(t, node, '>', 1, false) {
		return node, true
	}
	if uelc_compare(t, node, '!==', 0, true) || uelc_compare(t, node, '!=', 0, true)
		|| uelc_compare(t, node, '>', 0, true) || uelc_compare(t, node, '>=', 1, true)
		|| uelc_compare(t, node, '!==', 0, false) || uelc_compare(t, node, '!=', 0, false)
		|| uelc_compare(t, node, '<', 0, false) || uelc_compare(t, node, '<=', 1, false) {
		return node, false
	}
	return none
}

// un_boolean_ancestor ports getBooleanAncestor: through `!` and `Boolean()`, and whether the
// count of `!` is odd.
fn un_boolean_ancestor(t &estree.EsTree, start int) (int, bool) {
	mut node := start
	mut negative := false
	for {
		parent := t.nodes[node].parent
		if un_is_logic_not(t, parent) && t.node(parent, .argument) or { -1 } == node {
			negative = !negative
			node = parent
		} else if un_is_boolean_call(t, parent)
			&& (t.list(parent, .arguments) or { []int{} })[0] == node {
			node = parent
		} else {
			break
		}
	}
	return node, negative
}

fn (mut c Checker) lint_unicorn_explicit_length_check(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	non_zero_style := uelc_options(c.rule_options(unicorn_explicit_length_check))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for length in 0 .. t.nodes.len {
		if t.typ(length) != .member_expression {
			continue
		}
		stats.checked++
		if !un_is_member(t, length, properties: ['length', 'size'], optional: false)
			|| t.typ(t.node(length, .object) or { continue }) == .this_expression {
			continue
		}
		value := c.un_static_value(t, length)
		if value.found {
			number := value.value.number
			if value.value.kind != .number_ || math.trunc(number) != number || math.is_inf(number, 0)
				|| number < 0 {
				// Ignore known, non-positive-integer length properties.
				continue
			}
		}
		mut node := -1
		mut auto_fix := true
		mut is_zero := false
		if check, zero := uelc_length_check(t, length) {
			ancestor, negative := un_boolean_ancestor(t, check)
			node = ancestor
			is_zero = if negative { !zero } else { zero }
		} else {
			ancestor, negative := un_boolean_ancestor(t, length)
			parent := t.nodes[length].parent
			if un_is_boolean_expression(t, ancestor) || un_is_control_flow_test(t, ancestor) {
				is_zero = negative
				node = ancestor
			} else if un_is_logical(t, parent) && (t.string_of(parent, .operator) or { '' }) == '&&' {
				is_zero = negative
				node = length
				auto_fix = false
			}
		}
		if node < 0 {
			continue
		}
		parent := t.nodes[node].parent
		unsafe_negation := un_is_logic_not(t, node) && parent >= 0
			&& t.typ(parent) == .binary_expression && t.node(parent, .left) or { -1 } == node
		// getProblem
		code := if is_zero {
			'=== 0'
		} else if non_zero_style == 'not-equal' {
			'!== 0'
		} else {
			'> 0'
		}
		if (is_zero && uelc_compare(t, node, '===', 0, true)) || (!is_zero && non_zero_style == 'greater-than'
			&& uelc_compare(t, node, '>', 0, true)) || (!is_zero && non_zero_style == 'not-equal'
			&& uelc_compare(t, node, '!==', 0, true)) {
			continue
		}
		mut fixed := '${c.un_text(t, length)} ${code}'
		if !c.un_is_parenthesized(t, tokens, node) && t.typ(node) == .unary_expression
			&& t.typ(parent) in [.unary_expression, .await_expression] {
			fixed = '(${fixed})'
		}
		mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)]
		fixes << c.un_fix_space_around_keyword(t, tokens, node)
		_, fix := c.merge_fixes(fixes)!
		property := t.string_of(t.node(length, .property) or { continue }, .name) or { continue }
		data := {
			'code':     code
			'property': property
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: if is_zero { 'zero' } else { 'non-zero' }
			data:       data
		}
		if auto_fix && !unsafe_negation {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		} else if !unsafe_negation {
			finding = Finding{
				...finding
				suggestions: [Suggestion{
					message_id: 'suggestion'
					data:       data
					fix:        fix
				}]
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
