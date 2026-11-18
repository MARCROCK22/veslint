module rules

import time

// Port of the `vue/no-negated-v-if-condition` rule of eslint-plugin-vue 10.12.1: a `v-if` or
// `v-else-if` whose condition is `!x`, `a != b` or `a !== b` on an element the next sibling
// element of which has `v-else`, fixed by swapping the two elements, the condition turned around
// and the directives exchanged.

const vnvic_messages = {
	'negatedCondition': 'Unexpected negated condition in v-if with v-else.'
}

// vnvic_next_sibling is getNextSibling: the next element among the parent's children.
fn (c &Checker) vnvic_next_sibling(element int) int {
	parent := c.vue.doc.nodes[element].parent
	if parent < 0 {
		return -1
	}
	siblings := c.vue.doc.nodes[parent].children
	idx := siblings.index(element)
	if idx < 0 {
		return -1
	}
	for k := idx + 1; k < siblings.len; k++ {
		if c.vue.doc.nodes[siblings[k]].typ == .v_element {
			return siblings[k]
		}
	}
	return -1
}

// vnvic_directive is getDirective: the first v-if, v-else-if or v-else of the element.
fn (c &Checker) vnvic_directive(element int) int {
	for a in c.vue_attributes(element) {
		if c.vue.doc.nodes[a].directive && c.vue_directive_name(a) in ['if', 'else-if', 'else'] {
			return a
		}
	}
	return -1
}

fn (mut c Checker) lint_vue_no_negated_v_if_condition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut processed := map[string]bool{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !node.directive || c.vue_directive_name(i) !in [
			'if',
			'else-if',
		] {
			continue
		}
		if node.value < 0 {
			continue
		}
		e := c.vue.doc.nodes[node.value].expression
		if e.kind == .null {
			continue
		}
		stats.checked++
		if e.kind != .estree {
			continue
		}
		t := c.vue_expr_es(e)
		typ := t.typ(e.node)
		operator := t.string_of(e.node, .operator) or { '' }
		negated := (typ == .unary_expression && operator == '!')
			|| (typ == .binary_expression && operator in ['!=', '!=='])
		if !negated {
			continue
		}
		element := c.vue_attribute_element(i)
		else_element := c.vnvic_next_sibling(element)
		if else_element < 0 || !c.vue_has_directive(else_element, 'else', none) {
			continue
		}
		key := '${element}-${else_element}'
		if key in processed {
			continue
		}
		processed[key] = true
		expr_start, expr_end := c.vue_expr_range(e)
		finding := c.vue_report(expr_start, expr_end, 'negatedCondition', map[string]string{})
		if_dir := c.vnvic_directive(element)
		else_dir := c.vnvic_directive(else_element)
		if if_dir < 0 || else_dir < 0 {
			findings << finding
			continue
		}
		src := c.vue.doc.src
		mut converted := c.vue_text(expr_start, expr_end)
		if typ == .unary_expression {
			converted = c.vue_text(expr_start + 1, expr_end)
		} else {
			left := t.node(e.node, .left) or { -1 }
			right := t.node(e.node, .right) or { -1 }
			if left >= 0 && right >= 0 {
				left_text := c.vue_text(t.nodes[left].start, t.nodes[left].end)
				right_text := c.vue_text(t.nodes[right].start, t.nodes[right].end)
				converted = if operator == '!=' {
					'${left_text} == ${right_text}'
				} else {
					'${left_text} === ${right_text}'
				}
			}
		}
		el := c.vue.doc.nodes[element]
		else_el := c.vue.doc.nodes[else_element]
		ifd := c.vue.doc.nodes[if_dir]
		elsed := c.vue.doc.nodes[else_dir]
		new_if := src[else_el.start..elsed.start] + 'v-${c.vue_directive_name(if_dir)}="${converted}"' +
			src[elsed.end..else_el.end]
		new_else := src[el.start..ifd.start] + 'v-else' + src[ifd.end..el.end]
		findings << c.with_fixes(finding, [
			fix_replace_range(el.start, el.end, new_if),
			fix_replace_range(else_el.start, else_el.end, new_else),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
