module rules

import json2
import time

// Port of the `vue/attributes-order` rule of eslint-plugin-vue 10.12.1 (options `order`,
// `alphabetical`, `sortLineLength`, `ignoreVBindObject`): an attribute of a start tag whose kind
// goes before the kind of an attribute before it (or, of the same kind, a shorter one or one
// first in alphabetical order), fixed by moving it before that one; a suggestion instead when the
// move changes what a `v-bind="object"` overrides.

const vattro_messages = {
	'expectedOrder': 'Attribute "{{currentNode}}" should go before "{{prevNode}}".'
	'moveAttribute': 'Move "{{currentNode}}" before "{{prevNode}}", which changes what `v-bind="..."` overrides.'
}

const vattro_kinds = ['DEFINITION', 'LIST_RENDERING', 'CONDITIONALS', 'RENDER_MODIFIERS', 'GLOBAL',
	'UNIQUE', 'SLOT', 'TWO_WAY_BINDING', 'OTHER_DIRECTIVES', 'OTHER_ATTR', 'ATTR_STATIC', 'ATTR_DYNAMIC',
	'ATTR_SHORTHAND_BOOL', 'EVENTS', 'CONTENT']

const vattro_other_attrs = ['ATTR_DYNAMIC', 'ATTR_STATIC', 'ATTR_SHORTHAND_BOOL']

const vattro_default_order = [['DEFINITION'], ['LIST_RENDERING'], ['CONDITIONALS'],
	['RENDER_MODIFIERS'], ['GLOBAL'], ['UNIQUE', 'SLOT'], ['TWO_WAY_BINDING'], ['OTHER_DIRECTIVES'],
	vattro_other_attrs, ['EVENTS'], ['CONTENT']]

struct VattroOptions {
	position         map[string]int
	alphabetical     bool
	sort_line_length bool
	ignore_vbind_obj bool
}

fn vattro_options(options []json2.Any) !VattroOptions {
	o := option_object(vue_attributes_order, options, ['order', 'alphabetical', 'sortLineLength',
		'ignoreVBindObject'])!
	mut order := vattro_default_order.clone()
	if value := o.values['order'] {
		if value !is []json2.Any {
			return error('option `order` of `${vue_attributes_order}` must be a list')
		}
		order = [][]string{}
		mut flat := []string{}
		for item in value.as_array() {
			mut group := []string{}
			if item is string {
				group << item
			} else if item is []json2.Any {
				for k in item.as_array() {
					if k !is string {
						return error('option `order` of `${vue_attributes_order}` must hold kinds of attributes')
					}
					group << k as string
				}
			} else {
				return error('option `order` of `${vue_attributes_order}` must hold kinds of attributes')
			}
			for k in group {
				if k !in vattro_kinds {
					return error('option `order` of `${vue_attributes_order}`: unknown kind `${k}`')
				}
				flat << k
			}
			order << group
		}
		// `OTHER_ATTR` with one of the kinds it stands for is an error.
		if 'OTHER_ATTR' in flat {
			for k in flat {
				if k in vattro_other_attrs {
					return error('Value "OTHER_ATTR" is not allowed with "${k}".')
				}
			}
		}
		// `OTHER_ATTR` stands for the kinds of vattro_other_attrs.
		for i, group in order {
			if 'OTHER_ATTR' in group {
				mut expanded := group.filter(it != 'OTHER_ATTR')
				expanded << vattro_other_attrs
				order[i] = expanded
			}
		}
	}
	mut position := map[string]int{}
	for i, group in order {
		for k in group {
			position[k] = i
		}
	}
	return VattroOptions{
		position:         position
		alphabetical:     o.bool_value('alphabetical')!
		sort_line_length: o.bool_value('sortLineLength')!
		ignore_vbind_obj: o.bool_value('ignoreVBindObject')!
	}
}

// vattro_is_vbind is isVBind.
fn (c &Checker) vattro_is_vbind(attr int) bool {
	return attr >= 0 && c.vue.doc.nodes[attr].directive && c.vue_directive_name(attr) == 'bind'
}

// vattro_is_plain_bind_model is isVAttributeOrVBindOrVModel.
fn (c &Checker) vattro_is_plain_bind_model(attr int) bool {
	if attr < 0 {
		return false
	}
	return !c.vue.doc.nodes[attr].directive || c.vue_directive_name(attr) in ['bind', 'model']
}

// vattro_is_vbind_object is isVBindObject: `v-bind="object"`.
fn (c &Checker) vattro_is_vbind_object(attr int) bool {
	return c.vattro_is_vbind(attr) && c.vue.doc.nodes[c.vue.doc.nodes[attr].key].argument < 0
}

fn (c &Checker) vattro_text(node int) string {
	start, end := c.vue_vnode_range(node)
	return c.vue_text(start, end)
}

// vattro_name is getAttributeName.
fn (c &Checker) vattro_name(attr int) string {
	node := &c.vue.doc.nodes[attr]
	key := &c.vue.doc.nodes[node.key]
	if !node.directive {
		return key.name
	}
	if c.vattro_is_vbind(attr) {
		return if key.argument >= 0 { c.vattro_text(key.argument) } else { '' }
	}
	mut text := 'v-${c.vue_directive_name(attr)}'
	if key.argument >= 0 {
		text += ':${c.vattro_text(key.argument)}'
	}
	for m in key.modifiers {
		text += '.${c.vue.doc.nodes[m].name}'
	}
	return text
}

// vattro_kind is getAttributeType.
fn (c &Checker) vattro_kind(attr int) string {
	node := &c.vue.doc.nodes[attr]
	key := &c.vue.doc.nodes[node.key]
	mut prop_name := ''
	if node.directive {
		if !c.vattro_is_vbind(attr) {
			return match c.vue_directive_name(attr) {
				'for' { 'LIST_RENDERING' }
				'if', 'else-if', 'else', 'show', 'cloak' { 'CONDITIONALS' }
				'pre', 'once' { 'RENDER_MODIFIERS' }
				'model' { 'TWO_WAY_BINDING' }
				'on' { 'EVENTS' }
				'html', 'text' { 'CONTENT' }
				'slot' { 'SLOT' }
				'is' { 'DEFINITION' }
				else { 'OTHER_DIRECTIVES' }
			}
		}
		prop_name = if key.argument >= 0 && c.vue.doc.nodes[key.argument].typ == .v_identifier {
			c.vue.doc.nodes[key.argument].raw_name
		} else {
			''
		}
	} else {
		prop_name = key.name
	}
	return match prop_name {
		'is' {
			'DEFINITION'
		}
		'id' {
			'GLOBAL'
		}
		'ref', 'key' {
			'UNIQUE'
		}
		'slot', 'slot-scope' {
			'SLOT'
		}
		else {
			if c.vattro_is_vbind(attr) {
				'ATTR_DYNAMIC'
			} else if node.value < 0 {
				'ATTR_SHORTHAND_BOOL'
			} else {
				'ATTR_STATIC'
			}
		}
	}
}

// vattro_is_alphabetical is isAlphabetical.
fn (c &Checker) vattro_is_alphabetical(prev int, curr int) bool {
	prev_name := c.vattro_name(prev)
	curr_name := c.vattro_name(curr)
	if prev_name == curr_name {
		return !c.vattro_is_vbind(prev) || c.vattro_is_vbind(curr)
	}
	return utf16_less(prev_name, curr_name)
}

fn (mut c Checker) lint_vue_attributes_order(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	o := vattro_options(c.rule_options(vue_attributes_order))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if c.vue.doc.nodes[i].typ != .v_start_tag {
			continue
		}
		stats.checked++
		all := c.vue.doc.nodes[i].attributes
		// getAttributeAndPositionList
		mut attributes := []int{}
		for k, attr in all {
			if o.ignore_vbind_obj && c.vattro_is_vbind_object(attr) {
				continue
			}
			if c.vattro_is_vbind_object(attr) && (c.vattro_is_plain_bind_model(if k > 0 {
				all[k - 1]
			} else {
				-1
			}) || c.vattro_is_plain_bind_model(if k + 1 < all.len { all[k + 1] } else { -1 })) {
				continue
			}
			attributes << attr
		}
		mut list := [][]int{} // [attribute, position]
		for k, attr in attributes {
			mut index := k
			if c.vattro_is_vbind_object(attr) {
				// Its position is that of the next attribute, v-bind or v-model after it.
				for next in k + 1 .. attributes.len {
					if c.vattro_is_plain_bind_model(attributes[next])
						&& !c.vattro_is_vbind_object(attributes[next]) {
						index = next
						break
					}
				}
			}
			position := o.position[c.vattro_kind(attributes[index])] or { continue }
			list << [attr, position]
		}
		if list.len <= 1 {
			continue
		}
		mut previous, mut previous_position := list[0][0], list[0][1]
		for entry in list[1..] {
			attr, position := entry[0], entry[1]
			mut valid := previous_position <= position
			if valid && previous_position == position {
				mut by_length := false
				if o.sort_line_length {
					prev_len := utf16_units(c.vattro_text(previous)).len
					curr_len := utf16_units(c.vattro_text(attr)).len
					if prev_len != curr_len {
						valid = prev_len < curr_len
						by_length = true
					}
				}
				if o.alphabetical && !by_length {
					valid = c.vattro_is_alphabetical(previous, attr)
				}
			}
			if valid {
				previous, previous_position = attr, position
			} else {
				findings << c.vattro_report(all, attr, previous)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vattro_report is reportIssue: `node` moved before `previous`, with the attributes between them
// that must stay before it (a `v-bind="object"` and the bindings around it) moved too.
fn (c &Checker) vattro_report(all []int, node int, previous int) !Finding {
	data := {
		'currentNode': c.vattro_text(c.vue.doc.nodes[node].key)
		'prevNode':    c.vattro_text(c.vue.doc.nodes[previous].key)
	}
	previous_nodes := all[all.index(previous)..all.index(node)]
	mut move_nodes := [node]
	for n in previous_nodes {
		move_up := if c.vattro_is_vbind_object(node) {
			c.vattro_is_plain_bind_model(n)
		} else if c.vattro_is_plain_bind_model(node) {
			c.vattro_is_vbind_object(n)
		} else {
			false
		}
		if move_up {
			move_nodes.insert(0, n)
		} else {
			move_nodes << n
		}
	}
	mut fixes := []Fix{}
	for k, move in move_nodes {
		target := if k < previous_nodes.len { previous_nodes[k] } else { node }
		start, end := c.vue_vnode_range(target)
		fixes << fix_replace_range(start, end, c.vattro_text(move))
	}
	mut before := previous_nodes.clone()
	before << node
	f := c.vue_report_vnode(node, 'expectedOrder', data)
	if c.vattro_override_changed(before, move_nodes) {
		ok, suggestion := c.suggestion('moveAttribute', data, fixes)!
		return Finding{
			...f
			suggestions: if ok { [suggestion] } else { []Suggestion{} }
		}
	}
	return c.with_fixes(f, fixes)!
}

// vattro_override_changed is isVBindObjectOverrideChanged: moving the attributes changes which
// of a `v-bind="object"` and another binding comes first.
fn (c &Checker) vattro_override_changed(before []int, after []int) bool {
	for object_index, object in before {
		if !c.vattro_is_vbind_object(object) {
			continue
		}
		for index, attr in before {
			if c.vattro_is_plain_bind_model(attr) && !c.vattro_is_vbind_object(attr)
				&& (index < object_index) != (after.index(attr) < after.index(object)) {
				return true
			}
		}
	}
	return false
}
