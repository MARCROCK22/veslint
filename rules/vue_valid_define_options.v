module rules

import time

// Port of the `vue/valid-define-options` rule of eslint-plugin-vue 10.12.1 (no options): in
// `<script setup>`, a defineOptions without an argument, with type arguments, that declares
// `props`, `emits`, `expose` or `slots`, whose argument uses a variable `<script setup>` declares
// (but a `const` initialized with a literal), or called more than once.

const vue_valid_define_options_messages = {
	'referencingLocally': '`defineOptions` is referencing locally declared variables.'
	'multiple':           '`defineOptions` has been called multiple times.'
	'notDefined':         'Options are not defined.'
	'disallowProp':       '`defineOptions()` cannot be used to declare `{{propName}}`. Use `{{insteadMacro}}()` instead.'
	'typeArgs':           '`defineOptions()` cannot accept type arguments.'
}

fn (mut c Checker) lint_vue_valid_define_options(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
	calls := c.vue_macros_named(t, 'defineOptions')
	mut def_expressions := []int{}
	for call in calls {
		stats.checked++
		args := t.list(call, .arguments) or { []int{} }
		if args.len > 0 {
			define := args[0]
			if t.typ(define) == .object_expression {
				for pair in [['props', 'defineProps'], ['emits', 'defineEmits'],
					['expose', 'defineExpose'], ['slots', 'defineSlots']] {
					if vue_find_property(t, define, pair[0], none) >= 0 {
						findings << Finding{
							stmt:       c.es_tree_position(t, call)
							message_id: 'disallowProp'
							data:       {
								'propName':     pair[0]
								'insteadMacro': pair[1]
							}
						}
					}
				}
			}
			def_expressions << define
		} else {
			findings << Finding{
				stmt:       c.es_tree_position(t, call)
				message_id: 'notDefined'
			}
		}
		if type_args := t.node(call, .type_arguments) {
			findings << Finding{
				stmt:       c.es_tree_position(t, type_args)
				message_id: 'typeArgs'
			}
		}
	}
	for node in c.vx6_referencing_locally(root, t, s, def_expressions, true) {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'referencingLocally'
		}
	}
	if calls.len > 1 {
		for call in calls {
			findings << Finding{
				stmt:       c.es_tree_position(t, call)
				message_id: 'multiple'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
