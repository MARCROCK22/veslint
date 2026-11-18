module rules

import json2
import os
import time

// Port of the `vue/multi-word-component-names` rule of eslint-plugin-vue 10.12.1 (option
// `ignores`): a component name of one word (`x.component('name', …)`, the `name` of a Vue object
// or of defineOptions), or, for a component without a name, the file's name.

const vue_multi_word_component_names_messages = {
	'unexpected': 'Component name "{{value}}" should always be multi-word.'
}

fn vue_multi_word_component_names_options(options []json2.Any) !map[string]bool {
	o := option_object(vue_multi_word_component_names, options, ['ignores'])!
	mut ignores := {
		'App': true
		'app': true
	}
	for ignore in o.string_list('ignores')! {
		ignores[ignore] = true
		if vue_is_pascal_case(ignore) {
			ignores[vue_kebab_case(ignore)] = true
		}
	}
	return ignores
}

fn vmwc_is_valid_name(ignores map[string]bool, name string) bool {
	if name in ignores || name in vue_builtin_component_names {
		return true
	}
	return vue_kebab_case(name).split('-').len > 1
}

fn (mut c Checker) lint_vue_multi_word_component_names(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignores := vue_multi_word_component_names_options(c.rule_options(vue_multi_word_component_names))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut has_vue := s.has_setup
	mut has_name := false
	mut name_nodes := []int{}
	for call in vue_call_component_calls(t) {
		has_vue = true
		args := t.list(call, .arguments) or { []int{} }
		if args.len != 2 {
			continue
		}
		has_name = true
		name_nodes << args[0]
	}
	for obj in s.objects_of(vue_all_object_types) {
		has_vue = true
		name := vue_find_property(t, obj, 'name', none)
		if name < 0 {
			continue
		}
		has_name = true
		name_nodes << vue_property_value(t, name)
	}
	for call in c.vue_macros_named(t, 'defineOptions') {
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 0 || t.typ(args[0]) != .object_expression {
			continue
		}
		name := vue_find_property(t, args[0], 'name', none)
		if name < 0 {
			continue
		}
		has_name = true
		name_nodes << vue_property_value(t, name)
	}
	for node in name_nodes {
		stats.checked++
		if node < 0 || t.typ(node) != .literal {
			continue
		}
		value := vue_literal_string(t, node)
		if !vmwc_is_valid_name(ignores, value) {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'unexpected'
				data:       {
					'value': value
				}
			}
		}
	}
	if !has_name && (has_vue || (t.list(t.root, .body) or { []int{} }).len == 0) {
		findings << c.vmwc_file_name_finding(s.filename, ignores)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vmwc_file_name_finding is the report of `Program:exit` on the file's name (at line 1, column
// 0), when it is a Vue file whose name is one word.
fn (c &Checker) vmwc_file_name_finding(filename string, ignores map[string]bool) []Finding {
	base := os.file_name(filename)
	ext := os.file_ext(base)
	name := if ext.len > 0 && ext.len < base.len { base[..base.len - ext.len] } else { base }
	if !(filename.ends_with('.vue') || filename.ends_with('.jsx') || filename.ends_with('.tsx'))
		|| vmwc_is_valid_name(ignores, name) {
		return []
	}
	return [
		Finding{
			stmt:         c.position_at(0)
			message_id:   'unexpected'
			data:         {
				'value': name
			}
			fixed_line:   1
			fixed_column: 1
		},
	]
}
