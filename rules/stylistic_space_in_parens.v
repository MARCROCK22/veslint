module rules

import estree
import treesitter { node_kind }
import time
import x.json2

// Port of the `@stylistic/space-in-parens` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`"always"` or `"never"`, the default, and the `exceptions` `{}`, `[]`, `()` and
// `empty`) and its fixes.

const sinp_messages = {
	'missingOpeningSpace':  'There must be a space after this paren.'
	'missingClosingSpace':  'There must be a space before this paren.'
	'rejectedOpeningSpace': 'There should be no space after this paren.'
	'rejectedClosingSpace': 'There should be no space before this paren.'
}

struct SinpOptions {
	always bool
	empty  bool
	// The values of the tokens that are exceptions after an opening paren and before a closing one
	// (getExceptions).
	openers []string
	closers []string
}

fn sinp_options(given []json2.Any) !SinpOptions {
	options := sty_options(given, [json2.Any('never')])
	mut exceptions := []string{}
	if list := sty_option_object(options, 1)['exceptions'] {
		if list is []json2.Any {
			for item in list {
				if item is string {
					exceptions << item
				}
			}
		}
	}
	mut openers := []string{}
	mut closers := []string{}
	if '{}' in exceptions {
		openers << '{'
		closers << '}'
	}
	if '[]' in exceptions {
		openers << '['
		closers << ']'
	}
	if '()' in exceptions {
		openers << '('
		closers << ')'
	}
	empty := 'empty' in exceptions
	if empty {
		openers << ')'
		closers << '('
	}
	return SinpOptions{
		always:  sty_option_string(options, 0, '') == 'always'
		empty:   empty
		openers: openers
		closers: closers
	}
}

fn (mut c Checker) lint_stylistic_space_in_parens(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sinp_options(c.rule_options(stylistic_space_in_parens))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t).all
	for i, token in tokens {
		opening := c.sinp_is_paren(token, '(')
		if !opening && !c.sinp_is_paren(token, ')') {
			continue
		}
		stats.checked++
		if opening {
			if i + 1 >= tokens.len {
				continue
			}
			next := tokens[i + 1]
			if c.sinp_opener_missing_space(options, token, next) {
				findings << c.sinp_report(token.start, token.end, 'missingOpeningSpace', fix_replace_range(token.end,
					token.end, ' '))
			}
			if c.sinp_opener_rejects_space(t, options, token, next) {
				findings << c.sinp_report(token.end, next.start, 'rejectedOpeningSpace',
					fix_remove_range(token.end, next.start))
			}
		} else {
			if i == 0 {
				continue
			}
			previous := tokens[i - 1]
			if c.sinp_closer_missing_space(options, previous, token) {
				findings << c.sinp_report(token.start, token.end, 'missingClosingSpace', fix_replace_range(token.start,
					token.start, ' '))
			}
			if c.sinp_closer_rejects_space(t, options, previous, token) {
				findings << c.sinp_report(previous.end, token.start, 'rejectedClosingSpace',
					fix_remove_range(previous.end, token.start))
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sinp_is_paren ports isOpeningParenToken and isClosingParenToken: a Punctuator token (a JSXText
// token is not one).
fn (c &Checker) sinp_is_paren(token SourceToken, paren string) bool {
	return c.token_is(token, paren) && node_kind(token.node) != 'jsx_text'
}

// sinp_value is the `value` of a token or a comment: the text of a comment without its
// delimiters.
fn (c &Checker) sinp_value(token SourceToken) string {
	text := c.token_text(token)
	return match token.kind {
		.line_comment, .shebang_comment { text[2..] }
		.block_comment { text[2..text.len - 2] }
		else { text }
	}
}

// sinp_opener_missing_space ports openerMissingSpace.
fn (c &Checker) sinp_opener_missing_space(options SinpOptions, paren SourceToken, after SourceToken) bool {
	if paren.end != after.start {
		return false
	}
	if !options.empty && c.sinp_is_paren(after, ')') {
		return false
	}
	exception := c.sinp_value(after) in options.openers
	return if options.always { !exception } else { exception }
}

// sinp_opener_rejects_space ports openerRejectsSpace.
fn (c &Checker) sinp_opener_rejects_space(t &estree.EsTree, options SinpOptions, paren SourceToken, after SourceToken) bool {
	if !sty_same_line(t, paren, after) {
		return false
	}
	if after.kind == .line_comment {
		return false
	}
	if paren.end == after.start {
		return false
	}
	exception := c.sinp_value(after) in options.openers
	return if options.always { exception } else { !exception }
}

// sinp_closer_missing_space ports closerMissingSpace.
fn (c &Checker) sinp_closer_missing_space(options SinpOptions, before SourceToken, paren SourceToken) bool {
	if before.end != paren.start {
		return false
	}
	if !options.empty && c.sinp_is_paren(before, '(') {
		return false
	}
	exception := c.sinp_value(before) in options.closers
	return if options.always { !exception } else { exception }
}

// sinp_closer_rejects_space ports closerRejectsSpace.
fn (c &Checker) sinp_closer_rejects_space(t &estree.EsTree, options SinpOptions, before SourceToken, paren SourceToken) bool {
	if !sty_same_line(t, before, paren) {
		return false
	}
	if before.end == paren.start {
		return false
	}
	exception := c.sinp_value(before) in options.closers
	return if options.always { exception } else { !exception }
}

fn (c &Checker) sinp_report(start int, end int, message_id string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}
