module rules

import time
import treesitter { node_end, node_field, node_kind, node_start, position_of }

// Port of the `no-confusing-non-null-assertion` rule of typescript-eslint 8.62.0 (it has no
// options), with its suggestions.

const ncnna_messages = {
	'confusingAssign':    'Confusing combination of non-null assertion and assignment like `a! = b`, which looks very similar to `a != b`.'
	'confusingEqual':     'Confusing combination of non-null assertion and equality test like `a! == b`, which looks very similar to `a !== b`.'
	'confusingOperator':  'Confusing combination of non-null assertion and `{{operator}}` operator like `a! {{operator}} b`, which might be misinterpreted as `!(a {{operator}} b)`.'
	'notNeedInAssign':    'Remove unnecessary non-null assertion (!) in assignment left-hand side.'
	'notNeedInEqualTest': 'Remove unnecessary non-null assertion (!) in equality test.'
	'notNeedInOperator':  'Remove possibly unnecessary non-null assertion (!) in the left operand of the `{{operator}}` operator.'
	'wrapUpLeft':         'Wrap the left-hand side in parentheses to avoid confusion with "{{operator}}" operator.'
}

fn (mut c Checker) lint_no_confusing_non_null_assertion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// BinaryExpression and AssignmentExpression with `=`, `==`, `===`, `in` or `instanceof`.
	for node in c.nodes_of_kinds(root, ['binary_expression', 'assignment_expression'], []) {
		operator := if node_kind(node) == 'assignment_expression' {
			'='
		} else {
			operator_of(node)
		}
		if operator !in ['=', '==', '===', 'in', 'instanceof'] {
			continue
		}
		left_field := node_field(node, 'left') or { continue }
		left := es_child(left_field)
		checked++
		// The last token of the left side is a `!` (also in `1 + two! === 3`), and the token after
		// the left side is not a `)`.
		last := c.last_token(left.node) or { continue }
		if !c.token_is(last, '!') {
			continue
		}
		if after := c.source_tokens(left.node).after(node_end(left.node), false) {
			if c.token_text(after) == ')' {
				continue
			}
		}
		message_id := match operator {
			'=' { 'confusingAssign' }
			'==', '===' { 'confusingEqual' }
			else { 'confusingOperator' }
		}
		data := if message_id == 'confusingOperator' {
			{
				'operator': operator
			}
		} else {
			map[string]string{}
		}
		remove_bang := fix_remove_range(last.start, last.end)
		wrap := [fix_insert_at(node_start(left.node), '('), fix_insert_at(node_end(left.node), ')')]
		mut suggestions := []Suggestion{}
		if !left.chain && node_kind(left.node) == 'non_null_expression' {
			match operator {
				'=' {
					_, s := c.suggestion('notNeedInAssign', map[string]string{}, [remove_bang])!
					suggestions << s
				}
				'==', '===' {
					_, s := c.suggestion('notNeedInEqualTest', map[string]string{}, [remove_bang])!
					suggestions << s
				}
				else {
					_, s := c.suggestion('notNeedInOperator', {
						'operator': operator
					}, [remove_bang])!
					suggestions << s
					_, w := c.suggestion('wrapUpLeft', {
						'operator': operator
					}, wrap)!
					suggestions << w
				}
			}
		} else {
			_, w := c.suggestion('wrapUpLeft', {
				'operator': operator
			}, wrap)!
			suggestions << w
		}
		findings << Finding{
			stmt:        position_of(node)
			message_id:  message_id
			data:        data
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
