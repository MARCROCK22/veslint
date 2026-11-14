module rules

import estree

// Helpers of eslint-plugin-unicorn 79.0.0 (rules/utils, rules/fix, rules/ast and rules/shared)
// that are new in it or changed since 64.0.0, for the rules that were brought to 79.0.0 (see
// unicorn_utils.v for the ones that did not change). Offsets are bytes of the source.

// UnbRange is a range of the source, in bytes.
struct UnbRange {
	start int
	end   int
}

// unb_node_range is the range of an ESTree node.
fn unb_node_range(t &estree.EsTree, node int) UnbRange {
	return UnbRange{t.nodes[node].start, t.nodes[node].end}
}

// unb_comment_value is the value of a comment token: its text without `//`, `/*` and `*/`.
fn (c &Checker) unb_comment_value(comment SourceToken) string {
	text := c.src[comment.start..comment.end]
	return match comment.kind {
		.block_comment { text[2..text.len - 2] }
		else { text[2..] }
	}
}

// unb_is_disable_or_enable_directive ports isEslintDisableOrEnableDirective (utils/
// eslint-directive.js): the comment is one of the directives of sourceCode.getDisableDirectives()
// (a `disable`, `enable`, `disable-line` or `disable-next-line` one).
fn (c &Checker) unb_is_disable_or_enable_directive(comment SourceToken) bool {
	if comment.kind == .shebang_comment {
		return false
	}
	label, _, _ := parse_directive(c.unb_comment_value(comment)) or { return false }
	if label !in ['eslint-disable', 'eslint-enable', 'eslint-disable-line', 'eslint-disable-next-line'] {
		return false
	}
	if comment.kind == .line_comment && label !in ['eslint-disable-line', 'eslint-disable-next-line'] {
		return false
	}
	// A multi-line `eslint-disable-line` is a problem, not a directive.
	if label == 'eslint-disable-line' && c.src[comment.start..comment.end].contains_any('\n\r  ') {
		return false
	}
	return true
}

// unb_would_remove_comments ports wouldRemoveComments (utils/comments.js): replacing or removing
// the range would remove a comment that is inside it and outside every preserved range (with
// `ignore_directives`, disable and enable directives do not count).
fn (c &Checker) unb_would_remove_comments(tokens &SourceTokens, replaced UnbRange, preserved []UnbRange, ignore_directives bool) bool {
	for comment in tokens.comments_inside(replaced.start, replaced.end) {
		if comment.end > replaced.end {
			continue
		}
		if preserved.any(comment.start >= it.start && comment.end <= it.end) {
			continue
		}
		if ignore_directives && c.unb_is_disable_or_enable_directive(comment) {
			continue
		}
		return true
	}
	return false
}

// unb_has_non_directive_comment ports hasNonDirectiveComment (utils/comments.js).
fn (c &Checker) unb_has_non_directive_comment(tokens &SourceTokens, replaced UnbRange, preserved []UnbRange) bool {
	return c.unb_would_remove_comments(tokens, replaced, preserved, true)
}

// unb_parenthesized_range is getParenthesizedRange as an UnbRange.
fn (c &Checker) unb_parenthesized_range(t &estree.EsTree, tokens &SourceTokens, node int) UnbRange {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return UnbRange{start, end}
}

// unb_linebreak ports getLinebreak (utils/get-linebreak.js): the first line ending of the file, or
// `\n` for a file of one line.
fn (c &Checker) unb_linebreak() string {
	for i := 0; i < c.src.len; i++ {
		match c.src[i] {
			`\r` {
				return if i + 1 < c.src.len && c.src[i + 1] == `\n` { '\r\n' } else { '\r' }
			}
			`\n` {
				return '\n'
			}
			0xe2 {
				// U+2028 and U+2029: E2 80 A8 and E2 80 A9.
				if i + 2 < c.src.len && c.src[i + 1] == 0x80 && c.src[i + 2] in [u8(0xa8), 0xa9] {
					return c.src[i..i + 3]
				}
			}
			else {}
		}
	}
	return '\n'
}

// unb_needs_semicolon ports needsSemicolon (utils/needs-semicolon.js) of 79.0.0: whether code that
// starts with `code` and goes right after the token `before` needs a `;` first. An empty `code`
// never does; none is any code.
fn (c &Checker) unb_needs_semicolon(t &estree.EsTree, tokens &SourceTokens, before ?SourceToken, code ?string) bool {
	if text := code {
		if text == '' || text[0] !in [`[`, `(`, `/`, `\``, `+`, `-`, `*`, `,`, `.`, `<`] {
			return false
		}
	}
	token := before or { return false }
	value := c.token_text(token)
	if token.kind == .punctuator && value == ';' {
		return false
	}
	// Parser wrapper tokens have no node.
	last_block := un_node_by_range_index(t, token.start) or { return false }
	for node := last_block; node >= 0 && t.nodes[node].end == token.end; node = t.nodes[node].parent {
		if t.typ(node) in [.expression_statement, .variable_declaration, .return_statement,
			.throw_statement, .export_default_declaration] {
			return true
		}
	}
	last_block_parent := t.nodes[last_block].parent
	parent_type := if last_block_parent >= 0 { t.typ(last_block_parent) } else { estree.NodeType.program }
	if token.kind == .punctuator {
		if value == ']' {
			return true
		}
		if value == '}' && ((t.typ(last_block) == .block_statement && parent_type == .function_expression)
			|| (t.typ(last_block) == .class_body && parent_type == .class_expression)) {
			return true
		}
		if value == ')' {
			body_key := match t.typ(last_block) {
				.if_statement {
					?estree.Key(estree.Key.consequent)
				}
				.for_statement, .for_in_statement, .for_of_statement, .while_statement,
				.do_while_statement, .with_statement {
					?estree.Key(estree.Key.body)
				}
				else {
					?estree.Key(none)
				}
			}
			if key := body_key {
				if body := t.node(last_block, key) {
					if previous := tokens.before(t.nodes[body].start, false) {
						if previous.start == token.start {
							return false
						}
					}
				}
			}
			return true
		}
	}
	if token.kind in [.string_, .null_, .boolean, .numeric, .regular_expression] {
		return true
	}
	if token.kind == .template {
		return value.ends_with('`')
	}
	// The trailing `!`, not the opening parenthesis of `(foo)!`.
	if t.typ(last_block) == .object_expression
		|| (t.typ(last_block) == .ts_non_null_expression && value == '!')
		|| (t.typ(last_block) == .ts_type_parameter_instantiation
		&& parent_type == .ts_instantiation_expression) {
		return true
	}
	if token.kind == .identifier {
		// `for...of`
		if value == 'of' && t.typ(last_block) == .for_of_statement {
			return false
		}
		// `await`
		return !(value == 'await' && t.typ(last_block) == .await_expression)
	}
	return false
}

const unb_precedence_unary = 16
const unb_precedence_call = 18
const unb_precedence_addition = 12

// unb_operator_precedence is the precedence of a binary or logical operator (get-precedence.js).
fn unb_operator_precedence(operator string) int {
	return match operator {
		'??', '||' { 4 }
		'&&' { 5 }
		'|' { 6 }
		'^' { 7 }
		'&' { 8 }
		'==', '!=', '===', '!==' { 9 }
		'<', '<=', '>', '>=', 'in', 'instanceof' { 10 }
		'<<', '>>', '>>>' { 11 }
		'+', '-' { 12 }
		'*', '/', '%' { 13 }
		'**' { 15 }
		else { 0 }
	}
}

// unb_precedence ports getPrecedence (utils/get-precedence.js): a higher number binds tighter.
fn unb_precedence(t &estree.EsTree, node int) int {
	return match t.typ(node) {
		.sequence_expression {
			0
		}
		.assignment_expression, .arrow_function_expression, .yield_expression {
			1
		}
		.conditional_expression {
			3
		}
		.logical_expression, .binary_expression {
			unb_operator_precedence(t.string_of(node, .operator) or { '' })
		}
		.ts_as_expression, .ts_satisfies_expression {
			10
		}
		.unary_expression, .await_expression, .ts_type_assertion, .ts_non_null_expression {
			unb_precedence_unary
		}
		.update_expression {
			if t.flag(node, .prefix) or { false } { unb_precedence_unary } else { 17 }
		}
		.call_expression, .chain_expression, .import_expression {
			unb_precedence_call
		}
		.new_expression {
			19
		}
		else {
			20
		}
	}
}

// unb_should_add_parens_to_comparison ports shouldAddParenthesesToComparison (utils/
// should-add-parentheses-to-comparison.js): replacing `node` with a comparison of `operator` needs
// parentheses where it is.
fn (c &Checker) unb_should_add_parens_to_comparison(t &estree.EsTree, tokens &SourceTokens, node int, operator string) bool {
	if c.un_is_parenthesized(t, tokens, node) {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		// `(foo.length > 0).x`
		.member_expression {
			t.node(parent, .object) or { -1 } == node
		}
		// `(foo.length > 0)()`, `new (foo.length > 0)()`
		.call_expression, .new_expression {
			t.node(parent, .callee) or { -1 } == node
		}
		// `(foo.length > 0)\`x\``
		.tagged_template_expression {
			t.node(parent, .tag) or { -1 } == node
		}
		// `bar === (foo.length === 0)`, `bar + (foo.length > 0)`, `(foo.length > 0) ** 2`
		.binary_expression, .ts_as_expression, .ts_satisfies_expression {
			precedence := unb_operator_precedence(operator)
			parent_precedence := unb_precedence(t, parent)
			parent_precedence > precedence || (parent_precedence == precedence
				&& t.typ(parent) == .binary_expression && t.node(parent, .right) or { -1 } == node)
		}
		// `typeof (foo.length > 0)`, `await (foo.length > 0)`, `(foo.length > 0)!`
		.await_expression, .ts_non_null_expression, .ts_type_assertion, .unary_expression {
			true
		}
		else {
			false
		}
	}
}
