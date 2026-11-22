module rules

import time

// Port of the `vue/no-deprecated-data-object-declaration` rule of eslint-plugin-vue 10.12.1 (no
// options): the `data` of a Vue object that is not a function (or an identifier), with the fix
// that wraps it in one (no-shared-component-data's, for every Vue object).

const vue_no_deprecated_data_object_declaration_messages = {
	'objectDeclarationIsDeprecated': "Object declaration on 'data' property is deprecated. Using function declaration instead."
}

fn (mut c Checker) lint_vue_no_deprecated_data_object_declaration(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		finding := c.vue_data_function_finding(t, obj, 'objectDeclarationIsDeprecated') or {
			continue
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
