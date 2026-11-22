module rules

import time

// Port of the `vue/no-v-for-template-key` rule of eslint-plugin-vue 10.12.1 (deprecated; no
// options): the `key` (or `:key`) of a <template> with a `v-for`, once per `v-for`.

const vnvftk_messages = {
	'disallow': "'<template v-for>' cannot be keyed. Place the key on real elements instead."
}

fn (mut c Checker) lint_vue_no_v_for_template_key(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VElement[name='template'] > VStartTag > VAttribute[directive=true][key.name.name='for']`
		if !c.vue_is_directive(i, 'for') {
			continue
		}
		element := c.vue_attribute_element(i)
		if element < 0 || c.vue.doc.nodes[element].name != 'template' {
			continue
		}
		stats.checked++
		mut key := c.vue_get_attribute(element, 'key', none)
		if key < 0 {
			key = c.vue_get_directive(element, 'bind', 'key')
		}
		if key >= 0 {
			findings << c.vue_report_vnode(key, 'disallow', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
