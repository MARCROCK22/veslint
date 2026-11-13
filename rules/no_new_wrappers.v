module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-new-wrappers` rule of ESLint 10.6.0 (it has no options).

const nnwr_messages = {
	'noConstructor': 'Do not use {{fn}} as a constructor.'
}

fn (mut c Checker) lint_no_new_wrappers(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['new_expression'], []) {
		stats.checked++
		callee := unwrap_parens(node_field(node, 'constructor') or { continue })
		if node_kind(callee) != 'identifier' {
			continue
		}
		name := c.text(callee)
		if name !in ['String', 'Number', 'Boolean'] {
			continue
		}
		// getVariableByName: the variable of that name the scope sees, a builtin one.
		tree := c.scope_tree(root)
		v := tree.find_variable(tree.get_scope(node), name, -1)
		if v >= 0 && tree.variables[v].identifiers.len == 0 {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'noConstructor'
				data:       {
					'fn': name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
