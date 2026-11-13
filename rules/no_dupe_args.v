module rules

import time
import treesitter { node_field, position_of }

// Port of the `no-dupe-args` rule of ESLint 10.6.0 (it has no options).

const nda_messages = {
	'unexpected': "Duplicate param '{{name}}'."
}

fn (mut c Checker) lint_no_dupe_args(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	kinds := ['function_declaration', 'function_expression', 'generator_function',
		'generator_function_declaration', 'method_definition']
	for node in c.nodes_of_kinds(root, kinds, []) {
		parameters := node_field(node, 'parameters') or { continue }
		stats.checked++
		tree := c.scope_tree(root)
		scope := tree.get_scope(parameters)
		// The variables the function declares, in order: those with two parameter definitions.
		for v in tree.scopes[scope].variables {
			variable := tree.variables[v]
			if variable.defs.filter(it.kind == .parameter).len >= 2 {
				findings << Finding{
					stmt:       position_of(parameters)
					message_id: 'unexpected'
					data:       {
						'name': variable.name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
