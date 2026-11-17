module rules

import json2
import time

// Port of the `vue/no-restricted-html-elements` rule of eslint-plugin-vue 10.12.1 (options: each a
// rawName, or an object with `element`, one name or several, and an optional `message`): the start
// tag of an HTML, SVG or MathML element the first matching option names.

const vnrhe_messages = {
	'forbiddenElement': 'Unexpected use of forbidden element {{name}}.'
	'customMessage':    '{{message}}'
}

struct VnrheOption {
	elements    []string
	message     string
	has_message bool
}

fn vnrhe_options(options []json2.Any) ![]VnrheOption {
	mut out := []VnrheOption{}
	for option in options {
		if option is string {
			out << VnrheOption{
				elements: [option]
			}
			continue
		}
		if option !is map[string]json2.Any {
			return error('an option of `${vue_no_restricted_html_elements}` must be a string or an object')
		}
		o := option.as_map()
		element := o['element'] or { json2.Any('') }
		mut elements := []string{}
		if element is string {
			elements << element
		} else if element is []json2.Any {
			for item in element {
				if item !is string {
					return error('`element` of `${vue_no_restricted_html_elements}` must be strings')
				}
				elements << item as string
			}
		} else {
			return error('`element` of `${vue_no_restricted_html_elements}` must be a string or strings')
		}
		message := o['message'] or { json2.Any('') }
		out << VnrheOption{
			elements:    elements
			message:     if message is string { message } else { '' }
			has_message: message is string && message != ''
		}
	}
	return out
}

fn (mut c Checker) lint_vue_no_restricted_html_elements(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	options := vnrhe_options(c.rule_options(vue_no_restricted_html_elements))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		// Every element has one of the three namespaces.
		if node.typ != .v_element {
			continue
		}
		stats.checked++
		for option in options {
			if node.raw_name !in option.elements {
				continue
			}
			findings << c.vue_report_vnode(node.start_tag, if option.has_message {
				'customMessage'
			} else {
				'forbiddenElement'
			}, {
				'name':    node.raw_name
				'message': option.message
			})
			break
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
