module rules

import time
import treesitter { named_children, node_kind, node_parent, position_of }

// Port of the `no-constructor-return` rule of ESLint 10.6.0 (it has no options).

const ncr_messages = {
	'unexpected': 'Unexpected return statement in constructor.'
}

fn (mut c Checker) lint_no_constructor_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['return_statement'], []) {
		stats.checked++
		if named_children(node).filter(node_kind(it) != 'comment').len == 0 {
			continue
		}
		// The node of the innermost code path: a function, a static block or the program.
		mut current := node
		for {
			current = node_parent(current) or { break }
			kind := node_kind(current)
			if kind in function_kinds || kind == 'class_static_block' {
				break
			}
		}
		if node_kind(current) != 'method_definition' {
			continue
		}
		owner := node_parent(current) or { continue }
		if node_kind(owner) == 'class_body' && c.cm_method_kind(current) == 'constructor' {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
