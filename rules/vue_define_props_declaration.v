module rules

import json2
import time

// Port of the `vue/define-props-declaration` rule of eslint-plugin-vue 10.12.1 (option
// "type-based", the default, or "runtime"): in a `<script setup lang="ts">`, a `defineProps` with
// arguments (type-based) or with type arguments (runtime).

const vue_define_props_declaration_messages = {
	'hasArg':     'Use type-based declaration instead of runtime declaration.'
	'hasTypeArg': 'Use runtime declaration instead of type-based declaration.'
}

fn vue_define_props_declaration_options(options []json2.Any) !string {
	return vue_enum_option(vue_define_props_declaration, options, ['type-based', 'runtime'],
		'type-based')!
}

// vue_enum_option reads the first option of a rule whose schema is `{ enum: [...] }` (the
// default when it is missing).
fn vue_enum_option(rule string, options []json2.Any, allowed []string, default_value string) !string {
	if options.len == 0 {
		return default_value
	}
	value := options[0]
	if value !is string || value as string !in allowed {
		return error('the option of `${rule}` must be one of ${allowed.map('"${it}"').join(', ')}')
	}
	return value as string
}

fn (mut c Checker) lint_vue_define_props_declaration(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	define_type := vue_define_props_declaration_options(c.rule_options(vue_define_props_declaration))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.setup_element < 0 || !c.vue_has_attribute(s.setup_element, 'lang', 'ts') {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineProps') {
		stats.checked++
		if define_type == 'type-based' {
			if (t.list(call, .arguments) or { []int{} }).len > 0 {
				findings << Finding{
					stmt:       c.es_tree_position(t, call)
					message_id: 'hasArg'
				}
			}
		} else if vue_type_arguments(t, call).len > 0 {
			findings << Finding{
				stmt:       c.es_tree_position(t, call)
				message_id: 'hasTypeArg'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
