module rules

import time

// Port of the `unicorn/no-unreadable-iife` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its suggestion.

const unui_messages = {
	'no-unreadable-iife': 'IIFE with parenthesized arrow function body is considered unreadable.'
	'suggestion':         'Use a block statement body.'
}

fn (mut c Checker) lint_unicorn_no_unreadable_iife(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		callee := t.node(node, .callee) or { continue }
		if t.typ(callee) != .arrow_function_expression {
			continue
		}
		body := t.node(callee, .body) or { continue }
		if t.typ(body) == .block_statement || !c.un_is_parenthesized(t, tokens, body) {
			continue
		}
		start, end := c.un_parenthesized_range(t, tokens, body)
		mut suggestions := []Suggestion{}
		// Comments inside the parentheses but outside the body would be removed.
		if !un_would_remove_comments(tokens, start, end, [un_range(t, body)]) {
			suggestions << Suggestion{
				message_id: 'suggestion'
				fix:        fix_replace_range(start, end, '{ return ${c.un_text(t, body)}; }')
			}
		}
		findings << Finding{
			stmt:        c.position_range(start, end)
			message_id:  'no-unreadable-iife'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
