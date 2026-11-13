module rules

import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-unassigned-vars` rule of ESLint 10.6.0 (it has no options).

const nuv2_messages = {
	'unassigned': "'{{name}}' is always 'undefined' because it's never assigned."
}

fn (mut c Checker) lint_no_unassigned_vars(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['variable_declarator'], []) {
		if _ := node_field(node, 'value') {
			continue
		}
		name := node_field(node, 'name') or { continue }
		if node_kind(name) != 'identifier' {
			continue
		}
		declaration := node_parent(node) or { continue }
		if kind := node_field(declaration, 'kind') {
			if node_kind(kind) == 'const' {
				continue
			}
		}
		// `declare let x;`, or inside `declare module` / `declare global`.
		if nuv2_is_ambient(declaration) {
			continue
		}
		stats.checked++
		tree := c.scope_tree(root)
		v := tree.declared_variable(name)
		if v < 0 {
			continue
		}
		mut has_read := false
		mut written := false
		for r in tree.variables[v].references {
			reference := tree.references[r]
			if reference.write {
				written = true
				break
			}
			if reference.read {
				has_read = true
			}
		}
		if written || !has_read {
			continue
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'unassigned'
			data:       {
				'name': c.text(name)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn nuv2_is_ambient(n C.TSNode) bool {
	mut current := n
	for {
		current = node_parent(current) or { return false }
		if node_kind(current) == 'ambient_declaration' {
			return true
		}
	}
	return false
}
