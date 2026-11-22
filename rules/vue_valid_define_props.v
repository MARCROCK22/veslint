module rules

import time

// Port of the `vue/valid-define-props` rule of eslint-plugin-vue 10.12.1 (no options): in
// `<script setup>`, `defineProps` with both a type argument and an argument, an argument that uses a
// variable `<script setup>` declares, more than one call, a call without props (unless
// `export default` has `props`), and props in both `defineProps` and `export default`.

const vue_valid_define_props_messages = {
	'hasTypeAndArg':      '`defineProps` has both a type-only props and an argument.'
	'referencingLocally': '`defineProps` is referencing locally declared variables.'
	'multiple':           '`defineProps` has been called multiple times.'
	'notDefined':         'Props are not defined.'
	'definedInBoth':      'Props are defined in both `defineProps` and `export default {}`.'
}

fn (mut c Checker) lint_vue_valid_define_props(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	calls := c.vue_macros_named(t, 'defineProps')
	mut def_expressions := []int{}
	mut empty_call := -1
	for call in calls {
		stats.checked++
		args := t.list(call, .arguments) or { []int{} }
		has_type_args := vue_type_arguments(t, call).len > 0
		if args.len > 0 {
			if has_type_args {
				findings << Finding{
					stmt:       c.es_tree_position(t, call)
					message_id: 'hasTypeAndArg'
				}
				continue
			}
			def_expressions << args[0]
		} else if !has_type_args {
			empty_call = call
		}
	}
	for node in c.vx6_referencing_locally(root, t, s, def_expressions, false) {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'referencingLocally'
		}
	}
	mut has_default_export := false
	for obj in s.objects_of(vue_all_object_types) {
		if s.object_type(obj) != .export || s.in_script_setup(t, obj) {
			continue
		}
		has_default_export = vue_find_property(t, obj, 'props', none) >= 0
	}
	if calls.len > 1 {
		for call in calls {
			findings << Finding{
				stmt:       c.es_tree_position(t, call)
				message_id: 'multiple'
			}
		}
	} else if calls.len == 1 {
		if empty_call >= 0 {
			if !has_default_export {
				findings << Finding{
					stmt:       c.es_tree_position(t, empty_call)
					message_id: 'notDefined'
				}
			}
		} else if has_default_export {
			findings << Finding{
				stmt:       c.es_tree_position(t, calls[0])
				message_id: 'definedInBoth'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
