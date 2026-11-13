module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-useless-call` rule of ESLint 10.6.0 (it has no options).

const nuca2_messages = {
	'unnecessaryCall': "Unnecessary '.{{name}}()'."
}

fn (mut c Checker) lint_no_useless_call(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['call_expression'], []) {
		args := (call_arguments(node) or { continue }).filter(node_kind(it) != 'comment')
		callee := unwrap_parens(node_field(node, 'function') or { continue })
		if node_kind(callee) != 'member_expression' {
			continue
		}
		property := node_field(callee, 'property') or { continue }
		if node_kind(property) != 'property_identifier' {
			continue
		}
		stats.checked++
		name := c.text(property)
		// `.call(thisArg, …)` and `.apply(thisArg, [ … ])`.
		if !((name == 'call' && args.len >= 1) || (name == 'apply' && args.len == 2
			&& node_kind(unwrap_parens(args[1])) == 'array')) {
			continue
		}
		applied := unwrap_parens(node_field(callee, 'object') or { continue })
		if c.es_valid_this_arg(applied, args[0]) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unnecessaryCall'
				data:       {
					'name': name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
