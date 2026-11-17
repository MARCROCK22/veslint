module rules

import json2
import time

// Port of the `vue/no-use-v-if-with-v-for` rule of eslint-plugin-vue 10.12.1 (option
// `allowUsingIterationVar`, false by default): a `v-if` on an element with a `v-for`, which should
// be on a wrapper element, or, when its value uses a variable of the `v-for`, be a computed property
// that filters the array.

const vnuviwvf_messages = {
	'movedToWrapper':    "This 'v-if' should be moved to the wrapper element."
	'shouldUseComputed': "The '{{iteratorName}}' {{kind}} inside 'v-for' directive should be replaced with a computed property that returns filtered array instead. You should not mix 'v-for' with 'v-if'."
}

fn vnuviwvf_options(options []json2.Any) !bool {
	o := option_object(vue_no_use_v_if_with_v_for, options, ['allowUsingIterationVar'])!
	return o.bool_value('allowUsingIterationVar')!
}

// vnuviwvf_iteration_var is getVForUsingIterationVar: the first `v-for` variable of the element
// that a reference of the `v-if`'s value names (-1 if none).
fn (c &Checker) vnuviwvf_iteration_var(attr int) int {
	value := c.vue.doc.nodes[attr].value
	if value < 0 {
		return -1
	}
	element := c.vue_attribute_element(attr)
	for r in c.vue.doc.nodes[value].references {
		name := c.vue.doc.references[r].name
		for v in c.vue.doc.nodes[element].variables {
			variable := &c.vue.doc.variables[v]
			if variable.name == name && variable.kind == 'v-for' {
				return v
			}
		}
	}
	return -1
}

// vnuviwvf_for_expression is the VForExpression that declares a variable of the element: the value
// of the element's `v-for` whose range holds the variable's id.
fn (c &Checker) vnuviwvf_for_expression(element int, variable int) int {
	id_start, id_end := c.vue_expr_range(c.vue.doc.variables[variable].id)
	for a in c.vue_get_directives(element, 'for') {
		e := c.vue_container_expression(c.vue.doc.nodes[a].value)
		if e.kind != .vnode {
			continue
		}
		start, end := c.vue_vnode_range(e.node)
		if start <= id_start && id_end <= end {
			return e.node
		}
	}
	return -1
}

fn (mut c Checker) lint_vue_no_use_v_if_with_v_for(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allow_iteration_var := vnuviwvf_options(c.rule_options(vue_no_use_v_if_with_v_for))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'if') {
			continue
		}
		element := c.vue_attribute_element(i)
		if !c.vue_has_directive(element, 'for', none) {
			continue
		}
		stats.checked++
		variable := c.vnuviwvf_iteration_var(i)
		if variable < 0 {
			findings << c.vue_report_vnode(i, 'movedToWrapper', {})
			continue
		}
		if allow_iteration_var {
			continue
		}
		for_expression := c.vnuviwvf_for_expression(element, variable)
		if for_expression < 0 {
			continue
		}
		right := c.vue.doc.nodes[for_expression].right
		is_identifier := c.vue_expr_type(right) == 'Identifier'
		iterator_name := if is_identifier {
			c.vue.doc.snippets[right.snippet].es.string_of(right.node, .name) or { '' }
		} else {
			start, end := c.vue_expr_range(right)
			c.vue_text(start, end)
		}
		findings << c.vue_report_vnode(i, 'shouldUseComputed', {
			'iteratorName': iterator_name
			'kind':         if is_identifier { 'variable' } else { 'expression' }
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
