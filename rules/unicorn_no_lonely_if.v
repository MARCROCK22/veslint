module rules

import estree
import time

// Port of the `unicorn/no-lonely-if` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
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

// unli_need_parenthesis: the test has a lower precedence than `&&` (an arrow function is an
// AssignmentExpression in the grammar).
fn unli_need_parenthesis(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.logical_expression { (t.string_of(node, .operator) or { '' }) in ['||', '??'] }
		.conditional_expression, .arrow_function_expression, .assignment_expression,
		.yield_expression, .sequence_expression { true }
		else { false }
	}
}

// unli_between is getTextBetween: the source from the end of one token or node to the start of
// another.
fn (c &Checker) unli_between(left_end int, right_start int) string {
	return c.src[left_end..right_start]
}

// unli_preserve_gap is preserveGap: the text, or nothing when it is only white space.
fn unli_preserve_gap(text string) string {
	return if js_trim(text) != '' { text } else { '' }
}

// unli_join is joinSourceText: one of the white spaces between the two goes away.
fn unli_join(left string, right string) string {
	left_runes := left.runes()
	right_runes := right.runes()
	if left_runes.len > 0 && is_js_space(left_runes.last()) && right_runes.len > 0
		&& is_js_space(right_runes[0]) {
		return left + unb_trim_start(right)
	}
	return left + right
}

// unli_test_text is getTestText: the text between the parentheses of the `if`, in parentheses when
// its test binds more loosely than `&&`.
fn (c &Checker) unli_test_text(t &estree.EsTree, tokens &SourceTokens, part UnliIfTokens) string {
	text := c.unli_between(part.opening_paren.end, part.closing_paren.start)
	if c.un_is_parenthesized(t, tokens, part.test) {
		return text
	}
	return if unli_need_parenthesis(t, part.test) { '(${text})' } else { text }
}

// unli_fix ports the fixer, one replacement of the outer `if`: `if (a) { if (b) x }` becomes
// `if (a && b) x`, with the comments of the outer `if` kept.
fn (c &Checker) unli_fix(t &estree.EsTree, tokens &SourceTokens, inner_node int) []Fix {
	parent := t.nodes[inner_node].parent
	outer_node := if t.typ(parent) == .block_statement { t.nodes[parent].parent } else { parent }
	outer := unli_if_tokens(t, tokens, outer_node) or { return [] }
	inner := unli_if_tokens(t, tokens, inner_node) or { return [] }
	outer_prefix := c.unli_between(outer.if_token.end, outer.opening_paren.start)
	outer_test := c.unli_test_text(t, tokens, outer)
	inner_condition := unli_join(unli_preserve_gap(c.unli_between(inner.if_token.end,
		inner.opening_paren.start)), c.unli_test_text(t, tokens, inner))
	// getReplacementRange: without a block, a `;` keeps the statement after the outer `if` from
	// joining the inner one.
	range_start := t.nodes[outer_node].start
	mut range_end := t.nodes[outer_node].end
	if t.typ(inner.consequent) != .block_statement {
		if last := un_last_token(t, tokens, inner.consequent) {
			if !c.token_is(last, ';') {
				if next := tokens.after(t.nodes[outer_node].end, false) {
					if c.unb_needs_semicolon(t, tokens, last, c.token_text(next)) {
						range_end = next.start
					}
				}
			}
		}
	}
	// getConsequentTextPieces
	mut outer_condition_gap := ''
	mut outer_leading := ''
	mut outer_trailing := ''
	if opening := outer.opening_brace {
		closing := outer.closing_brace or { return [] }
		outer_condition_gap = unli_preserve_gap(c.unli_between(outer.closing_paren.end, opening.start))
		outer_leading = unli_preserve_gap(c.unli_between(opening.end, inner.if_token.start))
		outer_trailing = unli_preserve_gap(c.unli_between(t.nodes[inner_node].end, closing.start))
	} else {
		outer_leading = unli_preserve_gap(c.unli_between(outer.closing_paren.end, inner.if_token.start))
	}
	// getOuterConditionGapTextPieces: a `// …` after the outer condition stays after the merged one,
	// for line directives; everything else goes before the merged statement.
	mut leading := ''
	mut condition_suffix := ''
	if unb_trim_start(outer_condition_gap).starts_with('//') {
		leading = unb_trim_start(unli_preserve_gap(outer_leading))
		condition_suffix = outer_condition_gap
	} else {
		leading = unb_trim_start(unli_preserve_gap(unli_join(outer_condition_gap, outer_leading)))
	}
	// getConsequentText
	mut consequent := ''
	if opening := inner.opening_brace {
		closing := inner.closing_brace or { return [] }
		before_block := c.unli_between(inner.closing_paren.end, opening.start)
		body := c.unli_between(opening.end, closing.start)
		consequent = '${condition_suffix}${before_block}{${body}${outer_trailing}}'
	} else {
		before := c.unli_between(inner.closing_paren.end, t.nodes[inner.consequent].start)
		consequent = '${condition_suffix}${before}${c.un_text(t, inner.consequent)}${outer_trailing}'
		// getAsiSuffix
		outer_end := t.nodes[outer_node].end
		if range_end != outer_end {
			gap := c.src[outer_end..range_end]
			consequent += if js_trim(gap) == '' {
				if gap.contains('\n') { ';${gap}' } else { ';' }
			} else {
				';${gap}'
			}
		}
	}
	return [
		fix_replace_range(range_start, range_end, '${leading}if${outer_prefix}(${outer_test} && ${inner_condition})${consequent}'),
	]
}
