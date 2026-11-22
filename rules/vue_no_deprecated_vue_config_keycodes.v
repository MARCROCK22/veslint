module rules

import time

// Port of the `vue/no-deprecated-vue-config-keycodes` rule of eslint-plugin-vue 10.12.1 (no
// options): `Vue.config.keyCodes`.

const vue_no_deprecated_vue_config_keycodes_messages = {
	'unexpected': '`Vue.config.keyCodes` are deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_vue_config_keycodes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		// "MemberExpression[property.type='Identifier'][property.name='keyCodes']"
		if t.typ(node) != .member_expression {
			continue
		}
		property := t.node(node, .property) or { continue }
		if t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != 'keyCodes' {
			continue
		}
		stats.checked++
		config := vue_skip_chain(t, t.node(node, .object) or { continue })
		if t.typ(config) != .member_expression {
			continue
		}
		config_property := t.node(config, .property) or { continue }
		object := t.node(config, .object) or { continue }
		if t.typ(config_property) != .identifier
			|| (t.string_of(config_property, .name) or { '' }) != 'config'
			|| t.typ(object) != .identifier || (t.string_of(object, .name) or { '' }) != 'Vue' {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'unexpected'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
