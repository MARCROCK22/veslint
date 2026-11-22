module rules

import estree
import time

// Port of the `unicorn/no-process-exit` rule of eslint-plugin-unicorn 79.0.0 (it has no options).

const unpe_messages = {
	'no-process-exit': 'Only use `process.exit()` in CLI apps. Throw an error instead.'
}

fn (mut c Checker) lint_unicorn_no_process_exit(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	// A file that starts with a hashbang is a CLI.
	if c.src.starts_with('#!') {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut depth := 0
	mut worker_threads := false
	mut problems := []int{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if step.leave {
			if typ == .call_expression && unpe_is_process_event_handler(t, node) {
				depth--
			}
			continue
		}
		match typ {
			.call_expression {
				stats.checked++
				// `require('worker_threads')`
				if un_is_call(t, node, names: ['require'], arguments_length: 1, optional: false)
					&& unpe_is_worker_threads(t, (t.list(node, .arguments) or { continue })[0]) {
					worker_threads = true
				}
				if unpe_is_process_event_handler(t, node) {
					depth++
				}
				if depth == 0 && un_is_method_call(t, node,
					objects:         ['process']
					methods:         ['exit']
					optional_call:   false
					optional_member: false
				) {
					problems << node
				}
			}
			// `import workerThreads from 'worker_threads'`
			.import_declaration {
				source := t.node(node, .source) or { continue }
				if t.typ(source) == .literal && unpe_is_worker_threads(t, source) {
					worker_threads = true
				}
			}
			else {}
		}
	}
	if !worker_threads {
		for node in problems {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'no-process-exit'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn unpe_is_worker_threads(t &estree.EsTree, node int) bool {
	return (un_static_string_value(t, node) or { '' }) in ['node:worker_threads', 'worker_threads']
}

// unpe_is_process_event_handler: `process.on(…)`, `process.once(…)` and their aliases.
fn unpe_is_process_event_handler(t &estree.EsTree, node int) bool {
	return un_is_method_call(t, node,
		objects:           ['process']
		methods:           ['on', 'once', 'addListener', 'prependListener', 'prependOnceListener']
		minimum_arguments: 1
		optional_call:     false
		optional_member:   false
	)
}
