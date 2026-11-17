module rules

import time

// Port of the `vue/no-template-key` rule of eslint-plugin-vue 10.12.1 (no options): the `key` (or
// `:key`) of a <template> without a `v-for`.

const vntk_messages = {
	'disallow': "'<template>' cannot be keyed. Place the key on real elements instead."
}

fn (mut c Checker) lint_vue_no_template_key(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.name != 'template' {
			continue
		}
		stats.checked++
		mut key := c.vue_get_attribute(i, 'key', none)
		if key < 0 {
			key = c.vue_get_directive(i, 'bind', 'key')
		}
		if key < 0 || c.vue_has_directive(i, 'for', none) {
			continue
		}
		findings << c.vue_report_vnode(key, 'disallow', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
