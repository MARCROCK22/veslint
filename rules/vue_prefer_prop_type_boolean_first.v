module rules

import estree
import time

// Port of the `vue/prefer-prop-type-boolean-first` rule of eslint-plugin-vue 10.12.1 (no
// options): a `Boolean` that is not the first type of a prop (the array of an object prop, or of
// its `type`), with the suggestion that moves it first.

const vue_prefer_prop_type_boolean_first_messages = {
	'shouldBeFirst': 'Type `Boolean` should be at first in prop types.'
	'moveToFirst':   'Move `Boolean` to be first in prop types.'
}

fn (mut c Checker) lint_vue_prefer_prop_type_boolean_first(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut props := []VueProp{}
	for call in c.vue_macros_named(t, 'defineProps') {
		props << c.vue_define_props(root, t, call, abs_path, false, mut stats)
	}
	for obj in s.objects_of(vue_all_object_types) {
		props << vue_props_from_options(t, obj)
	}
	for prop in props {
		if prop.kind != .object || prop.value < 0 {
			continue
		}
		stats.checked++
		if t.typ(prop.value) == .array_expression {
			c.vue_check_boolean_first(t, prop.value, mut findings)!
		} else if t.typ(prop.value) == .object_expression {
			typ := vue_find_property(t, prop.value, 'type', none)
			if typ >= 0 && t.typ(vue_property_value(t, typ)) == .array_expression {
				c.vue_check_boolean_first(t, vue_property_value(t, typ), mut findings)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vue_check_boolean_first(t &estree.EsTree, array int, mut findings []Finding) ! {
	elements := t.list(array, .elements) or { return }
	mut index := -1
	for i, e in elements {
		if e >= 0 && t.typ(e) == .identifier && (t.string_of(e, .name) or { '' }) == 'Boolean' {
			index = i
			break
		}
	}
	if index <= 0 {
		return
	}
	mut code := ['Boolean']
	for i, e in elements {
		if i != index && e >= 0 {
			code << c.src[t.nodes[e].start..t.nodes[e].end]
		}
	}
	_, suggestion := c.suggestion('moveToFirst', {}, [
		fix_replace_range(t.nodes[array].start, t.nodes[array].end, '[${code.join(', ')}]'),
	])!
	findings << Finding{
		stmt:        c.es_tree_position(t, elements[index])
		message_id:  'shouldBeFirst'
		suggestions: [suggestion]
	}
}
