module rules

import estree
import json2
import time

// Port of the `vue/component-definition-name-casing` rule of eslint-plugin-vue 10.12.1 (option
// "PascalCase", the default, or "kebab-case"): the name of `x.component('name', {…})`, of the
// `name` option of a Vue object and of the `name` of `defineOptions`, when it is a string not in
// that case, with the fix that converts it.

const vue_component_definition_name_casing_messages = {
	'incorrectCase': 'Property name "{{value}}" is not {{caseType}}.'
}

fn vue_component_definition_name_casing_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'PascalCase'
	}
	value := options[0]
	if value !is string || value as string !in ['PascalCase', 'kebab-case'] {
		return error('the option of `${vue_component_definition_name_casing}` must be "PascalCase" or "kebab-case"')
	}
	return value as string
}

fn (mut c Checker) lint_vue_component_definition_name_casing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	case_type := vue_component_definition_name_casing_options(c.rule_options(vue_component_definition_name_casing))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut name_nodes := []int{}
	for call in vue_call_component_calls(t) {
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 2 && vue_is_string_literal(t, args[0]) {
			name_nodes << args[0]
		}
	}
	for obj in s.objects_of(vue_all_object_types) {
		name := vue_find_property(t, obj, 'name', none)
		if name >= 0 && vue_is_string_literal(t, vue_property_value(t, name)) {
			name_nodes << vue_property_value(t, name)
		}
	}
	for call in c.vue_macros_named(t, 'defineOptions') {
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 0 || t.typ(args[0]) != .object_expression {
			continue
		}
		name := vue_find_property(t, args[0], 'name', none)
		if name >= 0 && vue_is_string_literal(t, vue_property_value(t, name)) {
			name_nodes << vue_property_value(t, name)
		}
	}
	for node in name_nodes {
		stats.checked++
		finding := c.vue_convert_name(t, node, case_type) or { continue }
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_convert_name is the rule's convertName: the report of a string not in the case, with the
// fix that writes the exact conversion between its quotes.
fn (c &Checker) vue_convert_name(t &estree.EsTree, node int, case_type string) ?Finding {
	value := vue_string_literal_value(t, node, false)?
	if vue_case_check(case_type, value) {
		return none
	}
	return c.with_fixes(Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'incorrectCase'
		data:       {
			'value':    value
			'caseType': case_type
		}
	}, [fix_replace_range(t.nodes[node].start + 1, t.nodes[node].end - 1, vue_case_exact_convert(case_type,
		value))]) or { return none }
}
