module rules

import time
import offsets
import treesitter { node_kind, node_parent, node_start, position_of }

// Port of the `block-scoped-var` rule of ESLint 10.6.0 (it has no options).

const bsv_messages = {
	'outOfScope': "'{{name}}' declared on line {{definitionLine}} column {{definitionColumn}} is used outside of binding context."
}

const bsv_scope_kinds = ['statement_block', 'for_statement', 'for_in_statement', 'switch_statement',
	'catch_clause', 'class_static_block']

fn (mut c Checker) lint_block_scoped_var(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	lines := offsets.line_starts(c.src)
	for node in c.nodes_of_kinds(root, ['variable_declaration', 'for_in_statement'], []) {
		// `for (var a in b)`: the declaration is part of the for-in for tree-sitter.
		if node_kind(node) == 'for_in_statement' {
			kind := treesitter.node_field(node, 'kind') or { continue }
			if node_kind(kind) != 'var' {
				continue
			}
		}
		stats.checked++
		// The range of the closest block, loop, switch, catch clause or static block (the
		// program otherwise); the body of a static block is that block.
		mut start := node_start(root)
		mut end := c.es_end(root)
		mut current := node
		if node_kind(node) == 'for_in_statement' {
			start = node_start(node)
			end = c.es_end(node)
		}
		for node_kind(node) != 'for_in_statement' {
			current = node_parent(current) or { break }
			kind := node_kind(current)
			if kind == 'statement_block' {
				if parent := node_parent(current) {
					if node_kind(parent) == 'class_static_block' {
						continue
					}
				}
			}
			if kind in bsv_scope_kinds {
				start = node_start(current)
				end = c.es_end(current)
				break
			}
		}
		tree := c.scope_tree(root)
		for v in c.es_declared_variables(root, node) {
			variable := tree.variables[v]
			mut definition := ?ScopeDefinition(none)
			for def in variable.defs {
				if parent := es_def_parent(def) {
					if node_key(parent) == node_key(node) {
						definition = def
						break
					}
				}
			}
			def := definition or { continue }
			line, column := c.line_column(lines, node_start(def.name))
			for r in variable.references {
				id := tree.references[r].identifier
				if node_start(id) >= start && c.es_end(id) <= end {
					continue
				}
				findings << Finding{
					stmt:       position_of(id)
					message_id: 'outOfScope'
					data:       {
						'name':             c.text(id)
						'definitionLine':   '${line}'
						'definitionColumn': '${column}'
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
