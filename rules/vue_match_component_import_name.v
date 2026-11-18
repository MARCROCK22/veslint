module rules

import time

// Port of the `vue/match-component-import-name` rule of eslint-plugin-vue 10.12.1 (no options): a
// property of the `components` option of a component whose value is an Identifier and whose name
// is neither its PascalCase nor its kebab-case.

const vue_match_component_import_name_messages = {
	'unexpected': 'Component alias {{importedName}} should be one of: {{expectedName}}.'
}

fn (mut c Checker) lint_vue_match_component_import_name(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_component_object_types) {
		components := vue_find_property(t, obj, 'components', none)
		if components < 0 || t.typ(vue_property_value(t, components)) != .object_expression {
			continue
		}
		for property in t.list(vue_property_value(t, components), .properties) or { []int{} } {
			if t.typ(property) == .spread_element {
				continue
			}
			value := vue_property_value(t, property)
			if value < 0 || t.typ(value) != .identifier || (t.flag(property, .computed) or { false }) {
				continue
			}
			stats.checked++
			imported_name := vue_static_property_name(t, property) or { '' }
			name := t.string_of(value, .name) or { '' }
			expected := [vue_pascal_case(name), vue_kebab_case(name)]
			if imported_name !in expected {
				findings << Finding{
					stmt:       c.es_tree_position(t, property)
					message_id: 'unexpected'
					data:       {
						'importedName': imported_name
						'expectedName': expected.join(', ')
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
