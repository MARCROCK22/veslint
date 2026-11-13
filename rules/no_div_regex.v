module rules

import time
import treesitter { node_start, position_of }

// Port of the `no-div-regex` rule of ESLint 10.6.0 (it has no options).

const ndr_messages = {
	'unexpected': "A regular expression literal can be confused with '/='."
}

fn (mut c Checker) lint_no_div_regex(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['regex'], []) {
		stats.checked++
		start := node_start(node)
		if start + 1 < c.src.len && c.src[start + 1] == `=` {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
				has_fix:    true
				fix:        Fix{start + 1, start + 2, '[=]'}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
