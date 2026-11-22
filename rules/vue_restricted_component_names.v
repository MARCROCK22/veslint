module rules

import json2
import time

// Port of the `vue/restricted-component-names` rule of eslint-plugin-vue 10.12.1 (option `allow`:
// names or regular expressions as strings): an element whose rawName is not an HTML, deprecated
// HTML or SVG element name, a built-in component of Vue 2 or 3, or allowed.

const vrcn_messages = {
	'invalidName': 'Component name "{{name}}" is not allowed.'
}

fn vrcn_options(options []json2.Any) !VueRegexpGroup {
	o := option_object(vue_restricted_component_names, options, ['allow'])!
	return vue_regexp_group(o.string_list('allow')!)!
}

fn (mut c Checker) lint_vue_restricted_component_names(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allowed := vrcn_options(c.rule_options(vue_restricted_component_names))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element {
			continue
		}
		stats.checked++
		name := node.raw_name
		if name in vue_html_element_names || name in vue_deprecated_html_element_names
			|| name in vue_svg_element_names || name in vue_builtin_component_names
			|| allowed.matches(name) {
			continue
		}
		findings << c.vue_report_vnode(i, 'invalidName', {
			'name': name
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
