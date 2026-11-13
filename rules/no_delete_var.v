module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-delete-var` rule of ESLint 10.6.0 (it has no options).

const ndv_messages = {
	'unexpected': 'Variables should not be deleted.'
}

fn (mut c Checker) lint_no_delete_var(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['unary_expression'], []) {
		stats.checked++
		if operator_of(node) != 'delete' {
			continue
		}
		argument := unwrap_parens(node_field(node, 'argument') or { continue })
		if node_kind(argument) in ['identifier', 'undefined'] {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
