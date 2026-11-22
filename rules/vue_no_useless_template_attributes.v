module rules

import time

// Port of the `vue/no-useless-template-attributes` rule of eslint-plugin-vue 10.12.1 (no options):
// on a <template> inside an element that has a directive that makes it a fragment (v-if, v-else,
// v-else-if, v-for, v-slot, slot-scope, scope, or a `slot`), every other attribute but `key`.

const vnuta_messages = {
	'unexpectedAttr': 'Unexpected useless attribute on `<template>`.'
	'unexpectedDir':  'Unexpected useless directive on `<template>`.'
}

// vnuta_is_fragment_attribute is isFragmentTemplateAttribute.
fn (c &Checker) vnuta_is_fragment_attribute(attr int) bool {
	if c.vue.doc.nodes[attr].directive && c.vue_directive_name(attr) in ['slot-scope', 'scope',
		'if', 'else', 'else-if', 'for', 'slot'] {
		return true
	}
	return c.vnlt_key_name(attr) == 'slot'
}

fn (mut c Checker) lint_vue_no_useless_template_attributes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VElement[name='template'][parent.type='VElement'] > VStartTag`
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.name != 'template' || node.parent < 0
			|| c.vue.doc.nodes[node.parent].typ != .v_element {
			continue
		}
		stats.checked++
		attributes := c.vue_attributes(i)
		if !attributes.any(c.vnuta_is_fragment_attribute(it)) {
			continue
		}
		for attr in attributes {
			if c.vnuta_is_fragment_attribute(attr) || c.vnlt_key_name(attr) == 'key' {
				continue
			}
			findings << c.vue_report_vnode(attr, if c.vue.doc.nodes[attr].directive {
				'unexpectedDir'
			} else {
				'unexpectedAttr'
			}, {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
