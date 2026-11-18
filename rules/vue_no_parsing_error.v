module rules

import json2
import time
import tsgo
import vue

// Port of the `vue/no-parsing-error` rule of eslint-plugin-vue 10.12.1: the errors of the document
// (templateBody.errors: the HTML parse errors of the whole file, with their codes, and the errors of
// the template expressions), each code on or off by its option (the defaults of DEFAULT_OPTIONS;
// an error whose code is not there is never reported).

const vnpe_messages = {
	'parsingError': 'Parsing error: {{message}}.'
}

// vnpe_default_codes is DEFAULT_OPTIONS.
const vnpe_default_codes = {
	'abrupt-closing-of-empty-comment':                       true
	'absence-of-digits-in-numeric-character-reference':      true
	'cdata-in-html-content':                                 true
	'character-reference-outside-unicode-range':             true
	'control-character-in-input-stream':                     true
	'control-character-reference':                           true
	'eof-before-tag-name':                                   true
	'eof-in-cdata':                                          true
	'eof-in-comment':                                        true
	'eof-in-tag':                                            true
	'incorrectly-closed-comment':                            true
	'incorrectly-opened-comment':                            true
	'invalid-first-character-of-tag-name':                   true
	'missing-attribute-value':                               true
	'missing-end-tag-name':                                  true
	'missing-semicolon-after-character-reference':           true
	'missing-whitespace-between-attributes':                 true
	'nested-comment':                                        true
	'noncharacter-character-reference':                      true
	'noncharacter-in-input-stream':                          true
	'null-character-reference':                              true
	'surrogate-character-reference':                         true
	'surrogate-in-input-stream':                             true
	'unexpected-character-in-attribute-name':                true
	'unexpected-character-in-unquoted-attribute-value':      true
	'unexpected-equals-sign-before-attribute-name':          true
	'unexpected-null-character':                             true
	'unexpected-question-mark-instead-of-tag-name':          true
	'unexpected-solidus-in-tag':                             true
	'unknown-named-character-reference':                     true
	'end-tag-with-attributes':                               true
	'duplicate-attribute':                                   true
	'end-tag-with-trailing-solidus':                         true
	'non-void-html-element-start-tag-with-trailing-solidus': false
	'x-invalid-end-tag':                                     true
	'x-invalid-namespace':                                   true
}

// vnpe_options is `Object.assign({}, DEFAULT_OPTIONS, context.options[0] || {})`.
fn vnpe_options(options []json2.Any) !map[string]bool {
	mut codes := vnpe_default_codes.clone()
	o := option_object(vue_no_parsing_error, options, vnpe_default_codes.keys())!
	for key, _ in o.values {
		codes[key] = o.bool_value(key)!
	}
	return codes
}

fn (mut c Checker) lint_vue_no_parsing_error(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	codes := vnpe_options(c.rule_options(vue_no_parsing_error))!
	mut findings := []Finding{}
	for e in c.vue_document_errors() {
		stats.checked++
		if e.code != '' && !(codes[e.code] or { false }) {
			continue
		}
		message := if e.message.ends_with('.') { e.message[..e.message.len - 1] } else { e.message }
		loc := c.vue_error_loc(e)
		findings << Finding{
			stmt:         c.position_at(if e.index < c.src.len { e.index } else { c.src.len })
			message_id:   'parsingError'
			data:         {
				'message': message
			}
			fixed_line:   loc.line
			fixed_column: loc.column + 1
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_error_loc is the lineNumber and column of an error of the document.
fn (c &Checker) vue_error_loc(e vue.ParseError) vue.Loc {
	if e.line != 0 {
		return vue.Loc{e.line, e.column}
	}
	doc := c.vue.doc
	if e.index <= doc.src.len {
		return doc.loc(e.index)
	}
	// Past the end of the file (an error at the end of the input): on the last line.
	last := doc.loc(doc.src.len)
	return vue.Loc{last.line, last.column + (e.index - doc.src.len)}
}

// vue_scanner_order puts each "Unterminated string literal." (1002, which TypeScript's scanner
// reports at the end of the string's line when it reads the token) before the parser's errors at
// the string's start, which TypeScript reports after it, once the token is the current one
// (`0(a "x` gives it, then "',' expected." at the quote). Positions are UTF-16 offsets of code.
fn vue_scanner_order(code string, diagnostics []tsgo.Diagnostic) []tsgo.Diagnostic {
	if !diagnostics.any(it.code == 1002) {
		return diagnostics
	}
	mut units := []u16{cap: code.len}
	for r in code.runes() {
		if r > 0xffff {
			v := u32(r) - 0x10000
			units << u16(0xd800 + (v >> 10))
			units << u16(0xdc00 + (v & 0x3ff))
		} else {
			units << u16(r)
		}
	}
	mut out := diagnostics.clone()
	for i := 0; i < out.len; i++ {
		u := out[i]
		if u.code != 1002 {
			continue
		}
		// The first error before it whose position is a quote that opens a string running to it.
		for j in 0 .. i {
			if vue_opens_string_to(units, out[j].pos, u.pos) {
				out.delete(i)
				out.insert(j, u)
				break
			}
		}
	}
	return out
}

// vue_opens_string_to: units[start] is a quote, and the text after it up to end has neither a line
// terminator nor that quote unescaped (a string from start would be unterminated at end).
fn vue_opens_string_to(units []u16, start int, end int) bool {
	if start < 0 || start >= end || end > units.len || units[start] !in [u16(`'`), u16(`"`)] {
		return false
	}
	quote := units[start]
	mut k := start + 1
	for k < end {
		ch := units[k]
		if ch in [u16(`\n`), u16(`\r`), u16(0x2028), u16(0x2029)] || ch == quote {
			return false
		}
		k += if ch == u16(`\\`) { 2 } else { 1 }
	}
	return true
}

// vue_document_errors are the errors of the document as vue-eslint-parser gives them: those whose
// message is TypeScript's first syntactic diagnostic for the code of a template expression
// (ParseError.ts_message) get it from tsgo, with its position, and go back among the errors without
// a code in the order of their positions (insertError's sorted insert).
fn (mut c Checker) vue_document_errors() []vue.ParseError {
	doc := c.vue.doc
	if !doc.errors.any(it.ts_message && it.snippet >= 0) {
		return doc.errors
	}
	mut coded := []vue.ParseError{}
	mut inserted := []vue.ParseError{}
	for e in doc.errors {
		if e.code != '' {
			coded << e
			continue
		}
		if !e.ts_message || e.snippet < 0 {
			inserted << e
			continue
		}
		snippet := &doc.snippets[e.snippet]
		diagnostics := c.client.transpile_diagnostics(snippet.code, if snippet.tsx {
			'snippet.tsx'
		} else {
			'snippet.ts'
		}) or { []tsgo.Diagnostic{} }
		if diagnostics.len == 0 {
			// TypeScript parses the code: vue-eslint-parser has no error there.
			continue
		}
		// typescript-estree throws the first diagnostic the parser reported; tsgo gives them by
		// position, which puts the ones reported once what follows was parsed (a JSX element or
		// fragment without its closing tag, JSX expressions without one parent) first, and those
		// reported at the start of an unterminated string before the string's own.
		ordered := vue_scanner_order(snippet.code, diagnostics)
		mut first := ordered[0]
		for d in ordered {
			if d.code !in [17008, 17014, 2657] {
				first = d
				break
			}
		}
		index := snippet.utf16_to_file(first.pos)
		inserted << vue.ParseError{
			...e
			index:   index
			message: if e.adjust_end >= 0 && index >= e.adjust_end {
				'Unexpected end of expression.'
			} else {
				first.text
			}
		}
	}
	// insertError: before the first error whose index is not smaller, in document order.
	mut out := coded.clone()
	for e in inserted {
		mut lo := 0
		mut hi := out.len
		for lo < hi {
			mid := (lo + hi) / 2
			if out[mid].index < e.index {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		out.insert(lo, e)
	}
	return out
}
