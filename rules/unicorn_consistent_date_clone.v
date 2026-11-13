module rules

import time

// Port of the `unicorn/consistent-date-clone` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const ucdc_messages = {
	'consistent-date-clone/error': 'Unnecessary `.getTime()` call.'
}

fn (mut c Checker) lint_unicorn_consistent_date_clone(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		if !un_is_new(t, node, names: ['Date'], arguments_length: 1) {
			continue
		}
		call := (t.list(node, .arguments) or { continue })[0]
		if !un_is_method_call(t, call,
			methods:          ['getTime']
			arguments_length: 0
			optional_call:    false
			optional_member:  false
		) {
			continue
		}
		property := t.node(t.node(call, .callee) or { continue }, .property) or { continue }
		has_fix, fix := c.merge_fixes(c.un_remove_method_call(t, tokens, call))!
		findings << Finding{
			stmt:       c.position_range(t.nodes[property].start, t.nodes[call].end)
			message_id: 'consistent-date-clone/error'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
