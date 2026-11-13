module rules

import time
import treesitter { node_kind, position_of }

// Port of the `no-new` rule of ESLint 10.6.0 (it has no options).

const nnew_messages = {
	'noNewStatement': "Do not use 'new' for side effects."
}

fn (mut c Checker) lint_no_new(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['expression_statement'], []) {
		stats.checked++
		expression := unwrap_parens(first_named(node) or { continue })
		if node_kind(expression) == 'new_expression' {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'noNewStatement'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
