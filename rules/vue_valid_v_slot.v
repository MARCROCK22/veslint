module rules

import json2
import time
import vue

// Port of the `vue/valid-v-slot` rule of eslint-plugin-vue 10.12.1 (option `allowModifiers`): a
// `v-slot` not owned by a custom component, a named slot not on a `<template>`, a default slot on
// the component when `<template>`s have slots, several on one element or on sibling templates for
// the same slot (by name, and by the v-for variables a dynamic name uses), a dynamic name that uses
// the slot's own parameters, modifiers, and a default slot on the component without a value.

const vvslot_messages = {
	'ownerMustBeCustomElement':         "'v-slot' directive must be owned by a custom element, but '{{name}}' is not."
	'namedSlotMustBeOnTemplate':        "Named slots must use '<template>' on a custom element."
	'defaultSlotMustBeOnTemplate':      "Default slot must use '<template>' on a custom element when there are other named slots."
	'disallowDuplicateSlotsOnElement':  "An element cannot have multiple 'v-slot' directives."
	'disallowDuplicateSlotsOnChildren': "An element cannot have multiple '<template>' elements which are distributed to the same slot."
	'disallowArgumentUseSlotParams':    "Dynamic argument of 'v-slot' directive cannot use that slot parameter."
	'disallowAnyModifier':              "'v-slot' directive doesn't support any modifier."
	'requireAttributeValue':            "'v-slot' directive on a custom element requires that attribute value."
}

fn vvslot_options(options []json2.Any) !bool {
	o := option_object(vue_valid_v_slot, options, ['allowModifiers'])!
	return o.bool_value('allowModifiers')!
}

// VvslotVFor is VSlotVForVariables: the VForExpression node and the v-for variables the slot's
// dynamic name uses.
struct VvslotVFor {
	expr      int
	variables []int
}

// vvslot_child_groups is getSlotDirectivesOnChildren: by chain of child elements, the v-slot of
// the `<template>`s.
fn (c &Checker) vvslot_child_groups(owner int) [][]int {
	mut groups := [][]int{}
	for chain in c.vue_child_element_chains(owner) {
		mut dirs := []int{}
		for child in chain {
			if c.vue.doc.nodes[child].name == 'template' {
				d := c.vue_get_directive(child, 'slot', none)
				if d >= 0 {
					dirs << d
				}
			}
		}
		if dirs.len > 0 {
			groups << dirs
		}
	}
	return groups
}

// vvslot_name is getNormalizedName.
fn (c &Checker) vvslot_name(slot int) string {
	key := &c.vue.doc.nodes[c.vue.doc.nodes[slot].key]
	if key.argument < 0 {
		return 'default'
	}
	argument := &c.vue.doc.nodes[key.argument]
	if key.modifiers.len == 0 {
		return c.vue_text(argument.start, argument.end)
	}
	return c.vue_text(argument.start, key.end)
}

// vvslot_using_vars is getUsingIterationVars: the v-for variables (defined in the element's start
// tag) the dynamic argument refers to.
fn (c &Checker) vvslot_using_vars(slot int, element int) []int {
	key := &c.vue.doc.nodes[c.vue.doc.nodes[slot].key]
	mut out := []int{}
	if key.argument < 0 || c.vue.doc.nodes[key.argument].typ != .v_expression_container {
		return out
	}
	start_tag := &c.vue.doc.nodes[c.vue.doc.nodes[element].start_tag]
	for r in c.vue.doc.nodes[key.argument].references {
		v := c.vue.doc.references[r].variable
		if v < 0 {
			continue
		}
		variable := c.vue.doc.variables[v]
		id_start, id_end := c.vue_expr_range(variable.id)
		if variable.kind == 'v-for' && id_start > start_tag.start && id_end < start_tag.end {
			out << v
		}
	}
	return out
}

// vvslot_vfor is getVSlotVForVariableIfUsingIterationVars.
fn (c &Checker) vvslot_vfor(slot int, v_for int) ?VvslotVFor {
	if v_for < 0 {
		return none
	}
	value := c.vue.doc.nodes[v_for].value
	if value < 0 {
		return none
	}
	e := c.vue.doc.nodes[value].expression
	if e.kind != .vnode || c.vue.doc.nodes[e.node].typ != .v_for_expression {
		return none
	}
	vars := c.vvslot_using_vars(slot, c.vue_attribute_element(slot))
	if vars.len == 0 {
		return none
	}
	return VvslotVFor{
		expr:      e.node
		variables: vars
	}
}

fn (c &Checker) vvslot_expr_equal(a vue.Expr, b vue.Expr) bool {
	if a.is_null() || b.is_null() {
		return a.is_null() && b.is_null()
	}
	if c.vue_expr_type(a) != c.vue_expr_type(b) {
		return false
	}
	a_start, a_end := c.vue_expr_range(a)
	b_start, b_end := c.vue_expr_range(b)
	return c.vue_equal_tokens(a_start, a_end, b_start, b_end)
}

// vvslot_var_in is `variables.find((v) => utils.isInRange(ptn, v.id))`.
fn (c &Checker) vvslot_var_in(ptn vue.Expr, variables []int) int {
	if ptn.is_null() {
		return -1
	}
	p_start, p_end := c.vue_expr_range(ptn)
	for v in variables {
		s, e := c.vue_expr_range(c.vue.doc.variables[v].id)
		if p_start <= s && e <= p_end {
			return v
		}
	}
	return -1
}

// vvslot_vfor_equal is areVSlotVForVariablesEqual.
fn (c &Checker) vvslot_vfor_equal(a VvslotVFor, b VvslotVFor) bool {
	a_expr := &c.vue.doc.nodes[a.expr]
	b_expr := &c.vue.doc.nodes[b.expr]
	if a.variables.len != b.variables.len || !c.vvslot_expr_equal(a_expr.right, b_expr.right) {
		return false
	}
	mut checked := map[string]bool{}
	len := if a_expr.exprs.len < b_expr.exprs.len { a_expr.exprs.len } else { b_expr.exprs.len }
	for k in 0 .. len {
		a_ptn := a_expr.exprs[k]
		b_ptn := b_expr.exprs[k]
		a_var := c.vvslot_var_in(a_ptn, a.variables)
		b_var := c.vvslot_var_in(b_ptn, b.variables)
		if a_var >= 0 && b_var >= 0 {
			a_name := c.vue.doc.variables[a_var].name
			if a_name != c.vue.doc.variables[b_var].name || !c.vvslot_expr_equal(a_ptn, b_ptn) {
				return false
			}
			checked[a_name] = true
		} else if a_var >= 0 || b_var >= 0 {
			return false
		}
	}
	for v in a.variables {
		name := c.vue.doc.variables[v].name
		if name !in checked && !b.variables.any(c.vue.doc.variables[it].name == name) {
			return false
		}
	}
	return true
}

// vvslot_same_slot is filterSameSlot.
fn (c &Checker) vvslot_same_slot(groups [][]int, current int, current_vfor ?VvslotVFor) [][]int {
	name := c.vvslot_name(current)
	mut out := [][]int{}
	for group in groups {
		mut kept := []int{}
		for slot in group {
			if c.vvslot_name(slot) != name {
				continue
			}
			v_for := c.vue_get_directive(c.vue_attribute_element(slot), 'for', none)
			slot_vfor := c.vvslot_vfor(slot, v_for)
			same := if cur := current_vfor {
				if other := slot_vfor { c.vvslot_vfor_equal(cur, other) } else { false }
			} else {
				if _ := slot_vfor { false } else { true }
			}
			if same {
				kept << slot
			}
		}
		if kept.len > 0 {
			out << kept
		}
	}
	return out
}

// vvslot_uses_scope_var is isUsingScopeVar.
fn (c &Checker) vvslot_uses_scope_var(slot int) bool {
	node := &c.vue.doc.nodes[slot]
	key := &c.vue.doc.nodes[node.key]
	if key.argument < 0 || node.value < 0
		|| c.vue.doc.nodes[key.argument].typ != .v_expression_container {
		return false
	}
	value := &c.vue.doc.nodes[node.value]
	for r in c.vue.doc.nodes[key.argument].references {
		v := c.vue.doc.references[r].variable
		if v < 0 {
			continue
		}
		variable := c.vue.doc.variables[v]
		s, e := c.vue_expr_range(variable.id)
		if variable.kind == 'scope' && s > value.start && e < value.end {
			return true
		}
	}
	return false
}

fn (mut c Checker) lint_vue_valid_v_slot(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allow_modifiers := vvslot_options(c.rule_options(vue_valid_v_slot))!
	mut findings := []Finding{}
	none_data := map[string]string{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !node.directive || c.vue_directive_name(i) != 'slot' {
			continue
		}
		stats.checked++
		key := &c.vue.doc.nodes[node.key]
		is_default := key.argument < 0 || (c.vue.doc.nodes[key.argument].typ == .v_identifier
			&& c.vue.doc.nodes[key.argument].name == 'default')
		element := c.vue_attribute_element(i)
		el := &c.vue.doc.nodes[element]
		parent := el.parent
		owner := if el.name == 'template' { parent } else { element }
		if owner < 0 || c.vue.doc.nodes[owner].typ == .v_document_fragment {
			continue
		}
		on_element := c.vue_get_directives(element, 'slot')
		child_groups := c.vvslot_child_groups(owner)
		if !c.vue_is_custom_component(owner, false) {
			findings << c.vue_report_vnode(i, 'ownerMustBeCustomElement', {
				'name': c.vue.doc.nodes[owner].raw_name
			})
		}
		if !is_default && el.name != 'template' {
			findings << c.vue_report_vnode(i, 'namedSlotMustBeOnTemplate', none_data)
		}
		if owner == element && child_groups.len > 0 {
			findings << c.vue_report_vnode(i, 'defaultSlotMustBeOnTemplate', none_data)
		}
		if on_element.len >= 2 && on_element[0] != i {
			findings << c.vue_report_vnode(i, 'disallowDuplicateSlotsOnElement', none_data)
		}
		if owner == parent {
			v_for := c.vue_get_directive(element, 'for', none)
			slot_vfor := c.vvslot_vfor(i, v_for)
			same := c.vvslot_same_slot(child_groups, i, slot_vfor)
			if same.len >= 2 && i !in same[0] {
				findings << c.vue_report_vnode(i, 'disallowDuplicateSlotsOnChildren', none_data)
			}
			has_slot_vfor := if _ := slot_vfor { true } else { false }
			if v_for >= 0 && !has_slot_vfor {
				findings << c.vue_report_vnode(i, 'disallowDuplicateSlotsOnChildren', none_data)
			}
		}
		if c.vvslot_uses_scope_var(i) {
			findings << c.vue_report_vnode(i, 'disallowArgumentUseSlotParams', none_data)
		}
		if key.modifiers.len > 0 {
			invalid := if allow_modifiers { key.argument < 0 } else { true }
			if invalid {
				first := c.vue.doc.nodes[key.modifiers[0]]
				last := c.vue.doc.nodes[key.modifiers.last()]
				findings << c.vue_report(first.start, last.end, 'disallowAnyModifier', none_data)
			}
		}
		if owner == element && is_default && (node.value < 0 || c.vue_is_empty_value_directive(i)
			|| c.vue_is_empty_expression_value_directive(i)) {
			findings << c.vue_report_vnode(i, 'requireAttributeValue', none_data)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
