module rules

import estree
import time

// Port of the `unicorn/prefer-date-now` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix.

const updn_messages = {
	'prefer-date':                            'Prefer `Date.now()` over `new Date()`.'
	'prefer-date-now-over-methods':           'Prefer `Date.now()` over `Date#{{method}}()`.'
	'prefer-date-now-over-number-data-object': 'Prefer `Date.now()` over `Number(new Date())`.'
}

fn updn_is_new_date(t &estree.EsTree, node int) bool {
	return un_is_new(t, node, names: ['Date'], arguments_length: 0)
}

fn (mut c Checker) lint_unicorn_prefer_date_now(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		operator := t.string_of(node, .operator) or { '' }
		match t.typ(node) {
			.call_expression {
				stats.checked++
				// `new Date().{getTime,valueOf}()`
				callee := t.node(node, .callee) or { continue }
				if un_is_method_call(t, node,
					methods:          ['getTime', 'valueOf']
					arguments_length: 0
					optional_call:    false
					optional_member:  false
				) && updn_is_new_date(t, t.node(callee, .object) or { -1 }) {
					method := t.node(callee, .property) or { continue }
					findings << c.updn_problem(t, tokens, node, method, 'prefer-date-now-over-methods',
						{
						'method': t.string_of(method, .name) or { '' }
					})!
					continue
				}
				// `{Number,BigInt}(new Date())`
				if un_is_call(t, node, names: ['Number', 'BigInt'], arguments_length: 1, optional: false) {
					argument := (t.list(node, .arguments) or { continue })[0]
					if !updn_is_new_date(t, argument) {
						continue
					}
					if (t.string_of(callee, .name) or { '' }) == 'Number' {
						findings << c.updn_problem(t, tokens, node, node, 'prefer-date-now-over-number-data-object',
							map[string]string{})!
					} else {
						findings << c.updn_problem(t, tokens, argument, argument, 'prefer-date',
							map[string]string{})!
					}
				}
			}
			.unary_expression {
				stats.checked++
				argument := t.node(node, .argument) or { continue }
				if operator in ['+', '-'] && updn_is_new_date(t, argument) {
					target := if operator == '-' { argument } else { node }
					findings << c.updn_problem(t, tokens, target, target, 'prefer-date', map[string]string{})!
				}
			}
			.assignment_expression {
				stats.checked++
				right := t.node(node, .right) or { continue }
				if operator in ['-=', '*=', '/=', '%=', '**='] && updn_is_new_date(t, right) {
					findings << c.updn_problem(t, tokens, right, right, 'prefer-date', map[string]string{})!
				}
			}
			.binary_expression {
				stats.checked++
				if operator !in ['-', '*', '/', '%', '**'] {
					continue
				}
				for key in [estree.Key.left, .right] {
					side := t.node(node, key) or { continue }
					if updn_is_new_date(t, side) {
						findings << c.updn_problem(t, tokens, side, side, 'prefer-date', map[string]string{})!
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// updn_problem ports getProblem: `node` becomes `Date.now()`; the problem is at `at`.
fn (c &Checker) updn_problem(t &estree.EsTree, tokens &SourceTokens, node int, at int, message_id string, data map[string]string) !Finding {
	mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Date.now()')]
	if t.typ(node) == .unary_expression {
		fixes << c.un_fix_space_around_keyword(t, tokens, node)
	}
	has_fix, fix := c.merge_fixes(fixes)!
	return Finding{
		stmt:       c.es_tree_position(t, at)
		message_id: message_id
		data:       data
		has_fix:    has_fix
		fix:        fix
	}
}
