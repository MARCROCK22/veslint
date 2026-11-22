module rules

import time

// Port of the `vue/require-render-return` rule of eslint-plugin-vue 10.12.1 (no options): the
// `render` function of a Vue object that does not always return a value
// (executeOnFunctionsWithoutReturn, which reads the types for an exhaustive switch), reported
// at its key.

const vue_require_render_return_messages = {
	'expectedReturn': 'Expected to return a value in render function.'
}

fn (mut c Checker) lint_vue_require_render_return(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	// onRenderFunctionEnter: the render function and the key of its property.
	mut render_keys := map[int]int{}
	for node in 0 .. t.nodes.len {
		if s.vue_function_kind(t, node) == 'render' {
			render_keys[node] = t.node(t.nodes[node].parent, .key) or { continue }
		}
	}
	if render_keys.len == 0 {
		return findings
	}
	for f in c.vue_functions_without_return(root, abs_path, true, mut stats) {
		stats.checked++
		key := render_keys[f] or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, key)
			message_id: 'expectedReturn'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
