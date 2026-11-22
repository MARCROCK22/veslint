module rules

import time

// Port of the `promise/no-return-in-finally` rule of eslint-plugin-promise 7.3.0 (it has no
// options).

const prm_no_return_in_finally_messages = {
	'avoidReturnInFinally': 'No return in finally'
}

fn (mut c Checker) lint_promise_no_return_in_finally(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		if !prm_is_promise(t, node) || prm_callee_property_name(t, node) != 'finally' {
			continue
		}
		args := t.list(node, .arguments) or { continue }
		if args.len == 0 {
			continue
		}
		// `node.arguments[0].body.body`: the statements of a function's block, or the members of
		// a class body an arrow function returns. Another node there (the block of an arrow
		// function an arrow function returns) has no `some`: the rule throws, and ESLint stops
		// linting the file: no problem of the rule is left.
		body := prm_child(t, args[0], .body)
		if body < 0 {
			continue
		}
		if prm_child(t, body, .body) >= 0 {
			return []Finding{}
		}
		statements := t.list(body, .body) or { continue }
		if statements.any(it >= 0 && t.typ(it) == .return_statement) {
			findings << Finding{
				stmt:       c.es_tree_position(t, prm_child(t, prm_child(t, node, .callee),
					.property))
				message_id: 'avoidReturnInFinally'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
