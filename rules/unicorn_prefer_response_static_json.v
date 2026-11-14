module rules

import time

// Port of the `unicorn/prefer-response-static-json` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const uprsj_messages = {
	'prefer-response-static-json': 'Prefer using `Response.json(…)` over `JSON.stringify()`.'
}

fn (mut c Checker) lint_unicorn_prefer_response_static_json(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		if !un_is_new(t, node, names: ['Response'], minimum_arguments: 1) {
			continue
		}
		stringify := (t.list(node, .arguments) or { continue })[0]
		if !un_is_method_call(t, stringify,
			objects:          ['JSON']
			methods:          ['stringify']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) {
			continue
		}
		data := (t.list(stringify, .arguments) or { continue })[0]
		call_start, call_end := c.un_parenthesized_range(t, tokens, stringify)
		data_start, data_end := c.un_parenthesized_range(t, tokens, data)
		mut finding := Finding{
			stmt:       c.es_tree_position(t, t.node(stringify, .callee) or { continue })
			message_id: 'prefer-response-static-json'
		}
		// A comment in the removed part of the call would be dropped; `Response.json()` throws on
		// what `JSON.stringify()` turns into `undefined`.
		value := un_unwrap_ts_expression(t, data)
		if !un_has_comment_in_range(tokens, call_start, data_start)
			&& !un_has_comment_in_range(tokens, data_end, call_end)
			&& !(unb_is_undefined_value(t, value) || unb_is_function(t, value)
			|| t.typ(value) == .class_expression) {
			callee := t.node(node, .callee) or { continue }
			mut fixes := [fix_insert_at(t.nodes[callee].end, '.json')]
			fixes << c.un_switch_new_to_call(t, tokens, node)
			fixes << fix_remove_range(call_start, data_start)
			fixes << fix_remove_range(data_end, call_end)
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
