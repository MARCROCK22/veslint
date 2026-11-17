module rules

import time

// Port of the `vue/no-multiple-objects-in-class` rule of eslint-plugin-vue 10.12.1 (no options): a
// `v-bind:class` whose value is an array with more than one object.

const vnmoic_messages = {
	'unexpected': 'Unexpected multiple objects. Merge objects.'
}

fn (mut c Checker) lint_vue_no_multiple_objects_in_class(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VAttribute[directive=true][key.argument.name="class"][key.name.name="bind"][value.expression.type="ArrayExpression"]`
		if !c.vue_is_directive(i, 'bind') {
			continue
		}
		argument := c.vue_directive_argument(i)
		if argument < 0 || c.vue.doc.nodes[argument].name != 'class' {
			continue
		}
		e := c.vue_container_expression(c.vue.doc.nodes[i].value)
		if c.vue_expr_type(e) != 'ArrayExpression' {
			continue
		}
		stats.checked++
		es := &c.vue.doc.snippets[e.snippet].es
		elements := es.list(e.node, .elements) or { []int{} }
		if elements.filter(it >= 0 && es.typ(it).type_name() == 'ObjectExpression').len > 1 {
			findings << c.vue_report_vnode(i, 'unexpected', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
