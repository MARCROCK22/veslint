module rules

import time
import treesitter { node_field, position_of }

// Port of the `no-self-compare` rule of ESLint 10.6.0 (it has no options).

const nsc_messages = {
	'comparingToSelf': 'Comparing to itself is potentially pointless.'
}

const nsc_operators = ['===', '==', '!==', '!=', '>', '<', '>=', '<=']

fn (mut c Checker) lint_no_self_compare(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		if c.text(node_field(node, 'operator') or { continue }) !in nsc_operators {
			continue
		}
		stats.checked++
		left := node_field(node, 'left') or { continue }
		right := node_field(node, 'right') or { continue }
		// hasSameTokens: the same tokens, comments aside.
		if c.es_equal_tokens(left, right) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'comparingToSelf'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
