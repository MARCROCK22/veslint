module rules

import time

// Port of the `promise/avoid-new` rule of eslint-plugin-promise 7.3.0 (it has no options).

const prm_avoid_new_messages = {
	'avoidNew': 'Avoid creating new promises.'
}

fn (mut c Checker) lint_promise_avoid_new(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		if prm_name(t, prm_child(t, node, .callee)) == 'Promise' {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'avoidNew'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
