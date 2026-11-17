module rules

import json2
import jsregexp
import time

// Port of the `vue/no-restricted-block` rule of eslint-plugin-vue 10.12.1 (options: block names or
// `/regexp/` strings, or objects with `element` and `message`): a top-level block of a .vue file
// that an option matches (the first one gives the message), reported at its start tag.

const vue_no_restricted_block_messages = {
	'restrictedBlock': '{{message}}'
}

struct VueRestrictedBlock {
	test    jsregexp.JsRegex
	message string
}

fn vue_no_restricted_block_options(options []json2.Any) ![]VueRestrictedBlock {
	mut out := []VueRestrictedBlock{}
	for option in options {
		if option is string {
			out << VueRestrictedBlock{
				test: vue_to_regexp(option, 'g')!
			}
			continue
		}
		if option !is map[string]json2.Any {
			return error('an option of `${vue_no_restricted_block}` must be a string or an object')
		}
		o := option.as_map()
		element := o['element'] or { json2.Any(0) }
		if element !is string {
			return error('`element` of `${vue_no_restricted_block}` must be a string')
		}
		message := o['message'] or { json2.Any('') }
		out << VueRestrictedBlock{
			test:    vue_to_regexp(element as string, 'g')!
			message: if message is string { message } else { '' }
		}
	}
	return out
}

fn (mut c Checker) lint_vue_no_restricted_block(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() || c.vue_has_invalid_eof() {
		return []
	}
	sw := time.new_stopwatch()
	options := vue_no_restricted_block_options(c.rule_options(vue_no_restricted_block))!
	mut findings := []Finding{}
	doc := c.vue.doc
	for block in doc.nodes[0].children {
		node := &doc.nodes[block]
		if node.typ != .v_element {
			continue
		}
		stats.checked++
		raw_name := utf16_units(node.raw_name)
		for option in options {
			if !(option.test.test(raw_name) or { false }) {
				continue
			}
			message := if option.message != '' {
				option.message
			} else {
				'Using `<${node.raw_name}>` is not allowed.'
			}
			findings << c.vue_report_vnode(node.start_tag, 'restrictedBlock', {
				'message': message
			})
			break
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
