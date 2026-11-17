module rules

import time

// Port of the `vue/valid-attribute-name` rule of eslint-plugin-vue 10.12.1 (no options): on an
// element that is not a custom component, a plain attribute, or the static argument of a `v-bind`,
// whose name is not an XML Name (xml-name-validator's `name`).

const vvan_messages = {
	'attribute': 'Attribute name {{name}} is not valid.'
}

// vvan_is_name_start is NameStartChar (with `:`).
fn vvan_is_name_start(r rune) bool {
	return r == `:` || (r >= `A` && r <= `Z`) || r == `_` || (r >= `a` && r <= `z`)
		|| (r >= 0xc0 && r <= 0xd6) || (r >= 0xd8 && r <= 0xf6) || (r >= 0xf8 && r <= 0x2ff)
		|| (r >= 0x370 && r <= 0x37d) || (r >= 0x37f && r <= 0x1fff)
		|| (r >= 0x200c && r <= 0x200d) || (r >= 0x2070 && r <= 0x218f)
		|| (r >= 0x2c00 && r <= 0x2fef) || (r >= 0x3001 && r <= 0xd7ff)
		|| (r >= 0xf900 && r <= 0xfdcf) || (r >= 0xfdf0 && r <= 0xfffd)
		|| (r >= 0x10000 && r <= 0xeffff)
}

// vvan_is_xml_name is xml-name-validator's name(): /^NameStartChar NameChar*$/u.
fn vvan_is_xml_name(name string) bool {
	runes := name.runes()
	if runes.len == 0 || !vvan_is_name_start(runes[0]) {
		return false
	}
	for r in runes[1..] {
		if !(vvan_is_name_start(r) || r == `-` || r == `.` || (r >= `0` && r <= `9`) || r == 0xb7
			|| (r >= 0x300 && r <= 0x36f) || (r >= 0x203f && r <= 0x2040)) {
			return false
		}
	}
	return true
}

fn (mut c Checker) lint_vue_valid_attribute_name(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		stats.checked++
		if c.vue_is_custom_component(c.vue_attribute_element(i), false) {
			continue
		}
		if node.directive {
			if c.vue_directive_name(i) == 'bind' {
				if argument := c.vue_static_argument(i) {
					if !vvan_is_xml_name(argument) {
						findings << c.vue_report_vnode(i, 'attribute', {
							'name': argument
						})
					}
				}
			}
			continue
		}
		name := c.vue.doc.nodes[node.key].name
		if !vvan_is_xml_name(name) {
			findings << c.vue_report_vnode(i, 'attribute', {
				'name': name
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
