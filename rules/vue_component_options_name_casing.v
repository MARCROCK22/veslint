module rules

import json2
import time

// Port of the `vue/component-options-name-casing` rule of eslint-plugin-vue 10.12.1 (option
// "PascalCase", the default, "kebab-case" or "camelCase"): a name of the `components` option of
// a Vue object not in that case, with the fix that converts it (PascalCase) or a suggestion (the
// other cases).

const vue_component_options_name_casing_messages = {
	'caseNotMatched':   'Component name "{{component}}" is not {{caseType}}.'
	'possibleRenaming': 'Rename component name to be in {{caseType}}.'
}

fn vue_component_options_name_casing_options(options []json2.Any) !string {
	return vue_enum_option(vue_component_options_name_casing, options, ['camelCase', 'kebab-case',
		'PascalCase'], 'PascalCase')!
}

fn (mut c Checker) lint_vue_component_options_name_casing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	case_type := vue_component_options_name_casing_options(c.rule_options(vue_component_options_name_casing))!
	can_auto_fix := case_type == 'PascalCase'
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		components := vue_find_property(t, obj, 'components', none)
		if components < 0 || t.typ(vue_property_value(t, components)) != .object_expression {
			continue
		}
		for property in t.list(vue_property_value(t, components), .properties) or { []int{} } {
			if t.typ(property) != .property {
				continue
			}
			key := t.node(property, .key) or { continue }
			// getOptionsComponentName
			name := match t.typ(key) {
				.identifier { t.string_of(key, .name) or { '' } }
				.literal {
					if v := t.string_of(key, .value) { v } else { '' }
				}
				else { '' }
			}
			stats.checked++
			if name == '' || vue_case_check(case_type, name) {
				continue
			}
			converted := vue_case_convert(case_type, name)
			shorthand := t.flag(property, .shorthand) or { false }
			key_start, key_end := t.nodes[key].start, t.nodes[key].end
			prop_start, prop_end := t.nodes[property].start, t.nodes[property].end
			finding := Finding{
				stmt:       c.es_tree_position(t, key)
				message_id: 'caseNotMatched'
				data:       {
					'component': name
					'caseType':  case_type
				}
			}
			if can_auto_fix {
				fix := if shorthand {
					fix_replace_range(prop_start, prop_end, '${converted}: ${name}')
				} else {
					fix_replace_range(key_start, key_end, converted)
				}
				findings << c.with_fixes(finding, [fix])!
				continue
			}
			fix := if case_type == 'kebab-case' {
				if shorthand {
					fix_replace_range(prop_start, prop_end, "'${converted}': ${name}")
				} else {
					fix_replace_range(key_start, key_end, "'${converted}'")
				}
			} else if shorthand {
				fix_replace_range(prop_start, prop_end, '${converted}: ${name}')
			} else {
				fix_replace_range(key_start, key_end, converted)
			}
			_, suggestion := c.suggestion('possibleRenaming', {
				'caseType': case_type
			}, [fix])!
			findings << Finding{
				...finding
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
