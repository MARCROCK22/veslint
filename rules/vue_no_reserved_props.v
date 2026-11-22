module rules

import json2
import time

// Port of the `vue/no-reserved-props` rule of eslint-plugin-vue 10.12.1 (option `vueVersion`, 3
// by default): a prop named like an attribute Vue reserves (`key`, `ref`; in Vue 2 also `is`,
// `slot`, `slot-scope`, `slotScope`, `class`, `style`), of the options or of `defineProps`.

const vue_no_reserved_props_messages = {
	'reserved': "'{{propName}}' is a reserved attribute and cannot be used as props."
}

fn vue_no_reserved_props_options(options []json2.Any) ![]string {
	o := option_object(vue_no_reserved_props, options, ['vueVersion'])!
	value := o.values['vueVersion'] or { return ['key', 'ref'] }
	version := if value is f64 || value is int || value is i64 { value.int() } else { 0 }
	return match version {
		3 { ['key', 'ref'] }
		2 { ['key', 'ref', 'is', 'slot', 'slot-scope', 'slotScope', 'class', 'style'] }
		else { error('option `vueVersion` of `${vue_no_reserved_props}` must be 2 or 3') }
	}
}

fn (mut c Checker) lint_vue_no_reserved_props(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	reserved := vue_no_reserved_props_options(c.rule_options(vue_no_reserved_props))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut props := []VueProp{}
	for call in c.vue_macros_named(t, 'defineProps') {
		props << c.vue_define_props(root, t, call, abs_path, true, mut stats)
	}
	for obj in s.objects_of(vue_all_object_types) {
		props << vue_props_from_options(t, obj)
	}
	for prop in props {
		stats.checked++
		if prop.has_name && prop.name in reserved {
			findings << Finding{
				stmt:       c.es_tree_position(t, prop.node)
				message_id: 'reserved'
				data:       {
					'propName': vue_kebab_case(prop.name)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
