module rules

import time
import treesitter { position_of }

// Port of the `no-debugger` rule of ESLint 10.6.0 (it has no options).

const nd_messages = {
	'unexpected': "Unexpected 'debugger' statement."
}

fn (mut c Checker) lint_no_debugger(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['debugger_statement'], []) {
		stats.checked++
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'unexpected'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
