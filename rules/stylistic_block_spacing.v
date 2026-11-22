module rules

import estree
import time
import x.json2

// Port of the `@stylistic/block-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its option
// (`"always"`, the default, or `"never"`) and its fixes: the spaces after the `{` and before the `}`
// of blocks, static blocks and switch statements.

const sbls_messages = {
	'missing': "Requires a space {{location}} '{{token}}'."
	'extra':   "Unexpected space(s) {{location}} '{{token}}'."
}

fn sbls_options(given []json2.Any) !bool {
	options := sty_options(given, [json2.Any('always')])
	return sty_option_string(options, 0, '') != 'never'
}

fn (mut c Checker) lint_stylistic_block_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	always := sbls_options(c.rule_options(stylistic_block_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if !t.visits(node) {
			continue
		}
		if t.typ(node) !in [.block_statement, .static_block, .switch_statement] {
			continue
		}
		stats.checked++
		c.sbls_check(t, tokens, node, always, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sbls_check ports checkSpacingInsideBraces.
fn (c &Checker) sbls_check(t &estree.EsTree, tokens &SourceTokens, node int, always bool, mut findings []Finding) {
	// getOpenBrace: the first `{` token of the node; for a switch statement, the first `{` after
	// the discriminant, which may itself contain braces, e.g. `switch (a || {}) {}`.
	mut open_brace := SourceToken{}
	mut found := false
	mut from := t.nodes[node].start
	if t.typ(node) == .switch_statement {
		discriminant := t.node(node, .discriminant) or { return }
		from = t.nodes[discriminant].end
	}
	for token in tokens.inside(from, t.nodes[node].end, false) {
		if c.token_is(token, '{') {
			open_brace = token
			found = true
			break
		}
	}
	if !found {
		return
	}
	close_brace := un_last_token(t, tokens, node) or { return }
	first_token := tokens.after(open_brace.end, true) or { return }
	last_token := tokens.before(close_brace.start, true) or { return }
	if !c.token_is(close_brace, '}') || first_token.start == close_brace.start {
		return
	}
	// Skip line comments for option never
	if !always && first_token.kind == .line_comment {
		return
	}
	message_id := if always { 'missing' } else { 'extra' }
	if !sbls_is_valid(t, tokens, open_brace, first_token, always) {
		start := if always { open_brace.start } else { open_brace.end }
		end := if always { open_brace.end } else { first_token.start }
		fix := if always {
			fix_insert_at(first_token.start, ' ')
		} else {
			fix_remove_range(open_brace.end, first_token.start)
		}
		findings << c.sbls_report(start, end, message_id, 'after', c.token_text(open_brace), fix)
	}
	if !sbls_is_valid(t, tokens, last_token, close_brace, always) {
		start := if always { close_brace.start } else { last_token.end }
		end := if always { close_brace.end } else { close_brace.start }
		fix := if always {
			fix_insert_at(last_token.end, ' ')
		} else {
			fix_remove_range(last_token.end, close_brace.start)
		}
		findings << c.sbls_report(start, end, message_id, 'before', c.token_text(close_brace), fix)
	}
}

// sbls_is_valid ports isValid: the tokens are on different lines, or there is a space between
// them exactly when the option is "always".
fn sbls_is_valid(t &estree.EsTree, tokens &SourceTokens, left SourceToken, right SourceToken, always bool) bool {
	return !sty_same_line(t, left, right) || tokens.is_space_between(left.end, right.start) == always
}

fn (c &Checker) sbls_report(start int, end int, message_id string, location string, token string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       {
			'location': location
			'token':    token
		}
		has_fix:    true
		fix:        fix
	}
}
