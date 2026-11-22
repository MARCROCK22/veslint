module rules

import json2
import time

// Port of the `vue/define-props-destructuring` rule of eslint-plugin-vue 10.12.1 (option
// `destructure`: "only-when-assigned", the default, "always" or "never"): a `defineProps` (with
// props) not destructured where it should be, destructured where it should not, or destructured
// with `withDefaults`.

const vue_define_props_destructuring_messages = {
	'preferDestructuring': 'Prefer destructuring from `defineProps` directly.'
	'avoidDestructuring':  'Avoid destructuring from `defineProps`.'
	'avoidWithDefaults':   'Avoid using `withDefaults` with destructuring.'
}

fn vue_define_props_destructuring_options(options []json2.Any) !string {
	o := option_object(vue_define_props_destructuring, options, ['destructure'])!
	if 'destructure' !in o.values {
		return 'only-when-assigned'
	}
	return o.string_value('destructure', ['only-when-assigned', 'always', 'never'])!
}

fn (mut c Checker) lint_vue_define_props_destructuring(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	preference := vue_define_props_destructuring_options(c.rule_options(vue_define_props_destructuring))!
	mut findings := []Finding{}
	c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineProps') {
		stats.checked++
		props := c.vue_define_props(root, t, call, abs_path, true, mut stats)
		if !props.any((it.has_name && it.name != '') || (it.kind == .unknown && it.node >= 0)) {
			continue
		}
		has_destructure := vue_is_using_props_destructure(t, call)
		has_with_defaults := vue_has_with_defaults(t, call)
		has_assigned := vue_left_of_define_props(t, call) >= 0
		if preference == 'never' {
			if has_destructure {
				findings << Finding{
					stmt:       c.es_tree_position(t, call)
					message_id: 'avoidDestructuring'
				}
			}
			continue
		}
		if !has_destructure && (preference == 'always' || has_assigned) {
			findings << Finding{
				stmt:       c.es_tree_position(t, call)
				message_id: 'preferDestructuring'
			}
			continue
		}
		if has_with_defaults {
			callee := t.node(t.nodes[call].parent, .callee) or { continue }
			findings << Finding{
				stmt:       c.es_tree_position(t, callee)
				message_id: 'avoidWithDefaults'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
