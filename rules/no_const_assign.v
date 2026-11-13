module rules

import time
import treesitter { node_kind, position_of }

// Port of the `no-const-assign` rule of ESLint 10.6.0 (it has no options).

const ncona_messages = {
	'const': "'{{name}}' is constant."
}

fn (mut c Checker) lint_no_const_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['lexical_declaration'], []) {
		// const, `using` and `await using`: a constant binding.
		if kind := treesitter.node_field(node, 'kind') {
			if node_kind(kind) !in ['const', 'using', 'await'] {
				continue
			}
		} else {
			continue
		}
		stats.checked++
		tree := c.scope_tree(root)
		for v in c.es_declared_variables(root, node) {
			for r in es_modifying_references(tree, v) {
				id := tree.references[r].identifier
				findings << Finding{
					stmt:       position_of(id)
					message_id: 'const'
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
