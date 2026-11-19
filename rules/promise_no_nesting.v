module rules

import time
import treesitter { node_end, node_start }

// Port of the `promise/no-nesting` rule of eslint-plugin-promise 7.3.0 (it has no options).

const prm_no_nesting_messages = {
	'avoidNesting': 'Avoid nesting promises.'
}

fn (mut c Checker) lint_promise_no_nesting(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	// callbackScopes: the scopes of the callback functions around, the closest last.
	mut callback_scopes := []int{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if typ in [.function_declaration, .function_expression, .arrow_function_expression] {
			if !prm_is_inside_promise(t, node) {
				continue
			}
			if step.leave {
				callback_scopes.delete_last()
			} else {
				ts := t.ts_node(node) or { continue }
				callback_scopes << tree.get_scope(ts)
			}
			continue
		}
		if step.leave || typ != .call_expression {
			continue
		}
		stats.checked++
		if !prm_has_promise_callback(t, node) || callback_scopes.len == 0 {
			continue
		}
		closest := callback_scopes.last()
		args := t.list(node, .arguments) or { []int{} }
		mut uses_variable := false
		for v in tree.scopes[closest].variables {
			for r in tree.variables[v].references {
				identifier := tree.references[r].identifier
				if args.any(t.nodes[it].start <= node_start(identifier)
					&& node_end(identifier) <= t.nodes[it].end) {
					uses_variable = true
					break
				}
			}
			if uses_variable {
				break
			}
		}
		if uses_variable {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, prm_child(t, prm_child(t, node, .callee), .property))
			message_id: 'avoidNesting'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
