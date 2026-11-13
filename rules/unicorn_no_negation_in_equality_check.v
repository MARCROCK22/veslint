module rules

import estree
import time

// Port of the `unicorn/no-negation-in-equality-check` rule of eslint-plugin-unicorn 64.0.0 (it has
// no options), with its suggestion.

const unnec_messages = {
	'no-negation-in-equality-check/error':      'Negated expression is not allowed in equality check.'
	'no-negation-in-equality-check/suggestion': "Switch to '{{operator}}' check."
}

fn unnec_is_negated(t &estree.EsTree, node int) bool {
	return t.typ(node) == .unary_expression && (t.flag(node, .prefix) or { false })
		&& (t.string_of(node, .operator) or { '' }) == '!'
}

fn (mut c Checker) lint_unicorn_no_negation_in_equality_check(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .binary_expression {
			continue
		}
		stats.checked++
		operator := t.string_of(node, .operator) or { continue }
		left := t.node(node, .left) or { continue }
		if operator !in ['===', '!==', '==', '!='] || !unnec_is_negated(t, left)
			|| unnec_is_negated(t, t.node(left, .argument) or { continue }) {
			continue
		}
		bang := un_first_token(t, tokens, left, 0) or { continue }
		negated := (if operator.starts_with('!') { '=' } else { '!' }) + operator[1..]
		data := {
			'operator': negated
		}
		_, fix := c.merge_fixes(c.unnec_fix(t, tokens, node, left, bang, operator, negated))!
		findings << Finding{
			stmt:        c.position_range(bang.start, bang.end)
			message_id:  'no-negation-in-equality-check/error'
			suggestions: [
				Suggestion{
					message_id: 'no-negation-in-equality-check/suggestion'
					data:       data
					fix:        fix
				},
			]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) unnec_fix(t &estree.EsTree, tokens &SourceTokens, node int, left int, bang SourceToken, operator string, negated string) []Fix {
	mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
	after_bang := tokens.after(bang.end, false) or { return [] }
	parent := t.nodes[node].parent
	if t.typ(parent) in [.return_statement, .throw_statement]
		&& !c.un_is_parenthesized(t, tokens, node) {
		keyword := un_first_token(t, tokens, parent, 0) or { return [] }
		if !un_same_line(t, keyword.start, after_bang.start) {
			fixes << c.un_add_parens_to_return_or_throw(t, tokens, parent)
		}
	}
	fixes << fix_remove_range(bang.start, bang.end)
	previous := tokens.before(bang.start, false)
	if c.un_needs_semicolon(t, tokens, previous, c.token_text(after_bang)) {
		fixes << fix_insert_at(bang.end, ';')
	}
	operator_token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or {
		return []
	}
	fixes << fix_replace_range(operator_token.start, operator_token.end, negated)
	return fixes
}
