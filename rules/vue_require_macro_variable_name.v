module rules

import json2
import time

// Port of the `vue/require-macro-variable-name` rule of eslint-plugin-vue 10.12.1 (options: the
// name for `defineProps` (`props`), `defineEmits` (`emit`), `defineSlots` and `useSlots`
// (`slots`), `useAttrs` (`attrs`)): a variable of `<script setup>` initialized with one of those
// calls (or `withDefaults`, as `defineProps`) under another name, with the suggestion that
// renames it.

const vue_require_macro_variable_name_messages = {
	'requireName': 'The variable name of "{{macroName}}" must be "{{variableName}}".'
	'changeName':  'Change the variable name to "{{variableName}}".'
}

fn vue_require_macro_variable_name_options(options []json2.Any) !map[string]string {
	keys := ['defineProps', 'defineEmits', 'defineSlots', 'useSlots', 'useAttrs']
	mut variable_names := {
		'defineProps': 'props'
		'defineEmits': 'emit'
		'defineSlots': 'slots'
		'useSlots':    'slots'
		'useAttrs':    'attrs'
	}
	o := option_object(vue_require_macro_variable_name, options, keys)!
	for key, value in o.values {
		if value !is string {
			return error('option `${key}` of `${vue_require_macro_variable_name}` must be a string')
		}
		variable_names[key] = value as string
	}
	return variable_names
}

fn (mut c Checker) lint_vue_require_macro_variable_name(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	variable_names := vue_require_macro_variable_name_options(c.rule_options(vue_require_macro_variable_name))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .variable_declarator || !s.in_script_setup(t, node) {
			continue
		}
		init := t.node(node, .init) or { continue }
		if t.typ(init) != .call_expression {
			continue
		}
		callee := vue_callee_name(t, init)
		if callee !in ['defineProps', 'defineEmits', 'defineSlots', 'useSlots', 'useAttrs',
			'withDefaults'] {
			continue
		}
		stats.checked++
		macro_name := if callee == 'withDefaults' { 'defineProps' } else { callee }
		id := t.node(node, .id) or { continue }
		expected := variable_names[macro_name]
		if t.typ(id) != .identifier || (t.string_of(id, .name) or { '' }) == expected {
			continue
		}
		_, suggestion := c.suggestion('changeName', {
			'variableName': expected
		}, [fix_replace_range(t.nodes[id].start, t.nodes[id].end, expected)])!
		findings << Finding{
			stmt:        c.es_tree_position(t, id)
			message_id:  'requireName'
			data:        {
				'macroName':    macro_name
				'variableName': expected
			}
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
