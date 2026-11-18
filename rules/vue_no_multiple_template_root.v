module rules

import json2
import time

// Port of the `vue/no-multiple-template-root` rule of eslint-plugin-vue 10.12.1 (option
// `disallowComments`): the root of the template must be one element (a v-if/v-else-if/v-else
// chain counts as one), not text, a `<template>` or `<slot>`, nor an element with `v-for`.

const vue_no_multiple_template_root_messages = {
	'commentRoot':         'The template root disallows comments.'
	'multipleRoot':        'The template root requires exactly one element.'
	'textRoot':            'The template root requires an element rather than texts.'
	'disallowedElement':   "The template root disallows '<{{name}}>' elements."
	'disallowedDirective': "The template root disallows 'v-for' directives."
}

fn vue_no_multiple_template_root_options(options []json2.Any) !bool {
	o := option_object(vue_no_multiple_template_root, options, ['disallowComments'])!
	return o.bool_value('disallowComments')!
}

fn (mut c Checker) lint_vue_no_multiple_template_root(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	disallow_comments := vue_no_multiple_template_root_options(c.rule_options(vue_no_multiple_template_root))!
	mut findings := []Finding{}
	doc := c.vue.doc
	element := doc.template_body
	if element < 0 {
		return findings
	}
	stats.checked++
	body := &doc.nodes[element]
	if disallow_comments {
		for comment in doc.comments {
			if !(body.start <= comment.start && comment.end <= body.end) {
				continue
			}
			if body.children.any(doc.nodes[it].start <= comment.start
				&& comment.end <= doc.nodes[it].end) {
				continue
			}
			findings << c.vue_report(comment.start, comment.end, 'commentRoot', {})
		}
	}
	mut root_elements := []int{}
	mut extra_text := -1
	mut extra_element := -1
	mut is_vif := false
	for child in body.children {
		if doc.nodes[child].typ == .v_element {
			if root_elements.len == 0 {
				root_elements << child
				is_vif = c.vue_has_directive(child, 'if', none)
			} else if is_vif && c.vue_has_directive(child, 'else-if', none) {
				root_elements << child
			} else if is_vif && c.vue_has_directive(child, 'else', none) {
				root_elements << child
				is_vif = false
			} else {
				extra_element = child
			}
		} else if js_trim(c.vue_vnode_text(child)) != '' {
			extra_text = child
		}
	}
	if extra_text >= 0 {
		findings << c.vue_report_vnode(extra_text, 'textRoot', {})
	} else if extra_element < 0 {
		for e in root_elements {
			tag := doc.nodes[e].start_tag
			name := doc.nodes[e].name
			if name == 'template' || name == 'slot' {
				findings << c.vue_report_vnode(tag, 'disallowedElement', {
					'name': name
				})
			}
			if c.vue_has_directive(e, 'for', none) {
				findings << c.vue_report_vnode(tag, 'disallowedDirective', {})
			}
		}
	} else {
		findings << c.vue_report_vnode(extra_element, 'multipleRoot', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
