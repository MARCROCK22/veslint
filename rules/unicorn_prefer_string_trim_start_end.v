module rules

import time

// Port of the `unicorn/prefer-string-trim-start-end` rule of eslint-plugin-unicorn 64.0.0 (it has
// no options), with its fix.

const upstse_messages = {
	'prefer-string-trim-start-end': 'Prefer `String#{{replacement}}()` over `String#{{method}}()`.'
}

fn (mut c Checker) lint_unicorn_prefer_string_trim_start_end(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node,
			methods:          ['trimLeft', 'trimRight']
			arguments_length: 0
			optional_call:    false
		) {
			continue
		}
		property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
		method := t.string_of(property, .name) or { continue }
		replacement := if method == 'trimLeft' { 'trimStart' } else { 'trimEnd' }
		findings << Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'prefer-string-trim-start-end'
			data:       {
				'method':      method
				'replacement': replacement
			}
			has_fix:    true
			fix:        fix_replace_range(t.nodes[property].start, t.nodes[property].end,
				replacement)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
