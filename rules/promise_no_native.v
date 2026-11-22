module rules

import time
import treesitter { position_of }

// Port of the `promise/no-native` rule of eslint-plugin-promise 7.3.0 (it has no options), on
// the scope tree: at Program:exit, every reference of the global variables named `Promise` and
// every unresolved reference to `Promise` (globalScope.through) is reported, unless a variable of
// the global scope with that name has a definition.

const prm_no_native_messages = {
	'name': '"{{name}}" is not defined.'
}

fn (mut c Checker) lint_promise_no_native(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	global := tree.global_scope()
	mut references := []int{}
	for v in tree.scopes[global].variables {
		if tree.variables[v].name == 'Promise' {
			references << tree.variables[v].references
		}
	}
	for r in tree.through {
		if tree.references[r].name == 'Promise' {
			references << r
		}
	}
	for r in references {
		stats.checked++
		name := tree.references[r].name
		// isDeclared: a variable of the global scope with the name and a definition.
		if tree.scopes[global].variables.any(tree.variables[it].name == name
			&& tree.variables[it].defs.len > 0) {
			continue
		}
		findings << Finding{
			stmt:       position_of(tree.references[r].identifier)
			message_id: 'name'
			data:       {
				'name': name
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
