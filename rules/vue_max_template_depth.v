module rules

import json2
import time

// Port of the `vue/max-template-depth` rule of eslint-plugin-vue 10.12.1 (option `maxDepth`):
// every element of the `<template>` deeper than the maximum (the template's root elements are at
// depth 1).

const vue_max_template_depth_messages = {
	'templateTooDeep': 'Element is nested too deeply (depth of {{depth}}, maximum allowed is {{limit}}).'
}

// vue_max_template_depth_options is `maxDepth`, -1 when it is not given (no element is then too
// deep).
fn vue_max_template_depth_options(options []json2.Any) !f64 {
	o := option_object(vue_max_template_depth, options, ['maxDepth'])!
	value := o.values['maxDepth'] or { return -1 }
	if value !is f64 && value !is int && value !is i64 {
		return error('option `maxDepth` of `${vue_max_template_depth}` must be an integer')
	}
	return value.f64()
}

fn (mut c Checker) lint_vue_max_template_depth(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	max_depth := vue_max_template_depth_options(c.rule_options(vue_max_template_depth))!
	mut findings := []Finding{}
	if max_depth < 0 {
		return findings
	}
	limit := max_depth
	c.vue_check_max_depth(c.vue.doc.template_body, 0, limit, mut findings, mut stats)
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) vue_check_max_depth(element int, depth int, limit f64, mut findings []Finding, mut stats Stats) {
	stats.checked++
	if f64(depth) > limit {
		findings << c.vue_report_vnode(element, 'templateTooDeep', {
			'depth': depth.str()
			'limit': js_number_to_string(limit)
		})
	}
	for child in c.vue.doc.nodes[element].children {
		if c.vue.doc.nodes[child].typ == .v_element {
			c.vue_check_max_depth(child, depth + 1, limit, mut findings, mut stats)
		}
	}
}
