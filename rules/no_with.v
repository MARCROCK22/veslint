module rules

import time
import treesitter { children, position_of }

// Port of the `no-with` rule of ESLint 10.6.0 (it has no options).

const nw_messages = {
	'unexpectedWith': "Unexpected use of 'with' statement."
}

fn (mut c Checker) lint_no_with(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['with_statement'], []) {
		stats.checked++
		// At the `with` keyword, the first token of the statement.
		findings << Finding{
			stmt:       position_of(children(node)[0])
			message_id: 'unexpectedWith'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
