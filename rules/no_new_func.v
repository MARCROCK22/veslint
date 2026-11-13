module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-new-func` rule of ESLint 10.6.0 (it has no options).

const nnf_messages = {
	'noFunctionConstructor': 'The Function constructor is eval.'
}

fn (mut c Checker) lint_no_new_func(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for id in c.es_global_variable_references(root, 'Function') {
		stats.checked++
		// `new Function()`, `Function()`, and `Function.call()`, `.apply()` and `.bind()`.
		if call := es_callee_of(id) {
			findings << Finding{
				stmt:       position_of(call)
				message_id: 'noFunctionConstructor'
			}
			continue
		}
		member := cti_estree_parent(id) or { continue }
		if node_kind(member) !in ['member_expression', 'subscript_expression'] {
			continue
		}
		object := node_field(member, 'object') or { continue }
		if node_key(unwrap_parens(object)) != node_key(id) {
			continue
		}
		name := c.es_static_property_name(member) or { continue }
		if name !in ['apply', 'bind', 'call'] {
			continue
		}
		if call := es_callee_of(member) {
			if node_kind(call) == 'call_expression' {
				findings << Finding{
					stmt:       position_of(call)
					message_id: 'noFunctionConstructor'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
