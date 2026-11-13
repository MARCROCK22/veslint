module rules

import json2
import time
import treesitter { children, node_end, node_kind, node_start }

// Port of the `no-irregular-whitespace` rule of ESLint 10.6.0, with its options.

const niw_messages = {
	'noIrregularWhitespace': 'Irregular whitespace not allowed.'
}

// The irregular whitespace (IRREGULAR_WHITESPACE) and line terminators of the rule.
const niw_spaces = [rune(`\f`), `\v`, `\u0085`, `﻿`, ` `, ` `, `᠎`, ` `, ` `, ` `,
	` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, `​`, ` `, ` `, `　`]
const niw_terminators = [rune(` `), ` `]

struct NiwOptions {
	skip_comments  bool
	skip_jsx_text  bool
	skip_regexps   bool
	skip_strings   bool
	skip_templates bool
}

// niw_options reads skipComments, skipJSXText, skipRegExps, skipStrings and skipTemplates.
fn niw_options(options []json2.Any) !NiwOptions {
	o := option_object(no_irregular_whitespace, options, ['skipComments', 'skipJSXText', 'skipRegExps',
		'skipStrings', 'skipTemplates'])!
	return NiwOptions{
		skip_comments:  o.bool_value('skipComments')!
		skip_jsx_text:  o.bool_value('skipJSXText')!
		skip_regexps:   o.bool_value('skipRegExps')!
		skip_strings:   o.bool_value('skipStrings')!
		skip_templates: o.bool_value('skipTemplates')!
	}
}

fn niw_has_irregular(text string) bool {
	for r in text.runes() {
		if r in niw_spaces || r in niw_terminators {
			return true
		}
	}
	return false
}

fn (mut c Checker) lint_no_irregular_whitespace(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := niw_options(c.rule_options(no_irregular_whitespace))!
	mut findings := []Finding{}
	stats.checked++
	if !niw_has_irregular(c.src) {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	// The runs of irregular whitespace, then the irregular line terminators, by byte offset.
	mut errors := []int{}
	mut i := 0
	mut in_run := false
	for i < c.src.len {
		r, size := niw_rune_at(c.src, i)
		if r in niw_spaces {
			if !in_run {
				errors << i
				in_run = true
			}
		} else {
			in_run = false
		}
		i += size
	}
	i = 0
	for i < c.src.len {
		r, size := niw_rune_at(c.src, i)
		if r in niw_terminators {
			errors << i
		}
		i += size
	}
	// The ranges where irregular whitespace is allowed.
	mut allowed := [][]int{}
	mut kinds := ['string', 'regex']
	if o.skip_templates {
		kinds << 'template_string'
	}
	if o.skip_jsx_text {
		kinds << 'jsx_text'
	}
	for node in c.nodes_of_kinds(root, kinds, []) {
		match node_kind(node) {
			'string' {
				if o.skip_strings && niw_has_irregular(c.text(node)) {
					allowed << [node_start(node), node_end(node)]
				}
			}
			'regex' {
				if o.skip_regexps && niw_has_irregular(c.text(node)) {
					allowed << [node_start(node), node_end(node)]
				}
			}
			'template_string' {
				// Each TemplateElement, with its delimiters.
				mut from := node_start(node)
				for child in children(node) {
					if node_kind(child) == 'template_substitution' {
						to := node_start(child) + 2
						if niw_has_irregular(c.src[from..to]) {
							allowed << [from, to]
						}
						from = node_end(child) - 1
					}
				}
				to := node_end(node)
				if niw_has_irregular(c.src[from..to]) {
					allowed << [from, to]
				}
			}
			else {
				if niw_has_irregular(c.text(node)) {
					allowed << [node_start(node), node_end(node)]
				}
			}
		}
	}
	if o.skip_comments {
		for comment in c.source_tokens(root).comments {
			text := c.src[comment.start..comment.end]
			value := if text.starts_with('//') { text[2..] } else { text[2..text.len - 2] }
			if niw_has_irregular(value) {
				allowed << [comment.start, comment.end]
			}
		}
	}
	for offset in errors {
		if allowed.any(offset >= it[0] && offset < it[1]) {
			continue
		}
		findings << Finding{
			stmt:       c.position_at(offset)
			message_id: 'noIrregularWhitespace'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// niw_rune_at is the character that starts at a byte offset, and its size.
fn niw_rune_at(s string, i int) (rune, int) {
	b := s[i]
	size := if b < 0x80 {
		1
	} else if b >= 0xf0 {
		4
	} else if b >= 0xe0 {
		3
	} else if b >= 0xc0 {
		2
	} else {
		1
	}
	end := if i + size > s.len { s.len } else { i + size }
	runes := s[i..end].runes()
	return if runes.len > 0 { runes[0] } else { rune(b) }, end - i
}
