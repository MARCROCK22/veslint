module rules

import json2
import jsregexp
import time

// Port of the `vue/no-restricted-static-attribute` rule of eslint-plugin-vue 10.12.1 (options: each
// a key, or an object with `key`, `value` (a string, or true: no value or the key's name),
// `element` (names or regular expressions as strings) and `message`): a plain attribute the first
// matching option restricts.

const vnrsa_messages = {
	'restrictedAttr': '{{message}}'
}

struct VnrsaOption {
	key         jsregexp.JsRegex
	use_value   bool
	value_true  bool
	value       jsregexp.JsRegex
	use_element bool
	element     jsregexp.JsRegex
	message     string
}

fn vnrsa_options(options []json2.Any) ![]VnrsaOption {
	mut out := []VnrsaOption{}
	for option in options {
		if option is string {
			out << VnrsaOption{
				key: vue_to_regexp(option, '', 'g')!
			}
			continue
		}
		if option !is map[string]json2.Any {
			return error('an option of `${vue_no_restricted_static_attribute}` must be a string or an object')
		}
		o := option_object(vue_no_restricted_static_attribute, [option], ['key', 'value', 'element',
			'message'])!
		key := o.values['key'] or {
			return error('an option of `${vue_no_restricted_static_attribute}` needs `key`')
		}
		if key !is string {
			return error('`key` of `${vue_no_restricted_static_attribute}` must be a string')
		}
		mut parsed := VnrsaOption{
			key: vue_to_regexp(key as string, '', 'g')!
		}
		value := o.values['value'] or { json2.Any(false) }
		if value is bool {
			if value {
				parsed = VnrsaOption{
					...parsed
					use_value:  true
					value_true: true
				}
			}
		} else if value is string {
			if value != '' {
				parsed = VnrsaOption{
					...parsed
					use_value: true
					value:     vue_to_regexp(value, '', 'g')!
				}
			}
		} else {
			return error('`value` of `${vue_no_restricted_static_attribute}` must be a string or true')
		}
		element := o.values['element'] or { json2.Any('') }
		if element is string && element != '' {
			parsed = VnrsaOption{
				...parsed
				use_element: true
				element:     vue_to_regexp(element, '', 'g')!
			}
		}
		message := o.values['message'] or { json2.Any('') }
		out << VnrsaOption{
			...parsed
			message: if message is string { message } else { '' }
		}
	}
	return out
}

fn (c &Checker) vnrsa_test(option &VnrsaOption, attr int) bool {
	node := &c.vue.doc.nodes[attr]
	key := c.vue.doc.nodes[node.key].raw_name
	if !vue_regexp_test(option.key, key) {
		return false
	}
	if option.use_value {
		if option.value_true {
			if node.value >= 0 && c.vue.doc.nodes[node.value].text != key {
				return false
			}
		} else if node.value < 0 || !vue_regexp_test(option.value, c.vue.doc.nodes[node.value].text) {
			return false
		}
	}
	if option.use_element {
		element := c.vue_attribute_element(attr)
		if !vue_regexp_test(option.element, c.vue.doc.nodes[element].raw_name) {
			return false
		}
	}
	return true
}

// vnrsa_default_message is defaultMessage.
fn (c &Checker) vnrsa_default_message(attr int, option &VnrsaOption) string {
	node := &c.vue.doc.nodes[attr]
	key := c.vue.doc.nodes[node.key].raw_name
	mut value := ''
	if option.use_value {
		value = if node.value < 0 {
			'` set to `true'
		} else {
			'="${c.vue.doc.nodes[node.value].text}"'
		}
	}
	on := if option.use_element {
		' on `<${c.vue.doc.nodes[c.vue_attribute_element(attr)].raw_name}>`'
	} else {
		''
	}
	return 'Using `${key}${value}`${on} is not allowed.'
}

fn (mut c Checker) lint_vue_no_restricted_static_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	options := vnrsa_options(c.rule_options(vue_no_restricted_static_attribute))!
	if options.len == 0 {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || node.directive {
			continue
		}
		stats.checked++
		for option in options {
			if c.vnrsa_test(option, i) {
				message := if option.message != '' {
					option.message
				} else {
					c.vnrsa_default_message(i, option)
				}
				findings << c.vue_report_vnode(i, 'restrictedAttr', {
					'message': message
				})
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
