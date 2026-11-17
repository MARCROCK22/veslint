module rules

import time

// Port of the `vue/no-arrow-functions-in-watch` rule of eslint-plugin-vue 10.12.1 (no options):
// an arrow function as a handler of the `watch` option of a Vue object.

const vue_no_arrow_functions_in_watch_messages = {
	'noArrowFunctionsInWatch': 'You should not use an arrow function to define a watcher.'
}

fn (mut c Checker) lint_vue_no_arrow_functions_in_watch(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		watch := vue_find_property(t, obj, 'watch', none)
		if watch < 0 {
			continue
		}
		value := vue_property_value(t, watch)
		if t.typ(value) != .object_expression {
			continue
		}
		for property in t.list(value, .properties) or { []int{} } {
			if t.typ(property) != .property {
				continue
			}
			mut handlers := []int{}
			vue_watch_handler_values(t, property, mut handlers)
			for handler in handlers {
				if t.typ(handler) == .arrow_function_expression {
					findings << Finding{
						stmt:       c.es_tree_position(t, handler)
						message_id: 'noArrowFunctionsInWatch'
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
