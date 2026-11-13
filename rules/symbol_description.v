module rules

import time
import treesitter { node_kind, position_of }

// Port of the `symbol-description` rule of ESLint 10.6.0 (it has no options).

const sd_messages = {
	'expected': 'Expected Symbol to have a description.'
}

fn (mut c Checker) lint_symbol_description(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for id in c.es_global_variable_references(root, 'Symbol') {
		stats.checked++
		call := es_callee_of(id) or { continue }
		if node_kind(call) != 'call_expression' {
			continue
		}
		args := (call_arguments(call) or { continue }).filter(node_kind(it) != 'comment')
		if args.len == 0 {
			findings << Finding{
				stmt:       position_of(call)
				message_id: 'expected'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
