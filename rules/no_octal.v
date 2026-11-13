module rules

import time
import treesitter { position_of }

// Port of the `no-octal` rule of ESLint 10.6.0 (it has no options).

const noc_messages = {
	'noOctal': 'Octal literals should not be used.'
}

fn (mut c Checker) lint_no_octal(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['number'], []) {
		stats.checked++
		text := c.text(node)
		// A number (not a BigInt) written /^0\d/.
		if text.len > 1 && text[0] == `0` && text[1].is_digit() && !text.ends_with('n') {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'noOctal'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
