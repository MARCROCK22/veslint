module rules

import json2

// Port of the `vue/no-console` rule of eslint-plugin-vue 10.12.1: ESLint core's no-console
// wrapped with skipBaseHandlers, so only the wrapper's own listener runs on the template (option
// `allow`, the methods allowed; no suggestion). It goes through vue_wrap.v like the other
// wrappers: vue_wrap_no_console_base runs on a snippet.

const vncon_messages = {
	'unexpected': 'Unexpected console statement.'
}

// vncon_allowed reads `allow` of the first option (`context.options[0] || {}`).
fn vncon_allowed(options []json2.Any) []string {
	if options.len == 0 {
		return []
	}
	first := options[0]
	if first !is map[string]json2.Any {
		return []
	}
	allow := (first as map[string]json2.Any)['allow'] or { return [] }
	if allow !is []json2.Any {
		return []
	}
	mut out := []string{}
	for item in allow as []json2.Any {
		if item is string {
			out << item
		}
	}
	return out
}

fn (mut c Checker) vue_wrap_no_console_base(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	mut findings := []Finding{}
	allowed := vncon_allowed(c.rule_options(vue_wrap_no_console))
	t := c.es_tree(root, abs_path) or { return findings }
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .member_expression {
			continue
		}
		node := step.node
		stats.checked++
		object := t.node(node, .object) or { continue }
		if t.typ(object) != .identifier || (t.string_of(object, .name) or { '' }) != 'console' {
			continue
		}
		name := vue_static_property_name(t, node) or { '' }
		if name != '' && name in allowed {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, object)
			message_id: 'unexpected'
		}
	}
	return findings
}
