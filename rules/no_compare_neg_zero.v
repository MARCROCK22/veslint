module rules

import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `no-compare-neg-zero` rule of ESLint 10.15.0, with its suggestions (it has no
// options).

const ncnz_messages = {
	'unexpected':         "Do not use the '{{operator}}' operator to compare against -0."
	'suggestRemoveMinus': "Replace '-0' with '0' (keeps the current comparison behavior)."
	'suggestObjectIs':    "Replace with 'Object.is()' (changes the comparison to distinguish -0 from +0)."
	'suggestNotObjectIs': "Replace with '!Object.is()' (changes the comparison to distinguish -0 from +0)."
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
		left := unwrap_parens(node_field(node, 'left') or { continue })
		right := unwrap_parens(node_field(node, 'right') or { continue })
		left_neg_zero := c.ncnz_is_neg_zero(left)
		right_neg_zero := c.ncnz_is_neg_zero(right)
		if !left_neg_zero && !right_neg_zero {
			continue
		}
		mut suggestions := []Suggestion{}
		mut minus_fixes := []Fix{}
		if left_neg_zero {
			minus_fixes << fix_replace(left, '0')
		}
		if right_neg_zero {
			minus_fixes << fix_replace(right, '0')
		}
		_, remove_minus := c.suggestion('suggestRemoveMinus', map[string]string{}, minus_fixes)!
		suggestions << remove_minus
		// Object.is: only for `===` and `!==`, without comments inside, with the builtin Object.
		if operator in ['===', '!=='] {
			tokens := c.source_tokens(root)
			if tokens.comments_inside(node_start(node), c.es_end(node)).len == 0 {
				tree := c.scope_tree(root)
				v := tree.find_variable(tree.get_scope(node), 'Object', -1)
				if v >= 0 && tree.variables[v].identifiers.len == 0 {
					negation := if operator == '===' { '' } else { '!' }
					_, object_is := c.suggestion(if operator == '===' {
						'suggestObjectIs'
					} else {
						'suggestNotObjectIs'
					}, map[string]string{}, [
						fix_replace(node, '${negation}Object.is(${c.ncnz_operand_text(left)}, ${c.ncnz_operand_text(right)})'),
					])!
					suggestions << object_is
				}
			}
		}
		findings << Finding{
			stmt:        position_of(node)
			message_id:  'unexpected'
			data:        {
				'operator': operator
			}
			suggestions: suggestions
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

// ncnz_operand_text ports getOperandText: the text of the operand, in parentheses for a
// SequenceExpression.
fn (c &Checker) ncnz_operand_text(operand C.TSNode) string {
	text := c.es_text(operand)
	return if node_kind(operand) == 'sequence_expression' { '(${text})' } else { text }
}
