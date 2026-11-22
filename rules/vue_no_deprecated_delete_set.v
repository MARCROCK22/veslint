module rules

import estree
import time

// Port of the `vue/no-deprecated-delete-set` rule of eslint-plugin-vue 10.12.1 (no options): a
// call of `this.$set`, `this.$delete`, `Vue.set` or `Vue.delete` in a Vue object or in
// `<script setup>` (reported once for each of the two it is in), and a call of the `set` and
// `del` of `vue` (imported, or from its require()).

const vue_no_deprecated_delete_set_messages = {
	'deprecated': 'The `$delete`, `$set` is deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_delete_set(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if s.objects.len > 0 || s.has_setup {
		for node in 0 .. t.nodes.len {
			if t.typ(node) != .identifier {
				continue
			}
			// The listener of defineVueVisitor and that of defineScriptSetupVisitor.
			times := (if s.owner_of(node) >= 0 { 1 } else { 0 }) + (if s.in_script_setup(t, node) {
				1
			} else {
				0
			})
			if times == 0 {
				continue
			}
			stats.checked++
			if !c.vue_is_deprecated_delete_set_call(root, t, node) {
				continue
			}
			for _ in 0 .. times {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'deprecated'
				}
			}
		}
	}
	// import { set } from 'vue'; set() and const { set } = require('vue'); set()
	call_trace := EsTrace{
		call: true
	}
	traced := c.es_esm_references(root, {
		'vue': EsTrace{
			esm:      true
			children: {
				'set': call_trace
				'del': call_trace
			}
		}
	})
	mut all := traced.clone()
	all << c.es_cjs_references(root, {
		'vue': EsTrace{
			children: {
				'set': call_trace
				'del': call_trace
			}
		}
	})
	for r in all {
		call := c.es_index_of(t, r.node) or { continue }
		callee := t.node(call, .callee) or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, callee)
			message_id: 'deprecated'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_is_deprecated_delete_set_call is getVueDeprecatedCallExpression: the identifier is in the
// callee `x.y` of a call, and is `$set` or `$delete` with `this` as `x`, or `set` or `delete` with
// `Vue` as `x`.
fn (mut c Checker) vue_is_deprecated_delete_set_call(root C.vt_node, t &estree.EsTree, node int) bool {
	member := t.nodes[node].parent
	if member < 0 || t.typ(member) != .member_expression {
		return false
	}
	call := t.nodes[member].parent
	if call < 0 || t.typ(call) != .call_expression || (t.node(call, .callee) or { -1 }) != member {
		return false
	}
	name := t.string_of(node, .name) or { return false }
	object := t.node(member, .object) or { return false }
	if name in ['\$set', '\$delete'] && c.vue_is_this(root, t, object) {
		return true
	}
	return name in ['set', 'delete'] && t.typ(object) == .identifier
		&& (t.string_of(object, .name) or { '' }) == 'Vue'
}
