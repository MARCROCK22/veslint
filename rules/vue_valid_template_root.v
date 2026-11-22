module rules

import time

// Port of the `vue/valid-template-root` rule of eslint-plugin-vue 10.12.1 (no options): a
// `<template src>` with content (each child whose text is not blank), or a `<template>` without
// it.

const vue_valid_template_root_messages = {
	'emptySrc': "The template root with 'src' attribute is required to be empty."
	'noChild':  'The template requires child element.'
}

fn (mut c Checker) lint_vue_valid_template_root(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	stats.checked++
	body := c.vue.doc.template_body
	has_src := c.vue_has_attribute(body, 'src', none)
	mut root_elements := []int{}
	for child in c.vue.doc.nodes[body].children {
		if js_trim(c.vue_vnode_text(child)) != '' {
			root_elements << child
		}
	}
	if has_src && root_elements.len > 0 {
		for element in root_elements {
			findings << c.vue_report_vnode(element, 'emptySrc', {})
		}
	} else if !has_src && root_elements.len == 0 {
		findings << c.vue_report_vnode(body, 'noChild', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
