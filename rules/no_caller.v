module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-caller` rule of ESLint 10.6.0 (it has no options).

const ncal_messages = {
	'unexpected': 'Avoid arguments.{{prop}}.'
}

fn (mut c Checker) lint_no_caller(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['member_expression'], []) {
		stats.checked++
		object := unwrap_parens(node_field(node, 'object') or { continue })
		property := node_field(node, 'property') or { continue }
		if node_kind(object) != 'identifier' || c.text(object) != 'arguments'
			|| node_kind(property) != 'property_identifier' {
			continue
		}
		name := c.text(property)
		if name in ['callee', 'caller'] {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
				data:       {
					'prop': name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
