module rules

import estree
import time

// Port of the `vue/prefer-separate-static-class` rule of eslint-plugin-vue 10.12.1 (no options):
// the static class names of a `:class` (a string, the static parts of a template literal, the
// strings of an array, the `true` keys of an object), fixed by moving them to the static `class`
// attribute (not those of a template literal).

const vpssc_messages = {
	'preferSeparateStaticClass': 'Static class "{{className}}" should be in a static `class` attribute.'
}

// vpssc_static_classes is findStaticClasses: the nodes of the static class names of `node`.
fn vpssc_static_classes(t &estree.EsTree, node int) []int {
	if t.typ(node) == .template_literal {
		expressions := t.list(node, .expressions) or { []int{} }
		if expressions.len > 0 {
			mut out := []int{}
			for i, quasi in t.list(node, .quasis) or { []int{} } {
				value := vpssc_cooked(t, quasi) or { continue }
				if js_trim(value) != '' && (i == 0 || vpssc_starts_with_space(value))
					&& (i == expressions.len || vpssc_ends_with_space(value)) {
					out << quasi
				}
			}
			return out
		}
	}
	if vue_is_string_literal(t, node) {
		return [node]
	}
	mut out := []int{}
	match t.typ(node) {
		.array_expression {
			for element in t.list(node, .elements) or { []int{} } {
				if element >= 0 && t.typ(element) != .spread_element {
					out << vpssc_static_classes(t, element)
				}
			}
		}
		.object_expression {
			for property in t.list(node, .properties) or { []int{} } {
				if t.typ(property) != .property {
					continue
				}
				value := t.node(property, .value) or { continue }
				if t.typ(value) != .literal || t.get(value, .value) !is bool
					|| !(t.get(value, .value) as bool) {
					continue
				}
				key := t.node(property, .key) or { continue }
				if vue_is_string_literal(t, key) || (t.typ(key) == .identifier
					&& !(t.flag(property, .computed) or { false })) {
					out << key
				}
			}
		}
		else {}
	}
	return out
}

// vpssc_cooked is a TemplateElement's `value.cooked` (none when it is null).
fn vpssc_cooked(t &estree.EsTree, quasi int) ?string {
	v := t.get(quasi, .value)
	if v is estree.TemplateValue && v.has_cooked {
		return v.cooked
	}
	return none
}

fn vpssc_starts_with_space(s string) bool {
	return s.len > 0 && is_js_space(s.runes()[0])
}

fn vpssc_ends_with_space(s string) bool {
	return s.len > 0 && is_js_space(s.runes().last())
}

// vpssc_class_name is getStaticClassName (none for a null cooked value).
fn vpssc_class_name(t &estree.EsTree, node int) ?string {
	if t.typ(node) == .identifier {
		return t.string_of(node, .name)
	}
	if t.typ(node) == .template_element {
		value := vpssc_cooked(t, node)?
		return vue_split_whitespace(js_trim(value)).join(' ')
	}
	return vue_string_literal_value(t, node, true)
}

fn (mut c Checker) lint_vue_prefer_separate_static_class(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !node.directive || c.vue_directive_name(i) != 'bind' {
			continue
		}
		key := &c.vue.doc.nodes[node.key]
		if key.argument < 0 || c.vue.doc.nodes[key.argument].typ != .v_identifier
			|| c.vue.doc.nodes[key.argument].name != 'class' {
			continue
		}
		stats.checked++
		// `.attr` and `.prop` set the raw attribute or property: not a normalized class list.
		if key.modifiers.any(c.vue.doc.nodes[it].name in ['attr', 'prop']) {
			continue
		}
		if node.value < 0 {
			continue
		}
		e := c.vue.doc.nodes[node.value].expression
		if e.kind != .estree {
			continue
		}
		t := &c.vue.doc.snippets[e.snippet].es
		for class_node in vpssc_static_classes(t, e.node) {
			class_name := vpssc_class_name(t, class_node) or { continue }
			f := Finding{
				stmt:       c.position_range(t.nodes[class_node].start, t.nodes[class_node].end)
				message_id: 'preferSeparateStaticClass'
				data:       {
					'className': class_name
				}
			}
			if t.typ(class_node) == .template_element {
				findings << f
				continue
			}
			findings << c.with_fixes(f, c.vpssc_fixes(i, t, e.node, class_node, class_name))!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vpssc_fixes are removeFromClassDirective's and addToClassAttribute's fixes.
fn (c &Checker) vpssc_fixes(attr int, t &estree.EsTree, expression int, class_node int, class_name string) []Fix {
	mut fixes := []Fix{}
	mut removed := false
	attr_start, attr_end := c.vue_vnode_range(attr)
	if vue_is_string_literal(t, expression) {
		fixes << fix_remove_range(attr_start, attr_end)
		removed = true
	} else {
		parent := t.nodes[class_node].parent
		list_element := if parent >= 0 && t.typ(parent) == .property { parent } else { class_node }
		// The parent of the expression is the VExpressionContainer.
		list_node := if list_element == expression { -1 } else { t.nodes[list_element].parent }
		if list_node >= 0 && t.typ(list_node) in [.array_expression, .object_expression] {
			elements := if t.typ(list_node) == .object_expression {
				t.list(list_node, .properties) or { []int{} }
			} else {
				t.list(list_node, .elements) or { []int{} }
			}
			if list_node == expression && elements.len == 1 {
				fixes << fix_remove_range(attr_start, attr_end)
				removed = true
			} else if elements.len == 1 {
				fixes << c.vpssc_remove_with_comma(t, list_node)
			} else {
				fixes << c.vpssc_remove_with_comma(t, list_element)
			}
		}
	}
	element := c.vue_attribute_element(attr)
	start_tag := &c.vue.doc.nodes[c.vue.doc.nodes[element].start_tag]
	for a in start_tag.attributes {
		other := &c.vue.doc.nodes[a]
		if !other.directive && c.vue.doc.nodes[other.key].name == 'class' && other.value >= 0 {
			literal := &c.vue.doc.nodes[other.value]
			fixes << fix_replace_range(literal.start, literal.end, '"${literal.text} ${class_name}"')
			return fixes
		}
	}
	separator := if removed { '' } else { ' ' }
	fixes << fix_insert_at(attr_start, 'class="${class_name}"${separator}')
	return fixes
}

// vpssc_remove_with_comma is removeNodeWithComma: the node with the comma before it, or after it
// when that comma does not end the list.
fn (c &Checker) vpssc_remove_with_comma(t &estree.EsTree, node int) Fix {
	start, end := t.nodes[node].start, t.nodes[node].end
	if prev := c.vue_token_before(start, false, false) {
		if prev.typ == 'Punctuator' && prev.value == ',' {
			return fix_remove_range(prev.start, end)
		}
	}
	if next := c.vue_token_after(end, false, false) {
		if next_next := c.vue_token_after(next.end, false, false) {
			if next.typ == 'Punctuator' && next.value == ','
				&& (next_next.typ != 'Punctuator' || next_next.value !in [']', '}']) {
				return fix_remove_range(start, next_next.start)
			}
		}
	}
	return fix_remove_range(start, end)
}
