module rules

import json2
import time
import vue

// Ports of the `vue/no-deprecated-slot-attribute` and `vue/no-deprecated-slot-scope-attribute`
// rules of eslint-plugin-vue 10.12.1 (lib/rules/syntaxes/slot-attribute.ts and
// slot-scope-attribute.ts, with syntaxes/utils/can-convert-to-v-slot.ts):
//
// no-deprecated-slot-attribute (options `ignore`, element names, and `ignoreParents`, names of the
// parent element, both names or regular expressions as strings): the key of a `slot` attribute or
// a `:slot`, fixed into a `v-slot` (on the element when it is a <template>, else on a <template>
// around it, which takes its `v-for` and its slot scope) when the element can use one.
//
// no-deprecated-slot-scope-attribute: the key of a `slot-scope`, fixed the same way when the
// element has no `slot` or `:slot` and can use a `v-slot`.

const vndslota_messages = {
	'forbiddenSlotAttribute': '`slot` attributes are deprecated.'
}

const vndslotsa_messages = {
	'forbiddenSlotScopeAttribute': '`slot-scope` are deprecated.'
}

// VueSlotVForVars is SlotVForVariables: the VForExpression of the element's `v-for` and its
// variables the `:slot` uses.
struct VueSlotVForVars {
	expr      int // the VForExpression
	variables []int
}

// VueSlotContext is SlotContext.
struct VueSlotContext {
	element         int
	slot            int // a `slot` attribute or a `:slot`, or -1
	v_for           int // the `v-for`, or -1
	has_v_for_vars  bool
	v_for_vars      VueSlotVForVars
	normalized_name string
}

// vue_slot_context is getSlotContext.
fn (c &Checker) vue_slot_context(element int) VueSlotContext {
	mut slot := c.vue_get_attribute(element, 'slot', none)
	if slot < 0 {
		slot = c.vue_get_directive(element, 'bind', 'slot')
	}
	v_for := c.vue_get_directive(element, 'for', none)
	mut has_vars := false
	mut vars := VueSlotVForVars{}
	// getSlotVForVariableIfUsingIterationVars
	if slot >= 0 && c.vue.doc.nodes[slot].directive && v_for >= 0 {
		e := c.vue_container_expression(c.vue.doc.nodes[v_for].value)
		if e.kind == .vnode && c.vue.doc.nodes[e.node].typ == .v_for_expression {
			used := c.vue_using_iteration_vars(c.vue.doc.nodes[slot].value, element)
			if used.len > 0 {
				has_vars = true
				vars = VueSlotVForVars{
					expr:      e.node
					variables: used
				}
			}
		}
	}
	// getNormalizedName
	mut name := 'default'
	if slot >= 0 {
		value := c.vue.doc.nodes[slot].value
		if !c.vue.doc.nodes[slot].directive {
			if value >= 0 {
				name = c.vue.doc.nodes[value].text
			}
		} else {
			name = if value >= 0 { '[${c.vue_vnode_text(value)}]' } else { '[null]' }
		}
	}
	return VueSlotContext{
		element:         element
		slot:            slot
		v_for:           v_for
		has_v_for_vars:  has_vars
		v_for_vars:      vars
		normalized_name: name
	}
}

// vue_using_iteration_vars is getUsingIterationVars: the `v-for` variables defined in the start
// tag of `element` that the expression container refers to.
fn (c &Checker) vue_using_iteration_vars(container int, element int) []int {
	mut out := []int{}
	if container < 0 || c.vue.doc.nodes[container].typ != .v_expression_container {
		return out
	}
	start_tag := &c.vue.doc.nodes[c.vue.doc.nodes[element].start_tag]
	for r in c.vue.doc.nodes[container].references {
		v := c.vue.doc.references[r].variable
		if v < 0 || c.vue.doc.variables[v].kind != 'v-for' {
			continue
		}
		start, end := c.vue_expr_range(c.vue.doc.variables[v].id)
		if start > start_tag.start && end < start_tag.end {
			out << v
		}
	}
	return out
}

// vue_can_convert_to_v_slot is canConvertToVSlot of can-convert-to-v-slot.ts.
fn (c &Checker) vue_can_convert_to_v_slot(element int) bool {
	owner := c.vue.doc.nodes[element].parent
	if owner < 0 || c.vue.doc.nodes[owner].typ != .v_element || !c.vue_is_custom_component(owner, false)
		|| c.vue.doc.nodes[owner].name == 'component' {
		return false
	}
	slot := c.vue_slot_context(element)
	return !(slot.v_for >= 0 && !slot.has_v_for_vars) && !c.vue_has_same_slot_directive(owner, slot)
}

// vue_has_same_slot_directive is hasSameSlotDirective.
fn (c &Checker) vue_has_same_slot_directive(owner int, target VueSlotContext) bool {
	for group in c.vue_child_element_chains(owner) {
		if target.element in group {
			continue
		}
		for child in group {
			slot := c.vue_slot_context(child)
			if !target.has_v_for_vars || !slot.has_v_for_vars {
				if !target.has_v_for_vars && !slot.has_v_for_vars
					&& target.normalized_name == slot.normalized_name {
					return true
				}
			} else if c.vue_slot_v_for_vars_equal(target.v_for_vars, slot.v_for_vars) {
				return true
			}
		}
	}
	return false
}

// vue_slot_expr_equal is isEqual: the same type and the same tokens.
fn (c &Checker) vue_slot_expr_equal(a vue.Expr, b vue.Expr) bool {
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

// vue_slot_v_for_vars_equal is areSlotVForVariablesEqual.
fn (c &Checker) vue_slot_v_for_vars_equal(a VueSlotVForVars, b VueSlotVForVars) bool {
	a_expr := &c.vue.doc.nodes[a.expr]
	b_expr := &c.vue.doc.nodes[b.expr]
	if a.variables.len != b.variables.len || !c.vue_slot_expr_equal(a_expr.right, b_expr.right) {
		return false
	}
	mut checked := map[string]bool{}
	n := if a_expr.exprs.len < b_expr.exprs.len { a_expr.exprs.len } else { b_expr.exprs.len }
	for index in 0 .. n {
		a_ptn := a_expr.exprs[index]
		b_ptn := b_expr.exprs[index]
		a_var := c.vue_variable_in(a.variables, a_ptn)
		b_var := c.vue_variable_in(b.variables, b_ptn)
		if a_var >= 0 && b_var >= 0 {
			if c.vue_variable_name(a_var) != c.vue_variable_name(b_var)
				|| !c.vue_slot_expr_equal(a_ptn, b_ptn) {
				return false
			}
			checked[c.vue_variable_name(a_var)] = true
		} else if a_var >= 0 || b_var >= 0 {
			return false
		}
	}
	b_names := b.variables.map(c.vue_variable_name(it))
	return a.variables.all(c.vue_variable_name(it) in checked || c.vue_variable_name(it) in b_names)
}

// vue_variable_in is the first of the variables whose identifier is inside the pattern (isInRange).
fn (c &Checker) vue_variable_in(variables []int, pattern vue.Expr) int {
	if pattern.is_null() {
		return -1
	}
	start, end := c.vue_expr_range(pattern)
	for v in variables {
		id_start, id_end := c.vue_expr_range(c.vue.doc.variables[v].id)
		if start <= id_start && id_end <= end {
			return v
		}
	}
	return -1
}

struct VndslotaOptions {
	ignore         VueRegexpGroup
	ignore_parents VueRegexpGroup
}

fn vndslota_options(options []json2.Any) !VndslotaOptions {
	o := option_object(vue_no_deprecated_slot_attribute, options, ['ignore', 'ignoreParents'])!
	return VndslotaOptions{
		ignore:         vue_regexp_group(o.string_list('ignore')!)!
		ignore_parents: vue_regexp_group(o.string_list('ignoreParents')!)!
	}
}

// vue_slot_name_ok is `!/[^\w\-]/u.test(name)`.
fn vue_slot_name_ok(name string) bool {
	return name.bytes().all(it.is_letter() || it.is_digit() || it == `_` || it == `-`)
}

fn (mut c Checker) lint_vue_no_deprecated_slot_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vndslota_options(c.rule_options(vue_no_deprecated_slot_attribute))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		is_v_bind := node.directive
		if is_v_bind {
			argument := c.vue_directive_argument(i)
			if c.vue_directive_name(i) != 'bind' || argument < 0
				|| c.vue.doc.nodes[argument].typ != .v_identifier
				|| c.vue.doc.nodes[argument].name != 'slot' {
				continue
			}
		} else if c.vue.doc.nodes[node.key].name != 'slot' {
			continue
		}
		stats.checked++
		// isIgnored
		component := c.vue_attribute_element(i)
		raw := c.vue.doc.nodes[component].raw_name
		if opts.ignore.matches(raw, vue_pascal_case(raw), vue_kebab_case(raw)) {
			continue
		}
		parent := c.vue.doc.nodes[component].parent
		if parent >= 0 && c.vue.doc.nodes[parent].typ == .v_element
			&& opts.ignore_parents.matches(c.vue.doc.nodes[parent].raw_name) {
			continue
		}
		report := c.vue_report_vnode(node.key, 'forbiddenSlotAttribute', {})
		mut slot_name := ''
		mut convertible := c.vue_can_convert_to_v_slot(component)
		if !is_v_bind {
			if node.value >= 0 {
				slot_name = c.vue.doc.nodes[node.value].text
				convertible = convertible && vue_slot_name_ok(slot_name)
			}
		} else if node.value >= 0 {
			e := c.vue_container_expression(node.value)
			convertible = convertible && c.vue_expr_type(e) == 'Identifier'
			if !e.is_null() {
				start, end := c.vue_expr_range(e)
				slot_name = js_trim(c.vue_text(start, end))
			}
		}
		if !convertible {
			findings << report
			continue
		}
		findings << c.with_fixes(report, c.vue_fix_slot_to_v_slot(i, slot_name, is_v_bind))!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_fix_slot_to_v_slot is fixSlotToVSlot.
fn (c &Checker) vue_fix_slot_to_v_slot(slot_attr int, slot_name string, is_v_bind bool) []Fix {
	start_tag := c.vue.doc.nodes[slot_attr].parent
	mut scope_attr := -1
	for a in c.vue.doc.nodes[start_tag].attributes {
		if c.vue.doc.nodes[a].directive && c.vue_directive_name(a) in ['slot-scope', 'scope'] {
			scope_attr = a
			break
		}
	}
	name_argument := if slot_name == '' {
		''
	} else if is_v_bind {
		':[${slot_name}]'
	} else {
		':${slot_name}'
	}
	scope_value := if scope_attr >= 0 && c.vue.doc.nodes[scope_attr].value >= 0 {
		'=${c.vue_vnode_text(c.vue.doc.nodes[scope_attr].value)}'
	} else {
		''
	}
	replace_text := 'v-slot${name_argument}${scope_value}'
	element := c.vue.doc.nodes[start_tag].parent
	el := &c.vue.doc.nodes[element]
	attr := &c.vue.doc.nodes[slot_attr]
	mut fixes := []Fix{}
	if el.name == 'template' {
		fixes << fix_replace_range(attr.start, attr.end, replace_text)
		if scope_attr >= 0 {
			fixes << fix_remove_range(c.vue.doc.nodes[scope_attr].start, c.vue.doc.nodes[scope_attr].end)
		}
		return fixes
	}
	fixes << fix_remove_range(attr.start, attr.end)
	if scope_attr >= 0 {
		fixes << fix_remove_range(c.vue.doc.nodes[scope_attr].start, c.vue.doc.nodes[scope_attr].end)
	}
	mut v_for_text := ''
	for a in c.vue.doc.nodes[start_tag].attributes {
		if c.vue.doc.nodes[a].directive && c.vue_directive_name(a) == 'for' {
			v_for_text = '${c.vue_vnode_text(a)} '
			fixes << fix_remove_range(c.vue.doc.nodes[a].start, c.vue.doc.nodes[a].end)
			break
		}
	}
	fixes << fix_insert_at(el.start, '<template ${v_for_text}${replace_text}>\n')
	fixes << fix_insert_at(el.end, '\n</template>')
	return fixes
}

fn (mut c Checker) lint_vue_no_deprecated_slot_scope_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'slot-scope') {
			continue
		}
		stats.checked++
		node := &c.vue.doc.nodes[i]
		report := c.vue_report_vnode(node.key, 'forbiddenSlotScopeAttribute', {})
		element := c.vue_attribute_element(i)
		// canConvertToVSlot: the element can use a `v-slot` and has no `slot` nor `:slot`.
		if !c.vue_can_convert_to_v_slot(element) || c.vue_has_attribute(element, 'slot', none)
			|| c.vue_has_directive(element, 'bind', 'slot') {
			findings << report
			continue
		}
		scope_value := if node.value >= 0 { '=${c.vue_vnode_text(node.value)}' } else { '' }
		replace_text := 'v-slot${scope_value}'
		el := &c.vue.doc.nodes[element]
		if el.name == 'template' {
			findings << c.with_fixes(report, [fix_replace_range(node.start, node.end, replace_text)])!
			continue
		}
		before := c.vue_token_before(node.start, false, false) or {
			findings << report
			continue
		}
		findings << c.with_fixes(report, [
			fix_remove_range(before.end, node.end),
			fix_insert_at(el.start, '<template ${replace_text}>\n'),
			fix_insert_at(el.end, '\n</template>'),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
