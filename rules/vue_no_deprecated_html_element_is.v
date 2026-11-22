module rules

import time

// Port of the `vue/no-deprecated-html-element-is` rule of eslint-plugin-vue 10.12.1 (no options): a
// `:is` or an `is` (unless its value starts with `vue:`) on a well-known HTML, SVG or MathML
// element.

const vndhei_messages = {
	'unexpected': 'The `is` attribute on HTML element are deprecated.'
}

// vndhei_is_valid_element is isValidElement: not a well-known element name.
fn (c &Checker) vndhei_is_valid_element(element int) bool {
	raw := c.vue.doc.nodes[element].raw_name
	return !vue_is_html_well_known_element_name(raw) && !vue_is_svg_well_known_element_name(raw)
		&& !vue_is_math_well_known_element_name(raw)
}

fn (mut c Checker) lint_vue_no_deprecated_html_element_is(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
		if node.directive {
			// `[key.name.name='bind'][key.argument.name='is']`
			argument := c.vue_directive_argument(i)
			if c.vue_directive_name(i) != 'bind' || argument < 0
				|| c.vue.doc.nodes[argument].name != 'is' {
				continue
			}
			stats.checked++
			if !c.vndhei_is_valid_element(c.vue_attribute_element(i)) {
				findings << c.vue_report_vnode(i, 'unexpected', {})
			}
			continue
		}
		if c.vue.doc.nodes[node.key].name != 'is' {
			continue
		}
		stats.checked++
		if c.vndhei_is_valid_element(c.vue_attribute_element(i))
			|| (node.value >= 0 && c.vue.doc.nodes[node.value].text.starts_with('vue:')) {
			continue
		}
		findings << c.vue_report_vnode(i, 'unexpected', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
