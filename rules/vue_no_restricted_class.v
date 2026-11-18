module rules

import estree
import json2
import time

// Port of the `vue/no-restricted-class` rule of eslint-plugin-vue 10.12.1 (options: class names or
// regular expressions as strings): a restricted class name in a static `class` attribute, or in
// the value of a `:class` (string literals, template literals, `+` concatenations, the keys of an
// object and the elements of an array).

const vnrc_messages = {
	'forbiddenClass': "'{{class}}' class is not allowed."
}

fn vnrc_options(options []json2.Any) !VueRegexpGroup {
	mut patterns := []string{}
	for option in options {
		if option !is string {
			return error('the options of `${vue_no_restricted_class}` must be strings')
		}
		patterns << option as string
	}
	return vue_regexp_group(patterns)!
}

// VnrcClassName is a class name and the node (of the snippet) it is reported on.
struct VnrcClassName {
	name string
	node int
}

// vnrc_literal_string is String(node.value) of a Literal.
fn vnrc_literal_string(es &estree.EsTree, node int) string {
	v := es.get(node, .value)
	return match v {
		string { v }
		f64 { js_number_to_string(v) }
		bool { v.str() }
		estree.BigIntValue { es.string_of(node, .bigint) or { '' } }
		estree.RegExpValue { vue_tpl_string_literal_value(es, node, false) or { '' } }
		else { 'null' }
	}
}

// vnrc_extract is extractClassNames.
fn vnrc_extract(es &estree.EsTree, node int, text_only bool, mut out []VnrcClassName) {
	match es.typ(node) {
		.literal {
			for name in vue_split_whitespace(vnrc_literal_string(es, node)) {
				out << VnrcClassName{name, node}
			}
		}
		.template_literal {
			for quasi in es.list(node, .quasis) or { []int{} } {
				v := es.get(quasi, .value)
				cooked := if v is estree.TemplateValue { v.cooked } else { '' }
				for name in vue_split_whitespace(cooked) {
					out << VnrcClassName{name, quasi}
				}
			}
			for expr in es.list(node, .expressions) or { []int{} } {
				vnrc_extract(es, expr, true, mut out)
			}
		}
		.binary_expression {
			if (es.string_of(node, .operator) or { '' }) != '+' {
				return
			}
			vnrc_extract(es, es.node(node, .left) or { return }, true, mut out)
			vnrc_extract(es, es.node(node, .right) or { return }, true, mut out)
		}
		.object_expression {
			if text_only {
				return
			}
			for prop in es.list(node, .properties) or { []int{} } {
				if es.typ(prop) != .property {
					continue
				}
				prop_names := vue_tpl_static_property_name(es, prop) or { continue }
				if prop_names == '' {
					continue
				}
				key := es.node(prop, .key) or { continue }
				for name in vue_split_whitespace(prop_names) {
					out << VnrcClassName{name, key}
				}
			}
		}
		.array_expression {
			if text_only {
				return
			}
			for element in es.list(node, .elements) or { []int{} } {
				if element < 0 || es.typ(element) == .spread_element {
					continue
				}
				vnrc_extract(es, element, false, mut out)
			}
		}
		else {}
	}
}

fn (mut c Checker) lint_vue_no_restricted_class(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	forbidden := vnrc_options(c.rule_options(vue_no_restricted_class))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		if !node.directive {
			if c.vue.doc.nodes[node.key].name != 'class' || node.value < 0 {
				continue
			}
			stats.checked++
			for name in vue_split_whitespace(c.vue.doc.nodes[node.value].text) {
				if forbidden.matches(name) {
					findings << c.vue_report_vnode(node.value, 'forbiddenClass', {
						'class': name
					})
				}
			}
			continue
		}
		if !c.vue_is_directive(i, 'bind') || node.value < 0 {
			continue
		}
		argument := c.vue_static_argument(i) or { continue }
		if argument != 'class' {
			continue
		}
		stats.checked++
		e := c.vue_container_expression(node.value)
		if e.kind != .estree {
			continue
		}
		es := c.vue_expr_es(e)
		mut class_names := []VnrcClassName{}
		vnrc_extract(es, e.node, false, mut class_names)
		for n in class_names {
			if forbidden.matches(n.name) {
				findings << c.vue_report(es.nodes[n.node].start, es.nodes[n.node].end, 'forbiddenClass',
					{
						'class': n.name
					})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
