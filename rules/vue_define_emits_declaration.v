module rules

import json2
import time

// Port of the `vue/define-emits-declaration` rule of eslint-plugin-vue 10.12.1 (option
// "type-based", the default, "type-literal" or "runtime"): in a `<script setup lang="ts">`, a
// `defineEmits` with arguments (type-based, type-literal), with type arguments (runtime), or
// whose type argument has call signatures or is a function type (type-literal).

const vue_define_emits_declaration_messages = {
	'hasArg':         'Use type based declaration instead of runtime declaration.'
	'hasTypeArg':     'Use runtime declaration instead of type based declaration.'
	'hasTypeCallArg': 'Use new type literal declaration instead of the old call signature declaration.'
}

fn vue_define_emits_declaration_options(options []json2.Any) !string {
	return vue_enum_option(vue_define_emits_declaration, options, ['type-based', 'type-literal',
		'runtime'], 'type-based')!
}

fn (mut c Checker) lint_vue_define_emits_declaration(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	define_type := vue_define_emits_declaration_options(c.rule_options(vue_define_emits_declaration))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.setup_element < 0 || !c.vue_has_attribute(s.setup_element, 'lang', 'ts') {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineEmits') {
		stats.checked++
		has_args := (t.list(call, .arguments) or { []int{} }).len > 0
		match define_type {
			'type-based' {
				if has_args {
					findings << Finding{
						stmt:       c.es_tree_position(t, call)
						message_id: 'hasArg'
					}
				}
			}
			'type-literal' {
				if has_args {
					findings << Finding{
						stmt:       c.es_tree_position(t, call)
						message_id: 'hasArg'
					}
					continue
				}
				params := vue_type_arguments(t, call)
				if params.len == 0 {
					continue
				}
				param := params[0]
				if t.typ(param) == .ts_type_literal {
					for member in t.list(param, .members) or { []int{} } {
						if t.typ(member) != .ts_property_signature {
							findings << Finding{
								stmt:       c.es_tree_position(t, member)
								message_id: 'hasTypeCallArg'
							}
						}
					}
				} else if t.typ(param) == .ts_function_type {
					findings << Finding{
						stmt:       c.es_tree_position(t, param)
						message_id: 'hasTypeCallArg'
					}
				}
			}
			else {
				if vue_type_arguments(t, call).len > 0 {
					findings << Finding{
						stmt:       c.es_tree_position(t, call)
						message_id: 'hasTypeArg'
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
