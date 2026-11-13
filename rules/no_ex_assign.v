module rules

import time
import treesitter { position_of }

// Port of the `no-ex-assign` rule of ESLint 10.6.0 (it has no options).

const nexa_messages = {
	'unexpected': 'Do not assign to the exception parameter.'
}

fn (mut c Checker) lint_no_ex_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['catch_clause'], []) {
		stats.checked++
		tree := c.scope_tree(root)
		for v in c.es_declared_variables(root, node) {
			for r in es_modifying_references(tree, v) {
				id := tree.references[r].identifier
				findings << Finding{
					stmt:       position_of(id)
					message_id: 'unexpected'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
