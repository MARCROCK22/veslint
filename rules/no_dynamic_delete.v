module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-dynamic-delete` rule of typescript-eslint 8.62.0 (it has no options).

const ndd_messages = {
	'dynamicDelete': 'Do not delete dynamically computed property keys.'
}

fn (mut c Checker) lint_no_dynamic_delete(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// `delete a[key]`: a computed MemberExpression (not an optional chain, which is a
	// ChainExpression) whose key is not a string or number literal, or `-` and a number literal.
	for node in c.nodes_of_kind(root, c'unary_expression') {
		if operator_of(node) != 'delete' {
			continue
		}
		argument := unwrap_parens(node_field(node, 'argument') or { continue })
		if node_kind(argument) != 'subscript_expression' || estree_type(argument) != 'MemberExpression' {
			continue
		}
		checked++
		property := unwrap_parens(node_field(argument, 'index') or { continue })
		if c.ndd_is_acceptable_index(property) {
			continue
		}
		findings << Finding{
			stmt:       position_of(property)
			message_id: 'dynamicDelete'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// ndd_is_acceptable_index ports isAcceptableIndexExpression: a Literal whose value is a number or
// a string (not a BigInt), or `-` and a number Literal.
fn (c &Checker) ndd_is_acceptable_index(property C.TSNode) bool {
	return match node_kind(property) {
		'string' {
			true
		}
		'number' {
			!c.text(property).ends_with('n')
		}
		'unary_expression' {
			argument := unwrap_parens(node_field(property, 'argument') or { return false })
			operator_of(property) == '-' && node_kind(argument) == 'number'
				&& !c.text(argument).ends_with('n')
		}
		else {
			false
		}
	}
}
