module rules

import time
import treesitter { children, named_children, node_field, node_kind }

// Port of the `require-yield` rule of ESLint 10.6.0 (it has no options).

const ry_messages = {
	'missingYield': "This generator function does not have 'yield'."
}

const ry_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition']

fn (mut c Checker) lint_require_yield(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	kinds := ['generator_function', 'generator_function_declaration', 'method_definition']
	for node in c.nodes_of_kinds(root, kinds, []) {
		if node_kind(node) == 'method_definition' && !children(node).any(node_kind(it) == '*') {
			continue
		}
		body := node_field(node, 'body') or { continue }
		stats.checked++
		if !named_children(body).any(node_kind(it) != 'comment') {
			continue
		}
		// The yields of the function itself, not of the functions inside it.
		if c.nodes_of_kinds(body, ['yield_expression'], ry_function_kinds).len > 0 {
			continue
		}
		findings << Finding{
			stmt:       function_head(node)
			message_id: 'missingYield'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
