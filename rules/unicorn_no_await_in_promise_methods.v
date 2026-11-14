module rules

import estree
import time

// Port of the `unicorn/no-await-in-promise-methods` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its suggestion.

const unaipm_messages = {
	'no-await-in-promise-methods/error':      'Avoid `await` inside `Promise.{{method}}()` arguments to prevent delaying the call.'
	'no-await-in-promise-methods/suggestion': 'Remove `await`.'
}

fn (mut c Checker) lint_unicorn_no_await_in_promise_methods(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .await_expression {
			continue
		}
		stats.checked++
		element := unaipm_array_element(t, node)
		if element < 0 {
			continue
		}
		call := t.nodes[t.nodes[element].parent].parent
		property := t.node(t.node(call, .callee) or { continue }, .property) or { continue }
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-await-in-promise-methods/error'
			data:       {
				'method': t.string_of(property, .name) or { '' }
			}
		}
		// Only suggest removing `await` when it is the element itself.
		if element == node {
			token := un_first_token(t, tokens, node, 0) or { continue }
			has_fix, fix := c.merge_fixes([fix_remove_range(token.start, token.end),
				c.un_remove_spaces_after(token.end)])!
			if has_fix {
				finding = Finding{
					...finding
					suggestions: [Suggestion{
						message_id: 'no-await-in-promise-methods/suggestion'
						fix:        fix
					}]
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unaipm_is_promise_method_call ports isPromiseMethodCallWithArrayExpression.
fn unaipm_is_promise_method_call(t &estree.EsTree, node int) bool {
	if !un_is_method_call(t, node,
		objects:          ['Promise']
		methods:          ['all', 'allSettled', 'any', 'race']
		optional_member:  false
		optional_call:    false
		arguments_length: 1
	) {
		return false
	}
	return t.typ((t.list(node, .arguments) or { return false })[0]) == .array_expression
}

// unaipm_array_element ports getPromiseMethodArrayElement: the element of the array of a `Promise`
// method that contains the `await` (-1 for none, or when a function or an outer `await` is between
// them).
fn unaipm_array_element(t &estree.EsTree, await_expression int) int {
	mut node := await_expression
	for t.nodes[node].parent >= 0 {
		parent := t.nodes[node].parent
		if unb_is_function(t, parent) || t.typ(parent) == .await_expression {
			return -1
		}
		if t.typ(parent) == .array_expression
			&& unaipm_is_promise_method_call(t, t.nodes[parent].parent) {
			return node
		}
		node = parent
	}
	return -1
}
