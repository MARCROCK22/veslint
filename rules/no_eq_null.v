module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-eq-null` rule of ESLint 10.6.0 (it has no options).

const neqn_messages = {
	'unexpected': "Use '===' to compare with null."
}

fn (mut c Checker) lint_no_eq_null(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		stats.checked++
		if operator_of(node) !in ['==', '!='] {
			continue
		}
		left := unwrap_parens(node_field(node, 'left') or { continue })
		right := unwrap_parens(node_field(node, 'right') or { continue })
		if node_kind(left) == 'null' || node_kind(right) == 'null' {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
