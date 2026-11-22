module rules

import time

// Port of the `vue/no-deprecated-functional-template` rule of eslint-plugin-vue 10.12.1 (no
// options): a `functional` attribute on the `<template>` of the file.

const vue_no_deprecated_functional_template_messages = {
	'unexpected': 'The `functional` template are deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_functional_template(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	stats.checked++
	functional := c.vue_get_attribute(c.vue.doc.template_body, 'functional', none)
	if functional >= 0 {
		findings << c.vue_report_vnode(functional, 'unexpected', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
