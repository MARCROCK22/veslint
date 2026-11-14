module rules

import estree
import time

// Port of the `unicorn/no-negated-condition` rule of eslint-plugin-unicorn 79.0.0 (it has no
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
		operands := if unb_is_logical_expression(t, test) {
			unb_logical_operands(t, test, t.string_of(test, .operator) or { '' })
		} else {
			[test]
		}
		if !operands.all(unnc_is_negated(t, it)) {
			continue
		}
		mut has_fix := false
		mut fix := Fix{}
		if fixes := c.unnc_fix(t, tokens, node, test, operands) {
			has_fix, fix = c.merge_fixes(fixes)!
		}
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

// unnc_is_negated: `!a`, `a != b` or `a !== b`.
fn unnc_is_negated(t &estree.EsTree, node int) bool {
	operator := t.string_of(node, .operator) or { '' }
	return (t.typ(node) == .unary_expression && operator == '!')
		|| (t.typ(node) == .binary_expression && operator in ['!=', '!=='])
}

// unnc_convert ports convertNegatedCondition: `!a` becomes `a`, `a != b` becomes `a == b`, and a
// `&&` or `||` of them becomes the other operator of the converted operands.
fn (c &Checker) unnc_convert(t &estree.EsTree, tokens &SourceTokens, test int) []Fix {
	mut fixes := []Fix{}
	operator := t.string_of(test, .operator) or { return [] }
	if unb_is_logical_expression(t, test) {
		left := t.node(test, .left) or { return [] }
		right := t.node(test, .right) or { return [] }
		token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or { return [] }
		fixes << fix_replace_range(token.start, token.end, if operator == '&&' { '||' } else { '&&' })
		fixes << c.unnc_convert(t, tokens, left)
		fixes << c.unnc_convert(t, tokens, right)
		return fixes
	}
	if t.typ(test) == .unary_expression {
		token := un_first_token(t, tokens, test, 0) or { return [] }
		argument := t.node(test, .argument) or { return [] }
		needs_parens := !c.un_is_parenthesized(t, tokens, argument)
			&& !tokens.comments_exist_between(token.end, t.nodes[argument].start)
			&& c.unb_should_add_parens_to_expression_start(t, tokens, argument, test)
		fixes << fix_replace_range(token.start, token.end, if needs_parens { '(' } else { '' })
		if needs_parens {
			fixes << fix_insert_at(t.nodes[argument].end, ')')
		}
		return fixes
	}
	left := t.node(test, .left) or { return [] }
	token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or { return [] }
	fixes << fix_replace_range(token.start, token.end, '=' + operator[1..])
	return fixes
}

// unnc_fix ports the fixer; none where it aborts.
fn (c &Checker) unnc_fix(t &estree.EsTree, tokens &SourceTokens, node int, test int, operands []int) ?[]Fix {
	mut fixes := []Fix{}
	is_if := t.typ(node) == .if_statement
	first_operand_unary := t.typ(operands[0]) == .unary_expression
	if first_operand_unary && c.unb_should_add_parens_to_expression_statement_expression(t, tokens,
		t.node(operands[0], .argument)?) {
		return none
	}
	if is_if && t.typ(test) == .unary_expression {
		fixes << c.un_remove_parentheses(t, tokens, t.node(test, .argument)?)
	}
	fixes << c.unnc_convert(t, tokens, test)
	// swapConsequentAndAlternate: a comment right before a branch moves with it, one right after
	// it aborts.
	mut parts := []UnncPart{}
	for key in [estree.Key.consequent, .alternate] {
		branch := t.node(node, key)?
		mut start, end := c.un_parenthesized_range(t, tokens, branch)
		if tokens.comments_after(end).len > 0 {
			return none
		}
		before := tokens.comments_before(start)
		if before.len > 0 {
			start = before[0].start
		}
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
	if t.typ(node) != .conditional_expression || !first_operand_unary {
		return fixes
	}
	fixes << c.unb_fix_space_around_keyword(t, tokens, node)
	keyword_parent := c.unb_unparenthesized_keyword_argument_parent(t, tokens, test)
	first := un_first_token(t, tokens, test, 0)?
	second := un_first_token(t, tokens, test, 1)?
	if c.token_text(first) != '!' {
		return fixes
	}
	if keyword_parent >= 0 && !un_same_line(t, first.start, second.start) {
		if t.typ(keyword_parent) == .yield_expression {
			return none
		}
		fixes << c.un_add_parens_to_return_or_throw(t, tokens, keyword_parent)
		return fixes
	}
	before := tokens.before(t.nodes[node].start, false)
	if c.unb_needs_semicolon(t, tokens, before, c.token_text(second)) {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	return fixes
}

struct UnncPart {
	start int
	end   int
	text  string
}
