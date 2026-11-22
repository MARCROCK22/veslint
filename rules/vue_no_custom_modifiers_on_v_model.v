module rules

import time

// Port of the `vue/no-custom-modifiers-on-v-model` rule of eslint-plugin-vue 10.12.1 (no options):
// on a custom component, each modifier of a `v-model` other than lazy, number and trim, reported on
// the directive.

const vncmovm_messages = {
	'notSupportedModifier': "'v-model' directives don't support the modifier '{{name}}'."
}

fn (mut c Checker) lint_vue_no_custom_modifiers_on_v_model(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
		if !c.vue_is_custom_component(c.vue_attribute_element(i), false) {
			continue
		}
		for m in c.vue_directive_modifiers(i) {
			name := c.vue.doc.nodes[m].name
			if name !in ['lazy', 'number', 'trim'] {
				findings << c.vue_report_vnode(i, 'notSupportedModifier', {
					'name': name
				})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
