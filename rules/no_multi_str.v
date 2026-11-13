module rules

import time
import treesitter { node_kind, node_parent, position_of }

// Port of the `no-multi-str` rule of ESLint 10.6.0 (it has no options).

const nmstr_messages = {
	'multilineString': 'Multiline support is limited to browsers supporting ES5 only.'
}

fn (mut c Checker) lint_no_multi_str(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['string'], []) {
		stats.checked++
		parent := node_parent(node) or { continue }
		// A string of a JSX attribute is a Literal whose parent is a JSX node.
		if node_kind(parent).starts_with('jsx') {
			continue
		}
		if es_has_line_break(c.text(node)) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'multilineString'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
