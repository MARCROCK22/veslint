module rules

import time
import tsgo { handle_path }
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `i18n-resolve-with-get` rule of @slipher/eslint-plugin 1.1.0 (it has no options): an
// expression of a template literal, or an operand of `+`, whose type has a `get` declared in
// seyfert's lib/langs (the proxy `ctx.t` gives).

const sy_irwg_messages = {
	'callGet': '`ctx.t` returns a locale proxy — resolve it with `.get()` before using it as a string.'
}

fn (mut c Checker) lint_seyfert_i18n_resolve_with_get(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// The expressions of each TemplateLiteral, and the left and right of each BinaryExpression with
	// `+`, in the order ESLint visits them.
	mut expressions := []C.TSNode{}
	for node in c.nodes_of_kinds(root, ['template_string', 'binary_expression'], []) {
		if node_kind(node) == 'template_string' {
			for substitution in named_children(node) {
				if node_kind(substitution) == 'template_substitution' {
					expression := first_named(substitution) or { continue }
					expressions << unwrap_parens(expression)
				}
			}
		} else if operator_of(node) == '+' {
			left := node_field(node, 'left') or { continue }
			right := node_field(node, 'right') or { continue }
			expressions << unwrap_parens(left)
			expressions << unwrap_parens(right)
		}
	}
	c.resolve_node_types(expressions, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for expression in expressions {
		t := c.node_type(expression) or { continue }
		get := c.property(t, 'get')!
		if get.declarations.any(sy_in_path(handle_path(it), '/seyfert/lib/langs/')) {
			findings << Finding{
				stmt:       position_of(expression)
				message_id: 'callGet'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += expressions.len
	return findings
}
