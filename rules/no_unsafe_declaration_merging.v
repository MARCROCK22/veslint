module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-unsafe-declaration-merging` rule of typescript-eslint 8.62.0 (it has no
// options).

const nudm_messages = {
	'unsafeMerging': 'Unsafe declaration merging between classes and interfaces.'
}

fn (mut c Checker) lint_no_unsafe_declaration_merging(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	tree := c.scope_tree(root)
	for node in c.nodes_of_kinds(root, ['class_declaration', 'abstract_class_declaration',
		'interface_declaration'], []) {
		id := node_field(node, 'name') or { continue }
		checked++
		if node_kind(node) == 'interface_declaration' {
			// TSInterfaceDeclaration: the scope of the interface, which is its own type scope when it
			// has type parameters.
			c.nudm_check(tree, tree.get_scope(node), id, ['class_declaration',
				'abstract_class_declaration'], mut findings)
		} else {
			// ClassDeclaration: getScope gives the class scope, and the merged variables are in the
			// scope around it.
			upper := tree.scopes[tree.get_scope(node)].upper
			if upper < 0 {
				continue
			}
			c.nudm_check(tree, upper, id, ['interface_declaration'], mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nudm_check ports checkUnsafeDeclaration: the variable the name has in `scope` has several
// definitions and one of them is a declaration of the unsafe kind.
fn (c &Checker) nudm_check(tree &ScopeTree, scope int, id C.TSNode, unsafe_kinds []string, mut findings []Finding) {
	variable := tree.own_variable(scope, c.identifier_name(id))
	if variable < 0 {
		return
	}
	defs := tree.variables[variable].defs
	if defs.len <= 1 {
		return
	}
	if defs.any(node_kind(it.node) in unsafe_kinds) {
		findings << Finding{
			stmt:       position_of(id)
			message_id: 'unsafeMerging'
		}
	}
}
