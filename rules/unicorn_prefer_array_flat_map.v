module rules

import time

// Port of the `unicorn/prefer-array-flat-map` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const upafm_messages = {
	'prefer-array-flat-map': 'Prefer `.flatMap(…)` over `.map(…).flat()`.'
}

fn (mut c Checker) lint_unicorn_prefer_array_flat_map(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: ['flat'], optional_call: false, optional_member: false) {
			continue
		}
		arguments := t.list(node, .arguments) or { []int{} }
		if !(arguments.len == 0 || (arguments.len == 1 && t.typ(arguments[0]) == .literal
			&& un_raw(t, arguments[0]) == '1')) {
			continue
		}
		map_call := t.node(t.node(node, .callee) or { continue }, .object) or { continue }
		if !un_is_method_call(t, map_call, methods: ['map'], optional_call: false) {
			continue
		}
		map_callee := t.node(map_call, .callee) or { continue }
		if un_is_node_matches(t, t.node(map_callee, .object) or { continue }, ['React.Children',
			'Children']) {
			continue
		}
		map_property := t.node(map_callee, .property) or { continue }
		mut fixes := c.un_remove_method_call(t, tokens, node)
		fixes << fix_replace_range(t.nodes[map_property].start, t.nodes[map_property].end, 'flatMap')
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			stmt:       c.position_range(t.nodes[map_property].start, t.nodes[node].end)
			message_id: 'prefer-array-flat-map'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
