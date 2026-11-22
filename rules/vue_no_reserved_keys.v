module rules

import json2
import time

// Port of the `vue/no-reserved-keys` rule of eslint-plugin-vue 10.12.1 (options `reserved`, more
// reserved names, and `groups`, more groups): a name a group of a Vue object (`props`,
// `computed`, `data`, `asyncData`, `methods`, `setup`) or `defineProps` defines that Vue
// reserves (lib/utils/vue-reserved.json), or a `data`/`asyncData` name that starts with `_`.

const vue_no_reserved_keys_messages = {
	'reserved':             "Key '{{name}}' is reserved."
	'startsWithUnderscore': "Keys starting with '_' are reserved in '{{name}}' group."
}

const vue_reserved_keys = ['\$data', '\$props', '\$el', '\$options', '\$parent', '\$root', '\$children',
	'\$slots', '\$scopedSlots', '\$refs', '\$isServer', '\$attrs', '\$listeners', '\$watch', '\$set',
	'\$delete', '\$on', '\$once', '\$off', '\$emit', '\$mount', '\$forceUpdate', '\$nextTick',
	'\$destroy']

struct VueReservedKeysOptions {
	reserved []string
	groups   []string
}

fn vue_no_reserved_keys_options(options []json2.Any) !VueReservedKeysOptions {
	o := option_object(vue_no_reserved_keys, options, ['reserved', 'groups'])!
	mut reserved := vue_reserved_keys.clone()
	reserved << o.string_list('reserved')!
	mut groups := ['props', 'computed', 'data', 'asyncData', 'methods', 'setup']
	groups << o.string_list('groups')!
	return VueReservedKeysOptions{
		reserved: reserved
		groups:   groups
	}
}

fn (mut c Checker) lint_vue_no_reserved_keys(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_no_reserved_keys_options(c.rule_options(vue_no_reserved_keys))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineProps') {
		for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
			stats.checked++
			if prop.has_name && prop.name != '' && prop.name in o.reserved {
				findings << Finding{
					stmt:       c.es_tree_position(t, prop.node)
					message_id: 'reserved'
					data:       {
						'name': prop.name
					}
				}
			}
		}
	}
	for obj in s.objects_of(vue_all_object_types) {
		for p in vue_iterate_properties(t, obj, o.groups) {
			stats.checked++
			if p.group in ['data', 'asyncData'] && p.name.starts_with('_') {
				findings << Finding{
					stmt:       c.es_tree_position(t, p.node)
					message_id: 'startsWithUnderscore'
					data:       {
						'name': p.name
					}
				}
			} else if p.name in o.reserved {
				findings << Finding{
					stmt:       c.es_tree_position(t, p.node)
					message_id: 'reserved'
					data:       {
						'name': p.name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
