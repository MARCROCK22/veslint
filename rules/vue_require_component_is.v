module rules

import time

// Port of the `vue/require-component-is` rule of eslint-plugin-vue 10.12.1 (no options): a
// <component> element without a `v-bind:is` (`:is`).

const vrci_messages = {
	'requireComponentIs': "Expected '<component>' elements to have 'v-bind:is' attribute."
}

fn (mut c Checker) lint_vue_require_component_is(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.name != 'component' {
			continue
		}
		stats.checked++
		if !c.vue_has_directive(i, 'bind', 'is') {
			findings << c.vue_report_vnode(i, 'requireComponentIs', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
