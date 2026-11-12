module rules

import time
import treesitter { node_end, node_field, node_kind, position_of }

// Port of the `no-extra-non-null-assertion` rule of typescript-eslint 8.62.0 (it has no options),
// with its fix.

const nenna_messages = {
	'noExtraNonNullAssertion': 'Forbidden extra non-null assertion.'
}

fn (mut c Checker) lint_no_extra_non_null_assertion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['member_expression', 'subscript_expression', 'call_expression',
		'non_null_expression'], []) {
		// A `!` that is the object or the callee of an element with its own `?.` (`a!?.b`,
		// `a!?.()`), or the expression of another `!` (`a!!`).
		child := match node_kind(node) {
			'non_null_expression' {
				first_named(node) or { continue }
			}
			'call_expression' {
				if !is_chain_element(node) || !is_optional_element(node) {
					continue
				}
				node_field(node, 'function') or { continue }
			}
			else {
				if !is_optional_element(node) {
					continue
				}
				node_field(node, 'object') or { continue }
			}
		}
		checked++
		inner := unwrap_parens(child)
		// A `!` that ends an optional chain in parentheses (`(a?.b!)!`, `(a?.b!)?.c`) is inside a
		// ChainExpression in ESTree, so it is not the child of this node there.
		if node_kind(inner) != 'non_null_expression' || is_estree_chain_root(inner) {
			continue
		}
		// The fix removes the last character of the reported `!` expression.
		findings << Finding{
			stmt:       position_of(inner)
			message_id: 'noExtraNonNullAssertion'
			has_fix:    true
			fix:        fix_remove_range(node_end(inner) - 1, node_end(inner))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
