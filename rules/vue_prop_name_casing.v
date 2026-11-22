module rules

import json2
import time

// Port of the `vue/prop-name-casing` rule of eslint-plugin-vue 10.12.1 (options "camelCase", the
// default, or "snake_case", and `ignoreProps`, names or `/regexp/` strings): a prop of the
// options or of `defineProps` whose name is not in that case.

const vue_prop_name_casing_messages = {
	'invalidCase': 'Prop "{{name}}" is not in {{caseType}}.'
}

struct VuePropNameCasingOptions {
	case_type string
	ignore    VueRegexpGroup
}

fn vue_prop_name_casing_options(options []json2.Any) !VuePropNameCasingOptions {
	mut case_type := 'camelCase'
	if options.len > 0 {
		value := options[0]
		if value !is string || value as string !in ['camelCase', 'snake_case'] {
			return error('the first option of `${vue_prop_name_casing}` must be "camelCase" or "snake_case"')
		}
		case_type = value as string
	}
	mut ignore := []string{}
	if options.len > 1 {
		o := option_object(vue_prop_name_casing, options[1..], ['ignoreProps'])!
		ignore = o.string_list('ignoreProps')!
	}
	return VuePropNameCasingOptions{
		case_type: case_type
		ignore:    vue_regexp_group(ignore)!
	}
}

fn (mut c Checker) lint_vue_prop_name_casing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_prop_name_casing_options(c.rule_options(vue_prop_name_casing))!
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
		if !prop.has_name {
			continue
		}
		if !vue_case_check(o.case_type, prop.name) && !o.ignore.matches(prop.name) {
			findings << Finding{
				stmt:       c.es_tree_position(t, prop.node)
				message_id: 'invalidCase'
				data:       {
					'name':     prop.name
					'caseType': o.case_type
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
