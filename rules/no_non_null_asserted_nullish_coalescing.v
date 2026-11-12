module rules

import time
import treesitter { node_end, node_field, node_kind, position_of }

// Port of the `no-non-null-asserted-nullish-coalescing` rule of typescript-eslint 8.62.0 (it has no
// options), with its suggestion.

const nnanc_messages = {
	'noNonNullAssertedNullishCoalescing': 'The nullish coalescing operator is designed to handle undefined and null - using a non-null assertion is not needed.'
	'suggestRemovingNonNull':             'Remove the non-null assertion.'
}

fn (mut c Checker) lint_no_non_null_asserted_nullish_coalescing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for binary in c.nodes_of_kinds(root, ['binary_expression'], []) {
		// `LogicalExpression[operator = "??"] > TSNonNullExpression.left`: a `!` that ends an optional
		// chain (`a?.b!`) is inside its ChainExpression.
		if operator_of(binary) != '??' {
			continue
		}
		left := node_field(binary, 'left') or { continue }
		node := unwrap_parens(left)
		if node_kind(node) != 'non_null_expression' || is_estree_chain_root(node) {
			continue
		}
		checked++
		expression := unwrap_parens(first_named(node) or { continue })
		if estree_type(expression) == 'Identifier' {
			// A variable that has no value yet where the `!` is: the assertion tells TypeScript it
			// has one.
			tree := c.scope_tree(root)
			variable := tree.find_variable(tree.get_scope(node), c.identifier_name(expression),
				-1)
			if variable >= 0 && !nnanc_has_assignment_before(tree, variable, node) {
				continue
			}
		}
		// The suggestion removes the last token of the node, its `!`.
		_, suggestion := c.suggestion('suggestRemovingNonNull', map[string]string{}, [
			fix_remove_range(node_end(node) - 1, node_end(node)),
		])!
		findings << Finding{
			stmt:        position_of(node)
			message_id:  'noNonNullAssertedNullishCoalescing'
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nnanc_has_assignment_before ports hasAssignmentBeforeNode: a write reference that ends before
// the end of the node, or a variable definition with an initializer or a definite assignment
// (`let x!: T`) that does.
fn nnanc_has_assignment_before(tree &ScopeTree, variable int, node C.TSNode) bool {
	end := node_end(node)
	for r in tree.variables[variable].references {
		reference := tree.references[r]
		if reference.write && node_end(reference.identifier) < end {
			return true
		}
	}
	for definition in tree.variables[variable].defs {
		if definition.kind != .variable || node_kind(definition.node) != 'variable_declarator' {
			continue
		}
		mut assigned := children_of_kind(definition.node, '!').len > 0
		if _ := definition.init {
			assigned = true
		}
		if assigned && node_end(definition.node) < end {
			return true
		}
	}
	return false
}
