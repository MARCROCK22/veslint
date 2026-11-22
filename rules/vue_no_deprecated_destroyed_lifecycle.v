module rules

import estree
import time

// Port of the `vue/no-deprecated-destroyed-lifecycle` rule of eslint-plugin-vue 10.12.1 (no
// options): the `destroyed` and `beforeDestroy` hooks of a Vue object, with the fix that renames
// them `unmounted` and `beforeUnmount`.

const vue_no_deprecated_destroyed_lifecycle_messages = {
	'deprecatedDestroyed':     'The `destroyed` lifecycle hook is deprecated. Use `unmounted` instead.'
	'deprecatedBeforeDestroy': 'The `beforeDestroy` lifecycle hook is deprecated. Use `beforeUnmount` instead.'
}

fn (mut c Checker) lint_vue_no_deprecated_destroyed_lifecycle(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		for hook in [['destroyed', 'deprecatedDestroyed', 'unmounted'],
			['beforeDestroy', 'deprecatedBeforeDestroy', 'beforeUnmount']] {
			property := vue_find_property(t, obj, hook[0], none)
			if property < 0 {
				continue
			}
			key := t.node(property, .key) or { continue }
			finding := Finding{
				stmt:       c.es_tree_position(t, key)
				message_id: hook[1]
			}
			findings << c.with_fixes(finding, vue_rename_hook_fix(t, property, key, hook[2]))!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_rename_hook_fix is the rule's fix: the new name inside the quotes of a computed string key
// (none for another computed key), before a shorthand's key (`name:`), or for the key.
fn vue_rename_hook_fix(t &estree.EsTree, property int, key int, new_name string) []Fix {
	if t.flag(property, .computed) or { false } {
		if vue_is_string_literal(t, key) {
			return [fix_replace_range(t.nodes[key].start + 1, t.nodes[key].end - 1, new_name)]
		}
		return []
	}
	if t.flag(property, .shorthand) or { false } {
		return [fix_insert_at(t.nodes[key].start, '${new_name}:')]
	}
	return [fix_replace_range(t.nodes[key].start, t.nodes[key].end, new_name)]
}
