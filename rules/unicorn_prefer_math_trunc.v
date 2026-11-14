module rules

import estree
import time

// Port of the `unicorn/prefer-math-trunc` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fixes and suggestion.

const upmt_messages = {
	'error-bitwise':      'Use `Math.trunc` instead of `{{operator}} {{value}}`.'
	'error-bitwise-not':  'Use `Math.trunc` instead of `~~`.'
	'suggestion-bitwise': 'Replace `{{operator}} {{value}}` with `Math.trunc`.'
}

fn upmt_is_bitwise_not(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .unary_expression
		&& (t.string_of(node, .operator) or { '' }) == '~'
}

// upmt_call is mathTruncFunctionCall.
fn (c &Checker) upmt_call(t &estree.EsTree, node int) string {
	text := c.un_text(t, node)
	return 'Math.trunc(${if t.typ(node) == .sequence_expression { '(${text})' } else { text }})'
}

fn (mut c Checker) lint_unicorn_prefer_math_trunc(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ in [.binary_expression, .assignment_expression] {
			stats.checked++
			operator := t.string_of(node, .operator) or { continue }
			left := t.node(node, .left) or { continue }
			right := t.node(node, .right) or { continue }
			assignment := typ == .assignment_expression
			bare := if assignment { operator[..operator.len - 1] } else { operator }
			value := t.get(right, .value)
			if t.typ(right) != .literal || !(value is f64 && value == 0) || bare !in ['|', '>>', '<<', '^'] {
				continue
			}
			mut finding := Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error-bitwise'
				data:       {
					'operator': operator
					'value':    un_raw(t, right)
				}
			}
			if !assignment || !un_has_side_effect(t, left) {
				fixed := c.upmt_call(t, left)
				mut fixes := []Fix{}
				if assignment {
					operator_token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or {
						continue
					}
					fixes << fix_replace_range(operator_token.start, operator_token.end, '=')
					fixes << fix_replace_range(t.nodes[right].start, t.nodes[right].end, fixed)
				} else {
					fixes << c.un_fix_space_around_keyword(t, tokens, node)
					fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)
				}
				has_fix, fix := c.merge_fixes(fixes)!
				if operator == '|' {
					finding = Finding{
						...finding
						suggestions: [
							Suggestion{
								message_id: 'suggestion-bitwise'
								data:       finding.data
								fix:        fix
							},
						]
					}
				} else {
					finding = Finding{
						...finding
						has_fix: has_fix
						fix:     fix
					}
				}
			}
			findings << finding
			continue
		}
		if typ == .unary_expression {
			stats.checked++
			argument := t.node(node, .argument) or { continue }
			if !upmt_is_bitwise_not(t, node) || !upmt_is_bitwise_not(t, argument)
				|| upmt_is_bitwise_not(t, t.node(argument, .argument) or { -1 }) {
				continue
			}
			inner := t.node(argument, .argument) or { continue }
			mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, c.upmt_call(t,
				inner))]
			fixes << c.un_fix_space_around_keyword(t, tokens, node)
			has_fix, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error-bitwise-not'
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
