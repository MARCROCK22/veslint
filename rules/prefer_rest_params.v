module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `prefer-rest-params` rule of ESLint 10.6.0 (it has no options).

const prp_messages = {
	'preferRestParams': "Use the rest parameters instead of 'arguments'."
}

fn (mut c Checker) lint_prefer_rest_params(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	kinds := ['function_declaration', 'function_expression', 'generator_function',
		'generator_function_declaration', 'method_definition']
	for node in c.nodes_of_kinds(root, kinds, []) {
		body := node_field(node, 'body') or { continue }
		stats.checked++
		tree := c.scope_tree(root)
		scope := tree.get_scope(body)
		// The function's own `arguments` (implicit: no identifiers).
		mut function_scope := scope
		for function_scope >= 0 && tree.scopes[function_scope].kind != .function {
			function_scope = tree.scopes[function_scope].upper
		}
		if function_scope < 0 {
			continue
		}
		v := tree.own_variable(function_scope, 'arguments')
		if v < 0 || tree.variables[v].identifiers.len > 0 {
			continue
		}
		for r in tree.variables[v].references {
			id := tree.references[r].identifier
			// `arguments.length` and other normal member accesses are fine.
			if parent := cti_estree_parent(id) {
				if node_kind(parent) == 'member_expression' {
					object := node_field(parent, 'object') or { parent }
					if node_key(unwrap_parens(object)) == node_key(id) {
						continue
					}
				}
			}
			findings << Finding{
				stmt:       position_of(id)
				message_id: 'preferRestParams'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
