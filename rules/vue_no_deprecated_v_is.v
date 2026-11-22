module rules

import time

// Port of the `vue/no-deprecated-v-is` rule of eslint-plugin-vue 10.12.1 (syntaxes/v-is.ts; no
// options): every `v-is` directive, on its key.

const vndvi_messages = {
	'forbiddenVIs': '`v-is` directive is deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_v_is(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if c.vue_is_directive(i, 'is') {
			stats.checked++
			findings << c.vue_report_vnode(c.vue.doc.nodes[i].key, 'forbiddenVIs', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
