module rules

import estree
import time
import x.json2

// Port of the `@stylistic/semi-spacing` rule of @stylistic/eslint-plugin 5.10.0, with its options
// (`before`, false by default, and `after`, true by default) and its fixes.

const ssmi_messages = {
	'unexpectedWhitespaceBefore': 'Unexpected whitespace before semicolon.'
	'unexpectedWhitespaceAfter':  'Unexpected whitespace after semicolon.'
	'missingWhitespaceBefore':    'Missing whitespace before semicolon.'
	'missingWhitespaceAfter':     'Missing whitespace after semicolon.'
}

struct SsmiOptions {
	require_space_before bool
	require_space_after  bool
}

fn ssmi_options(given []json2.Any) !SsmiOptions {
	options := sty_options(given, [
		json2.Any({
			'before': json2.Any(false)
			'after':  json2.Any(true)
		}),
	])
	config := sty_option_object(options, 0)
	return SsmiOptions{
		require_space_before: sty_option_bool(config, 'before') or { false }
		require_space_after:  sty_option_bool(config, 'after') or { false }
	}
}

// The nodes whose last token is checked (checkNode).
const ssmi_checked_nodes = [estree.NodeType.variable_declaration, .expression_statement,
	.break_statement, .continue_statement, .debugger_statement, .do_while_statement,
	.return_statement, .throw_statement, .import_declaration, .export_named_declaration,
	.export_all_declaration, .export_default_declaration, .property_definition, .accessor_property,
	.ts_declare_function, .ts_type_alias_declaration]

fn (mut c Checker) lint_stylistic_semi_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := ssmi_options(c.rule_options(stylistic_semi_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ in ssmi_checked_nodes {
			stats.checked++
			c.ssmi_check_node(t, tokens, node, options, mut findings)
		} else if typ == .for_statement {
			stats.checked++
			if init := t.node(node, .init) {
				if token := tokens.after(t.nodes[init].end, false) {
					c.ssmi_check_semicolon_spacing(t, tokens, token, options, mut findings)
				}
			}
			if test := t.node(node, .test) {
				if token := tokens.after(t.nodes[test].end, false) {
					c.ssmi_check_semicolon_spacing(t, tokens, token, options, mut findings)
				}
			}
		} else if typ == .ts_type_annotation {
			// TSTypeAnnotation checks its parent, but in a TSDeclareFunction.
			parent := t.nodes[node].parent
			if parent >= 0 && t.typ(parent) != .ts_declare_function {
				stats.checked++
				c.ssmi_check_node(t, tokens, parent, options, mut findings)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ssmi_check_node ports checkNode: the spacing of the last token of the node, when it is a
// semicolon.
fn (c &Checker) ssmi_check_node(t &estree.EsTree, tokens &SourceTokens, node int, options SsmiOptions, mut findings []Finding) {
	token := un_last_token(t, tokens, node) or { return }
	c.ssmi_check_semicolon_spacing(t, tokens, token, options, mut findings)
}

// ssmi_check_semicolon_spacing ports checkSemicolonSpacing.
fn (c &Checker) ssmi_check_semicolon_spacing(t &estree.EsTree, tokens &SourceTokens, token SourceToken, options SsmiOptions, mut findings []Finding) {
	if !c.token_is(token, ';') {
		return
	}
	token_before := tokens.before(token.start, false)
	token_after := tokens.after(token.end, false)
	// hasLeadingSpace
	mut has_leading_space := false
	if before := token_before {
		has_leading_space = sty_same_line(t, before, token)
			&& tokens.is_space_between(before.end, token.start)
	}
	if has_leading_space {
		if !options.require_space_before {
			before := token_before or { return }
			findings << c.ssmi_report(before.end, token.start, 'unexpectedWhitespaceBefore',
				fix_remove_range(before.end, token.start))
		}
	} else if options.require_space_before {
		findings << c.ssmi_report(token.start, token.end, 'missingWhitespaceBefore', fix_replace_range(token.start,
			token.start, ' '))
	}
	// isFirstTokenInCurrentLine: isTokenOnSameLine(token, tokenBefore).
	mut is_first_in_line := true
	if before := token_before {
		is_first_in_line = !sty_same_line(t, token, before)
	}
	// isLastTokenInCurrentLine and isBeforeClosingParen (a `}` or a `)`).
	mut is_last_in_line := true
	mut is_before_closing := false
	if after := token_after {
		is_last_in_line = !sty_same_line(t, token, after)
		is_before_closing = c.token_is(after, '}') || c.token_is(after, ')')
	}
	if is_first_in_line || is_last_in_line || is_before_closing {
		return
	}
	after := token_after or { return }
	// hasTrailingSpace (the token after is on the same line here).
	if tokens.is_space_between(token.end, after.start) {
		if !options.require_space_after {
			findings << c.ssmi_report(token.end, after.start, 'unexpectedWhitespaceAfter',
				fix_remove_range(token.end, after.start))
		}
	} else if options.require_space_after {
		findings << c.ssmi_report(token.start, token.end, 'missingWhitespaceAfter', fix_replace_range(token.end,
			token.end, ' '))
	}
}

fn (c &Checker) ssmi_report(start int, end int, message_id string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}
