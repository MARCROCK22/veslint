module rules

import estree
import time

// Port of the `unicorn/prefer-code-point` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its suggestions.

const upcp_messages = {
	'error/charCodeAt':         'Prefer `String#codePointAt()` over `String#charCodeAt()`.'
	'error/fromCharCode':       'Prefer `String.fromCodePoint()` over `String.fromCharCode()`.'
	'suggestion/codePointAt':   'Use `String#codePointAt()`.'
	'suggestion/fromCodePoint': 'Use `String.fromCodePoint()`.'
}

fn (mut c Checker) lint_unicorn_prefer_code_point(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.call_expression {
				stats.checked++
				if un_is_method_call(t, node, methods: ['charCodeAt'], optional_call: false) {
					property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
					findings << c.upcp_problem(t, property, 'codePointAt', !upcp_is_result_used_numerically(t,
						node))
				}
			}
			.member_expression {
				stats.checked++
				if un_is_member(t, node,
					objects:    ['String']
					properties: ['fromCharCode']
					optional:   false
				) {
					property := t.node(node, .property) or { continue }
					findings << c.upcp_problem(t, property, 'fromCodePoint', true)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) upcp_problem(t &estree.EsTree, node int, replacement string, has_suggestion bool) Finding {
	return Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  'error/${t.string_of(node, .name) or { '' }}'
		suggestions: if has_suggestion {
			[
				Suggestion{
					message_id: 'suggestion/${replacement}'
					fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, replacement)
				},
			]
		} else {
			[]Suggestion{}
		}
	}
}

const upcp_numeric_binary_operators = ['+', '-', '*', '/', '%', '**', '&', '|', '^', '<<', '>>', '>>>']

// upcp_numeric_context_node ports getNumericContextNode: the node with the chains, logical
// expressions, TypeScript wrappers and branches of a conditional around it.
fn upcp_numeric_context_node(t &estree.EsTree, node int) int {
	mut current := node
	for {
		parent := t.nodes[current].parent
		if parent < 0 {
			return current
		}
		if t.typ(parent) in [.chain_expression, .logical_expression] || unb_is_ts_wrapper(t, parent) {
			current = parent
			continue
		}
		if t.typ(parent) == .conditional_expression && (t.node(parent, .consequent) or { -1 } == current
			|| t.node(parent, .alternate) or { -1 } == current) {
			current = parent
			continue
		}
		return current
	}
	return current
}

// upcp_is_result_used_numerically ports isResultUsedNumerically: `codePointAt` is not a safe
// rename when the value is used as a number (a string hash in a loop over `length` would visit
// the trailing surrogate too), so there is no suggestion then.
fn upcp_is_result_used_numerically(t &estree.EsTree, node int) bool {
	current := upcp_numeric_context_node(t, node)
	parent := t.nodes[current].parent
	if parent < 0 {
		return false
	}
	operator := t.string_of(parent, .operator) or { '' }
	return match t.typ(parent) {
		.binary_expression {
			operator in upcp_numeric_binary_operators
		}
		.unary_expression {
			operator in ['+', '-', '~']
		}
		// Compound assignment (`hash += …`); `=`, `&&=`, `||=` and `??=` are not numeric.
		.assignment_expression {
			t.node(parent, .right) or { -1 } == current && operator.len > 1
				&& operator[..operator.len - 1] in upcp_numeric_binary_operators
		}
		else {
			false
		}
	}
}
