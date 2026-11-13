module rules

import json2
import jsregexp
import time
import treesitter { position_of }

// Port of the `no-warning-comments` rule of ESLint 10.6.0.

const nwc_messages = {
	'unexpectedComment': "Unexpected '{{matchedTerm}}' comment: '{{comment}}'."
}

const nwc_char_limit = 40

struct NwcOptions {
	terms      []string
	start      bool // location: "start"
	decoration []string
}

fn nwc_options(options []json2.Any) !NwcOptions {
	o := option_object(no_warning_comments, options, ['terms', 'location', 'decoration'])!
	terms := if 'terms' in o.values { o.string_list('terms')! } else { ['todo', 'fixme', 'xxx'] }
	location := o.string_value('location', ['start', 'anywhere'])!
	return NwcOptions{
		terms:      terms
		start:      location != 'anywhere'
		decoration: o.string_list('decoration')!
	}
}

// nwc_escape ports escape-string-regexp 4.
fn nwc_escape(s string) string {
	mut out := []u8{cap: s.len}
	for ch in s.bytes() {
		if ch == `-` {
			out << '\\x2d'.bytes()
			continue
		}
		if ch in '|\\{}()[]^$+*?.'.bytes() {
			out << `\\`
		}
		out << ch
	}
	return out.bytestr()
}

fn nwc_is_word_char(ch u8) bool {
	return ch.is_letter() || ch.is_digit() || ch == `_`
}

fn (mut c Checker) lint_no_warning_comments(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nwc_options(c.rule_options(no_warning_comments))!
	// convertToRegExp: the term with word boundaries (at the start of the comment, after white
	// space and decoration, for location "start"), with the flags `iu`.
	decoration := nwc_escape(o.decoration.join(''))
	mut programs := []?jsregexp.RegexpProgram{}
	for term in o.terms {
		mut prefix := ''
		if o.start {
			prefix = '^[\\s${decoration}]*'
		} else if term.len > 0 && nwc_is_word_char(term[0]) {
			prefix = '\\b'
		}
		suffix := if term.len > 0 && nwc_is_word_char(term[term.len - 1]) { '\\b' } else { '' }
		programs << jsregexp.regexp_compile('(?i:${prefix}${nwc_escape(term)}${suffix})') or { none }
	}
	mut findings := []Finding{}
	for comment in c.nodes_of_kinds(root, ['comment'], []) {
		stats.checked++
		text := c.text(comment)
		if text.starts_with('#!') {
			continue
		}
		block := text.starts_with('/*')
		value := if block { text[2..text.len - 2] } else { text[2..] }
		trimmed := js_trim(value)
		// A directive comment that names this rule.
		if (!block && trimmed.starts_with('eslint-')) || (block && nwc_is_directive(trimmed)) {
			if nwc_names_self(value) {
				continue
			}
		}
		for i, term in o.terms {
			program := programs[i] or { continue }
			if !(jsregexp.regexp_test(program, value) or { false }) {
				continue
			}
			mut display := ''
			mut truncated := false
			for word in nwc_split_space(trimmed) {
				candidate := if display == '' { word } else { '${display} ${word}' }
				if utf16_units(candidate).len <= nwc_char_limit {
					display = candidate
				} else {
					truncated = true
					break
				}
			}
			findings << Finding{
				stmt:       position_of(comment)
				message_id: 'unexpectedComment'
				data:       {
					'matchedTerm': term
					'comment':     display + if truncated { '...' } else { '' }
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nwc_is_directive ports ESLINT_DIRECTIVE_PATTERN: /^(?:eslint[- ]|(?:globals?|exported) )/u.
fn nwc_is_directive(comment string) bool {
	for prefix in ['eslint-', 'eslint ', 'global ', 'globals ', 'exported '] {
		if comment.starts_with(prefix) {
			return true
		}
	}
	return false
}

// nwc_names_self ports /\bno-warning-comments\b/u.
fn nwc_names_self(comment string) bool {
	name := 'no-warning-comments'
	mut from := 0
	for {
		at := comment.index_after(name, from) or { return false }
		before_ok := at == 0 || !nwc_is_word_char(comment[at - 1])
		end := at + name.len
		after_ok := end >= comment.len || !nwc_is_word_char(comment[end])
		if before_ok && after_ok {
			return true
		}
		from = at + 1
	}
	return false
}

// nwc_split_space ports `text.split(/\s+/u)` of a trimmed text.
fn nwc_split_space(text string) []string {
	mut out := []string{}
	mut current := []rune{}
	mut in_space := false
	for r in text.runes() {
		if is_js_space(r) {
			if !in_space {
				out << current.string()
				current = []rune{}
			}
			in_space = true
			continue
		}
		in_space = false
		current << r
	}
	out << current.string()
	return out
}
