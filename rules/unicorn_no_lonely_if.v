module rules

import estree
import time

// Port of the `unicorn/no-lonely-if` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix.

const unli_messages = {
	'no-lonely-if': 'Unexpected `if` as the only statement in a `if` block without `else`.'
}

fn unli_without_alternate(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .if_statement && t.node(node, .alternate) == none
}

fn (mut c Checker) lint_unicorn_no_lonely_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .if_statement {
			continue
		}
		stats.checked++
		if !unli_without_alternate(t, node) {
			continue
		}
		parent := t.nodes[node].parent
		// `if (a) { if (b) {} }`
		mut lonely := false
		if parent >= 0 && t.typ(parent) == .block_statement {
			body := t.list(parent, .body) or { []int{} }
			outer := t.nodes[parent].parent
			lonely = body.len == 1 && body[0] == node && unli_without_alternate(t, outer)
				&& t.node(outer, .consequent) or { -1 } == parent
		}
		// `if (a) if (b) {}`
		if !lonely && unli_without_alternate(t, parent) && t.node(parent, .consequent) or { -1 } == node {
			lonely = true
		}
		if !lonely {
			continue
		}
		has_fix, fix := c.merge_fixes(c.unli_fix(t, tokens, node))!
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-lonely-if'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// UnliIfTokens are the tokens of getIfStatementTokens.
struct UnliIfTokens {
	node          int
	test          int
	consequent    int
	if_token      SourceToken
	opening_paren SourceToken
	closing_paren SourceToken
	opening_brace ?SourceToken
	closing_brace ?SourceToken
}

fn unli_if_tokens(t &estree.EsTree, tokens &SourceTokens, node int) ?UnliIfTokens {
	consequent := t.node(node, .consequent)?
	block := t.typ(consequent) == .block_statement
	return UnliIfTokens{
		node:          node
		test:          t.node(node, .test)?
		consequent:    consequent
		if_token:      un_first_token(t, tokens, node, 0)?
		opening_paren: un_first_token(t, tokens, node, 1)?
		closing_paren: tokens.before(t.nodes[consequent].start, false)?
		opening_brace: if block { un_first_token(t, tokens, consequent, 0) } else { none }
		closing_brace: if block { un_last_token(t, tokens, consequent) } else { none }
	}
}

// unli_need_parenthesis: the test has a lower precedence than `&&`.
fn unli_need_parenthesis(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.logical_expression { (t.string_of(node, .operator) or { '' }) in ['||', '??'] }
		.conditional_expression, .assignment_expression, .yield_expression, .sequence_expression { true }
		else { false }
	}
}

// unli_fix ports the fixer: `if (a) { if (b) x }` becomes `if (a && b) x`.
fn (c &Checker) unli_fix(t &estree.EsTree, tokens &SourceTokens, inner_node int) []Fix {
	parent := t.nodes[inner_node].parent
	outer_node := if t.typ(parent) == .block_statement { t.nodes[parent].parent } else { parent }
	outer := unli_if_tokens(t, tokens, outer_node) or { return [] }
	inner := unli_if_tokens(t, tokens, inner_node) or { return [] }
	mut fixes := []Fix{}
	// Remove the inner `if`.
	fixes << fix_remove_range(inner.if_token.start, inner.if_token.end)
	fixes << c.un_remove_spaces_after(inner.if_token.end)
	// Remove the outer `{}`.
	if opening := outer.opening_brace {
		closing := outer.closing_brace or { return [] }
		fixes << fix_remove_range(opening.start, opening.end)
		fixes << c.un_remove_spaces_after(opening.end)
		fixes << fix_remove_range(closing.start, closing.end)
		before := tokens.before(closing.start, true) or { return [] }
		fixes << c.un_remove_spaces_after(before.end)
	}
	// Add the new `()`.
	fixes << fix_insert_at(outer.opening_paren.start, '(')
	fixes << fix_insert_at(inner.closing_paren.end, if t.typ(inner.consequent) == .empty_statement {
		')'
	} else {
		') '
	})
	// Add ` && `.
	fixes << fix_insert_at(outer.closing_paren.end, ' && ')
	// Remove the `()` of a test that does not need them.
	for part in [outer, inner] {
		if c.un_is_parenthesized(t, tokens, part.test) || !unli_need_parenthesis(t, part.test) {
			fixes << fix_remove_range(part.opening_paren.start, part.opening_paren.end)
			fixes << fix_remove_range(part.closing_paren.start, part.closing_paren.end)
		}
		fixes << c.un_remove_spaces_after(part.closing_paren.end)
	}
	// Without a block, a `;` keeps the statement after the outer `if` from joining the inner one.
	if t.typ(inner.consequent) != .block_statement {
		last := un_last_token(t, tokens, inner.consequent) or { return fixes }
		if !c.token_is(last, ';') {
			if next := tokens.after(t.nodes[outer_node].end, false) {
				if c.un_needs_semicolon(t, tokens, last, c.token_text(next)) {
					fixes << fix_insert_at(next.start, ';')
				}
			}
		}
	}
	return fixes
}
