module rules

import esquery
import json2
import math
import svelte

// Port of the `svelte/indent` rule of eslint-plugin-svelte 3.24.1 (src/rules/indent.ts and
// src/rules/indent-helpers/): the indentation of every line of a .svelte file, the template, the
// script and the template expressions (the <style> contents and preformatted elements are left
// alone), with its options (indent, indentScript, switchCase, alignAttributesVertically,
// ignoredNodes) and its fixes. Like upstream it runs in two passes: while ESLint's traversal
// enters the nodes, each node's handler records the offset of some of its tokens from a base token
// (OffsetContext); at the end, the lines are checked one by one, the first token of each line
// getting its expected indentation from its base's (OffsetCalculator).
//
// Files: this one (options, token store, offsets, the line pass, the dispatch of the handlers),
// svelte_indent_es.v (indent-helpers/es.ts), svelte_indent_ts.v (ts.ts) and svelte_indent_sv.v
// (svelte.ts). Tokens and nodes are both spans (svelte.Token: a node is a span without a type);
// a token is identified by where it starts, as the offsets are.

const svi_messages = {
	'unexpectedChar':        'Expected {{expected}} character, but found {{actual}} character.'
	'unexpectedIndentation': 'Expected indentation of {{expectedIndent}} {{expectedUnit}}{{expectedIndentPlural}} but found {{actualIndent}} {{actualUnit}}{{actualIndentPlural}}.'
}

// svi_null is a null node or token in a list of them (setOffsetElementList skips them).
const svi_null = svelte.Token{
	start: -1
	end:   -1
}

struct SviOptions {
	indent_char   u8   = ` `
	indent_script bool = true
	indent_size   int  = 2
	switch_case   int  = 1
	align         bool // alignAttributesVertically
	ignored_nodes []string
}

// svi_safe_int is the value when Number.isSafeInteger holds for it.
fn svi_safe_int(v json2.Any) ?int {
	if v is string || v is bool || v is json2.Null || v is map[string]json2.Any || v is []json2.Any {
		return none
	}
	n := json_number(v)
	if n != math.floor(n) || math.abs(n) > 9007199254740991.0 {
		return none
	}
	return int(n)
}

// svi_options is parseOptions of indent-helpers/index.ts (the schema has been checked).
fn svi_options(options []json2.Any) !SviOptions {
	if options.len == 0 || options[0] !is map[string]json2.Any {
		return SviOptions{}
	}
	m := options[0] as map[string]json2.Any
	mut indent_char := u8(` `)
	mut indent_size := 2
	if v := m['indent'] {
		if n := svi_safe_int(v) {
			indent_size = n
		} else if v is string && v == 'tab' {
			indent_char = `\t`
			indent_size = 1
		}
	}
	mut indent_script := true
	if v := m['indentScript'] {
		if v is bool {
			indent_script = v
		}
	}
	mut switch_case := 1
	if v := m['switchCase'] {
		if n := svi_safe_int(v) {
			switch_case = n
		}
	}
	mut ignored := []string{}
	if v := m['ignoredNodes'] {
		if v is []json2.Any {
			for item in v {
				if item is string {
					ignored << item
				}
			}
		}
	}
	mut align := false
	if v := m['alignAttributesVertically'] {
		// A truthy value with spaces.
		truthy := match v {
			bool { v }
			string { v != '' }
			json2.Null { false }
			map[string]json2.Any, []json2.Any { true }
			else { json_number(v) != 0 }
		}
		align = truthy && indent_char == ` `
	}
	return SviOptions{
		indent_char:   indent_char
		indent_script: indent_script
		indent_size:   indent_size
		switch_case:   switch_case
		align:         align
		ignored_nodes: ignored
	}
}

enum SviKind as u8 {
	normal
	align
	start
}

// SviOffset is OffsetData: the indentation of a token as an offset (in indentation units) from
// a base token's, an alignment (in columns) from it, or a fixed offset from the line start.
struct SviOffset {
mut:
	kind         SviKind
	base         int
	offset       int
	align        int
	expected     int
	has_expected bool
}

enum SviFilter {
	any
	not_ws
	open_paren
	close_paren
	not_close_paren
	not_open_paren
	open_bracket
	close_bracket
	open_brace
	close_brace
	not_open_brace
	arrow
	not_semicolon
	optional
}

// SviCtx is the rule's state for one file: the document, the options, the offsets
// (OffsetContext: by token start, an index of `data`, whose items saveExpectedIndent updates)
// and the ignored ranges.
@[heap]
struct SviCtx {
mut:
	doc     &svelte.Document = unsafe { nil }
	opts    SviOptions
	index   map[int]int
	data    []SviOffset
	ignores map[int]int
	// lines: where ESLint's sourceCode.lines start (bytes).
	lines []int
	// crashed: upstream would throw (a node without tokens, see stale_span); ESLint stops linting
	// the file, and the rule reports nothing here.
	crashed bool
}

// --- tokens (the token store of the whole file) ---

// svi_is_ws is isWhitespace of indent-helpers/ast.ts: a blank HTMLText (or JSXText) token.
fn svi_is_ws(t svelte.Token) bool {
	if t.typ != 'HTMLText' && t.typ != 'JSXText' {
		return false
	}
	for r in t.value.runes() {
		if !is_js_space(r) {
			return false
		}
	}
	return true
}

fn svi_pass(t svelte.Token, f SviFilter) bool {
	return match f {
		.any { true }
		.not_ws { !svi_is_ws(t) }
		.open_paren { sv_is_punctuator(t, '(') }
		.close_paren { sv_is_punctuator(t, ')') }
		.not_close_paren { !sv_is_punctuator(t, ')') }
		.not_open_paren { !sv_is_punctuator(t, '(') }
		.open_bracket { sv_is_punctuator(t, '[') }
		.close_bracket { sv_is_punctuator(t, ']') }
		.open_brace { sv_is_punctuator(t, '{') }
		.close_brace { sv_is_punctuator(t, '}') }
		.not_open_brace { !sv_is_punctuator(t, '{') }
		.arrow { sv_is_punctuator(t, '=>') }
		.not_semicolon { !sv_is_punctuator(t, ';') }
		.optional { sv_is_punctuator(t, '?.') }
	}
}

fn svi_is(t ?svelte.Token, f SviFilter) bool {
	if tok := t {
		return svi_pass(tok, f)
	}
	return false
}

// svi_same: the two are the same token (`===`).
fn svi_same(a ?svelte.Token, b ?svelte.Token) bool {
	if x := a {
		if y := b {
			return x.start == y.start && x.end == y.end
		}
	}
	return false
}

// after is getTokenAfter of a node or token ending at `offset`.
fn (x &SviCtx) after(offset int, comments bool, f SviFilter) ?svelte.Token {
	toks := x.doc.tokens
	mut i := sv_lower_bound(toks, offset)
	if !comments {
		for i < toks.len {
			if svi_pass(toks[i], f) {
				return toks[i]
			}
			i++
		}
		return none
	}
	cm := x.doc.comments
	mut j := sv_lower_bound(cm, offset)
	for i < toks.len || j < cm.len {
		mut t := svelte.Token{}
		if j >= cm.len || (i < toks.len && toks[i].start < cm[j].start) {
			t = toks[i]
			i++
		} else {
			t = cm[j]
			j++
		}
		if svi_pass(t, f) {
			return t
		}
	}
	return none
}

// before is getTokenBefore of a node or token starting at `offset`.
fn (x &SviCtx) before(offset int, comments bool, f SviFilter) ?svelte.Token {
	toks := x.doc.tokens
	mut i := sv_upper_end(toks, offset) - 1
	if !comments {
		for i >= 0 {
			if svi_pass(toks[i], f) {
				return toks[i]
			}
			i--
		}
		return none
	}
	cm := x.doc.comments
	mut j := sv_upper_end(cm, offset) - 1
	for i >= 0 || j >= 0 {
		mut t := svelte.Token{}
		if j < 0 || (i >= 0 && toks[i].start > cm[j].start) {
			t = toks[i]
			i--
		} else {
			t = cm[j]
			j--
		}
		if svi_pass(t, f) {
			return t
		}
	}
	return none
}

// ta / tb: getTokenAfter / getTokenBefore of a span, without comments.
fn (x &SviCtx) ta(s svelte.Token) ?svelte.Token {
	return x.after(s.end, false, .any)
}

fn (x &SviCtx) taf(s svelte.Token, f SviFilter) ?svelte.Token {
	return x.after(s.end, false, f)
}

fn (x &SviCtx) tb(s svelte.Token) ?svelte.Token {
	return x.before(s.start, false, .any)
}

fn (x &SviCtx) tbf(s svelte.Token, f SviFilter) ?svelte.Token {
	return x.before(s.start, false, f)
}

// tokens is getTokens of a span (with comments, filtered).
fn (x &SviCtx) tokens(s svelte.Token, comments bool, f SviFilter) []svelte.Token {
	mut out := []svelte.Token{}
	toks := x.doc.tokens
	for i := sv_lower_bound(toks, s.start); i < toks.len && toks[i].end <= s.end; i++ {
		if svi_pass(toks[i], f) {
			out << toks[i]
		}
	}
	if comments {
		cm := x.doc.comments
		mut any := false
		for i := sv_lower_bound(cm, s.start); i < cm.len && cm[i].end <= s.end; i++ {
			if svi_pass(cm[i], f) {
				out << cm[i]
				any = true
			}
		}
		if any {
			out.sort(a.start < b.start)
		}
	}
	return out
}

// between is getTokensBetween of two spans (without comments).
fn (x &SviCtx) between(a svelte.Token, b svelte.Token) []svelte.Token {
	return x.tokens(svelte.Token{ start: a.end, end: b.start }, false, .any)
}

fn (x &SviCtx) between_f(a svelte.Token, b svelte.Token, f SviFilter) []svelte.Token {
	return x.tokens(svelte.Token{ start: a.end, end: b.start }, false, f)
}

// first / last are getFirstToken / getLastToken of a span (a token gives itself).
fn (x &SviCtx) first(s svelte.Token) ?svelte.Token {
	return x.first_f(s, .any)
}

fn (x &SviCtx) first_f(s svelte.Token, f SviFilter) ?svelte.Token {
	if s.start < 0 {
		return none
	}
	toks := x.doc.tokens
	for i := sv_lower_bound(toks, s.start); i < toks.len && toks[i].end <= s.end; i++ {
		if svi_pass(toks[i], f) {
			return toks[i]
		}
	}
	return none
}

fn (x &SviCtx) last(s svelte.Token) ?svelte.Token {
	return x.last_f(s, .any)
}

fn (x &SviCtx) last_f(s svelte.Token, f SviFilter) ?svelte.Token {
	if s.start < 0 {
		return none
	}
	toks := x.doc.tokens
	for i := sv_upper_end(toks, s.end) - 1; i >= 0 && toks[i].start >= s.start; i-- {
		if svi_pass(toks[i], f) {
			return toks[i]
		}
	}
	return none
}

// firsts / lasts are getFirstTokens / getLastTokens with a count (without comments).
fn (x &SviCtx) firsts(s svelte.Token, count int) []svelte.Token {
	mut out := []svelte.Token{}
	toks := x.doc.tokens
	for i := sv_lower_bound(toks, s.start); i < toks.len && toks[i].end <= s.end
		&& out.len < count; i++ {
		out << toks[i]
	}
	return out
}

fn (x &SviCtx) lasts(s svelte.Token, count int) []svelte.Token {
	mut out := []svelte.Token{}
	toks := x.doc.tokens
	for i := sv_upper_end(toks, s.end) - 1; i >= 0 && toks[i].start >= s.start && out.len < count; i-- {
		out.insert(0, toks[i])
	}
	return out
}

// svi_at is the item of a list of tokens, if any (a JavaScript index past the end gives undefined).
fn svi_at(list []svelte.Token, i int) ?svelte.Token {
	if i >= 0 && i < list.len {
		return list[i]
	}
	return none
}

// SviFl are the first and last tokens getFirstAndLastTokens gives.
struct SviFl {
	first svelte.Token
	last  svelte.Token
}

// fl is getFirstAndLastTokens: the outermost parentheses around the span (from border_offset
// on), without white space at either end.
fn (x &SviCtx) fl(s svelte.Token, border_offset int) ?SviFl {
	mut first := x.first(s)?
	mut last := x.last(s)?
	for {
		left := x.tb(first) or { break }
		right := x.ta(last) or { break }
		if !sv_is_punctuator(left, '(') || !sv_is_punctuator(right, ')') || border_offset > left.start {
			break
		}
		first = left
		last = right
	}
	for svi_is_ws(first) && first.start < last.start {
		first = x.ta(first) or { break }
	}
	for svi_is_ws(last) && first.start < last.start {
		last = x.tb(last) or { break }
	}
	return SviFl{first, last}
}

// flf is the first token of getFirstAndLastTokens.
fn (x &SviCtx) flf(s svelte.Token) ?svelte.Token {
	r := x.fl(s, 0)?
	return r.first
}

// --- locations ---

fn (x &SviCtx) start_line(t svelte.Token) int {
	return x.doc.loc(sv_token_loc_start(t)).line
}

fn (x &SviCtx) end_line(t svelte.Token) int {
	return x.doc.loc(sv_token_loc_end(t)).line
}

// is_beginning_of_line is isBeginningOfLine of indent-helpers/commons.ts.
fn (x &SviCtx) is_beginning_of_line(s svelte.Token) bool {
	prev := x.before(s.start, false, .not_ws) or { return true }
	return x.end_line(prev) < x.start_line(s)
}

// line_text is sourceCode.lines[line - 1] (ESLint's lines).
fn (x &SviCtx) line_text(line int) string {
	if line < 1 || line > x.lines.len {
		return ''
	}
	start := x.lines[line - 1]
	mut end := if line < x.lines.len { x.lines[line] } else { x.doc.src.len }
	src := x.doc.src
	// Without the line break.
	for end > start {
		c := src[end - 1]
		if c == `\n` || c == `\r` {
			end--
			continue
		}
		if end - start >= 3 && src[end - 3] == 0xe2 && src[end - 2] == 0x80
			&& (src[end - 1] == 0xa8 || src[end - 1] == 0xa9) {
			end -= 3
		}
		break
	}
	return src[start..end]
}

// --- OffsetContext ---

fn (mut x SviCtx) put(index int, o SviOffset) {
	x.index[index] = x.data.len
	x.data << o
}

// set_index is setOffsetIndex.
fn (mut x SviCtx) set_index(index int, offset int, base int) {
	if index == base {
		return
	}
	x.put(index, SviOffset{
		kind:   .normal
		base:   base
		offset: offset
	})
}

fn (mut x SviCtx) set_align(index int, align int, base int) {
	if index == base {
		return
	}
	x.put(index, SviOffset{
		kind:  .align
		base:  base
		align: align
	})
}

// set is setOffsetToken of one token (none: nothing).
fn (mut x SviCtx) set(t ?svelte.Token, offset int, base svelte.Token) {
	if tok := t {
		if tok.start >= 0 {
			x.set_index(tok.start, offset, base.start)
		}
	}
}

// set_base is setOffsetToken with a base that may be missing (upstream would throw: nothing is
// recorded).
fn (mut x SviCtx) set_base(t ?svelte.Token, offset int, base ?svelte.Token) {
	if b := base {
		x.set(t, offset, b)
	}
}

// sets is setOffsetToken of a list of tokens.
fn (mut x SviCtx) sets(ts []svelte.Token, offset int, base svelte.Token) {
	for t in ts {
		x.set(t, offset, base)
	}
}

// copy_offset is copyOffset.
fn (mut x SviCtx) copy_offset(index int, src int) {
	k := x.index[src] or { return }
	o := x.data[k]
	match o.kind {
		.start { x.set_start(index, o.offset) }
		.align { x.set_align(index, o.align, o.base) }
		.normal { x.set_index(index, o.offset, o.base) }
	}
}

// set_start is setStartOffsetIndex.
fn (mut x SviCtx) set_start(index int, offset int) {
	x.put(index, SviOffset{
		kind:   .start
		offset: offset
	})
}

// element_list is setOffsetElementList: each element (svi_null: none) is `offset` from the
// base's first token, as are the tokens between them, and `last`'s first token 0.
fn (mut x SviCtx) element_list(nodes []svelte.Token, base_node svelte.Token, last_node ?svelte.Token, offset int, align bool) {
	mut align_indent := 0
	mut aligned := false
	if align {
		for n in nodes {
			if n.start < 0 {
				continue
			}
			if !x.is_beginning_of_line(n) {
				loc := x.doc.loc(n.start)
				line := x.line_text(loc.line)
				mut lead := 0
				for r in line.runes() {
					if !is_js_space(r) {
						break
					}
					lead += if r > 0xffff { 2 } else { 1 }
				}
				align_indent = loc.column - lead
				aligned = true
			}
			break
		}
	}
	base_token := x.first(base_node) or { return }
	mut prev_token := x.last(base_node) or { return }
	for n in nodes {
		if n.start < 0 {
			continue
		}
		element := x.fl(n, prev_token.end) or {
			// getFirstAndLastTokens reads the range of the null first token: ESLint crashes.
			x.crashed = true
			return
		}
		mut t := prev_token
		for {
			t = x.after(t.end, true, .not_ws) or { break }
			if t.end > element.first.start {
				break
			}
			x.set_indent(t, base_token, offset, aligned, align_indent)
		}
		x.set_indent(element.first, base_token, offset, aligned, align_indent)
		prev_token = element.last
	}
	if ln := last_node {
		last_token := x.first(ln) or { return }
		mut t := prev_token
		for {
			t = x.after(t.end, true, .not_ws) or { break }
			if t.end > last_token.start {
				break
			}
			x.set_indent(t, base_token, offset, aligned, align_indent)
		}
		x.set(last_token, 0, base_token)
	}
}

fn (mut x SviCtx) set_indent(t svelte.Token, base svelte.Token, offset int, aligned bool, align_indent int) {
	if aligned {
		x.set_align(t.start, align_indent, base.start)
	} else {
		x.set(t, offset, base)
	}
}

// ignore is OffsetContext.ignore of a node's range.
fn (mut x SviCtx) ignore(start int, end int) {
	n := x.ignores[start] or { 0 }
	x.ignores[start] = math.max(n, end)
}

// --- OffsetCalculator ---

fn (mut x SviCtx) expected_of(index int, depth int) ?int {
	k := x.index[index] or { return none }
	o := x.data[k]
	if o.has_expected {
		return o.expected
	}
	if o.kind == .start {
		return o.offset * x.opts.indent_size
	}
	// A cycle of bases would overflow upstream's stack; nothing is expected here.
	if depth > 100000 {
		return none
	}
	base := x.expected_of(o.base, depth + 1)?
	if o.kind == .align {
		return base + o.align
	}
	return base + o.offset * x.opts.indent_size
}

fn (x &SviCtx) is_ignored(index int) bool {
	for f, t in x.ignores {
		if f <= index && index < t {
			return true
		}
	}
	return false
}

// expected_of_tokens is getExpectedIndentFromTokens.
fn (mut x SviCtx) expected_of_tokens(tokens []svelte.Token) ?int {
	for t in tokens {
		if x.is_ignored(t.start) {
			return none
		}
		if e := x.expected_of(t.start, 0) {
			return e
		}
	}
	return none
}

// save_expected is saveExpectedIndent.
fn (mut x SviCtx) save_expected(tokens []svelte.Token, expected int) {
	for t in tokens {
		k := x.index[t.start] or { continue }
		if !x.data[k].has_expected {
			x.data[k].expected = expected
			x.data[k].has_expected = true
		}
	}
}

// --- the line pass (Program:exit of indent-helpers/index.ts) ---

// svi_json_char is JSON.stringify of a one-character string of white space.
fn svi_json_char(r rune) string {
	return match r {
		`\t` { '"\\t"' }
		`\n` { '"\\n"' }
		`\r` { '"\\r"' }
		`\f` { '"\\f"' }
		`\b` { '"\\b"' }
		else {
			if r < 0x20 { '"\\u${int(r):04x}"' } else { '"${r.str()}"' }
		}
	}
}

// validate is validateToken.
fn (mut x SviCtx) validate(mut findings []Finding, c &Checker, token svelte.Token, expected int, optional []int) {
	loc := x.doc.loc(sv_token_loc_start(token))
	line := loc.line
	actual := loc.column
	if line < 1 || line > x.lines.len {
		return
	}
	line_start := x.lines[line - 1]
	text := x.line_text(line)
	// indentText: the first `actual` UTF-16 units of the line, and where each starts.
	mut chars := []rune{}
	mut starts := []int{}
	mut units := 0
	mut at := 0
	for units < actual && at < text.len {
		r_len := utf8_char_len(text[at])
		r := text[at..at + r_len].runes()[0]
		chars << r
		starts << line_start + at
		units += if r > 0xffff { 2 } else { 1 }
		at += r_len
	}
	text_end := line_start + at
	for r in chars {
		if !is_js_space(r) {
			return
		}
	}
	unit := if x.opts.indent_char == `\t` { 'tab' } else { 'space' }
	mut mismatches := []int{}
	for i, r in chars {
		if r != rune(x.opts.indent_char) {
			mismatches << i
		}
	}
	if actual != expected && actual !in optional {
		findings << Finding{
			...c.sv_report_text(line_start, text_end, 'unexpectedIndentation', {
				'expectedIndent':       expected.str()
				'actualIndent':         actual.str()
				'expectedUnit':         unit
				'actualUnit':           if mismatches.len > 0 { 'whitespace' } else { unit }
				'expectedIndentPlural': if expected == 1 { '' } else { 's' }
				'actualIndentPlural':   if actual == 1 { '' } else { 's' }
			})
			has_fix: true
			fix:     Fix{
				start: line_start
				end:   text_end
				text:  x.opts.indent_char.ascii_str().repeat(expected)
			}
		}
		return
	}
	for i in mismatches {
		end := if i + 1 < starts.len { starts[i + 1] } else { text_end }
		findings << Finding{
			...c.sv_report_text(starts[i], end, 'unexpectedChar', {
				'expected': svi_json_char(rune(x.opts.indent_char))
				'actual':   svi_json_char(chars[i])
			})
			has_fix: true
			fix:     Fix{
				start: starts[i]
				end:   end
				text:  x.opts.indent_char.ascii_str()
			}
		}
	}
}

// comment_expected is getCommentExpectedIndents.
fn (x &SviCtx) comment_expected(next svelte.Token, next_expected int, last_expected ?int) []int {
	if le := last_expected {
		if sv_is_punctuator(next, ')') || sv_is_punctuator(next, '}') || sv_is_punctuator(next, ']') {
			if next_expected == le {
				return [next_expected + x.opts.indent_size, next_expected]
			}
			return [le, next_expected]
		}
	}
	return [next_expected]
}

// process_line is processLine.
fn (mut x SviCtx) process_line(mut findings []Finding, c &Checker, tokens []svelte.Token, prev_comments []svelte.Token, prev_token ?svelte.Token, prev_expected ?int) ?int {
	first := tokens[0]
	actual := x.doc.loc(sv_token_loc_start(first)).column
	expected := x.expected_of_tokens(tokens) or {
		x.save_expected(tokens, actual)
		return none
	}
	mut line_expected := max_int
	for t in tokens {
		if e := x.expected_of(t.start, 0) {
			line_expected = math.min(line_expected, e)
		}
	}
	x.save_expected(tokens, line_expected)
	mut prev := prev_token
	if prev_comments.len > 0 {
		if p := prev {
			if x.end_line(p) < x.start_line(prev_comments[0]) {
				indents := x.comment_expected(first, expected, prev_expected)
				x.validate(mut findings, c, prev_comments[0], indents[0], indents[1..])
			}
		}
		prev = prev_comments.last()
	}
	if p := prev {
		if x.end_line(p) < x.start_line(first) {
			x.validate(mut findings, c, first, expected, [])
		}
	}
	return line_expected
}

// check_lines is Program:exit: the tokens of the file (comments included, not the white space)
// line by line; lines of comments only are checked with the next line.
fn (mut x SviCtx) check_lines(mut findings []Finding, c &Checker) {
	program := x.doc.nodes[0]
	all := x.tokens(svelte.Token{ start: program.start, end: program.end }, true, .not_ws)
	mut prev_token := ?svelte.Token(none)
	mut prev_expected := ?int(none)
	mut prev_comments := []svelte.Token{}
	mut buffer := []svelte.Token{}
	mut line := 0
	for token in all {
		this_line := x.start_line(token)
		if line == this_line || buffer.len == 0 {
			buffer << token
		} else {
			if buffer.all(sv_is_comment(it)) {
				prev_comments << buffer[0]
			} else {
				prev_expected = x.process_line(mut findings, c, buffer, prev_comments,
					prev_token, prev_expected)
				prev_token = buffer.last()
				prev_comments = []
			}
			buffer = [token]
		}
		line = this_line
	}
	if buffer.len > 0 && !buffer.all(sv_is_comment(it)) {
		x.process_line(mut findings, c, buffer, prev_comments, prev_token, prev_expected)
	}
}

// --- the traversal ---

// svi_known_types are the node types the handlers know (Object.keys of the merged visitors):
// the tokens of the others are ignored.
const svi_known_types = build_svi_known_types()

fn build_svi_known_types() map[string]bool {
	mut m := map[string]bool{}
	for name in ['Program', 'ArrayExpression', 'ArrayPattern', 'ArrowFunctionExpression',
		'AssignmentExpression', 'AssignmentPattern', 'BinaryExpression', 'LogicalExpression',
		'AwaitExpression', 'RestElement', 'SpreadElement', 'UnaryExpression', 'BlockStatement',
		'ClassBody', 'BreakStatement', 'ContinueStatement', 'CallExpression', 'CatchClause',
		'ClassDeclaration', 'ClassExpression', 'ConditionalExpression', 'DoWhileStatement',
		'ExportAllDeclaration', 'ExportDefaultDeclaration', 'ExportNamedDeclaration', 'ExportSpecifier',
		'ForInStatement', 'ForOfStatement', 'ForStatement', 'FunctionDeclaration', 'FunctionExpression',
		'IfStatement', 'ImportDeclaration', 'ImportExpression', 'ImportNamespaceSpecifier',
		'ImportSpecifier', 'LabeledStatement', 'SvelteReactiveStatement', 'MemberExpression',
		'MetaProperty', 'MethodDefinition', 'Property', 'NewExpression', 'ObjectExpression',
		'ObjectPattern', 'PropertyDefinition', 'ReturnStatement', 'ThrowStatement', 'SequenceExpression',
		'SwitchCase', 'SwitchStatement', 'TaggedTemplateExpression', 'TemplateLiteral', 'TryStatement',
		'UpdateExpression', 'VariableDeclaration', 'VariableDeclarator', 'WhileStatement',
		'WithStatement', 'YieldExpression', 'DebuggerStatement', 'Identifier', 'ImportDefaultSpecifier',
		'Literal', 'PrivateIdentifier', 'Super', 'TemplateElement', 'ThisExpression',
		'ExpressionStatement', 'ChainExpression', 'EmptyStatement', 
		// svelte.ts
		'SvelteScriptElement', 'SvelteStyleElement', 'SvelteElement', 'SvelteStartTag', 'SvelteEndTag',
		'SvelteAttribute', 'SvelteDirective', 'SvelteStyleDirective', 'SvelteSpecialDirective',
		'SvelteShorthandAttribute', 'SvelteSpreadAttribute', 'SvelteDirectiveKey',
		'SvelteSpecialDirectiveKey', 'SvelteText', 'SvelteLiteral', 'SvelteMustacheTag',
		'SvelteDebugTag', 'SvelteConstTag', 'SvelteDeclarationTag', 'SvelteRenderTag', 'SvelteIfBlock',
		'SvelteElseBlock', 'SvelteEachBlock', 'SvelteAwaitBlock', 'SvelteAwaitPendingBlock',
		'SvelteAwaitThenBlock', 'SvelteAwaitCatchBlock', 'SvelteKeyBlock', 'SvelteSnippetBlock',
		'SvelteHTMLComment', 'SvelteName', 'SvelteMemberExpressionName', 
		// ts.ts
		'TSTypeAnnotation', 'TSAsExpression', 'TSSatisfiesExpression', 'TSTypeReference',
		'TSInstantiationExpression', 'TSTypeParameterInstantiation', 'TSTypeParameterDeclaration',
		'TSTypeAliasDeclaration', 'TSFunctionType', 'TSConstructorType', 'TSTypeLiteral',
		'TSPropertySignature', 'TSIndexSignature', 'TSArrayType', 'TSTupleType', 'TSQualifiedName',
		'TSIndexedAccessType', 'TSUnionType', 'TSIntersectionType', 'TSMappedType', 'TSTypeParameter',
		'TSConditionalType', 'TSInterfaceDeclaration', 'TSInterfaceBody', 'TSClassImplements',
		'TSInterfaceHeritage', 'TSEnumDeclaration', 'TSEnumBody', 'TSModuleDeclaration', 'TSModuleBlock',
		'TSMethodSignature', 'TSCallSignatureDeclaration', 'TSConstructSignatureDeclaration',
		'TSEmptyBodyFunctionExpression', 'TSDeclareFunction', 'TSTypeOperator', 'TSTypeQuery',
		'TSInferType', 'TSTypePredicate', 'TSAbstractMethodDefinition', 'TSAbstractPropertyDefinition',
		'TSEnumMember', 'TSAbstractAccessorProperty', 'TSOptionalType', 'TSNonNullExpression',
		'TSJSDocNonNullableType', 'TSTypeAssertion', 'TSImportType', 'TSParameterProperty',
		'TSImportEqualsDeclaration', 'TSExternalModuleReference', 'TSExportAssignment',
		'TSNamedTupleMember', 'TSRestType', 'TSNamespaceExportDeclaration', 'TSTemplateLiteralType',
		'Decorator', 'AccessorProperty', 'StaticBlock', 'ImportAttribute', 'TSAnyKeyword',
		'TSBigIntKeyword', 'TSBooleanKeyword', 'TSNeverKeyword', 'TSNullKeyword', 'TSNumberKeyword',
		'TSObjectKeyword', 'TSStringKeyword', 'TSSymbolKeyword', 'TSUndefinedKeyword',
		'TSUnknownKeyword', 'TSVoidKeyword', 'TSAbstractKeyword', 'TSAsyncKeyword', 'TSPrivateKeyword',
		'TSProtectedKeyword', 'TSPublicKeyword', 'TSReadonlyKeyword', 'TSStaticKeyword',
		'TSDeclareKeyword', 'TSExportKeyword', 'TSIntrinsicKeyword', 'TSThisType', 'TSLiteralType',
		'TSParenthesizedType', 'ClassProperty', 'TSAbstractClassProperty'] {
		m[name] = true
	}
	return m
}

// svi_is_statement is esquery's `:statement` class (a type ending in Statement or Declaration).
fn svi_is_statement(typ string) bool {
	return typ.ends_with('Statement') || typ.ends_with('Declaration')
}

// svi_is_expression is esquery's `:expression` class.
fn svi_is_expression(typ string, parent_type string) bool {
	return typ.ends_with('Expression') || typ.ends_with('Literal')
		|| (typ == 'Identifier' && parent_type != 'MetaProperty') || typ == 'MetaProperty'
}

// svi_ts_semicolon_types are the types of the TS visitor's selector that processes semicolons.
const svi_ts_semicolon_types = ['TSTypeAliasDeclaration', 'TSCallSignatureDeclaration',
	'TSConstructSignatureDeclaration', 'TSImportEqualsDeclaration', 'TSAbstractMethodDefinition',
	'TSAbstractPropertyDefinition', 'AccessorProperty', 'TSAbstractAccessorProperty', 'TSEnumMember',
	'TSPropertySignature', 'TSIndexSignature', 'TSMethodSignature', 'TSAbstractClassProperty',
	'ClassProperty']

// svi_ts_paren_types are the type nodes whose parentheses the `*[type=/^TS/]` listener processes.
const svi_ts_paren_types = ['TSAnyKeyword', 'TSArrayType', 'TSBigIntKeyword', 'TSBooleanKeyword',
	'TSConditionalType', 'TSConstructorType', 'TSFunctionType', 'TSImportType', 'TSIndexedAccessType',
	'TSInferType', 'TSIntersectionType', 'TSIntrinsicKeyword', 'TSLiteralType', 'TSMappedType',
	'TSNamedTupleMember', 'TSNeverKeyword', 'TSNullKeyword', 'TSNumberKeyword', 'TSObjectKeyword',
	'TSOptionalType', 'TSRestType', 'TSStringKeyword', 'TSSymbolKeyword', 'TSTemplateLiteralType',
	'TSThisType', 'TSTupleType', 'TSTypeLiteral', 'TSTypeOperator', 'TSTypePredicate', 'TSTypeQuery',
	'TSTypeReference', 'TSUndefinedKeyword', 'TSUnionType', 'TSUnknownKeyword', 'TSVoidKeyword']

// span_of is the range of a node of either kind.
fn (x &SviCtx) span_of(r svelte.Ref) svelte.Token {
	if r.idx < 0 {
		return svi_null
	}
	if r.es {
		n := x.doc.es.nodes[r.idx]
		return svelte.Token{
			start: n.start
			end:   n.end
		}
	}
	n := x.doc.nodes[r.idx]
	return svelte.Token{
		start: n.start
		end:   n.end
	}
}

// es is the span of an ESTree node (-1: svi_null).
fn (x &SviCtx) es(i int) svelte.Token {
	if i < 0 {
		return svi_null
	}
	n := x.doc.es.nodes[i]
	return svelte.Token{
		start: n.start
		end:   n.end
	}
}

// sn is the span of a Svelte node (-1: svi_null).
fn (x &SviCtx) sn(i int) svelte.Token {
	if i < 0 {
		return svi_null
	}
	n := x.doc.nodes[i]
	return svelte.Token{
		start: n.start
		end:   n.end
	}
}

// type_of is a node's `type`.
fn (x &SviCtx) type_of(r svelte.Ref) string {
	if r.es {
		return x.doc.es_type_name(r.idx)
	}
	return x.doc.nodes[r.idx].typ.type_name()
}

// parent_of is a node's `parent` (the Svelte node above a template expression or a script's
// statement).
fn (x &SviCtx) parent_of(r svelte.Ref) ?svelte.Ref {
	if r.es {
		if p := x.doc.es_parent[r.idx] {
			return sv_snode_ref(p)
		}
		p := x.doc.es.nodes[r.idx].parent
		if p < 0 {
			return none
		}
		return sv_es_ref(p)
	}
	p := x.doc.nodes[r.idx].parent
	if p < 0 {
		return none
	}
	return sv_snode_ref(p)
}

fn (mut c Checker) lint_svelte_indent(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	opts := svi_options(c.rule_options(svelte_indent))!
	if !c.is_svelte() || !c.sv_file_path(abs_path).ends_with('.svelte') {
		return []
	}
	mut ignores := []esquery.EslintSelector{}
	for source in opts.ignored_nodes {
		ignores << esquery.parse_eslint(source)!
	}
	steps := c.sv_steps()
	mut x := &SviCtx{
		doc:   c.svelte.doc
		opts:  opts
		lines: svnts_line_starts(c.svelte.doc.src)
	}
	// The ancestors of the node being visited (ESLint's ancestry, the parent last).
	mut stack := []svelte.Ref{}
	for step in steps {
		r := step.node
		typ := x.type_of(r)
		if !step.leave {
			parent_type := if stack.len > 0 { x.type_of(stack.last()) } else { '' }
			// In the order ESLint calls the listeners on one node: by specificity, then by name.
			if svi_is_expression(typ, parent_type) {
				x.expression_parens(r)
			}
			if svi_is_statement(typ) || typ == 'PropertyDefinition' {
				x.statement_semicolon(r)
			}
			if r.es {
				if typ.starts_with('TS') || typ in ['Decorator', 'AccessorProperty', 'StaticBlock',
					'ImportAttribute', 'ClassProperty'] {
					x.visit_ts(r.idx, typ)
				} else {
					x.visit_es(r.idx, typ)
				}
			} else if typ == 'Program' {
				x.visit_program()
			} else {
				x.visit_sv(r.idx)
			}
			if typ in svi_ts_semicolon_types {
				x.statement_semicolon(r)
			}
			if typ.starts_with('TS') {
				x.ts_type_parens(r, typ, parent_type)
			}
			if r.es && typ in ['ClassDeclaration', 'ClassExpression'] {
				x.ts_class_extends(r.idx)
			}
			stack << r
			continue
		}
		stack.delete_last()
		span := x.span_of(r)
		if typ !in svi_known_types {
			x.ignore(span.start, span.end)
		}
		for sel in ignores {
			if x.ignore_matches(sel, r, typ, stack)! {
				x.ignore(span.start, span.end)
			}
		}
	}
	if x.crashed {
		return []
	}
	mut findings := []Finding{}
	x.check_lines(mut findings, c)
	stats.checked++
	return findings
}

// ignore_matches: an ignoredNodes selector matches the node being left. A plain type (or `*`)
// matches any node of that type; another selector is tried on the ESTree nodes, with their
// ESTree ancestors (the Svelte nodes are not ESTree's: a selector across them does not match).
fn (x &SviCtx) ignore_matches(sel esquery.EslintSelector, r svelte.Ref, typ string, stack []svelte.Ref) !bool {
	match sel.root.kind {
		.wildcard {
			return true
		}
		.identifier {
			return sel.root.value == typ
		}
		else {}
	}
	if !r.es {
		return false
	}
	if types := sel.node_types {
		if typ !in types {
			return false
		}
	}
	mut ancestry := []int{}
	for k := stack.len - 1; k >= 0; k-- {
		if !stack[k].es {
			break
		}
		ancestry << stack[k].idx
	}
	return esquery.matches(&x.doc.es, r.idx, &sel.root, ancestry)!
}

// statement_semicolon is the `:statement, PropertyDefinition` listener of es.ts (and its TS
// twin): a semicolon that ends a line is at the indentation of its statement's first token.
fn (mut x SviCtx) statement_semicolon(r svelte.Ref) {
	s := x.span_of(r)
	first := x.first(s) or { return }
	last := x.last(s) or { return }
	if sv_is_punctuator(last, ';') && !svi_same(first, last) {
		if next := x.ta(last) {
			if x.start_line(last) >= x.start_line(next) {
				return
			}
		}
		x.set(last, 0, first)
	}
}

// expression_parens is the `:expression` listener of es.ts: the parentheses around an
// expression.
fn (mut x SviCtx) expression_parens(r svelte.Ref) {
	s := x.span_of(r)
	mut left := x.tb(s)
	mut right := x.ta(s)
	mut first := x.first(s)
	for svi_is(left, .open_paren) && svi_is(right, .close_paren) {
		l := left or { break }
		x.set(first, 1, l)
		x.set(right, 0, l)
		first = l
		left = x.tb(l)
		right = x.ta(right or { break })
	}
}

// visit_program is es.ts's Program: the top-level nodes start at column 0.
fn (mut x SviCtx) visit_program() {
	for ch in x.doc.nodes[0].children {
		n := x.doc.nodes[ch]
		if n.typ == .text && svi_blank(n.value) {
			continue
		}
		if t := x.first(x.sn(ch)) {
			x.set_start(t.start, 0)
		}
	}
}

// svi_blank: `!value.trim()`.
fn svi_blank(s string) bool {
	for r in s.runes() {
		if !is_js_space(r) {
			return false
		}
	}
	return true
}
