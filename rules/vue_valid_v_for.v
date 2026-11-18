module rules

import json2
import time
import vue

// Port of the `vue/valid-v-for` rule of eslint-plugin-vue 10.12.1 (option `allowEmptyAlias`): a
// `v-for` with an argument, modifiers, no value or not `<alias> in <expression>`, with empty or
// non-identifier aliases, and the `:key` of its element (or of a `<template>`'s children) that is
// missing on a custom component or does not use the variables of the `v-for`.

const vvfor_messages = {
	'requireKey':           "Custom elements in iteration require 'v-bind:key' directives."
	'keyUseFVorVars':       "Expected 'v-bind:key' directive to use the variables which are defined by the 'v-for' directive."
	'unexpectedArgument':   "'v-for' directives require no argument."
	'unexpectedModifier':   "'v-for' directives require no modifier."
	'expectedValue':        "'v-for' directives require that attribute value."
	'unexpectedExpression': "'v-for' directives require the special syntax '<alias> in <expression>'."
	'invalidEmptyAlias':    'Invalid empty alias.'
	'invalidAlias':         "Invalid alias '{{text}}'."
}

fn vvfor_options(options []json2.Any) !bool {
	o := option_object(vue_valid_v_for, options, ['allowEmptyAlias'])!
	return o.bool_value('allowEmptyAlias')!
}

// vvfor_uses_vars: one of the references is named like a v-for variable of the element of `v_for`.
fn (c &Checker) vvfor_uses_vars(v_for int, references []int) bool {
	element := c.vue_attribute_element(v_for)
	if element < 0 {
		return false
	}
	variables := c.vue.doc.nodes[element].variables
	for r in references {
		name := c.vue.doc.references[r].name
		for v in variables {
			variable := c.vue.doc.variables[v]
			if variable.name == name && variable.kind == 'v-for' {
				return true
			}
		}
	}
	return false
}

fn (c &Checker) vvfor_check_key(v_for int, element int, mut findings []Finding) {
	key := c.vue_get_directive(element, 'bind', 'key')
	el := &c.vue.doc.nodes[element]
	if key < 0 && el.name == 'template' {
		for child in el.children {
			if c.vue.doc.nodes[child].typ != .v_element {
				continue
			}
			child_for := c.vue_get_directive(child, 'for', none)
			if child_for >= 0 {
				value := c.vue.doc.nodes[child_for].value
				refs := if value >= 0 { c.vue.doc.nodes[value].references } else { []int{} }
				if c.vvfor_uses_vars(v_for, refs) {
					continue
				}
			}
			c.vvfor_check_key(v_for, child, mut findings)
		}
		return
	}
	if key < 0 && c.vue_is_custom_component(element, false) {
		findings << c.vue_report_vnode(el.start_tag, 'requireKey', map[string]string{})
	}
	if key >= 0 {
		value := c.vue.doc.nodes[key].value
		if value < 0 || !c.vvfor_uses_vars(v_for, c.vue.doc.nodes[value].references) {
			findings << c.vue_report_vnode(key, 'keyUseFVorVars', map[string]string{})
		}
	}
}

// vvfor_alias reports an alias (`key` or `index`) that is not an identifier (or is empty, unless
// allowed).
fn (c &Checker) vvfor_alias(alias vue.Expr, expr int, allow_empty bool, mut findings []Finding) {
	if alias.is_null() {
		if !allow_empty {
			findings << c.vue_report_vnode(expr, 'invalidEmptyAlias', map[string]string{})
		}
		return
	}
	if c.vue_expr_type(alias) == 'Identifier' {
		return
	}
	start, end := c.vue_expr_range(alias)
	findings << c.vue_report(start, end, 'invalidAlias', {
		'text': c.vue_text(start, end)
	})
}

fn (mut c Checker) lint_vue_valid_v_for(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allow_empty := vvfor_options(c.rule_options(vue_valid_v_for))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !node.directive || c.vue_directive_name(i) != 'for' {
			continue
		}
		stats.checked++
		c.vvfor_check_key(i, c.vue_attribute_element(i), mut findings)
		key := &c.vue.doc.nodes[node.key]
		if key.argument >= 0 {
			findings << c.vue_report_vnode(key.argument, 'unexpectedArgument', map[string]string{})
		}
		if key.modifiers.len > 0 {
			first := c.vue.doc.nodes[key.modifiers[0]]
			last := c.vue.doc.nodes[key.modifiers.last()]
			findings << c.vue_report(first.start, last.end, 'unexpectedModifier', map[string]string{})
		}
		if node.value < 0 || c.vue_is_empty_value_directive(i) {
			findings << c.vue_report_vnode(i, 'expectedValue', map[string]string{})
			continue
		}
		e := c.vue.doc.nodes[node.value].expression
		if e.is_null() {
			continue
		}
		if c.vue_expr_type(e) != 'VForExpression' {
			findings << c.vue_report_vnode(node.value, 'unexpectedExpression', map[string]string{})
			continue
		}
		lhs := c.vue.doc.nodes[e.node].exprs
		if lhs.len > 0 && lhs[0].is_null() && !allow_empty {
			findings << c.vue_report_vnode(e.node, 'invalidEmptyAlias', map[string]string{})
		}
		if lhs.len > 1 {
			c.vvfor_alias(lhs[1], e.node, allow_empty, mut findings)
		}
		if lhs.len > 2 {
			c.vvfor_alias(lhs[2], e.node, allow_empty, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
