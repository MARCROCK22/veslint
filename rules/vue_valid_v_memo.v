module rules

import time
import vue

// Port of the `vue/valid-v-memo` rule of eslint-plugin-vue 10.12.1: a `v-memo` inside an element
// with `v-for` (not on it), with an argument, with modifiers, without a value, or whose value is
// (or ends in, through `=`, `as`, `,` and `?:`) an expression that cannot be an array.

const vvm_messages = {
	'unexpectedArgument': "'v-memo' directives require no argument."
	'unexpectedModifier': "'v-memo' directives require no modifier."
	'expectedValue':      "'v-memo' directives require that attribute value."
	'expectedArray':      "'v-memo' directives require the attribute value to be an array."
	'insideVFor':         "'v-memo' directive does not work inside 'v-for'."
}

fn (mut c Checker) lint_vue_valid_v_memo(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut v_for_element := -1
	for step in c.vue_template_steps() {
		if step.node.kind != .vnode {
			continue
		}
		i := step.node.v
		node := &c.vue.doc.nodes[i]
		if node.typ == .v_element {
			if step.leave {
				if v_for_element == i {
					v_for_element = -1
				}
			} else if v_for_element < 0 && c.vue_has_directive(i, 'for', none) {
				v_for_element = i
			}
			continue
		}
		if step.leave || !c.vue_is_directive(i, 'memo') {
			continue
		}
		stats.checked++
		key := &c.vue.doc.nodes[node.key]
		if v_for_element >= 0 && v_for_element != c.vue_attribute_element(i) {
			findings << c.vue_report_vnode(node.key, 'insideVFor', {})
		}
		if key.argument >= 0 {
			findings << c.vue_report_vnode(key.argument, 'unexpectedArgument', {})
		}
		if key.modifiers.len > 0 {
			first_start, _ := c.vue_vnode_range(key.modifiers[0])
			_, last_end := c.vue_vnode_range(key.modifiers.last())
			findings << c.vue_report(first_start, last_end, 'unexpectedModifier', {})
		}
		if node.value < 0 || c.vue_is_empty_value_directive(i) {
			findings << c.vue_report_vnode(i, 'expectedValue', {})
			continue
		}
		e := c.vue_container_expression(node.value)
		if e.is_null() {
			continue
		}
		mut stack := [e]
		for stack.len > 0 {
			expression := stack.pop()
			c.vvm_verify(expression, mut stack, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vvm_verify is verifyMemoExpression.
fn (c &Checker) vvm_verify(e vue.Expr, mut stack []vue.Expr, mut findings []Finding) {
	if e.kind != .estree {
		return
	}
	es := c.vue_expr_es(e)
	sub := fn [e] (node int) vue.Expr {
		return vue.Expr{
			kind:    .estree
			snippet: e.snippet
			node:    node
		}
	}
	match es.typ(e.node) {
		.object_expression, .class_expression, .arrow_function_expression, .function_expression,
		.literal, .template_literal, .unary_expression, .binary_expression, .update_expression {
			start, end := c.vue_expr_range(e)
			findings << c.vue_report(start, end, 'expectedArray', {})
		}
		.assignment_expression {
			if right := es.node(e.node, .right) {
				stack << sub(right)
			}
		}
		.ts_as_expression {
			if inner := es.node(e.node, .expression) {
				stack << sub(inner)
			}
		}
		.sequence_expression {
			expressions := es.list(e.node, .expressions) or { []int{} }
			if expressions.len > 0 {
				stack << sub(expressions.last())
			}
		}
		.conditional_expression {
			if consequent := es.node(e.node, .consequent) {
				stack << sub(consequent)
			}
			if alternate := es.node(e.node, .alternate) {
				stack << sub(alternate)
			}
		}
		else {}
	}
}
