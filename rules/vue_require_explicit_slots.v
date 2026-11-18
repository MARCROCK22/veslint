module rules

import estree
import time

// Port of the `vue/require-explicit-slots` rule of eslint-plugin-vue 10.12.1 (no options), in a
// .vue file with a `<script lang="ts">`: a <slot> of the template whose name (`name`, or a string
// literal `:name`; "default" without one) neither defineSlots nor the `slots: Object as
// SlotsType<{…}>` of a Vue object defines, and a slot these define twice.

const vue_require_explicit_slots_messages = {
	'requireExplicitSlots': 'Slots must be explicitly defined.'
	'alreadyDefinedSlot':   'Slot {{slotName}} is already defined.'
}

fn (mut c Checker) lint_vue_require_explicit_slots(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	doc := c.vue.doc
	scripts := doc.nodes[0].children.filter(doc.nodes[it].typ == .v_element
		&& doc.nodes[it].name == 'script')
	if scripts.all(!c.vue_has_attribute(it, 'lang', 'ts')) {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut defined := map[string]bool{}
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		mut slots_calls := map[int]bool{}
		for call in c.vue_macros_named(t, 'defineSlots') {
			slots_calls[call] = true
		}
		// The listeners in the order of the traversal: defineSlots at its CallExpression, a Vue
		// object at its `ObjectExpression:exit`.
		for step in t.steps() {
			node := step.node
			if !step.leave && node in slots_calls {
				for slot in c.vue_define_slots(root, t, node, abs_path, mut stats) {
					if slot.has_name && slot.name != '' {
						vres_define(t, slot.name, slot.node, mut defined, mut findings, c)
					}
				}
			} else if step.leave && s.object_type(node) != .none_ {
				for member, name in vres_slots_type_members(t, node) {
					vres_define(t, name, member, mut defined, mut findings, c)
				}
			}
		}
	}
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		if node.typ != .v_element || node.name != 'slot' {
			continue
		}
		stats.checked++
		name_attr := c.vres_slot_name_node(v)
		mut name := ?string('default')
		if name_attr >= 0 {
			attr := &doc.nodes[name_attr]
			if attr.directive {
				expression := c.vue_container_expression(attr.value)
				if expression.kind != .estree {
					continue
				}
				es := &doc.snippets[expression.snippet].es
				if !vue_tpl_is_string_literal(es, expression.node) {
					continue
				}
				value := vue_tpl_string_literal_value(es, expression.node, false) or { '' }
				name = if value == '' { none } else { value }
			} else {
				name = if attr.value >= 0 { doc.nodes[attr.value].text } else { none }
			}
		}
		if n := name {
			if n in defined {
				continue
			}
		}
		findings << c.vue_report_vnode(v, 'requireExplicitSlots', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vres_define adds a slot name, or reports it when it is already defined.
fn vres_define(t &estree.EsTree, name string, node int, mut defined map[string]bool, mut findings []Finding, c &Checker) {
	if name in defined {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'alreadyDefinedSlot'
			data:       {
				'slotName': name
			}
		}
	} else {
		defined[name] = true
	}
}

// vres_slots_type_members are the members of the type literal of `slots: … as SlotsType<{…}>` of
// a Vue object with their names (getSlotsName: a method or property signature with an Identifier
// key or a string Literal one), in order.
fn vres_slots_type_members(t &estree.EsTree, object int) map[int]string {
	mut out := map[int]string{}
	property := vue_find_property(t, object, 'slots', none)
	if property < 0 {
		return out
	}
	value := vue_property_value(t, property)
	if t.typ(value) != .ts_as_expression {
		return out
	}
	annotation := t.node(value, .type_annotation) or { return out }
	if t.typ(annotation) != .ts_type_reference {
		return out
	}
	type_name := t.node(annotation, .type_name) or { return out }
	if t.typ(type_name) != .identifier || (t.string_of(type_name, .name) or { '' }) != 'SlotsType' {
		return out
	}
	params := vue_type_arguments(t, annotation)
	if params.len == 0 || t.typ(params[0]) != .ts_type_literal {
		return out
	}
	for member in t.list(params[0], .members) or { []int{} } {
		if t.typ(member) !in [.ts_method_signature, .ts_property_signature] {
			continue
		}
		key := t.node(member, .key) or { continue }
		mut name := ''
		if t.typ(key) == .literal {
			v := t.get(key, .value)
			if v is string {
				name = v
			}
		} else if t.typ(key) == .identifier {
			name = t.string_of(key, .name) or { '' }
		}
		if name != '' {
			out[member] = name
		}
	}
	return out
}

// vres_slot_name_node is getSlotNameNode: the first `name` attribute or `:name` directive of the
// element, -1 for none.
fn (c &Checker) vres_slot_name_node(element int) int {
	doc := c.vue.doc
	for a in c.vue_attributes(element) {
		attr := &doc.nodes[a]
		if !attr.directive {
			if doc.nodes[attr.key].name == 'name' {
				return a
			}
			continue
		}
		key := &doc.nodes[attr.key]
		if c.vue_directive_name(a) == 'bind' && key.argument >= 0
			&& doc.nodes[key.argument].typ == .v_identifier && doc.nodes[key.argument].name == 'name' {
			return a
		}
	}
	return -1
}
