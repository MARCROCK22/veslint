module rules

import estree
import time
import x.json2

// Port of the `@stylistic/function-call-spacing` rule of @stylistic/eslint-plugin 6.0.1, with
// its options (`"never"`, the default, or `"always"` with `allowNewlines` and `optionalChain`) and
// its fixes: the spacing between the callee of a call, a `new` or an `import()` and its `(`.

const sfcs_messages = {
	'unexpectedWhitespace': 'Unexpected whitespace between function name and paren.'
	'unexpectedNewline':    'Unexpected newline between function name and paren.'
	'missing':              'Missing space between function name and paren.'
}

struct SfcsOptions {
	never           bool
	allow_newlines  bool
	before_optional bool
	after_optional  bool
}

fn sfcs_options(given []json2.Any) !SfcsOptions {
	options := sty_options(given, [json2.Any('never')])
	config := sty_option_object(options, 1)
	optional_chain := sty_option_object([config['optionalChain'] or { json2.Any(map[string]json2.Any{}) }],
		0)
	return SfcsOptions{
		never:           sty_option_string(options, 0, 'never') == 'never'
		allow_newlines:  sty_option_bool(config, 'allowNewlines') or { false }
		before_optional: sty_option_bool(optional_chain, 'before') or { true }
		after_optional:  sty_option_bool(optional_chain, 'after') or { true }
	}
}

fn (mut c Checker) lint_stylistic_function_call_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sfcs_options(c.rule_options(stylistic_function_call_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.call_expression, .new_expression {
				stats.checked++
				closing := un_last_token(t, tokens, node) or { continue }
				callee := t.node(node, .type_arguments) or { t.node(node, .callee) or { continue } }
				last_callee := un_last_token(t, tokens, callee) or { continue }
				// getFirstTokenBetween(lastCalleeToken, closingParenToken, isOpeningParenToken)
				mut opening := SourceToken{}
				mut found := false
				for token in tokens.inside(last_callee.end, closing.start, false) {
					if c.token_is(token, '(') {
						opening = token
						found = true
						break
					}
				}
				if !found || opening.end >= t.nodes[node].end {
					continue
				}
				// getTokenBefore(openingParenToken, isNotOptionalChainPunctuator)
				mut index := source_tokens_index(tokens.tokens, opening.start) - 1
				for index >= 0 && c.token_is(tokens.tokens[index], '?.') {
					index--
				}
				if index < 0 {
					continue
				}
				c.sfcs_check_spacing(t, tokens, node, tokens.tokens[index], opening, options, mut
					findings)
			}
			.import_expression {
				stats.checked++
				left := un_first_token(t, tokens, node, 0) or { continue }
				right := tokens.after(left.end, false) or { continue }
				c.sfcs_check_spacing(t, tokens, node, left, right, options, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sfcs_strip_comments is `.replace(/\/\*.*?\*\//gu, '')`: the block comments that do not span a
// line terminator removed.
fn sfcs_strip_comments(text string) string {
	mut out := []u8{cap: text.len}
	mut i := 0
	outer: for i < text.len {
		if i + 1 < text.len && text[i] == `/` && text[i + 1] == `*` {
			mut j := i + 2
			for j + 1 < text.len {
				if text[j] == `*` && text[j + 1] == `/` {
					i = j + 2
					continue outer
				}
				if sfcs_line_terminator_at(text, j) > 0 {
					break
				}
				j++
			}
		}
		out << text[i]
		i++
	}
	return out.bytestr()
}

// sfcs_line_terminator_at is the length in bytes of the line terminator (`\n`, `\r`, U+2028 or
// U+2029) at a byte offset, 0 if there is none.
fn sfcs_line_terminator_at(text string, i int) int {
	if text[i] == `\n` || text[i] == `\r` {
		return 1
	}
	if text[i] == 0xe2 && i + 2 < text.len && text[i + 1] == 0x80
		&& (text[i + 2] == 0xa8 || text[i + 2] == 0xa9) {
		return 3
	}
	return 0
}

// sfcs_has_line_terminator is LINEBREAK_MATCHER.test.
fn sfcs_has_line_terminator(text string) bool {
	for i in 0 .. text.len {
		if sfcs_line_terminator_at(text, i) > 0 {
			return true
		}
	}
	return false
}

// sfcs_trim_start is String#trimStart (JavaScript's whitespace and line terminators).
fn sfcs_trim_start(text string) string {
	mut i := 0
	for i < text.len {
		r, n := sks_rune_at(text, i)
		if !sks_is_js_whitespace(r) {
			break
		}
		i += n
	}
	return text[i..]
}

// sfcs_trim_end is String#trimEnd.
fn sfcs_trim_end(text string) string {
	mut end := text.len
	for end > 0 {
		mut start := end - 1
		for start > 0 && text[start] & 0xc0 == 0x80 {
			start--
		}
		r, _ := sks_rune_at(text, start)
		if !sks_is_js_whitespace(r) {
			break
		}
		end = start
	}
	return text[..end]
}

// sfcs_starts_with_space is `/^\s/u.test(text)`.
fn sfcs_starts_with_space(text string) bool {
	return text.len > 0 && sfcs_trim_start(text).len != text.len
}

// sfcs_ends_with_space is `/\s$/u.test(text)`.
fn sfcs_ends_with_space(text string) bool {
	return text.len > 0 && sfcs_trim_end(text).len != text.len
}

// sfcs_has_space is `/\s/u.test(text)`.
fn sfcs_has_space(text string) bool {
	mut i := 0
	for i < text.len {
		r, n := sks_rune_at(text, i)
		if sks_is_js_whitespace(r) {
			return true
		}
		i += n
	}
	return false
}

// sfcs_safe_replace ports safeReplaceTextBetween: no fix when comments are in between.
fn sfcs_safe_replace(tokens &SourceTokens, left SourceToken, right SourceToken, replacement string) ?Fix {
	if tokens.comments_exist_between(left.end, right.start) {
		return none
	}
	return fix_replace_range(left.end, right.start, replacement)
}

fn (c &Checker) sfcs_report(left SourceToken, right SourceToken, message_id string, fix ?Fix, mut findings []Finding) {
	findings << Finding{
		stmt:       c.position_range(left.end, right.start)
		message_id: message_id
		has_fix:    fix != none
		fix:        fix or { Fix{} }
	}
}

// sfcs_check_spacing ports checkSpacing.
fn (c &Checker) sfcs_check_spacing(t &estree.EsTree, tokens &SourceTokens, node int, left SourceToken, right SourceToken, options SfcsOptions, mut findings []Finding) {
	is_optional_call := t.typ(node) == .call_expression && (t.flag(node, .optional) or { false })
	text_between := sfcs_strip_comments(c.src[left.end..right.start])
	has_whitespace := sfcs_has_space(text_between)
	has_newline := has_whitespace && sfcs_has_line_terminator(text_between)
	if c.vue_wrap_core {
		c.sfcs_check_spacing_core(tokens, left, right, options, is_optional_call, has_whitespace,
			has_newline, mut findings)
		return
	}
	if options.never {
		if has_whitespace {
			c.sfcs_report(left, right, 'unexpectedWhitespace', sfcs_safe_replace(tokens, left,
				right, if is_optional_call { '?.' } else { '' }), mut findings)
		}
		return
	}
	if is_optional_call {
		has_prefix_space := sfcs_starts_with_space(text_between)
		has_suffix_space := sfcs_ends_with_space(text_between)
		correct_prefix := if options.before_optional { has_prefix_space } else { !has_prefix_space }
		correct_suffix := if options.after_optional { has_suffix_space } else { !has_suffix_space }
		correct_newline := options.allow_newlines || !has_newline
		if correct_prefix && correct_suffix && correct_newline {
			return
		}
		message_id := if !correct_newline {
			'unexpectedNewline'
		} else if (!options.before_optional && has_prefix_space)
			|| (!options.after_optional && has_suffix_space) {
			'unexpectedWhitespace'
		} else {
			'missing'
		}
		mut text := text_between
		if !options.allow_newlines {
			text = text.replace('\r\n', ' ').replace_each(['\r', ' ', '\n', ' ', ' ', ' ', ' ',
				' '])
		}
		if !correct_prefix {
			text = if options.before_optional { ' ${text}' } else { sfcs_trim_start(text) }
		}
		if !correct_suffix {
			text = if options.after_optional { '${text} ' } else { sfcs_trim_end(text) }
		}
		c.sfcs_report(left, right, message_id, sfcs_safe_replace(tokens, left, right, text), mut
			findings)
		return
	}
	if !has_whitespace {
		c.sfcs_report(left, right, 'missing', fix_insert_at(right.start, ' '), mut findings)
	} else if !options.allow_newlines && has_newline {
		c.sfcs_report(left, right, 'unexpectedNewline', sfcs_safe_replace(tokens, left, right,
			' '), mut findings)
	}
}

// sfcs_previous_char is the start of the character before `offset` (`column - 1`).
fn (c &Checker) sfcs_previous_char(offset int) int {
	mut i := offset - 1
	for i > 0 && c.src[i] & 0xc0 == 0x80 {
		i--
	}
	return if i < 0 { 0 } else { i }
}

// sfcs_check_spacing_core is checkSpacing of ESLint core's func-call-spacing, which
// vue/func-call-spacing runs without @stylistic/eslint-plugin (vue_wrap.v): no option for the
// spaces around `?.`, its own places and fixes.
fn (c &Checker) sfcs_check_spacing_core(tokens &SourceTokens, left SourceToken, right SourceToken, options SfcsOptions, optional bool, has_whitespace bool, has_newline bool, mut findings []Finding) {
	if options.never && has_whitespace {
		mut fix := ?Fix(none)
		if !tokens.comments_exist_between(left.end, right.start) {
			if optional {
				fix = fix_replace_range(left.end, right.start, '?.')
			} else if !has_newline {
				fix = fix_remove_range(left.end, right.start)
			}
		}
		findings << Finding{
			stmt:       c.position_range(left.end, c.sfcs_previous_char(right.start))
			message_id: 'unexpectedWhitespace'
			has_fix:    fix != none
			fix:        fix or { Fix{} }
		}
	} else if !options.never && !has_whitespace {
		findings << Finding{
			stmt:       c.position_range(c.sfcs_previous_char(left.end), right.start)
			message_id: 'missing'
			has_fix:    !optional
			fix:        if optional { Fix{} } else { fix_insert_at(right.start, ' ') }
		}
	} else if !options.never && !options.allow_newlines && has_newline {
		mut fix := ?Fix(none)
		if optional && !tokens.comments_exist_between(left.end, right.start) {
			if qd := tokens.after(left.end, false) {
				fix = if qd.start == left.end {
					fix_replace_range(left.end, right.start, '?. ')
				} else if qd.end == right.start {
					fix_replace_range(left.end, right.start, ' ?.')
				} else {
					fix_replace_range(left.end, right.start, ' ?. ')
				}
			}
		}
		findings << Finding{
			stmt:       c.position_range(left.end, right.start)
			message_id: 'unexpectedNewline'
			has_fix:    fix != none
			fix:        fix or { Fix{} }
		}
	}
}
