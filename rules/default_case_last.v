module rules

import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `default-case-last` rule of ESLint 10.6.0 (it has no options).

const dcl_messages = {
	'notLast': 'Default clause should be the last clause.'
}

fn (mut c Checker) lint_default_case_last(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['switch_statement'], []) {
		body := node_field(node, 'body') or { continue }
		stats.checked++
		cases := named_children(body).filter(node_kind(it) in ['switch_case', 'switch_default'])
		mut index := -1
		for i, clause in cases {
			if node_kind(clause) == 'switch_default' {
				index = i
				break
			}
		}
		if index >= 0 && index != cases.len - 1 {
			findings << Finding{
				stmt:       position_of(cases[index])
				message_id: 'notLast'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
