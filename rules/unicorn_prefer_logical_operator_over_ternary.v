module rules

import estree
import time

// Port of the `unicorn/prefer-logical-operator-over-ternary` rule of eslint-plugin-unicorn 64.0.0
// (it has no options), with its suggestions.

const uploot_messages = {
	'prefer-logical-operator-over-ternary/error':      'Prefer using a logical operator over a ternary.'
	'prefer-logical-operator-over-ternary/suggestion': 'Switch to `{{operator}}` operator.'
}

// uploot_same_node ports isSameNode.
fn (mut c Checker) uploot_same_node(t &estree.EsTree, left int, right int) bool {
	if c.un_is_same_reference(t, left, right) {
		return true
	}
	if t.typ(left) != t.typ(right) {
		return false
	}
	match t.typ(left) {
		.await_expression {
			return c.uploot_same_node(t, t.node(left, .argument) or { return false },
				t.node(right, .argument) or { return false })
		}
		.logical_expression {
			return t.string_of(left, .operator) or { '' } == t.string_of(right, .operator) or { '' }
				&& c.uploot_same_node(t, t.node(left, .left) or { return false }, t.node(right, .left) or {
				return false
			}) && c.uploot_same_node(t, t.node(left, .right) or { return false }, t.node(right,
				.right) or { return false })
		}
		.unary_expression {
			return t.string_of(left, .operator) or { '' } == t.string_of(right, .operator) or { '' }
				&& t.flag(left, .prefix) or { false } == t.flag(right, .prefix) or { false }
				&& c.uploot_same_node(t, t.node(left, .argument) or { return false }, t.node(right,
				.argument) or { return false })
		}
		.update_expression {
			return false
		}
		else {}
	}
	return c.un_text(t, left) == c.un_text(t, right)
}

fn (mut c Checker) lint_unicorn_prefer_logical_operator_over_ternary(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .conditional_expression {
			continue
		}
		stats.checked++
		test := t.node(node, .test) or { continue }
		consequent := t.node(node, .consequent) or { continue }
		alternate := t.node(node, .alternate) or { continue }
		mut left := -1
		mut right := -1
		if c.uploot_same_node(t, test, consequent) {
			// `foo ? foo : bar`
			left, right = test, alternate
		} else if t.typ(test) == .unary_expression && (t.string_of(test, .operator) or { '' }) == '!'
			&& (t.flag(test, .prefix) or { false })
			&& c.uploot_same_node(t, t.node(test, .argument) or { continue }, alternate) {
			// `!bar ? foo : bar`
			left, right = t.node(test, .argument) or { continue }, consequent
		} else {
			continue
		}
		mut suggestions := []Suggestion{}
		for operator in ['??', '||'] {
			suggestions << Suggestion{
				message_id: 'prefer-logical-operator-over-ternary/suggestion'
				data:       {
					'operator': operator
				}
				fix:        c.uploot_fix(t, tokens, node, left, right, operator)
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, node)
			message_id:  'prefer-logical-operator-over-ternary/error'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) uploot_fix(t &estree.EsTree, tokens &SourceTokens, node int, left int, right int, operator string) Fix {
	mut parts := []string{}
	for child in [left, right] {
		parenthesized := c.un_is_parenthesized(t, tokens, child)
		mut text := if parenthesized {
			c.un_parenthesized_text(t, tokens, child)
		} else {
			c.un_text(t, child)
		}
		if !parenthesized && un_logical_child_needs_parens(t, child, operator) {
			text = '(${text})'
		}
		parts << text
	}
	mut text := parts.join(' ${operator} ')
	if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), text) {
		text = ';${text}'
	}
	return fix_replace_range(t.nodes[node].start, t.nodes[node].end, text)
}
