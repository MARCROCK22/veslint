module rules

import estree
import json2
import time

// Port of the `vue/no-deprecated-model-definition` rule of eslint-plugin-vue 10.12.1 (option
// `allowVue3Compat`): the `model` option of a Vue object (with `allowVue3Compat`, unless its
// `prop` and `event` are Vue 3's `modelValue`/`update:modelValue`, with suggestions to make them
// so).

const vue_no_deprecated_model_definition_messages = {
	'deprecatedModel':         '`model` definition is deprecated.'
	'vue3Compat':              '`model` definition is deprecated. You may use the Vue 3-compatible `modelValue`/`update:modelValue` though.'
	'changeToModelValue':      'Change to `modelValue`/`update:modelValue`.'
	'changeToKebabModelValue': 'Change to `model-value`/`update:model-value`.'
}

fn vue_no_deprecated_model_definition_options(options []json2.Any) !bool {
	o := option_object(vue_no_deprecated_model_definition, options, ['allowVue3Compat'])!
	value := o.values['allowVue3Compat'] or { return false }
	return value is bool && value
}

// vndmd_property_value is the rule's findPropertyValue: the string literal value of the first
// Property whose key is the Identifier `key`, -1 for none.
fn vndmd_property_value(t &estree.EsTree, object int, key string) int {
	for p in t.list(object, .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		k := t.node(p, .key) or { continue }
		if t.typ(k) == .identifier && (t.string_of(k, .name) or { '' }) == key {
			value := vue_property_value(t, p)
			return if vue_is_string_literal(t, value) { value } else { -1 }
		}
	}
	return -1
}

fn (mut c Checker) lint_vue_no_deprecated_model_definition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_vue3_compat := vue_no_deprecated_model_definition_options(c.rule_options(vue_no_deprecated_model_definition))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		model := vue_find_property(t, obj, 'model', none)
		if model < 0 {
			continue
		}
		value := vue_property_value(t, model)
		if t.typ(value) != .object_expression {
			continue
		}
		if !allow_vue3_compat {
			findings << Finding{
				stmt:       c.es_tree_position(t, model)
				message_id: 'deprecatedModel'
			}
			continue
		}
		prop_name := vndmd_property_value(t, value, 'prop')
		event_name := vndmd_property_value(t, value, 'event')
		if prop_name >= 0 && event_name >= 0
			&& (vue_string_literal_value(t, prop_name, true) or { '' }) in [
				'modelValue',
				'model-value',
			]
			&& (vue_string_literal_value(t, event_name, true) or { '' }) in [
				'update:modelValue',
				'update:model-value',
			] {
			continue
		}
		mut suggestions := []Suggestion{}
		if prop_name >= 0 && event_name >= 0 {
			for id, pair in {
				'changeToModelValue':      ['modelValue', 'update:modelValue']
				'changeToKebabModelValue': ['model-value', 'update:model-value']
			} {
				ok, suggestion := c.suggestion(id, {}, [
					fix_replace_range(t.nodes[prop_name].start + 1, t.nodes[prop_name].end - 1,
						pair[0]),
					fix_replace_range(t.nodes[event_name].start + 1, t.nodes[event_name].end - 1,
						pair[1]),
				])!
				if ok {
					suggestions << suggestion
				}
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, model)
			message_id:  'vue3Compat'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
