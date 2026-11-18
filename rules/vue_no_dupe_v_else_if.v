module rules

import time
import vue

// Port of the `vue/no-dupe-v-else-if` rule of eslint-plugin-vue 10.12.1: the condition of a
// `v-else-if` (or one of its `&&` operands) that a previous condition of its `v-if` /
// `v-else-if` chain covers (as ESLint's no-dupe-else-if: equal tokens, `||` and `&&` commutative).

const vndvei_messages = {
	'unexpected': 'This branch can never execute. Its condition is a duplicate or covered by previous conditions in the `v-if` / `v-else-if` chain.'
}

// VndveiAnd is AndOperands: an operand of `||` and its `&&` operands.
struct VndveiAnd {
	node     vue.Expr
	operands []vue.Expr
}

// VndveiOr is OrOperands: a condition and its `||` operands.
struct VndveiOr {
	node vue.Expr
mut:
	operands []VndveiAnd
}

// vndvei_logical is the operator, left and right of a LogicalExpression, if `e` is one.
fn (c &Checker) vndvei_logical(e vue.Expr) ?(string, vue.Expr, vue.Expr) {
	if e.kind != .estree {
		return none
	}
	es := c.vue_expr_es(e)
	if es.typ(e.node) != .logical_expression {
		return none
	}
	left := es.node(e.node, .left)?
	right := es.node(e.node, .right)?
	return es.string_of(e.node, .operator)?, vue.Expr{
		kind:    .estree
		snippet: e.snippet
		node:    left
	}, vue.Expr{
		kind:    .estree
		snippet: e.snippet
		node:    right
	}
}

// vndvei_split is splitByLogicalOperator.
fn (c &Checker) vndvei_split(operator string, e vue.Expr) []vue.Expr {
	if op, left, right := c.vndvei_logical(e) {
		if op == operator {
			mut out := c.vndvei_split(operator, left)
			out << c.vndvei_split(operator, right)
			return out
		}
	}
	return [e]
}

// vndvei_build is buildOrOperands.
fn (c &Checker) vndvei_build(e vue.Expr) VndveiOr {
	return VndveiOr{
		node:     e
		operands: c.vndvei_split('||', e).map(VndveiAnd{
			node:     it
			operands: c.vndvei_split('&&', it)
		})
	}
}

// vndvei_equal is isEqual: the same type and the same tokens, or `||` / `&&` with the same
// operands in either order.
fn (c &Checker) vndvei_equal(a vue.Expr, b vue.Expr) bool {
	if c.vue_expr_type(a) != c.vue_expr_type(b) {
		return false
	}
	a_start, a_end := c.vue_expr_range(a)
	b_start, b_end := c.vue_expr_range(b)
	if c.vue_equal_tokens(a_start, a_end, b_start, b_end) {
		return true
	}
	a_op, a_left, a_right := c.vndvei_logical(a) or { return false }
	b_op, b_left, b_right := c.vndvei_logical(b) or { return false }
	return (a_op == '||' || a_op == '&&') && a_op == b_op
		&& ((c.vndvei_equal(a_left, b_left) && c.vndvei_equal(a_right, b_right))
			|| (c.vndvei_equal(a_left, b_right) && c.vndvei_equal(a_right, b_left)))
}

// vndvei_is_subset is isSubset: every operand of `a` equals one of `b`.
fn (c &Checker) vndvei_is_subset(a VndveiAnd, b VndveiAnd) bool {
	return a.operands.all(fn [c, b] (x vue.Expr) bool {
		return b.operands.any(c.vndvei_equal(x, it))
	})
}

fn (mut c Checker) lint_vue_no_dupe_v_else_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'else-if') {
			continue
		}
		test := c.vue_container_expression(c.vue.doc.nodes[i].value)
		if test.is_null() {
			continue
		}
		stats.checked++
		mut conditions := [test]
		if op, _, _ := c.vndvei_logical(test) {
			if op == '&&' {
				conditions = c.vndvei_split('&&', test)
				conditions << test
			}
		}
		mut list := conditions.map(c.vndvei_build(it))
		mut current := c.vue_attribute_element(i)
		chain: for {
			current = c.vue_prev_sibling(current)
			if current < 0 {
				break
			}
			v_if := c.vue_get_directive(current, 'if', none)
			dir := if v_if >= 0 { v_if } else { c.vue_get_directive(current, 'else-if', none) }
			if dir < 0 {
				break
			}
			current_test := c.vue_container_expression(c.vue.doc.nodes[dir].value)
			if !current_test.is_null() {
				current_or := c.vndvei_build(current_test)
				for mut condition in list {
					condition.operands = condition.operands.filter(fn [c, current_or] (or_operand VndveiAnd) bool {
						return current_or.operands.all(!c.vndvei_is_subset(it, or_operand))
					})
					if condition.operands.len == 0 {
						start, end := c.vue_expr_range(condition.node)
						findings << c.vue_report(start, end, 'unexpected', {})
						break chain
					}
				}
			}
			if v_if >= 0 {
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
