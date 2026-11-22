module rules

import json2
import time

// Port of the `vue/no-static-inline-styles` rule of eslint-plugin-vue 10.12.1 (option
// `allowBinding`): a plain `style` attribute, and (without `allowBinding`) the static parts of a
// `:style` binding: the properties with a literal value and a plain key up to the first spread,
// computed key or object that is not all static, or the whole directive when every property is.

const vnsis_messages = {
	'forbiddenStaticInlineStyle': 'Static inline `style` are forbidden.'
	'forbiddenStyleAttr':         '`style` attributes are forbidden.'
}

fn vnsis_options(options []json2.Any) !bool {
	o := option_object(vue_no_static_inline_styles, options, ['allowBinding'])!
	return o.bool_value('allowBinding')!
}

fn (mut c Checker) lint_vue_no_static_inline_styles(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allow_binding := vnsis_options(c.rule_options(vue_no_static_inline_styles))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		if !node.directive {
			if c.vue.doc.nodes[node.key].name == 'style' {
				stats.checked++
				findings << c.vue_report_vnode(i, 'forbiddenStyleAttr', {})
			}
			continue
		}
		if allow_binding || !c.vue_is_directive(i, 'bind') {
			continue
		}
		argument := c.vue_static_argument(i) or { continue }
		if argument != 'style' {
			continue
		}
		stats.checked++
		for n in c.vnsis_report_nodes(i) {
			if n < 0 {
				findings << c.vue_report_vnode(i, 'forbiddenStaticInlineStyle', {})
				continue
			}
			e := c.vue_container_expression(node.value)
			prop := c.vue_expr_es(e).nodes[n]
			findings << c.vue_report(prop.start, prop.end, 'forbiddenStaticInlineStyle', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnsis_report_nodes is getReportNodes: the static Property nodes (of the snippet of the
// directive's expression), or [-1] for the whole directive.
fn (c &Checker) vnsis_report_nodes(directive int) []int {
	e := c.vue_container_expression(c.vue.doc.nodes[directive].value)
	if e.kind != .estree {
		return []
	}
	es := c.vue_expr_es(e)
	elements := match es.typ(e.node) {
		.object_expression { [e.node] }
		.array_expression { es.list(e.node, .elements) or { []int{} } }
		else { return [] }
	}
	mut static_properties := []int{}
	for element in elements {
		if element < 0 {
			continue
		}
		if es.typ(element) != .object_expression {
			return static_properties
		}
		mut all_static := true
		for prop in es.list(element, .properties) or { []int{} } {
			computed := es.flag(prop, .computed) or { false }
			if es.typ(prop) == .spread_element || computed {
				return static_properties
			}
			value := es.node(prop, .value) or { -1 }
			key := es.node(prop, .key) or { -1 }
			if value >= 0 && es.typ(value) == .literal && key >= 0
				&& es.typ(key) in [.identifier, .literal] {
				static_properties << prop
			} else {
				all_static = false
			}
		}
		if !all_static {
			return static_properties
		}
	}
	return [-1]
}
