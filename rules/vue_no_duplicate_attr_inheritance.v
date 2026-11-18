module rules

import json2
import time

// Port of the `vue/no-duplicate-attr-inheritance` rule of eslint-plugin-vue 10.12.1 (option
// checkMultiRootNodes, default false): `v-bind="$attrs"` (a reference to `$attrs` no element
// defines, in a v-bind without argument) while `inheritAttrs` is not set to a falsy literal by the
// last Vue object or defineOptions of the script; unless checkMultiRootNodes, not when the
// template has several root elements that are not one v-if chain.

const vue_no_duplicate_attr_inheritance_messages = {
	'noDuplicateAttrInheritance': 'Set "inheritAttrs" to false.'
}

fn vndai_options(options []json2.Any) !bool {
	o := option_object(vue_no_duplicate_attr_inheritance, options, ['checkMultiRootNodes'])!
	return o.bool_value('checkMultiRootNodes')!
}

fn (mut c Checker) lint_vue_no_duplicate_attr_inheritance(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	check_multi_root_nodes := vndai_options(c.rule_options(vue_no_duplicate_attr_inheritance))!
	mut findings := []Finding{}
	// The template is traversed at Program:exit: the script has set inheritAttrs by then.
	mut inherit_attrs := true
	if t := c.es_tree(root, abs_path) {
		for object in c.vue_options_objects(root, abs_path, true) {
			prop := vue_find_property(t, object, 'inheritAttrs', none)
			if prop < 0 {
				continue
			}
			value := vue_property_value(t, prop)
			if t.typ(value) == .literal {
				inherit_attrs = vue_literal_truthy(t, value)
			}
		}
	}
	if !inherit_attrs {
		return findings
	}
	doc := c.vue.doc
	mut refs := []int{}
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		// VAttribute[directive=true][key.name.name='bind'][key.argument=null] > VExpressionContainer
		if node.typ != .v_expression_container || node.parent < 0 {
			continue
		}
		attr := &doc.nodes[node.parent]
		if attr.typ != .v_attribute || !attr.directive || c.vue_directive_name(node.parent) != 'bind'
			|| doc.nodes[attr.key].argument >= 0 {
			continue
		}
		for r in node.references {
			if doc.references[r].variable < 0 && doc.references[r].name == r'$attrs' {
				refs << r
				break
			}
		}
	}
	roots := doc.nodes[doc.template_body].children.filter(doc.nodes[it].typ == .v_element)
	if !check_multi_root_nodes && roots.len > 1 && !c.vndai_is_conditional_group(roots) {
		return findings
	}
	for r in refs {
		stats.checked++
		start, end := c.vue_expr_range(doc.references[r].id)
		findings << c.vue_report(start, end, 'noDuplicateAttrInheritance', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vndai_is_conditional_group is isConditionalGroup: a v-if, v-else-ifs and a last v-else-if or
// v-else.
fn (c &Checker) vndai_is_conditional_group(elements []int) bool {
	if elements.len < 2 {
		return false
	}
	last := elements.last()
	return c.vue_has_directive(elements[0], 'if', none)
		&& (c.vue_has_directive(last, 'else-if', none) || c.vue_has_directive(last, 'else', none))
		&& elements[1..elements.len - 1].all(c.vue_has_directive(it, 'else-if', none))
}
