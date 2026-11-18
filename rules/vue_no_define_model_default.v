module rules

import time

// Port of the `vue/no-define-model-default` rule of eslint-plugin-vue 10.12.1 (no options): the
// `default` property of the options of a `defineModel` of `<script setup>`.

const vue_no_define_model_default_messages = {
	'unexpected': 'Unexpected default value for the "{{name}}" model.'
}

fn (mut c Checker) lint_vue_no_define_model_default(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineModel') {
		stats.checked++
		model := vue_define_model(t, call)
		options := vue_skip_ts_as(t, model.options)
		if options < 0 || t.typ(options) != .object_expression {
			continue
		}
		default_property := vue_find_property(t, options, 'default', none)
		if default_property >= 0 {
			findings << Finding{
				stmt:       c.es_tree_position(t, default_property)
				message_id: 'unexpected'
				data:       {
					'name': model.name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
