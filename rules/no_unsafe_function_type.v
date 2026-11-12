module rules

import time
import treesitter { position_of }

// Port of the `no-unsafe-function-type` rule of typescript-eslint 8.62.0 (it has no options).

const nuft_messages = {
	'bannedFunctionType': 'The `Function` type accepts any function-like value.\nPrefer explicitly defining any function parameters and return type.'
}

fn (mut c Checker) lint_no_unsafe_function_type(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	scopes := c.scope_tree(root)
	// The name of a TSTypeReference, a TSClassImplements or a TSInterfaceHeritage that is
	// `Function`, the global one.
	for node in c.nodes_of_kind(root, c'type_identifier') {
		if c.text(node) != 'Function' || type_name_role(node) == .other {
			continue
		}
		checked++
		if is_reference_to_global_function(scopes, node, 'Function') {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'bannedFunctionType'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
