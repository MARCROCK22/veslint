module rules

import json2
import time
import treesitter { node_kind }

// Port of the `promise/prefer-await-to-then` rule of eslint-plugin-promise 7.3.0, with its
// options.

const prm_prefer_await_to_then_messages = {
	'preferAwaitToCallback': 'Prefer await to then()/catch()/finally().'
}

// prm_prefer_await_to_then_options is `strict`. The schema of the options object allows other
// properties, which the rule does not read.
fn prm_prefer_await_to_then_options(options []json2.Any) !bool {
	if options.len == 0 {
		return false
	}
	first := options[0]
	if first !is map[string]json2.Any {
		return error('the options of `${promise_prefer_await_to_then}` must be an object')
	}
	value := first.as_map()['strict'] or { return false }
	if value !is bool {
		return error('option `strict` of `${promise_prefer_await_to_then}` must be true or false')
	}
	return value as bool
}

fn (mut c Checker) lint_promise_prefer_await_to_then(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	strict := prm_prefer_await_to_then_options(c.rule_options(promise_prefer_await_to_then))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tree_scopes := c.scope_tree(root)
	for node in 0 .. t.nodes.len {
		// 'CallExpression > MemberExpression.callee'
		if t.typ(node) != .member_expression || !t.visits(node) {
			continue
		}
		parent := t.nodes[node].parent
		if parent < 0 || t.typ(parent) != .call_expression || prm_child(t, parent, .callee) != node {
			continue
		}
		stats.checked++
		// isTopLevelScoped: getScope(node).block is the Program.
		ts := t.ts_node(node) or { continue }
		if node_kind(tree_scopes.scopes[tree_scopes.get_scope(ts)].block) == 'program' {
			continue
		}
		ancestors := prm_ancestors(t, node)
		if !strict && ancestors.any(t.typ(it) in [.await_expression, .yield_expression]) {
			continue
		}
		if !strict && ancestors.any(t.typ(it) == .method_definition
			&& (t.string_of(it, .kind) or { '' }) == 'constructor') {
			continue
		}
		if prm_is_member_call_with_object_name(t, 'cy', parent) {
			continue
		}
		property := prm_child(t, node, .property)
		if prm_name(t, property) in ['then', 'catch', 'finally'] {
			findings << Finding{
				stmt:       c.es_tree_position(t, property)
				message_id: 'preferAwaitToCallback'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
