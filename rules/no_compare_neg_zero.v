module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-compare-neg-zero` rule of ESLint 10.6.0 (it has no options).

const ncnz_messages = {
	'unexpected': "Do not use the '{{operator}}' operator to compare against -0."
}

const ncnz_operators = ['>', '>=', '<', '<=', '==', '===', '!=', '!==']

fn (mut c Checker) lint_no_compare_neg_zero(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		operator := c.text(node_field(node, 'operator') or { continue })
		if operator !in ncnz_operators {
			continue
		}
		stats.checked++
		left := node_field(node, 'left') or { continue }
		right := node_field(node, 'right') or { continue }
		if c.ncnz_is_neg_zero(left) || c.ncnz_is_neg_zero(right) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
				data:       {
					'operator': operator
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ncnz_is_neg_zero ports isNegZero: a UnaryExpression `-` whose argument is the number literal 0
// (parentheses are not ESTree nodes; `-0n` is a BigInt, whose value is not 0).
fn (c &Checker) ncnz_is_neg_zero(n C.TSNode) bool {
	unary := unwrap_parens(n)
	if node_kind(unary) != 'unary_expression'
		|| c.text(node_field(unary, 'operator') or { return false }) != '-' {
		return false
	}
	argument := unwrap_parens(node_field(unary, 'argument') or { return false })
	return node_kind(argument) == 'number'
		&& (number_literal_value(c.text(argument)) or { return false }) == 0
}
