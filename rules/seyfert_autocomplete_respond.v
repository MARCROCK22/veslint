module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `autocomplete-respond` rule of @slipher/eslint-plugin 1.1.0 (it has no options):
// `x.reply(...)` where the type of `x` is, or extends, seyfert's AutocompleteInteraction.

const sy_ar_messages = {
	'useRespond': 'Use `.respond()` on an autocomplete interaction; `.reply()` is internal and throws.'
}

fn (mut c Checker) lint_seyfert_autocomplete_respond(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// CallExpression whose callee is a non-computed MemberExpression with the Identifier `reply`.
	mut properties := []C.TSNode{}
	mut objects := []C.TSNode{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		call_arguments(call) or { continue }
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		if node_kind(callee) != 'member_expression' {
			continue
		}
		property := node_field(callee, 'property') or { continue }
		if node_kind(property) != 'property_identifier' || c.identifier_name(property) != 'reply' {
			continue
		}
		object := node_field(callee, 'object') or { continue }
		properties << property
		objects << unwrap_parens(object)
	}
	c.resolve_node_types(objects, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, property in properties {
		t := c.node_type(objects[i]) or { continue }
		if c.sy_extends_class(t, ['AutocompleteInteraction'])! {
			findings << Finding{
				stmt:       position_of(property)
				message_id: 'useRespond'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += properties.len
	return findings
}
