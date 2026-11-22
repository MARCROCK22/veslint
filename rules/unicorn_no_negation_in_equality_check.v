module rules

import estree
import time

// Port of the `unicorn/no-negation-in-equality-check` rule of eslint-plugin-unicorn 79.0.0 (it has
// no options), with its suggestion.

const unnec_messages = {
	'no-negation-in-equality-check/error':      'Negated expression is not allowed in equality check.'
	'no-negation-in-equality-check/suggestion': "Switch to '{{operator}}' check."
}

fn unnec_is_negated(t &estree.EsTree, node int) bool {
	return t.typ(node) == .unary_expression && (t.flag(node, .prefix) or { false })
		&& (t.string_of(node, .operator) or { '' }) == '!'
}

fn (mut c Checker) lint_unicorn_no_negation_in_equality_check(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
		keyword_parent := c.un_unparenthesized_keyword_argument_parent(t, tokens, left) or { -1 }
		if keyword_parent >= 0 && t.typ(keyword_parent) == .yield_expression {
			after_bang := tokens.after(bang.end, false) or { continue }
			if !un_same_line(t, bang.start, after_bang.start) {
				findings << Finding{
					stmt:       c.position_range(bang.start, bang.end)
					message_id: 'no-negation-in-equality-check/error'
				}
				continue
			}
		}
		_, fix := c.merge_fixes(c.unnec_fix(t, tokens, node, left, bang, operator, negated,
			keyword_parent))!
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

fn (c &Checker) unnec_fix(t &estree.EsTree, tokens &SourceTokens, node int, left int, bang SourceToken, operator string, negated string, keyword_parent int) []Fix {
	argument := t.node(left, .argument) or { return [] }
	needs_parentheses := !c.un_is_parenthesized(t, tokens, argument)
		&& c.un_expression_start_needs_parens(t, tokens, argument, left)
	mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
	after_bang := tokens.after(bang.end, false) or { return [] }
	if keyword_parent >= 0 && t.typ(keyword_parent) in [.return_statement, .throw_statement] {
		keyword := un_first_token(t, tokens, keyword_parent, 0) or { return [] }
		if !un_same_line(t, keyword.start, after_bang.start) {
			fixes << c.un_add_parens_to_return_or_throw(t, tokens, keyword_parent)
		}
	}
	fixes << fix_remove_range(bang.start, bang.end)
	if needs_parentheses {
		fixes << fix_insert_at(t.nodes[argument].start, '(')
		fixes << fix_insert_at(t.nodes[argument].end, ')')
	}
	previous := tokens.before(bang.start, false)
	if c.un_needs_semicolon(t, tokens, previous, if needs_parentheses {
		'('
	} else {
		c.token_text(after_bang)
	}) {
		fixes << fix_insert_at(bang.start, ';')
	}
	operator_token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or {
		return []
	}
	fixes << fix_replace_range(operator_token.start, operator_token.end, negated)
	return fixes
}
