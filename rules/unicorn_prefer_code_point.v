module rules

import estree
import time

// Port of the `unicorn/prefer-code-point` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its suggestions.

const upcp_messages = {
	'error/charCodeAt':         'Prefer `String#codePointAt()` over `String#charCodeAt()`.'
	'error/fromCharCode':       'Prefer `String.fromCodePoint()` over `String.fromCharCode()`.'
	'suggestion/codePointAt':   'Use `String#codePointAt()`.'
	'suggestion/fromCodePoint': 'Use `String.fromCodePoint()`.'
}

fn (mut c Checker) lint_unicorn_prefer_code_point(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.call_expression {
				stats.checked++
				if un_is_method_call(t, node, methods: ['charCodeAt'], optional_call: false) {
					property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
					findings << c.upcp_problem(t, property, 'codePointAt')
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
					findings << c.upcp_problem(t, property, 'fromCodePoint')
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) upcp_problem(t &estree.EsTree, node int, replacement string) Finding {
	return Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  'error/${t.string_of(node, .name) or { '' }}'
		suggestions: [
			Suggestion{
				message_id: 'suggestion/${replacement}'
				fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, replacement)
			},
		]
	}
}
