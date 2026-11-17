module rules

import time

// Port of the `vue/no-deprecated-filter` rule of eslint-plugin-vue 10.12.1 (no options): every
// VFilterSequenceExpression (`{{ a | f }}`, `:x="a | f"`).

const vndf_messages = {
	'noDeprecatedFilter': 'Filters are deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_filter(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if c.vue.doc.nodes[i].typ == .v_filter_sequence_expression {
			stats.checked++
			findings << c.vue_report_vnode(i, 'noDeprecatedFilter', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
