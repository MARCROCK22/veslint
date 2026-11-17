module rules

import time

// Port of the `vue/no-v-model-argument` rule of eslint-plugin-vue 10.12.1 (deprecated; no options):
// a `v-model` with an argument on a custom component.

const vnvma_messages = {
	'vModelRequireNoArgument': "'v-model' directives require no argument."
}

fn (mut c Checker) lint_vue_no_v_model_argument(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'model') {
			continue
		}
		stats.checked++
		if c.vue_directive_argument(i) >= 0 && c.vue_is_custom_component(c.vue_attribute_element(i), false) {
			findings << c.vue_report_vnode(i, 'vModelRequireNoArgument', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
