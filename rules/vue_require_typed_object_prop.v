module rules

import estree
import time

// Port of the `vue/require-typed-object-prop` rule of eslint-plugin-vue 10.12.1 (no options): in
// a TypeScript file or a .vue with a `lang="ts"` script, a prop whose type is `Object` or `Array`
// without a `PropType` annotation, with suggestions to add `as PropType<any>` or
// `as PropType<unknown>`.

const vue_require_typed_object_prop_messages = {
	'expectedTypeAnnotation': 'Expected type annotation on object prop.'
	'addTypeAnnotation':      'Add `{{ type }}` type annotation.'
}

fn (mut c Checker) lint_vue_require_typed_object_prop(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	filename := s.filename
	if s.is_vue_file {
		// A .jsx or .tsx file has no document fragment: nothing to check.
		if !c.is_vue() {
			return findings
		}
		scripts := c.vue.doc.top_elements('script')
		if scripts.all(!c.vue_has_attribute(it, 'lang', 'ts')) {
			return findings
		}
	} else if !(filename.ends_with('.ts') || filename.ends_with('.tsx')
		|| filename.ends_with('.mts')) {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut props := []VueProp{}
	for call in c.vue_macros_named(t, 'defineProps') {
		props << c.vue_define_props(root, t, call, abs_path, false, mut stats)
	}
	for obj in s.objects_of(vue_all_object_types) {
		props << vue_props_from_options(t, obj)
	}
	for prop in props {
		stats.checked++
		if prop.kind != .object {
			continue
		}
		value := vue_property_value(t, prop.node)
		match t.typ(value) {
			.identifier { c.vrtop_check_identifier(t, value, mut findings) }
			.array_expression { c.vrtop_check_array(t, value, mut findings) }
			.object_expression { c.vrtop_check_object(t, value, mut findings) }
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vrtop_check_identifier(t &estree.EsTree, node int, mut findings []Finding) {
	name := t.string_of(node, .name) or { return }
	if name != 'Object' && name != 'Array' {
		return
	}
	suffix := if name == 'Array' { '[]' } else { '' }
	end := t.nodes[node].end
	findings << Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  'expectedTypeAnnotation'
		suggestions: [
			Suggestion{
				message_id: 'addTypeAnnotation'
				data:       {
					'type': 'any${suffix}'
				}
				fix:        fix_insert_at(end, ' as PropType<any${suffix}>')
			},
			Suggestion{
				message_id: 'addTypeAnnotation'
				data:       {
					'type': 'unknown${suffix}'
				}
				fix:        fix_insert_at(end, ' as PropType<unknown${suffix}>')
			},
		]
	}
}

fn (c &Checker) vrtop_check_array(t &estree.EsTree, node int, mut findings []Finding) {
	for element in t.list(node, .elements) or { []int{} } {
		if element >= 0 && t.typ(element) == .identifier {
			c.vrtop_check_identifier(t, element, mut findings)
		}
	}
}

fn (c &Checker) vrtop_check_object(t &estree.EsTree, node int, mut findings []Finding) {
	for p in t.list(node, .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		key := t.node(p, .key) or { continue }
		if t.typ(key) != .identifier || (t.string_of(key, .name) or { '' }) != 'type' {
			continue
		}
		value := vue_property_value(t, p)
		if t.typ(value) == .identifier {
			c.vrtop_check_identifier(t, value, mut findings)
		} else if t.typ(value) == .array_expression {
			c.vrtop_check_array(t, value, mut findings)
		}
		return
	}
}
