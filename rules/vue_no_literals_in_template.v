module rules

import json2
import time

// Port of the `vue/no-literals-in-template` rule of eslint-plugin-vue 10.12.1 (option `ignores`:
// argument names or regular expressions as strings): the value of a `v-bind` (but `:class`,
// `:style` and the ignored arguments) that is an object, array, function or arrow function
// literal, unless it refers to a variable of an enclosing element (v-for, slot scope).

const vnlit_messages = {
	'unexpected': 'Unexpected {{type}} literal in template.'
}

fn vnlit_options(options []json2.Any) !VueRegexpGroup {
	o := option_object(vue_no_literals_in_template, options, ['ignores'])!
	return vue_regexp_group(o.string_list('ignores')!)!
}

fn vnlit_literal_type(typ string) string {
	return match typ {
		'ObjectExpression' { 'object' }
		'ArrayExpression' { 'array' }
		'FunctionExpression' { 'function' }
		'ArrowFunctionExpression' { 'arrow function' }
		else { '' }
	}
}

fn (mut c Checker) lint_vue_no_literals_in_template(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	ignored := vnlit_options(c.rule_options(vue_no_literals_in_template))!
	mut findings := []Finding{}
	// The elements entered and not left yet (upperElements).
	mut upper := []int{}
	for step in c.vue_template_steps() {
		if step.node.kind != .vnode {
			continue
		}
		i := step.node.v
		node := &c.vue.doc.nodes[i]
		if node.typ == .v_element {
			if step.leave {
				upper.pop()
			} else {
				upper << i
			}
			continue
		}
		if step.leave || !c.vue_is_directive(i, 'bind') {
			continue
		}
		stats.checked++
		e := c.vue_container_expression(node.value)
		if e.is_null() {
			continue
		}
		if argument := c.vue_static_argument(i) {
			if argument == 'class' || argument == 'style' || ignored.matches(argument) {
				continue
			}
		}
		typ := vnlit_literal_type(c.vue_expr_type(e))
		if typ == '' {
			continue
		}
		start, end := c.vue_expr_range(e)
		if c.vue_refers_to_upper_variable(upper, start, end) {
			continue
		}
		findings << c.vue_report(start, end, 'unexpected', {
			'type': typ
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
