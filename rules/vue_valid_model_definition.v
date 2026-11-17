module rules

import time

// Port of the `vue/valid-model-definition` rule of eslint-plugin-vue 10.12.1 (deprecated; no
// options): a key of the `model` option of a Vue object other than `prop` and `event`.

const vue_valid_model_definition_messages = {
	'invalidKey': "Invalid key '{{name}}' in model option."
}

fn (mut c Checker) lint_vue_valid_model_definition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		model := vue_find_property(t, obj, 'model', none)
		if model < 0 || t.typ(vue_property_value(t, model)) != .object_expression {
			continue
		}
		for p in t.list(vue_property_value(t, model), .properties) or { []int{} } {
			if t.typ(p) != .property {
				continue
			}
			name := vue_static_property_name(t, p) or { continue }
			if name == '' {
				continue
			}
			if name !in ['prop', 'event'] {
				findings << Finding{
					stmt:       c.es_tree_position(t, p)
					message_id: 'invalidKey'
					data:       {
						'name': name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
