module rules

import estree
import time

// Port of the `vue/require-prop-type-constructor` rule of eslint-plugin-vue 10.12.1 (no
// options): a type of an object prop (its value, an item of it, or its `type`) that is a string,
// a template, a binary or an update expression, with the fix that writes a string's text as the
// constructor.

const vue_require_prop_type_constructor_messages = {
	'propTypeConstructor': 'The "{{name}}" property should be a constructor.'
}

fn (mut c Checker) lint_vue_require_prop_type_constructor(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut props := []VueProp{}
	for call in c.vue_macros_named(t, 'defineProps') {
		props << c.vue_define_props(root, t, call, abs_path, false, mut stats)
	}
	for obj in s.objects_of(vue_component_object_types) {
		props << vue_props_from_options(t, obj)
	}
	for prop in props {
		if prop.kind != .object || !prop.has_name || prop.value < 0 {
			continue
		}
		stats.checked++
		if vue_is_forbidden_type(t, prop.value) || t.typ(prop.value) == .array_expression {
			c.vue_check_prop_type_node(t, prop.name, prop.value, mut findings)!
		} else if t.typ(prop.value) == .object_expression {
			typ := vue_find_property(t, prop.value, 'type', none)
			if typ >= 0 {
				c.vue_check_prop_type_node(t, prop.name, vue_property_value(t, typ), mut
					findings)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_is_forbidden_type is the rule's isForbiddenType: a literal (not null), a template, a
// binary or an update expression.
fn vue_is_forbidden_type(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	typ := t.typ(node)
	if typ !in [.literal, .template_literal, .binary_expression, .update_expression] {
		return false
	}
	if typ == .literal && t.get(node, .value) is estree.Null && t.prop(node, .bigint) == none {
		return false
	}
	return true
}

fn (c &Checker) vue_check_prop_type_node(t &estree.EsTree, name string, node int, mut findings []Finding) ! {
	nodes := if t.typ(node) == .array_expression {
		(t.list(node, .elements) or { []int{} }).filter(it >= 0)
	} else {
		[node]
	}
	for prop in nodes {
		if !vue_is_forbidden_type(t, prop) {
			continue
		}
		mut fixes := []Fix{}
		if t.typ(prop) in [.literal, .template_literal] {
			text := vue_string_literal_value(t, prop, true) or { '' }
			if text != '' {
				fixes << fix_replace_range(t.nodes[prop].start, t.nodes[prop].end, text)
			}
		}
		findings << c.with_fixes(Finding{
			stmt:       c.es_tree_position(t, prop)
			message_id: 'propTypeConstructor'
			data:       {
				'name': name
			}
		}, fixes)!
	}
}
