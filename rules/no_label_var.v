module rules

import time
import treesitter { node_field, position_of }

// Port of the `no-label-var` rule of ESLint 10.6.0 (it has no options).

const nlv_messages = {
	'identifierClashWithLabel': 'Found identifier with same name as label.'
}

fn (mut c Checker) lint_no_label_var(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['labeled_statement'], []) {
		label := node_field(node, 'label') or { continue }
		stats.checked++
		tree := c.scope_tree(root)
		if tree.find_variable(tree.get_scope(node), c.text(label), -1) >= 0 {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'identifierClashWithLabel'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
