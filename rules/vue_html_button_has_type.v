module rules

import json2
import time

// Port of the `vue/html-button-has-type` rule of eslint-plugin-vue 10.12.1 (options `button`,
// `submit` and `reset`, each true by default: whether that type is allowed): a <button> (by its
// rawName) without a `type` or a `:type`, with an empty one, with a value that is not a button
// type, or with a type the options forbid.

const vhbht_messages = {
	'missingTypeAttribute':   'Missing an explicit type attribute for button.'
	'invalidTypeAttribute':   '{{value}} is an invalid value for button type attribute.'
	'forbiddenTypeAttribute': '{{value}} is a forbidden value for button type attribute.'
	'emptyTypeAttribute':     'A value must be set for button type attribute.'
}

fn vhbht_options(options []json2.Any) !map[string]bool {
	o := option_object(vue_html_button_has_type, options, ['button', 'submit', 'reset'])!
	mut allowed := {
		'button': true
		'submit': true
		'reset':  true
	}
	for key, _ in o.values {
		allowed[key] = o.bool_value(key)!
	}
	return allowed
}

fn (mut c Checker) lint_vue_html_button_has_type(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allowed := vhbht_options(c.rule_options(vue_html_button_has_type))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.raw_name != 'button' {
			continue
		}
		stats.checked++
		attr := c.vue_get_attribute(i, 'type', none)
		if attr >= 0 {
			value := c.vue.doc.nodes[attr].value
			if value < 0 || c.vue.doc.nodes[value].text == '' {
				findings << c.vue_report_vnode(if value >= 0 { value } else { attr }, 'emptyTypeAttribute',
					{})
				continue
			}
			text := c.vue.doc.nodes[value].text
			if text !in ['button', 'submit', 'reset'] {
				findings << c.vue_report_vnode(value, 'invalidTypeAttribute', {
					'value': text
				})
			} else if !allowed[text] {
				findings << c.vue_report_vnode(value, 'forbiddenTypeAttribute', {
					'value': text
				})
			}
			continue
		}
		directive := c.vue_get_directive(i, 'bind', 'type')
		if directive >= 0 {
			value := c.vue.doc.nodes[directive].value
			if value < 0 || c.vue_container_expression(value).is_null() {
				findings << c.vue_report_vnode(if value >= 0 { value } else { directive },
					'emptyTypeAttribute', {})
			}
			continue
		}
		findings << c.vue_report_vnode(node.start_tag, 'missingTypeAttribute', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
