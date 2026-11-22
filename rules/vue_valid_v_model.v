module rules

import estree
import time

// Port of the `vue/valid-v-model` rule of eslint-plugin-vue 10.12.1: a `v-model` on an element that
// does not support it, on a file input, with an argument or a modifier other than lazy, number
// and trim (not on a custom component), without a value, whose value is an optional chain, not a
// left-hand side or a member of a possibly null object, or the iteration variable itself.

const vvmod_messages = {
	'unexpectedInvalidElement':          "'v-model' directives aren't supported on <{{name}}> elements."
	'unexpectedInputFile':               "'v-model' directives don't support 'file' input type."
	'unexpectedArgument':                "'v-model' directives require no argument."
	'unexpectedModifier':                "'v-model' directives don't support the modifier '{{name}}'."
	'missingValue':                      "'v-model' directives require that attribute value."
	'unexpectedOptionalChaining':        "Optional chaining cannot appear in 'v-model' directives."
	'unexpectedNonLhsExpression':        "'v-model' directives require the attribute value which is valid as LHS."
	'unexpectedNullObject':              "'v-model' directive has potential null object property access."
	'unexpectedUpdateIterationVariable': "'v-model' directives cannot update the iteration variable '{{varName}}' itself."
}

fn vvmod_is_lhs(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.ts_as_expression, .ts_non_null_expression {
			inner := t.node(node, .expression) or { return false }
			vvmod_is_lhs(t, inner)
		}
		.identifier, .member_expression {
			true
		}
		else {
			false
		}
	}
}

fn vvmod_maybe_null_member(t &estree.EsTree, node int) bool {
	if t.typ(node) != .member_expression {
		return false
	}
	object := t.node(node, .object) or { return false }
	match t.typ(object) {
		.chain_expression {
			return true
		}
		.literal {
			if _ := t.prop(object, .bigint) {
				return false
			}
			return t.get(object, .value) is estree.Null
		}
		.member_expression {
			return vvmod_maybe_null_member(t, object)
		}
		else {
			return false
		}
	}
}

fn (c &Checker) vvmod_valid_element(element int) bool {
	name := c.vue.doc.nodes[element].name
	return name in ['input', 'select', 'textarea']
		|| (name !in ['keep-alive', 'slot', 'transition', 'transition-group']
			&& c.vue_is_custom_component(element, false))
}

// vvmod_has_variable is getVariable: a variable named `name` on the element or an ancestor below
// the document.
fn (c &Checker) vvmod_has_variable(name string, leaf int) bool {
	mut node := leaf
	for node >= 0 {
		for v in c.vue.doc.nodes[node].variables {
			if c.vue.doc.variables[v].name == name {
				return true
			}
		}
		parent := c.vue.doc.nodes[node].parent
		if parent < 0 || c.vue.doc.nodes[parent].typ == .v_document_fragment {
			break
		}
		node = parent
	}
	return false
}

fn (mut c Checker) lint_vue_valid_v_model(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !node.directive || c.vue_directive_name(i) != 'model' {
			continue
		}
		stats.checked++
		element := c.vue_attribute_element(i)
		name := c.vue.doc.nodes[element].name
		if !c.vvmod_valid_element(element) {
			findings << c.vue_report_vnode(i, 'unexpectedInvalidElement', {
				'name': name
			})
		}
		if name == 'input' && c.vue_has_attribute(element, 'type', 'file') {
			findings << c.vue_report_vnode(i, 'unexpectedInputFile', map[string]string{})
		}
		if !c.vue_is_custom_component(element, false) {
			key := &c.vue.doc.nodes[node.key]
			if key.argument >= 0 {
				findings << c.vue_report_vnode(key.argument, 'unexpectedArgument', map[string]string{})
			}
			for m in key.modifiers {
				modifier := c.vue.doc.nodes[m].name
				if modifier !in ['lazy', 'number', 'trim'] {
					findings << c.vue_report_vnode(m, 'unexpectedModifier', {
						'name': modifier
					})
				}
			}
		}
		if node.value < 0 || c.vue_is_empty_value_directive(i) {
			findings << c.vue_report_vnode(i, 'missingValue', map[string]string{})
			continue
		}
		container := &c.vue.doc.nodes[node.value]
		e := container.expression
		if e.is_null() {
			continue
		}
		e_start, e_end := c.vue_expr_range(e)
		if e.kind == .estree {
			t := c.vue_expr_es(e)
			mut optional_member := false
			if t.typ(e.node) == .chain_expression {
				inner := t.node(e.node, .expression) or { -1 }
				optional_member = inner >= 0 && t.typ(inner) == .member_expression
			}
			if optional_member {
				findings << c.vue_report(e_start, e_end, 'unexpectedOptionalChaining', map[string]string{})
			} else if !vvmod_is_lhs(t, e.node) {
				findings << c.vue_report(e_start, e_end, 'unexpectedNonLhsExpression', map[string]string{})
			} else if vvmod_maybe_null_member(t, e.node) {
				findings << c.vue_report(e_start, e_end, 'unexpectedNullObject', map[string]string{})
			}
		} else {
			findings << c.vue_report(e_start, e_end, 'unexpectedNonLhsExpression', map[string]string{})
		}
		for r in container.references {
			reference := c.vue.doc.references[r]
			// `id.parent.type === 'VExpressionContainer'`: the identifier is the whole expression.
			if reference.id.kind != .estree || reference.id.snippet != e.snippet
				|| reference.id.node != e.node || e.kind != .estree {
				continue
			}
			if c.vvmod_has_variable(reference.name, element) {
				findings << c.vue_report(e_start, e_end, 'unexpectedUpdateIterationVariable', {
					'varName': reference.name
				})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
