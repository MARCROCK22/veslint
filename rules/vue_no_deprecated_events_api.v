module rules

import time

// Port of the `vue/no-deprecated-events-api` rule of eslint-plugin-vue 10.12.1 (no options): a
// call of `this.$on`, `this.$off` or `this.$once` (not an optional call) in a Vue object,
// reported at the property.

const vue_no_deprecated_events_api_messages = {
	'noDeprecatedEventsApi': 'The Events api `$on`, `$off` `$once` is deprecated. Using external library instead, for example mitt.'
}

fn (mut c Checker) lint_vue_no_deprecated_events_api(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	for node in 0 .. t.nodes.len {
		// 'CallExpression > MemberExpression, CallExpression > ChainExpression > MemberExpression'
		if t.typ(node) != .member_expression || s.owner_of(node) < 0 {
			continue
		}
		parent := t.nodes[node].parent
		if parent < 0 {
			continue
		}
		mut call := parent
		if t.typ(parent) == .chain_expression {
			call = t.nodes[parent].parent
		}
		if call < 0 || t.typ(call) != .call_expression {
			continue
		}
		stats.checked++
		if (t.flag(call, .optional) or { false })
			|| vue_skip_chain(t, t.node(call, .callee) or { -1 }) != node {
			continue
		}
		name := vue_static_property_name(t, node) or { '' }
		if name !in ['$on', '$off', '$once'] || !c.vue_is_this(root, t, t.node(node, .object) or { -1 }) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, t.node(node, .property) or { continue })
			message_id: 'noDeprecatedEventsApi'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
