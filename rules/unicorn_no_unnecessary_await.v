module rules

import estree
import time

// Port of the `unicorn/no-unnecessary-await` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const unua_messages = {
	'no-unnecessary-await': 'Do not `await` non-promise value.'
}

fn (mut c Checker) lint_unicorn_no_unnecessary_await(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .await_expression {
			continue
		}
		stats.checked++
		value := t.node(node, .argument) or { continue }
		unwrapped := un_unwrap_ts_expression(t, value)
		if unwrapped < 0 || !unua_not_promise(t, unwrapped) {
			continue
		}
		await_token := un_first_token(t, tokens, node, 0) or { continue }
		mut finding := Finding{
			stmt:       c.position_range(await_token.start, await_token.end)
			message_id: 'no-unnecessary-await'
		}
		// Removing `await` may turn a function or class into a declaration; an `await` that is
		// not the last thing its function runs still delays what follows.
		if t.typ(unwrapped) !in [.function_expression, .class_expression]
			&& unua_is_last_evaluated(t, node) {
			mut fixes := []Fix{}
			if !un_same_line(t, await_token.start, t.nodes[value].start)
				&& !c.un_is_parenthesized(t, tokens, node) {
				fixes << c.un_add_parens_to_return_or_throw(t, tokens, t.nodes[node].parent)
			}
			fixes << fix_remove_range(await_token.start, await_token.end)
			fixes << c.un_remove_spaces_after(await_token.end)
			if next := tokens.after(await_token.end, false) {
				if c.un_needs_semicolon(t, tokens, tokens.before(await_token.start, false),
					c.src[next.start..next.end]) {
					fixes << fix_insert_at(next.start, ';')
				}
			}
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unua_not_promise ports notPromise: an expression that cannot be a promise.
fn unua_not_promise(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.array_expression, .arrow_function_expression, .await_expression, .binary_expression,
		.class_expression, .function_expression, .jsx_element, .jsx_fragment, .literal,
		.template_literal, .unary_expression, .update_expression {
			true
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { return false }
			expressions.len > 0 && unua_not_promise(t, expressions.last())
		}
		else {
			false
		}
	}
}

// unua_is_last_evaluated ports isLastEvaluated: the node is the last thing its function (or the
// module) runs.
fn unua_is_last_evaluated(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.arrow_function_expression {
			(t.node(parent, .body) or { -1 }) == node
		}
		.program {
			body := t.list(parent, .body) or { return false }
			body.len > 0 && body.last() == node
		}
		.block_statement {
			body := t.list(parent, .body) or { return false }
			body.len > 0 && body.last() == node
				&& (unb_is_function(t, t.nodes[parent].parent) || unua_is_last_evaluated(t, parent))
		}
		.if_statement {
			(t.node(parent, .test) or { -1 }) != node && unua_is_last_evaluated(t, parent)
		}
		.variable_declaration {
			declarations := t.list(parent, .declarations) or { return false }
			declarations.len > 0 && declarations.last() == node && unua_is_last_evaluated(t, parent)
		}
		.expression_statement, .return_statement, .throw_statement, .variable_declarator {
			unua_is_last_evaluated(t, parent)
		}
		else {
			false
		}
	}
}
