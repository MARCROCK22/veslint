module rules

import time
import treesitter { position_of }

// Port of the `no-func-assign` rule of ESLint 10.6.0 (it has no options).

const nfa_messages = {
	'isAFunction': "'{{name}}' is a function."
}

fn (mut c Checker) lint_no_func_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['function_declaration', 'function_expression',
		'generator_function', 'generator_function_declaration'], []) {
		stats.checked++
		tree := c.scope_tree(root)
		for v in c.es_declared_variables(root, node) {
			if tree.variables[v].defs.len == 0 || tree.variables[v].defs[0].kind != .function_name {
				continue
			}
			for r in es_modifying_references(tree, v) {
				id := tree.references[r].identifier
				findings << Finding{
					stmt:       position_of(id)
					message_id: 'isAFunction'
					data:       {
						'name': c.text(id)
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
