module rules

import estree
import time

// Port of the `unicorn/no-negated-condition` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const unnc_messages = {
	'no-negated-condition': 'Unexpected negated condition.'
}

fn (mut c Checker) lint_unicorn_no_negated_condition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ !in [.if_statement, .conditional_expression] {
			continue
		}
		stats.checked++
		if typ == .if_statement {
			alternate := t.node(node, .alternate) or { continue }
			if t.typ(alternate) == .if_statement {
				continue
			}
		}
		test := t.node(node, .test) or { continue }
		operator := t.string_of(test, .operator) or { '' }
		if !((t.typ(test) == .unary_expression && operator == '!')
			|| (t.typ(test) == .binary_expression && operator in ['!=', '!=='])) {
			continue
		}
		has_fix, fix := c.merge_fixes(c.unnc_fix(t, tokens, node, test))!
		findings << Finding{
			stmt:       c.es_tree_position(t, test)
			message_id: 'no-negated-condition'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) unnc_fix(t &estree.EsTree, tokens &SourceTokens, node int, test int) []Fix {
	mut fixes := []Fix{}
	is_if := t.typ(node) == .if_statement
	// convertNegatedCondition
	if t.typ(test) == .unary_expression {
		token := un_first_token(t, tokens, test, 0) or { return [] }
		if is_if {
			fixes << c.un_remove_parentheses(t, tokens, t.node(test, .argument) or { return [] })
		}
		fixes << fix_remove_range(token.start, token.end)
	} else {
		left := t.node(test, .left) or { return [] }
		operator := t.string_of(test, .operator) or { return [] }
		token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or { return [] }
		fixes << fix_replace_range(token.start, token.end, '=' + operator[1..])
	}
	// swapConsequentAndAlternate
	mut parts := []UnncPart{}
	for key in [estree.Key.consequent, .alternate] {
		branch := t.node(node, key) or { return fixes }
		start, end := c.un_parenthesized_range(t, tokens, branch)
		mut text := c.src[start..end]
		// `if (!a) b(); else c()` cannot become `if (!a) c() else b();`
		if is_if && t.typ(branch) != .block_statement {
			text = '{${text}}'
		}
		parts << UnncPart{start, end, text}
	}
	if parts[0].text != parts[1].text {
		fixes << fix_replace_range(parts[0].start, parts[0].end, parts[1].text)
		fixes << fix_replace_range(parts[1].start, parts[1].end, parts[0].text)
	}
	if t.typ(node) != .conditional_expression || t.typ(test) != .unary_expression {
		return fixes
	}
	fixes << c.un_fix_space_around_keyword(t, tokens, node)
	parent := t.nodes[node].parent
	first := un_first_token(t, tokens, test, 0) or { return fixes }
	second := un_first_token(t, tokens, test, 1) or { return fixes }
	if t.typ(parent) in [.return_statement, .throw_statement]
		&& t.node(parent, .argument) or { -1 } == node && !un_same_line(t, first.start, second.start)
		&& !c.un_is_parenthesized(t, tokens, node) && !c.un_is_parenthesized(t, tokens, test) {
		fixes << c.un_add_parens_to_return_or_throw(t, tokens, parent)
		return fixes
	}
	before := tokens.before(t.nodes[node].start, false)
	if c.un_needs_semicolon(t, tokens, before, c.token_text(second)) {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	return fixes
}

struct UnncPart {
	start int
	end   int
	text  string
}
