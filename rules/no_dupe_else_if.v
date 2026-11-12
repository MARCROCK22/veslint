module rules

import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-dupe-else-if` rule of ESLint 10.6.0 (it has no options).

const ndei_messages = {
	'unexpected': 'This branch can never execute. Its condition is a duplicate or covered by previous conditions in the if-else-if chain.'
}

fn (mut c Checker) lint_no_dupe_else_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['if_statement'], []) {
		test := unwrap_parens(node_field(node, 'condition') or { continue })
		stats.checked++
		// The test and, when it is a `&&`, each of its operands: the or-operands of each one,
		// each split into its and-operands.
		mut conditions := [test]
		if estree_binary_kind(test) == 'LogicalExpression' && operator_of(test) == '&&' {
			conditions << ndei_split(test, '&&')
		}
		mut list := conditions.map(ndei_or_operands(it))
		mut current := node
		for {
			current = ndei_else_if_parent(current) or { break }
			current_or := ndei_or_operands(node_field(current, 'condition') or { break })
			// The or-operands that no or-operand of the earlier test covers.
			mut next := [][][]C.TSNode{}
			for or_operands in list {
				mut kept := [][]C.TSNode{}
				for or_operand in or_operands {
					mut covered := false
					for current_operand in current_or {
						if c.ndei_is_subset(current_operand, or_operand) {
							covered = true
							break
						}
					}
					if !covered {
						kept << or_operand
					}
				}
				next << kept
			}
			list = next.clone()
			if list.any(it.len == 0) {
				findings << Finding{
					stmt:       position_of(test)
					message_id: 'unexpected'
				}
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ndei_split ports splitByLogicalOperator: the operands of a chain of LogicalExpressions with that
// operator (parentheses are not ESTree nodes), or the node itself.
fn ndei_split(n C.TSNode, operator string) []C.TSNode {
	node := unwrap_parens(n)
	if estree_binary_kind(node) == 'LogicalExpression' && operator_of(node) == operator {
		left := node_field(node, 'left') or { return [node] }
		right := node_field(node, 'right') or { return [node] }
		mut out := ndei_split(left, operator)
		out << ndei_split(right, operator)
		return out
	}
	return [node]
}

// ndei_or_operands is splitByOr(node).map(splitByAnd).
fn ndei_or_operands(n C.TSNode) [][]C.TSNode {
	return ndei_split(n, '||').map(ndei_split(it, '&&'))
}

// ndei_else_if_parent is the IfStatement whose alternate is `n` (an `else if`).
fn ndei_else_if_parent(n C.TSNode) ?C.TSNode {
	clause := node_parent(n)?
	if node_kind(clause) != 'else_clause' {
		return none
	}
	parent := node_parent(clause)?
	if node_kind(parent) != 'if_statement' {
		return none
	}
	return parent
}

// ndei_equal ports equal: the same ESTree type and, for `||` and `&&` with the same operator, equal
// operands in either order (the operators are commutative in a test); equalTokens otherwise.
fn (mut c Checker) ndei_equal(a C.TSNode, b C.TSNode) bool {
	x := unwrap_parens(a)
	y := unwrap_parens(b)
	if estree_type(x) != estree_type(y) {
		return false
	}
	if estree_binary_kind(x) == 'LogicalExpression' {
		operator := operator_of(x)
		if operator in ['||', '&&'] && operator == operator_of(y) {
			xl := node_field(x, 'left') or { return false }
			xr := node_field(x, 'right') or { return false }
			yl := node_field(y, 'left') or { return false }
			yr := node_field(y, 'right') or { return false }
			return (c.ndei_equal(xl, yl) && c.ndei_equal(xr, yr))
				|| (c.ndei_equal(xl, yr) && c.ndei_equal(xr, yl))
		}
	}
	return c.es_equal_tokens(x, y)
}

// ndei_is_subset ports isSubsetByComparator(equal, a, b): each node of `a` equals one of `b`.
fn (mut c Checker) ndei_is_subset(a []C.TSNode, b []C.TSNode) bool {
	for x in a {
		mut found := false
		for y in b {
			if c.ndei_equal(x, y) {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}
