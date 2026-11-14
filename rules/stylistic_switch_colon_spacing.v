module rules

import estree
import time
import x.json2

// Port of the `@stylistic/switch-colon-spacing` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`before`, false by default, and `after`, true by default) and its fixes.

const sscs_messages = {
	'expectedBefore':   'Expected space(s) before this colon.'
	'expectedAfter':    'Expected space(s) after this colon.'
	'unexpectedBefore': 'Unexpected space(s) before this colon.'
	'unexpectedAfter':  'Unexpected space(s) after this colon.'
}

struct SscsOptions {
	before_spacing bool
	after_spacing  bool
}

fn sscs_options(given []json2.Any) !SscsOptions {
	options := sty_options(given, [
		json2.Any({
			'before': json2.Any(false)
			'after':  json2.Any(true)
		}),
	])
	config := sty_option_object(options, 0)
	before := sty_option_bool(config, 'before') or { false }
	after := sty_option_bool(config, 'after') or { true }
	return SscsOptions{
		before_spacing: before
		after_spacing:  after
	}
}

fn (mut c Checker) lint_stylistic_switch_colon_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sscs_options(c.rule_options(stylistic_switch_colon_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .switch_case {
			continue
		}
		stats.checked++
		c.sscs_check(t, tokens, node, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sscs_colon_token ports getSwitchCaseColonToken of shared/utils/ast/general.ts.
fn (c &Checker) sscs_colon_token(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	if test := t.node(node, .test) {
		return c.un_token_after_punctuator(tokens, t.nodes[test].end, ':')
	}
	return un_first_token(t, tokens, node, 1)
}

fn (c &Checker) sscs_check(t &estree.EsTree, tokens &SourceTokens, node int, options SscsOptions, mut findings []Finding) {
	colon := c.sscs_colon_token(t, tokens, node) or { return }
	before := tokens.before(colon.start, false) or { return }
	after := tokens.after(colon.end, false) or { return }
	if !c.sscs_is_valid_spacing(t, tokens, before, colon, options.before_spacing) {
		findings << c.sscs_report(tokens, colon, if options.before_spacing {
			'expectedBefore'
		} else {
			'unexpectedBefore'
		}, before, colon, options.before_spacing)
	}
	if !c.sscs_is_valid_spacing(t, tokens, colon, after, options.after_spacing) {
		findings << c.sscs_report(tokens, colon, if options.after_spacing {
			'expectedAfter'
		} else {
			'unexpectedAfter'
		}, colon, after, options.after_spacing)
	}
}

// sscs_is_valid_spacing ports isValidSpacing.
fn (c &Checker) sscs_is_valid_spacing(t &estree.EsTree, tokens &SourceTokens, left SourceToken, right SourceToken, expected bool) bool {
	return c.token_is(right, '}') || !sty_same_line(t, left, right)
		|| tokens.is_space_between(left.end, right.start) == expected
}

// sscs_report reports at the colon, with the fix of `fix` (none when comments are between the
// tokens).
fn (c &Checker) sscs_report(tokens &SourceTokens, colon SourceToken, message_id string, left SourceToken, right SourceToken, spacing bool) Finding {
	if tokens.comments_exist_between(left.end, right.start) {
		return Finding{
			stmt:       c.position_range(colon.start, colon.end)
			message_id: message_id
		}
	}
	return Finding{
		stmt:       c.position_range(colon.start, colon.end)
		message_id: message_id
		has_fix:    true
		fix:        if spacing {
			fix_replace_range(left.end, left.end, ' ')
		} else {
			fix_remove_range(left.end, right.start)
		}
	}
}
