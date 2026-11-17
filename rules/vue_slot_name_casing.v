module rules

import json2
import time

// Port of the `vue/slot-name-casing` rule of eslint-plugin-vue 10.12.1 (option "camelCase", the
// default, "kebab-case" or "singleword"): the `name` attribute of a <slot> whose value is not in
// that case.

const vsnc_messages = {
	'invalidCase': 'Slot name "{{name}}" is not {{caseType}}.'
}

fn vsnc_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'camelCase'
	}
	value := options[0]
	if value is string && value in ['camelCase', 'kebab-case', 'singleword'] {
		return value
	}
	return error('the option of `${vue_slot_name_casing}` must be "camelCase", "kebab-case" or "singleword"')
}

// vsnc_is_single_word is isSingleWord: /^[a-z]+$/u.
fn vsnc_is_single_word(s string) bool {
	return s.len > 0 && s.bytes().all(it >= `a` && it <= `z`)
}

fn (mut c Checker) lint_vue_slot_name_casing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	case_type := vsnc_options(c.rule_options(vue_slot_name_casing))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.name != 'slot' {
			continue
		}
		stats.checked++
		attr := c.vue_get_attribute(i, 'name', none)
		if attr < 0 || c.vue.doc.nodes[attr].value < 0 {
			continue
		}
		name := c.vue.doc.nodes[c.vue.doc.nodes[attr].value].text
		if name == '' {
			continue
		}
		ok := if case_type == 'singleword' {
			vsnc_is_single_word(name)
		} else {
			vue_case_check(case_type, name)
		}
		if !ok {
			findings << c.vue_report_vnode(attr, 'invalidCase', {
				'name':     name
				'caseType': case_type
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
