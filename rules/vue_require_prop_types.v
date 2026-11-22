module rules

import estree
import time

// Port of the `vue/require-prop-types` rule of eslint-plugin-vue 10.12.1 (no options): a prop of
// the options or of `defineProps` without a type (an array item, or an object prop whose value
// has no `type` (non-empty) nor `validator`, an empty array, or a function), and a `defineModel`
// without a type argument nor typed options.

const vue_require_prop_types_messages = {
	'requireType': 'Prop "{{name}}" should define at least its type.'
}

fn (mut c Checker) lint_vue_require_prop_types(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
		if prop.kind !in [.object, .array] {
			continue
		}
		stats.checked++
		has_type := prop.kind != .array && (vue_option_has_type(t, prop.value) or { true })
		if has_type {
			continue
		}
		name := if prop.has_name && prop.name != '' {
			prop.name
		} else if prop.node >= 0 && t.typ(prop.node) == .identifier {
			t.string_of(prop.node, .name) or { 'Unknown prop' }
		} else {
			'Unknown prop'
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, prop.node)
			message_id: 'requireType'
			data:       {
				'name': name
			}
		}
	}
	for call in c.vue_macros_named(t, 'defineModel') {
		stats.checked++
		model := vue_define_model(t, call)
		if model.type_node >= 0
			|| (model.options >= 0 && (vue_option_has_type(t, model.options) or { true })) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, if model.options >= 0 { model.options } else { call })
			message_id: 'requireType'
			data:       {
				'name': model.name
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_option_has_type is the rule's optionHasType: whether the options of a prop give its type,
// none when they cannot tell.
fn vue_option_has_type(t &estree.EsTree, node int) ?bool {
	match t.typ(node) {
		.object_expression {
			typ := vue_find_property(t, node, 'type', fn [t] (p int) bool {
				value := vue_property_value(t, p)
				return t.typ(value) != .array_expression
					|| (t.list(value, .elements) or { []int{} }).len > 0
			})
			return typ >= 0 || vue_find_property(t, node, 'validator', none) >= 0
		}
		.array_expression {
			return (t.list(node, .elements) or { []int{} }).len > 0
		}
		.function_expression, .arrow_function_expression {
			return false
		}
		else {
			return none
		}
	}
}
