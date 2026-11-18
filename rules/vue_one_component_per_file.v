module rules

import time

// Port of the `vue/one-component-per-file` rule of eslint-plugin-vue 10.12.1 (no options): every
// component of a file that has more than one (executeOnVueComponent; mixins do not count).

const vue_one_component_per_file_messages = {
	'tooManyComponents': 'There is more than one component in this file.'
}

fn (mut c Checker) lint_vue_one_component_per_file(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut components := []int{}
	for node in s.objects_of(vue_component_object_types) {
		stats.checked++
		if s.object_type(node) == .definition
			&& c.vue_component_definition_type(root, t, node) == 'mixin' {
			continue
		}
		components << node
	}
	if components.len > 1 {
		for node in components {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'tooManyComponents'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
