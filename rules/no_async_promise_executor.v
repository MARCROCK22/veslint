module rules

import time
import treesitter { children, node_field, node_kind }

// Port of the `no-async-promise-executor` rule of ESLint 10.6.0 (it has no options).

const nape_messages = {
	'async': 'Promise executor functions should not be async.'
}

fn (mut c Checker) lint_no_async_promise_executor(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['new_expression'], []) {
		callee := unwrap_parens(node_field(node, 'constructor') or { continue })
		if node_kind(callee) != 'identifier' || c.text(callee) != 'Promise' {
			continue
		}
		stats.checked++
		args := (call_arguments(node) or { continue }).filter(node_kind(it) != 'comment')
		if args.len == 0 {
			continue
		}
		executor := unwrap_parens(args[0])
		if node_kind(executor) !in ['function_expression', 'arrow_function', 'generator_function']
			|| !es_is_async_function(executor) {
			continue
		}
		if !c.es_is_global_reference(root, callee) {
			continue
		}
		for child in children(executor) {
			if node_kind(child) == 'async' {
				findings << Finding{
					stmt:       c.position_at(treesitter.node_start(child))
					message_id: 'async'
				}
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
