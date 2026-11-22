module rules

import time

// Port of the `vue/no-v-text` rule of eslint-plugin-vue 10.12.1 (no options).

const vnvt_messages = {
	'unexpected': "Don't use 'v-text'."
}

fn (mut c Checker) lint_vue_no_v_text(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if c.vue_is_directive(i, 'text') {
			stats.checked++
			findings << c.vue_report_vnode(i, 'unexpected', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
