module rules

import json2
import time

// Port of the `vue/enforce-style-attribute` rule of eslint-plugin-vue 10.12.1 (option `allow`:
// some of "plain", "scoped" and "module", by default ["scoped"]): the first top-level `<style>`
// whose kind (`scoped`, `module` or neither) is not allowed.

const vue_enforce_style_attribute_messages = {
	'notAllowedScoped': 'The scoped attribute is not allowed. Allowed: {{ allowedAttrsString }}.'
	'notAllowedModule': 'The module attribute is not allowed. Allowed: {{ allowedAttrsString }}.'
	'notAllowedPlain':  'Plain <style> tags are not allowed. Allowed: {{ allowedAttrsString }}.'
}

fn vue_enforce_style_attribute_options(options []json2.Any) ![]string {
	o := option_object(vue_enforce_style_attribute, options, ['allow'])!
	allow := o.string_list('allow')!
	return if allow.len > 0 { allow } else { ['scoped'] }
}

fn (mut c Checker) lint_vue_enforce_style_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	allowed := vue_enforce_style_attribute_options(c.rule_options(vue_enforce_style_attribute))!
	mut findings := []Finding{}
	doc := c.vue.doc
	mut sorted := allowed.clone()
	sorted.sort()
	data := {
		'allowedAttrsString': sorted.join(', ')
	}
	for child in doc.nodes[0].children {
		if doc.nodes[child].typ != .v_element || doc.nodes[child].raw_name != 'style' {
			continue
		}
		stats.checked++
		scoped := doc.has_plain_attribute(child, 'scoped')
		module := doc.has_plain_attribute(child, 'module')
		message_id := if 'plain' !in allowed && !scoped && !module {
			'notAllowedPlain'
		} else if 'scoped' !in allowed && scoped {
			'notAllowedScoped'
		} else if 'module' !in allowed && module {
			'notAllowedModule'
		} else {
			''
		}
		if message_id != '' {
			findings << c.vue_report_vnode(child, message_id, data)
			break
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
