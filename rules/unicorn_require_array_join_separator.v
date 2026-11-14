module rules

import time

// Port of the `unicorn/require-array-join-separator` rule of eslint-plugin-unicorn 64.0.0 (it has
// no options), with its fix.

const urajs_messages = {
	'require-array-join-separator': 'Missing the separator argument.'
}

fn (mut c Checker) lint_unicorn_require_array_join_separator(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		// `foo.join()`, or `[].join.call(foo)` and `Array.prototype.join.call(foo)`
		if !(un_is_method_call(t, node, methods: ['join'], arguments_length: 0, optional_call: false)
			|| (un_is_method_call(t, node,
			methods:         ['call']
			arguments_length: 1
			optional_call:   false
			optional_member: false
		)
			&& un_is_prototype_property(t, t.node(t.node(node, .callee) or { continue }, .object) or {
			continue
		}, 'Array', ['join']))) {
			continue
		}
		inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
		if inside.len < 2 {
			continue
		}
		penultimate := inside[inside.len - 2]
		last := inside.last()
		is_prototype_method := (t.list(node, .arguments) or { []int{} }).len == 1
		fix := c.un_append_argument(t, tokens, node, "','") or { continue }
		findings << Finding{
			stmt:       c.position_range(if is_prototype_method {
				penultimate.end
			} else {
				penultimate.start
			}, last.end)
			message_id: 'require-array-join-separator'
			has_fix:    true
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
