module rules

import time
import x.json2

// Port of the `@stylistic/new-parens` rule of @stylistic/eslint-plugin 6.0.1, with its option
// (`"always"`, the default, or `"never"`) and its fixes.

const snwp_messages = {
	'missing':     "Missing '()' invoking a constructor."
	'unnecessary': "Unnecessary '()' invoking a constructor with no arguments."
}

// snwp_options gives `always`.
fn snwp_options(given []json2.Any) !bool {
	return sty_option_string(sty_options(given, decoded_default_options(stylistic_new_parens)),
		0, 'always') != 'never'
}

fn (mut c Checker) lint_stylistic_new_parens(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	always := snwp_options(c.rule_options(stylistic_new_parens))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		arguments := t.list(node, .arguments) or { []int{} }
		// If there are arguments, there have to be parens.
		if arguments.len != 0 {
			continue
		}
		last_token := un_last_token(t, tokens, node) or { continue }
		has_last_paren := c.token_is(last_token, ')')
		token_before_last := tokens.before(last_token.start, false) or { continue }
		callee := t.node(node, .callee) or { continue }
		// `hasParens` is true only if the new expression ends with its own parens.
		has_parens := has_last_paren && c.token_is(token_before_last, '(')
			&& t.nodes[callee].end < t.nodes[node].end
		start := t.nodes[node].start
		end := t.nodes[node].end
		if always {
			if !has_parens {
				findings << Finding{
					stmt:       c.position_range(start, end)
					message_id: 'missing'
					has_fix:    true
					fix:        fix_insert_at(end, '()')
				}
			}
		} else if has_parens {
			findings << c.with_fixes(Finding{
				stmt:       c.position_range(start, end)
				message_id: 'unnecessary'
			}, [fix_remove_range(token_before_last.start, token_before_last.end),
				fix_remove_range(last_token.start, last_token.end), fix_insert_at(start, '('),
				fix_insert_at(end, ')')])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
