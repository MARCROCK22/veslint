module rules

import estree
import time

// Port of the `unicorn/no-useless-length-check` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const unulc_messages = {
	'non-zero': 'The non-empty check is useless as `Array#some()` returns `false` for an empty array.'
	'zero':     'The empty check is useless as `Array#every()` returns `true` for an empty array.'
}

// unulc_length_compare_zero ports isLengthCompareZero: `x.length <op> 0` in a `&&` or `||`.
fn unulc_length_compare_zero(t &estree.EsTree, node int) bool {
	right := t.node(node, .right) or { return false }
	return t.typ(node) == .binary_expression && t.typ(right) == .literal && un_raw(t, right) == '0'
		&& un_is_member(t, t.node(node, .left) or { -1 }, properties: ['length'], optional: false)
		&& un_is_logical(t, t.nodes[node].parent)
}

// unulc_flat ports flatLogicalExpression.
fn unulc_flat(t &estree.EsTree, node int, mut out []int) {
	operator := t.string_of(node, .operator) or { '' }
	for key in [estree.Key.left, .right] {
		child := t.node(node, key) or { continue }
		if t.typ(child) == .logical_expression && (t.string_of(child, .operator) or { '' }) == operator {
			unulc_flat(t, child, mut out)
		} else {
			out << child
		}
	}
}

// unulc_array_call is the method call of `some` or `every` (isMethodCall, not optional, not
// computed, an identifier property).
fn unulc_array_call(t &estree.EsTree, node int, method string) bool {
	if !un_is_method_call(t, node, optional_call: false, optional_member: false, computed: false) {
		return false
	}
	property := t.node(t.node(node, .callee) or { return false }, .property) or { return false }
	return t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == method
}

fn (mut c Checker) lint_unicorn_no_useless_length_check(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut reported := map[int]bool{}
	mut nodes := []int{}
	for logical in un_enter_order(t) {
		if !un_is_logical(t, logical) {
			continue
		}
		stats.checked++
		operator := t.string_of(logical, .operator) or { continue }
		mut conditions := []int{}
		unulc_flat(t, logical, mut conditions)
		for index, node in conditions {
			if !unulc_length_compare_zero(t, node) {
				continue
			}
			comparison := t.string_of(node, .operator) or { continue }
			zero := comparison == '==='
			non_zero := comparison in ['>', '!==']
			method := if operator == '||' && zero {
				'every'
			} else if operator == '&&' && non_zero {
				'some'
			} else {
				continue
			}
			object := t.node(t.node(node, .left) or { continue }, .object) or { continue }
			mut siblings := []int{}
			if index > 0 {
				siblings << conditions[index - 1]
			}
			if index + 1 < conditions.len {
				siblings << conditions[index + 1]
			}
			if siblings.any(unulc_array_call(t, it, method)
				&& c.un_is_same_reference(t, object, t.node(t.node(it, .callee) or { -1 }, .object) or { -1 })) {
				if node !in reported {
					reported[node] = true
					nodes << node
				}
			}
		}
	}
	for node in nodes {
		left := t.node(node, .left) or { continue }
		property := t.node(left, .property) or { continue }
		parent := t.nodes[node].parent
		parent_left := t.node(parent, .left) or { continue }
		parent_right := t.node(parent, .right) or { continue }
		left_start, left_end := c.un_parenthesized_range(t, tokens, parent_left)
		right_start, right_end := c.un_parenthesized_range(t, tokens, parent_right)
		fix := if parent_left == node {
			fix_remove_range(left_start, right_start)
		} else {
			fix_remove_range(left_end, right_end)
		}
		findings << Finding{
			stmt:       c.position_range(t.nodes[property].start, t.nodes[node].end)
			message_id: if (t.string_of(node, .operator) or { '' }) == '===' { 'zero' } else { 'non-zero' }
			has_fix:    true
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
