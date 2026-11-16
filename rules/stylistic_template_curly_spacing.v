module rules

import estree
import time
import x.json2

// Port of the `@stylistic/template-curly-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// option (`"always"` or `"never"`, the default) and its fixes.

const stcs_messages = {
	'expectedBefore':   "Expected space(s) before '}'."
	'expectedAfter':    "Expected space(s) after '\${'."
	'unexpectedBefore': "Unexpected space(s) before '}'."
	'unexpectedAfter':  "Unexpected space(s) after '\${'."
}

fn stcs_options(given []json2.Any) !bool {
	options := sty_options(given, [json2.Any('never')])
	return sty_option_string(options, 0, '') == 'always'
}

fn (mut c Checker) lint_stylistic_template_curly_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	always := stcs_options(c.rule_options(stylistic_template_curly_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if t.typ(node) != .template_element {
			continue
		}
		stats.checked++
		token := un_first_token(t, tokens, node, 0) or { continue }
		c.stcs_check_before(t, tokens, token, always, mut findings)
		c.stcs_check_after(t, tokens, token, always, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// stcs_check_before ports checkSpacingBefore: the spacing before the `}` a Template token starts
// with.
fn (c &Checker) stcs_check_before(t &estree.EsTree, tokens &SourceTokens, token SourceToken, always bool, mut findings []Finding) {
	if !c.token_text(token).starts_with('}') {
		return
	}
	previous := tokens.before(token.start, true) or { return }
	has_space := tokens.is_space_between(previous.end, token.start)
	if !sty_same_line(t, previous, token) {
		return
	}
	if always && !has_space {
		findings << c.stcs_report(token.start, token.start + 1, 'expectedBefore', fix_replace_range(token.start,
			token.start, ' '))
	}
	if !always && has_space {
		findings << c.stcs_report(previous.end, token.start, 'unexpectedBefore', fix_remove_range(previous.end,
			token.start))
	}
}

// stcs_check_after ports checkSpacingAfter: the spacing after the `${` a Template token ends with.
fn (c &Checker) stcs_check_after(t &estree.EsTree, tokens &SourceTokens, token SourceToken, always bool, mut findings []Finding) {
	if !c.token_text(token).ends_with('\${') {
		return
	}
	next := tokens.after(token.end, true) or { return }
	has_space := tokens.is_space_between(token.end, next.start)
	if !sty_same_line(t, token, next) {
		return
	}
	if always && !has_space {
		findings << c.stcs_report(token.end - 2, token.end, 'expectedAfter', fix_replace_range(token.end,
			token.end, ' '))
	}
	if !always && has_space {
		findings << c.stcs_report(token.end, next.start, 'unexpectedAfter', fix_remove_range(token.end,
			next.start))
	}
}

fn (c &Checker) stcs_report(start int, end int, message_id string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}
