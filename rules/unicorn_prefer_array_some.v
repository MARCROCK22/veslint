module rules

import estree
import time

// Port of the `unicorn/prefer-array-some` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fixes and suggestion.

const upas_messages = {
	'some':            'Prefer `.some(…)` over `.{{method}}(…)`.'
	'some-suggestion': 'Replace `.{{method}}(…)` with `.some(…)`.'
	'filter':          'Prefer `.some(…)` over non-zero length check from `.filter(…)`.'
}

fn upas_is_checking_undefined(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .binary_expression || t.node(parent, .left) or { -1 } != node {
		return false
	}
	operator := t.string_of(parent, .operator) or { '' }
	right := t.node(parent, .right) or { return false }
	return (operator in ['!=', '==', '===', '!=='] && un_is_undefined(t, right))
		|| (operator in ['!=', '=='] && t.typ(right) == .literal && un_raw(t, right) == 'null')
}

fn upas_is_negative_one(t &estree.EsTree, node int) bool {
	if t.typ(node) != .unary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return false
	}
	argument := t.node(node, .argument) or { return false }
	value := t.get(argument, .value)
	return t.typ(argument) == .literal && value is f64 && value == 1
}

fn upas_is_literal_zero(t &estree.EsTree, node int) bool {
	value := t.get(node, .value)
	return t.typ(node) == .literal && value is f64 && value == 0
}

fn (mut c Checker) lint_unicorn_prefer_array_some(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ == .call_expression {
			stats.checked++
			// `.find(…)`, `.findLast(…)`
			if !un_is_method_call(t, node,
				methods:           ['find', 'findLast']
				minimum_arguments: 1
				maximum_arguments: 2
				optional_call:     false
				optional_member:   false
			) {
				continue
			}
			is_compare := upas_is_checking_undefined(t, node)
			if !is_compare && !(un_is_boolean_expression(t, node) || un_is_control_flow_test(t, node)) {
				continue
			}
			method := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
			name := t.string_of(method, .name) or { continue }
			mut fixes := [fix_replace_range(t.nodes[method].start, t.nodes[method].end, 'some')]
			if is_compare {
				parent := t.nodes[node].parent
				start, end := c.un_parenthesized_range(t, tokens, node)
				fixes << fix_remove_range(end, t.nodes[parent].end)
				if (t.string_of(parent, .operator) or { '' }) !in ['!=', '!=='] {
					fixes << fix_insert_at(start, '!')
				}
			}
			_, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:        c.es_tree_position(t, method)
				message_id:  'some'
				data:        {
					'method': name
				}
				suggestions: [
					Suggestion{
						message_id: 'some-suggestion'
						data:       {
							'method': name
						}
						fix:        fix
					},
				]
			}
			continue
		}
		if typ != .binary_expression {
			continue
		}
		stats.checked++
		left := t.node(node, .left) or { continue }
		right := t.node(node, .right) or { continue }
		operator := t.string_of(node, .operator) or { continue }
		// `.{findIndex,findLastIndex}(…) !== -1` and the like
		if un_is_method_call(t, left,
			methods:          ['findIndex', 'findLastIndex']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) && ((operator in ['!==', '!=', '>', '===', '=='] && upas_is_negative_one(t, right))
			|| (operator in ['>=', '<'] && upas_is_literal_zero(t, right))) {
			method := t.node(t.node(left, .callee) or { continue }, .property) or { continue }
			mut fixes := []Fix{}
			if operator in ['===', '==', '<'] {
				fixes << fix_insert_at(t.nodes[node].start, '!')
			}
			fixes << fix_replace_range(t.nodes[method].start, t.nodes[method].end, 'some')
			operator_token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or {
				continue
			}
			fixes << fix_remove_range(operator_token.start, t.nodes[node].end)
			has_fix, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:       c.es_tree_position(t, method)
				message_id: 'some'
				data:       {
					'method': t.string_of(method, .name) or { '' }
				}
				has_fix:    has_fix
				fix:        fix
			}
		}
		// `.filter(…).length > 0`, `.filter(…).length !== 0`
		if operator in ['>', '!=='] && t.typ(right) == .literal && un_raw(t, right) == '0'
			&& un_is_member(t, left, properties: ['length'], optional: false) {
			filter_call := t.node(left, .object) or { continue }
			if !un_is_method_call(t, filter_call,
				methods:         ['filter']
				optional_call:   false
				optional_member: false
			) {
				continue
			}
			arguments := t.list(filter_call, .arguments) or { []int{} }
			if arguments.len == 0 || un_is_node_value_not_function(t, arguments[0]) {
				continue
			}
			property := t.node(t.node(filter_call, .callee) or { continue }, .property) or { continue }
			_, length_end := c.un_parenthesized_range(t, tokens, left)
			has_fix, fix := c.merge_fixes([
				fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'some'),
				c.un_replace_member_property(t, tokens, left, ''),
				fix_remove_range(length_end, t.nodes[node].end),
			])!
			findings << Finding{
				stmt:       c.es_tree_position(t, property)
				message_id: 'filter'
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
