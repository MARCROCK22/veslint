module rules

import json2
import time

// Port of the `promise/no-promise-in-callback` rule of eslint-plugin-promise 7.3.0, with its
// options.

const prm_no_promise_in_callback_messages = {
	'avoidPromiseInCallback': 'Avoid using promises inside of callbacks.'
}

fn prm_no_promise_in_callback_options(options []json2.Any) !bool {
	o := option_object(promise_no_promise_in_callback, options, ['exemptDeclarations'])!
	return o.bool_value('exemptDeclarations')!
}

fn (mut c Checker) lint_promise_no_promise_in_callback(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	exempt_declarations := prm_no_promise_in_callback_options(c.rule_options(promise_no_promise_in_callback))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		if !prm_is_promise(t, node) {
			continue
		}
		parent := t.nodes[node].parent
		if parent >= 0 && t.typ(parent) == .return_statement {
			continue
		}
		if prm_ancestors(t, node).any(prm_is_inside_callback(t, it, exempt_declarations)) {
			findings << Finding{
				stmt:       c.es_tree_position(t, prm_child(t, node, .callee))
				message_id: 'avoidPromiseInCallback'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
