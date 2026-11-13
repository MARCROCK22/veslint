module rules

import time
import treesitter { position_of }

// Port of the `no-proto` rule of ESLint 10.6.0 (it has no options).

const nprt_messages = {
	'unexpectedProto': "The '__proto__' property is deprecated."
}

fn (mut c Checker) lint_no_proto(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['member_expression', 'subscript_expression'], []) {
		stats.checked++
		if (c.es_static_property_name(node) or { continue }) == '__proto__' {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpectedProto'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
