module rules

import json2
import jsregexp
import regexpp
import time

// Port of the `ban-ts-comment` rule of typescript-eslint 8.72.2, with its options
// `minimumDescriptionLength`, `ts-check`, `ts-expect-error`, `ts-ignore` and `ts-nocheck` (true,
// false, 'allow-with-description' or `{ descriptionFormat }`) and its suggestion to replace
// `@ts-ignore` with `@ts-expect-error`. The regular expressions run on the UTF-16 units of the
// comments, as in JavaScript.

const btsc_messages = {
	'replaceTsIgnoreWithTsExpectError':             'Replace "@ts-ignore" with "@ts-expect-error".'
	'tsDirectiveComment':                           'Do not use "@ts-{{directive}}" because it alters compilation errors.'
	'tsDirectiveCommentDescriptionNotMatchPattern': 'The description for the "@ts-{{directive}}" directive must match the {{format}} format.'
	'tsDirectiveCommentRequiresDescription':        'Include a description after the "@ts-{{directive}}" directive to explain why the @ts-{{directive}} is necessary. The description must be {{minimumDescriptionLength}} characters or longer.'
	'tsIgnoreInsteadOfExpectError':                 'Use "@ts-expect-error" instead of "@ts-ignore", as "@ts-ignore" will do nothing if the following line is error-free.'
}

const btsc_directives = ['ts-expect-error', 'ts-ignore', 'ts-nocheck', 'ts-check']

// BtscDirective is the option of a directive: `forbid` for true, `with_description` for
// 'allow-with-description' or an object with a non-empty `descriptionFormat` (then `format`).
struct BtscDirective {
	forbid           bool
	with_description bool
	format           ?jsregexp.JsRegex
	format_source    string
}

struct BtscOptions {
	minimum_description_length f64
	directives                 map[string]BtscDirective
}

fn btsc_options(options []json2.Any) !BtscOptions {
	o := option_object(ban_ts_comment, options, ['minimumDescriptionLength', 'ts-check',
		'ts-expect-error', 'ts-ignore', 'ts-nocheck'])!
	mut minimum := 0.0
	if value := o.values['minimumDescriptionLength'] {
		if json_kind(value) != .number {
			return error('option `minimumDescriptionLength` of `${ban_ts_comment}` must be a number')
		}
		minimum = json_number(value)
	}
	mut directives := map[string]BtscDirective{}
	for name in btsc_directives {
		value := o.values[name] or {
			directives[name] = BtscDirective{}
			continue
		}
		directives[name] = btsc_directive(name, value)!
	}
	return BtscOptions{
		minimum_description_length: minimum
		directives:                 directives
	}
}

fn btsc_directive(name string, value json2.Any) !BtscDirective {
	if value is bool {
		return BtscDirective{
			forbid: value
		}
	}
	if value is string {
		if value == 'allow-with-description' {
			return BtscDirective{
				with_description: true
			}
		}
	} else if value is map[string]json2.Any {
		for key, _ in value {
			if key != 'descriptionFormat' {
				return error('option `${name}` of `${ban_ts_comment}` has no property `${key}`')
			}
		}
		format := value['descriptionFormat'] or { return BtscDirective{} }
		if format !is string {
			return error('option `${name}.descriptionFormat` of `${ban_ts_comment}` must be a string')
		}
		pattern := format as string
		if pattern == '' {
			return BtscDirective{}
		}
		units := utf16_units(pattern)
		return BtscDirective{
			with_description: true
			format:           jsregexp.js_regex_new(pattern, '')!
			format_source:    regexpp.utf16_to_wtf8(jsregexp.regexp_escape_source(units))
		}
	}
	return error('option `${name}` of `${ban_ts_comment}` must be true, false, "allow-with-description" or { descriptionFormat }')
}

// BtscMatch is a directive found in a comment: its name without `ts-` and its description.
struct BtscMatch {
	directive   string
	description string
}

// btsc_exec ports execDirectiveRegEx: the groups `directive` (1) and `description` (2).
fn btsc_exec(regex &jsregexp.JsRegex, text string) !(bool, BtscMatch) {
	units := utf16_units(text)
	found, _, _, slots := regex.exec(units, 0)!
	if !found {
		return false, BtscMatch{}
	}
	return true, BtscMatch{
		directive:   regexpp.utf16_to_wtf8(units[slots[2]..slots[3]])
		description: regexpp.utf16_to_wtf8(units[slots[4]..slots[5]])
	}
}

// btsc_last_line is the last line of a block comment's value, split with LINEBREAK_MATCHER
// (/\r\n|[\r\n  ]/u).
fn btsc_last_line(value string) string {
	mut start := 0
	mut i := 0
	for i < value.len {
		if value[i] == `\r` || value[i] == `\n` {
			start = i + 1
		} else if value[i] == 0xe2 && i + 2 < value.len && value[i + 1] == 0x80
			&& value[i + 2] in [u8(0xa8), 0xa9] {
			start = i + 3
			i += 2
		}
		i++
	}
	return value[start..]
}

fn (mut c Checker) lint_ban_ts_comment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := btsc_options(c.rule_options(ban_ts_comment))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	single_line_pragma := jsregexp.js_regex_new(r'^\/\/\/?\s*@ts-(?<directive>check|nocheck)(?<description>.*)$',
		'')!
	single_line := jsregexp.js_regex_new(r'^\/*\s*@ts-(?<directive>expect-error|ignore)(?<description>.*)',
		'')!
	multi_line := jsregexp.js_regex_new(r'^\s*(?:\/|\*)*\s*@ts-(?<directive>expect-error|ignore)(?<description>.*)',
		'')!
	// The line of the first statement of the Program.
	mut first_statement_line := -1
	if body := t.list(t.root, .body) {
		if body.len > 0 {
			first_statement_line, _ = t.line_column(t.nodes[body[0]].start)
		}
	}
	tokens := c.source_tokens(root)
	mut checked := 0
	for comment in tokens.comments {
		checked++
		is_line := comment.kind == .line_comment
		value := if comment.kind == .block_comment {
			c.src[comment.start + 2..comment.end - 2]
		} else {
			c.src[comment.start + 2..comment.end]
		}
		// findDirectiveInComment.
		mut found, mut m := false, BtscMatch{}
		if is_line {
			found, m = btsc_exec(single_line_pragma, '//' + value)!
			if !found {
				found, m = btsc_exec(single_line, value)!
			}
		} else {
			found, m = btsc_exec(multi_line, btsc_last_line(value))!
		}
		if !found {
			continue
		}
		if m.directive == 'nocheck' && first_statement_line >= 0 {
			comment_line, _ := t.line_column(comment.start)
			if first_statement_line <= comment_line {
				continue
			}
		}
		full_directive := 'ts-${m.directive}'
		option := o.directives[full_directive] or { BtscDirective{} }
		position := c.position_range(comment.start, comment.end)
		if option.forbid {
			if m.directive == 'ignore' {
				// The first `@ts-ignore` of the value.
				text := value.replace_once('@ts-ignore', '@ts-expect-error')
				replacement := if is_line { '//${text}' } else { '/*${text}*/' }
				_, suggestion := c.suggestion('replaceTsIgnoreWithTsExpectError', map[string]string{},
					[fix_replace_range(comment.start, comment.end, replacement)])!
				findings << Finding{
					stmt:        position
					message_id:  'tsIgnoreInsteadOfExpectError'
					suggestions: [suggestion]
				}
			} else {
				findings << Finding{
					stmt:       position
					message_id: 'tsDirectiveComment'
					data:       {
						'directive': m.directive
					}
				}
			}
		}
		if option.with_description {
			if sty_string_length(js_trim(m.description)) < o.minimum_description_length {
				findings << Finding{
					stmt:       position
					message_id: 'tsDirectiveCommentRequiresDescription'
					data:       {
						'directive':                m.directive
						'minimumDescriptionLength': js_number_to_string(o.minimum_description_length)
					}
				}
			} else if format := option.format {
				if !format.test(utf16_units(m.description))! {
					findings << Finding{
						stmt:       position
						message_id: 'tsDirectiveCommentDescriptionNotMatchPattern'
						data:       {
							'directive': m.directive
							'format':    option.format_source
						}
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
