module rules

import time

// Port of the `vue/no-root-v-if` rule of eslint-plugin-vue 10.12.1 (no options): a `<template>`
// whose only root element has `v-if`, reported at the template.

const vue_no_root_v_if_messages = {
	'noRootVIf': '`v-if` should not be used on root element without `v-else`.'
}

fn (mut c Checker) lint_vue_no_root_v_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	stats.checked++
	body := c.vue.doc.template_body
	elements := c.vue.doc.nodes[body].children.filter(c.vue.doc.nodes[it].typ == .v_element)
	if elements.len == 1 && c.vue_has_directive(elements[0], 'if', none) {
		findings << c.vue_report_vnode(body, 'noRootVIf', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
