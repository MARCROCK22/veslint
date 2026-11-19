module rules

import estree
import time

// Port of the `promise/prefer-catch` rule of eslint-plugin-promise 7.3.0 (it has no options),
// with its fix.

const prm_prefer_catch_messages = {
	'preferCatchToThen': 'Prefer `catch` to `then(a, b)`/`then(null, b)`.'
}

fn (mut c Checker) lint_promise_prefer_catch(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
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
		property := prm_child(t, node, .property)
		args := t.list(parent, .arguments) or { continue }
		if prm_name(t, property) != 'then' || args.len < 2 {
			continue
		}
		then := args[0]
		mut fixes := []Fix{}
		if (t.typ(then) == .literal && t.get(then, .value) is estree.Null)
			|| (t.typ(then) == .identifier && prm_name(t, then) == 'undefined') {
			fixes << c.prm_remove_argument(t, tokens, then)
			fixes << fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'catch')
		} else {
			catcher := args[1]
			catcher_text := t.src[t.nodes[catcher].start..t.nodes[catcher].end]
			fixes << c.prm_remove_argument(t, tokens, catcher)
			fixes << fix_insert_at(t.nodes[property].start, 'catch(${catcher_text}).')
		}
		findings << c.with_fixes(Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'preferCatchToThen'
		}, fixes)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
