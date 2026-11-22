module rules

import time

// Port of the `vue/no-deprecated-v-on-native-modifier` rule of eslint-plugin-vue 10.12.1 (no
// options): every `native` modifier of a `v-on` directive.

const vndvonm_messages = {
	'deprecated': "'.native' modifier on 'v-on' directive is deprecated."
}

fn (mut c Checker) lint_vue_no_deprecated_v_on_native_modifier(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'on') {
			continue
		}
		stats.checked++
		for m in c.vue_directive_modifiers(i) {
			if c.vue.doc.nodes[m].name == 'native' {
				findings << c.vue_report_vnode(m, 'deprecated', {})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
