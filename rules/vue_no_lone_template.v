module rules

import json2
import time

// Port of the `vue/no-lone-template` rule of eslint-plugin-vue 10.12.1 (option `ignoreAccessible`):
// the start tag of a <template> inside an element without a directive that makes it useful (v-if,
// v-else, v-else-if, v-for, v-slot, slot-scope, scope) nor a `slot` (or `:slot`), nor, with
// ignoreAccessible, an `id` or a `ref` (or their v-binds).

const vnlt_messages = {
	'requireDirective': '`<template>` require directive.'
}

fn vnlt_options(options []json2.Any) !bool {
	o := option_object(vue_no_lone_template, options, ['ignoreAccessible'])!
	return o.bool_value('ignoreAccessible')!
}

// vnlt_key_name is getKeyName: a plain attribute's name, a `v-bind`'s static argument, or none.
fn (c &Checker) vnlt_key_name(attr int) string {
	if !c.vue.doc.nodes[attr].directive {
		return c.vue_attribute_name(attr)
	}
	if c.vue_directive_name(attr) != 'bind' {
		return ''
	}
	return c.vue_static_argument(attr) or { '' }
}

fn (mut c Checker) lint_vue_no_lone_template(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	ignore_accessible := vnlt_options(c.rule_options(vue_no_lone_template))!
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
		if attributes.any((c.vue.doc.nodes[it].directive && c.vue_directive_name(it) in [
			'slot-scope',
			'scope',
			'if',
			'else',
			'else-if',
			'for',
			'slot',
		]) || c.vnlt_key_name(it) == 'slot') {
			continue
		}
		if ignore_accessible && attributes.any(c.vnlt_key_name(it) in ['id', 'ref']) {
			continue
		}
		findings << c.vue_report_vnode(node.start_tag, 'requireDirective', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
