module rules

import jsregexp
import time
import x.json2

// Port of the `@stylistic/spaced-comment` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`"always"`, the default, or `"never"`, and `exceptions`, `markers`, and per comment type
// `line` and `block`, with `balanced`) and its fixes. The regular expressions are built as the rule
// builds them and run by jsregexp.

const sspc_messages = {
	'unexpectedSpaceAfterMarker': 'Unexpected space or tab after marker ({{refChar}}) in comment.'
	'expectedExceptionAfter':     "Expected exception block, space or tab after '{{refChar}}' in comment."
	'unexpectedSpaceBefore':      "Unexpected space or tab before '*/' in comment."
	'unexpectedSpaceAfter':       "Unexpected space or tab after '{{refChar}}' in comment."
	'expectedSpaceBefore':        "Expected space or tab before '*/' in comment."
	'expectedSpaceAfter':         "Expected space or tab after '{{refChar}}' in comment."
}

// SspcStyleRule is the StyleRuleRegExp of a comment type.
struct SspcStyleRule {
	begin_regex    jsregexp.JsRegex
	end_regex      jsregexp.JsRegex
	has_exceptions bool
	capture_marker jsregexp.JsRegex
	markers        []string
}

struct SspcOptions {
	require_space bool
	balanced      bool
	block         SspcStyleRule
	line          SspcStyleRule
}

fn sspc_options(given []json2.Any) !SspcOptions {
	options := sty_options(given, decoded_default_options(stylistic_spaced_comment))
	require_space := sty_option_string(options, 0, 'always') != 'never'
	config := sty_option_object(options, 1)
	type_config := fn [config] (name string) map[string]json2.Any {
		return sty_option_object([config[name] or { json2.Any(json2.Null{}) }], 0)
	}
	balanced := sty_option_bool(type_config('block'), 'balanced') or { false }
	return SspcOptions{
		require_space: require_space
		balanced:      balanced
		block:         sspc_style_rule(config, type_config('block'), require_space, balanced)!
		line:          sspc_style_rule(config, type_config('line'), require_space, balanced)!
	}
}

// sspc_strings is `object[key]` when it is an array (of strings, by the schema), else none.
fn sspc_strings(object map[string]json2.Any, key string) ?[]string {
	value := object[key] or { return none }
	if value is []json2.Any {
		mut out := []string{}
		for item in value {
			if item is string {
				out << item
			}
		}
		return out
	}
	return none
}

fn sspc_style_rule(config map[string]json2.Any, type_config map[string]json2.Any, require_space bool, balanced bool) !SspcStyleRule {
	mut markers := sspc_strings(type_config, 'markers') or {
		sspc_strings(config, 'markers') or { []string{} }
	}
	// parseMarkersOption: `*` is a marker for JSDoc comments.
	if '*' !in markers {
		markers << '*'
	}
	exceptions := sspc_strings(type_config, 'exceptions') or {
		sspc_strings(config, 'exceptions') or { []string{} }
	}
	begin := if require_space {
		sspc_always_style_pattern(markers, exceptions)
	} else {
		'^(${markers.map(sspc_escape(it)).join('|')})?[ \t]+'
	}
	end := if balanced && require_space {
		'${sspc_exceptions_pattern(exceptions)}$'
	} else {
		'[ \t]+$'
	}
	return SspcStyleRule{
		begin_regex:    jsregexp.js_regex_new(begin, 'u')!
		end_regex:      jsregexp.js_regex_new(end, 'u')!
		has_exceptions: exceptions.len > 0
		capture_marker: jsregexp.js_regex_new('^(${markers.map(sspc_escape(it)).join('|')})',
			'u')!
		markers:        markers
	}
}

// sspc_escape ports escape: `(?:${escapeRegExp(s)})`, with escapeRegExp of escape-string-regexp
// 4.0.0.
fn sspc_escape(s string) string {
	mut out := []u8{cap: s.len + 8}
	out << '(?:'.bytes()
	for b in s.bytes() {
		if b in '|\\{}()[]^$+*?.'.bytes() {
			out << `\\`
			out << b
		} else if b == `-` {
			out << '\\x2d'.bytes()
		} else {
			out << b
		}
	}
	out << `)`
	return out.bytestr()
}

// sspc_exceptions_pattern ports createExceptionsPattern.
fn sspc_exceptions_pattern(exceptions []string) string {
	if exceptions.len == 0 {
		return '\\s'
	}
	mut pattern := '(?:\\s|'
	if exceptions.len == 1 {
		pattern += '${sspc_escape(exceptions[0])}+'
	} else {
		pattern += '(?:${exceptions.map('${sspc_escape(it)}+').join('|')})'
	}
	// `[${Array.from(LINEBREAKS).join('')}]`
	pattern += '(?:$|[\r\n\r\n  ]))'
	return pattern
}

// sspc_always_style_pattern ports createAlwaysStylePattern.
fn sspc_always_style_pattern(markers []string, exceptions []string) string {
	mut pattern := '^'
	if markers.len == 1 {
		pattern += sspc_escape(markers[0])
	} else {
		pattern += '(?:${markers.map(sspc_escape(it)).join('|')})'
	}
	pattern += '?'
	pattern += sspc_exceptions_pattern(exceptions)
	return pattern
}

// SspcMatch is the result of `exec` on a comment's value (`ok`: a match), in bytes of the value:
// the match and its first group (-1 when it did not take part).
struct SspcMatch {
	ok          bool
	start       int
	end         int
	group_start int = -1
	group_end   int = -1
}

// opt is the match, none without one.
fn (m SspcMatch) opt() ?SspcMatch {
	return if m.ok { m } else { none }
}

fn sspc_exec(re jsregexp.JsRegex, value string) !SspcMatch {
	found, start, end, slots := re.exec(utf16_units(value), 0)!
	if !found {
		return SspcMatch{}
	}
	// The indexes are of code points (the `u` flag): their byte offsets.
	mut offsets := []int{cap: value.len + 1}
	mut i := 0
	for i < value.len {
		offsets << i
		i += utf8_char_len(value[i])
	}
	offsets << value.len
	mut m := SspcMatch{
		ok:    true
		start: offsets[start]
		end:   offsets[end]
	}
	if slots.len > 3 && slots[2] >= 0 {
		m = SspcMatch{
			...m
			group_start: offsets[slots[2]]
			group_end:   offsets[slots[3]]
		}
	}
	return m
}

fn (mut c Checker) lint_stylistic_spaced_comment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sspc_options(c.rule_options(stylistic_spaced_comment))!
	t := c.es_tree(root, abs_path) or { return findings }
	for comment in c.un_tokens(t).comments {
		if comment.kind == .shebang_comment {
			continue
		}
		stats.checked++
		c.sspc_check(comment, options, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sspc_check ports checkCommentForSpace.
fn (c &Checker) sspc_check(comment SourceToken, options SspcOptions, mut findings []Finding) ! {
	block := comment.kind == .block_comment
	rule := if block { options.block } else { options.line }
	comment_identifier := if block { '/*' } else { '//' }
	value := if block {
		c.src[comment.start + 2..comment.end - 2]
	} else {
		c.src[comment.start + 2..comment.end]
	}
	// Ignores empty comments and comments that consist only of a marker.
	if value.len == 0 || value in rule.markers {
		return
	}
	if !block && sspc_is_triple_slash_reference(value) {
		return
	}
	begin_match := sspc_exec(rule.begin_regex, value)!.opt()
	end_match := sspc_exec(rule.end_regex, value)!.opt()
	if options.require_space {
		if begin_match == none {
			has_marker := sspc_exec(rule.capture_marker, value)!.opt()
			marker := if m := has_marker {
				comment_identifier + value[m.start..m.end]
			} else {
				comment_identifier
			}
			message_id := if rule.has_exceptions {
				'expectedExceptionAfter'
			} else {
				'expectedSpaceAfter'
			}
			findings << c.sspc_report_begin(comment, message_id, has_marker, marker, options, value)
		}
		if options.balanced && block && end_match == none {
			findings << c.sspc_report_end(comment, 'expectedSpaceBefore', none, options)
		}
	} else {
		if m := begin_match {
			if m.group_start < 0 || m.group_start == m.group_end {
				findings << c.sspc_report_begin(comment, 'unexpectedSpaceAfter', m, comment_identifier,
					options, value)
			} else {
				findings << c.sspc_report_begin(comment, 'unexpectedSpaceAfterMarker', m,
					value[m.group_start..m.group_end], options, value)
			}
		}
		if options.balanced && block {
			if m := end_match {
				findings << c.sspc_report_end(comment, 'unexpectedSpaceBefore', m, options)
			}
		}
	}
}

// sspc_report_begin ports reportBegin.
fn (c &Checker) sspc_report_begin(comment SourceToken, message_id string, found ?SspcMatch, ref_char string, options SspcOptions, value string) Finding {
	start := comment.start
	mut end := start + 2
	if m := found {
		end += m.end - m.start
	}
	fix := if options.require_space {
		fix_insert_at(end, ' ')
	} else {
		mut text := if comment.kind == .block_comment { '/*' } else { '//' }
		if m := found {
			if m.group_start >= 0 {
				text += value[m.group_start..m.group_end]
			}
		}
		fix_replace_range(start, end, text)
	}
	return Finding{
		stmt:       c.position_range(comment.start, comment.end)
		message_id: message_id
		data:       {
			'refChar': ref_char
		}
		has_fix:    true
		fix:        fix
	}
}

// sspc_report_end ports reportEnd.
fn (c &Checker) sspc_report_end(comment SourceToken, message_id string, found ?SspcMatch, options SspcOptions) Finding {
	end := comment.end - 2
	fix := if options.require_space {
		fix_insert_at(end, ' ')
	} else {
		mut start := end
		if m := found {
			start -= m.end - m.start
		}
		fix_remove_range(start, end)
	}
	return Finding{
		stmt:       c.position_range(comment.start, comment.end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}

// sspc_is_triple_slash_reference ports isTripleSlashReference (shared/utils/ast/comment.ts) on the
// value of a line comment: TRIPLE_SLASH_REFERENCE_PATTERN, /^\/\s*<(?:reference|amd-)/u.
fn sspc_is_triple_slash_reference(value string) bool {
	if !value.starts_with('/') {
		return false
	}
	runes := value[1..].runes()
	mut i := 0
	for i < runes.len && is_js_space(runes[i]) {
		i++
	}
	rest := runes[i..].string()
	return rest.starts_with('<reference') || rest.starts_with('<amd-')
}
