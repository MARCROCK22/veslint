module svelte

// A port of the Svelte 5.56.0 compiler's template parser (src/compiler/phases/1-parse: index.js,
// state/{fragment,element,tag,text}.js, read/{expression,context,options,script,style}.js) as
// svelte-eslint-parser calls it: `parse(template, {modern: true})`, not loose. JavaScript is
// not parsed (see jsscan.v): expressions get their extent, kind and comments.

struct CParser {
	src string // the template, trimEnd()ed
	ts  bool
mut:
	index     int
	ast       CAst
	stack     []int // node indexes; -1 is the root
	fragments []int
	meta_tags map[string]bool
	// last_auto_closed_tag: tag, reason, depth (has_auto when set).
	auto_tag    string
	auto_reason string
	auto_depth  int
	has_auto    bool
	js          JsScanner
}

const regex_lang_needle = '<script'

// compiler_ts is the compiler's TypeScript mode: the first `<script …lang=…>` start tag (HTML
// comments skipped) has lang `ts` (regex_lang_attribute).
fn compiler_ts(template string) bool {
	mut i := 0
	for i < template.len {
		lt := template.index_after('<', i) or { return false }
		if template[lt..].starts_with('<!--') {
			e := template.index_after('-->', lt + 4) or { return false }
			i = e + 3
			continue
		}
		if template[lt..].starts_with('<script') && lt + 7 < template.len
			&& is_space_at(template, lt + 7) {
			if lang := script_lang_regex_match(template, lt + 7) {
				return lang == 'ts'
			}
		}
		i = lt + 1
	}
	return false
}

// script_lang_regex_match matches the rest of regex_lang_attribute after `<script` (at `i`, a
// whitespace): `\s+(?:[^>]*|(?:[^=>'"/]+=(?:"[^"]*"|'[^']*'|[^>\s]+)\s+)*)lang=(["'])?([^"'
// >]+)\1[^>]*>`. The first alternative `[^>]*` backtracks over everything up to the `>`, so
// a match is the last `lang=` before the first `>` that reads as `lang=` + value + the same
// quote (or none) + no `>` before the `>`.
fn script_lang_regex_match(t string, i int) ?string {
	gt := t.index_after('>', i) or { return none }
	// Backtracking of `[^>]*` tries the longest prefix first: the last `lang=` wins.
	mut pos := gt
	for pos > i {
		at := last_index_in(t, 'lang=', i, pos) or { return none }
		pos = at
		// `\s+` before the alternative needs at least one whitespace at i; `[^>]*` takes the rest.
		mut v := at + 5
		mut quote := u8(0)
		if v < gt && (t[v] == `"` || t[v] == `'`) {
			quote = t[v]
			v++
		}
		mut e := v
		for e < gt && t[e] != `"` && t[e] != `'` && t[e] != ` ` && t[e] != `>` {
			e++
		}
		if e > v {
			// Try the value lengths from the longest down (`[^"' >]+` backtracks).
			for end := e; end > v; end-- {
				if quote != 0 {
					if end < gt && t[end] == quote {
						return t[v..end]
					}
				} else {
					return t[v..end]
				}
			}
		}
	}
	return none
}

fn last_index_in(t string, needle string, lo int, hi int) ?int {
	mut k := hi - needle.len
	for k >= lo {
		if t[k..].starts_with(needle) {
			return k
		}
		k--
	}
	return none
}

// compile_parse parses the template code (the file with script and style contents blanked).
fn compile_parse(template string) !CAst {
	trimmed := template[..js_trim_end_len(template)]
	mut p := CParser{
		src: trimmed
		ts:  compiler_ts(template)
		js:  JsScanner{
			src: trimmed
		}
	}
	p.ast.ts = p.ts
	p.ast.fragment = p.ast.new_fragment()
	p.stack << -1
	p.fragments << p.ast.fragment
	for p.index < p.src.len {
		p.fragment()!
	}
	if p.stack.len > 1 {
		cur := p.stack.last()
		n := p.ast.nodes[cur]
		if n.typ == .regular_element {
			return compile_error('element_unclosed', '`<${n.name}>` was left open', n.start)
		}
		return compile_error('block_unclosed', 'Block was left open', n.start)
	}
	// The first SvelteOptions leaves the fragment and becomes root.options.
	root_nodes := p.ast.fragments[p.ast.fragment]
	for k, idx in root_nodes {
		if p.ast.nodes[idx].typ == .svelte_options {
			mut nodes := root_nodes.clone()
			nodes.delete(k)
			p.ast.fragments[p.ast.fragment] = nodes
			p.read_options(idx)!
			p.ast.options = idx
			break
		}
	}
	return p.ast
}

fn (mut p CParser) fragment() ! {
	if p.match_('<') {
		p.element()!
	} else if p.match_('{') {
		p.tag()!
	} else {
		p.text()
	}
}

// ---------------------------------------------------------------------------------------------
// Parser helpers (index.js).

@[inline]
fn (p &CParser) match_(s string) bool {
	if s.len == 1 {
		return p.index < p.src.len && p.src[p.index] == s[0]
	}
	return p.src.len - p.index >= s.len && p.src[p.index..p.index + s.len] == s
}

fn (mut p CParser) eat(s string) bool {
	if p.match_(s) {
		p.index += s.len
		return true
	}
	return false
}

fn (mut p CParser) eat_required(s string) ! {
	if !p.eat(s) {
		return compile_error('expected_token', 'Expected token ${s}', p.index)
	}
}

// is_svelte_whitespace is the compiler's is_whitespace (by UTF-16 code: also 160, 5760, 8192
// to 8202, 8232, 8233, 8239, 8287, 12288, 65279).
fn is_svelte_whitespace(src string, i int) (bool, int) {
	if i >= src.len {
		return false, 0
	}
	c := src[i]
	if c < 0x80 {
		return c == ` ` || (c >= 9 && c <= 13), 1
	}
	cp, n := code_point_at(src, i)
	return is_js_space(cp), n
}

fn (mut p CParser) allow_whitespace() {
	for p.index < p.src.len {
		ok, n := is_svelte_whitespace(p.src, p.index)
		if !ok {
			break
		}
		p.index += n
	}
}

fn (mut p CParser) require_whitespace() ! {
	ok, _ := is_svelte_whitespace(p.src, p.index)
	if !ok {
		return compile_error('expected_whitespace', 'Expected whitespace', p.index)
	}
	p.allow_whitespace()
}

// read_until reads up to the first match of a set of stop strings (each a literal), as
// read_until with a simple regex; unexpected_eof at the end.
fn (mut p CParser) read_until_any(stops []string) !string {
	if p.index >= p.src.len {
		return compile_error('unexpected_eof', 'Unexpected end of input', p.src.len)
	}
	start := p.index
	mut i := start
	for i < p.src.len {
		for s in stops {
			if p.src.len - i >= s.len && p.src[i..i + s.len] == s {
				p.index = i
				return p.src[start..i]
			}
		}
		i++
	}
	p.index = p.src.len
	return p.src[start..]
}

// read_until_ws_slash_gt is read_until(/(\s|\/|>)/).
fn (mut p CParser) read_until_ws_slash_gt() !string {
	if p.index >= p.src.len {
		return compile_error('unexpected_eof', 'Unexpected end of input', p.src.len)
	}
	start := p.index
	mut i := start
	for i < p.src.len {
		c := p.src[i]
		if c == `/` || c == `>` {
			break
		}
		ok, n := is_js_ws(p.src, i)
		if ok {
			break
		}
		i += n
	}
	p.index = i
	return p.src[start..i]
}

// is_js_ws is the regex `\s` at i, and the length of the character.
fn is_js_ws(src string, i int) (bool, int) {
	c := src[i]
	if c < 0x80 {
		return c == ` ` || (c >= 9 && c <= 13), 1
	}
	cp, n := code_point_at(src, i)
	return is_js_space(cp), n
}

// read_until_token_end is read_until(/[\s=/>"']/).
fn (mut p CParser) read_until_token_end() !string {
	if p.index >= p.src.len {
		return compile_error('unexpected_eof', 'Unexpected end of input', p.src.len)
	}
	start := p.index
	mut i := start
	for i < p.src.len {
		c := p.src[i]
		if c == `=` || c == `/` || c == `>` || c == `"` || c == `'` {
			break
		}
		ok, n := is_js_ws(p.src, i)
		if ok {
			break
		}
		i += n
	}
	p.index = i
	return p.src[start..i]
}

// read_identifier is Parser.read_identifier: acorn's identifier characters (astral too).
fn (mut p CParser) read_identifier() !(string, int, int) {
	start := p.index
	mut end := start
	cp, n := code_point_at(p.src, p.index)
	if n > 0 && is_id_start(cp) {
		end += n
		for end < p.src.len {
			c2, n2 := code_point_at(p.src, end)
			if !is_id_part(c2) {
				break
			}
			end += n2
		}
		name := p.src[start..end]
		p.index = end
		if name in reserved_words {
			return compile_error('unexpected_reserved_word', "'${name}' is a reserved word in JavaScript and cannot be used here",
				start)
		}
		return name, start, end
	}
	return '', start, end
}

// is_id_start / is_id_part approximate acorn's isIdentifierStart/isIdentifierChar: ASCII
// exactly, other code points as letters unless whitespace or punctuation (the corpus has none
// of the differences).
fn is_id_start(cp u32) bool {
	if cp < 0x80 {
		c := u8(cp)
		return c.is_letter() || c == `$` || c == `_`
	}
	return !is_js_space(cp) && !is_unicode_punct(cp)
}

fn is_id_part(cp u32) bool {
	if cp < 0x80 {
		c := u8(cp)
		return c.is_letter() || c.is_digit() || c == `$` || c == `_`
	}
	return cp == 0x200c || cp == 0x200d || (!is_js_space(cp) && !is_unicode_punct(cp))
}

fn is_unicode_punct(cp u32) bool {
	return (cp >= 0x2010 && cp <= 0x2027) || (cp >= 0x2030 && cp <= 0x205e)
		|| (cp >= 0x3000 && cp <= 0x3003) || cp == 0xa7 || cp == 0xab || cp == 0xbb
		|| cp == 0xbf || cp == 0xd7 || cp == 0xf7
}

fn (p &CParser) current() int {
	return p.stack.last()
}

fn (p &CParser) current_type() CType {
	c := p.stack.last()
	return if c < 0 { CType.root } else { p.ast.nodes[c].typ }
}

fn (mut p CParser) pop() {
	p.fragments.pop()
	p.stack.pop()
}

fn (mut p CParser) append(n CNode) int {
	idx := p.ast.add(n)
	f := p.fragments.last()
	p.ast.fragments[f] << idx
	return idx
}

// ---------------------------------------------------------------------------------------------
// Text (state/text.js) and character references (utils/html.js).

fn (mut p CParser) text() {
	start := p.index
	for p.index < p.src.len && p.src[p.index] != `<` && p.src[p.index] != `{` {
		p.index++
	}
	raw := p.src[start..p.index]
	p.append(CNode{
		typ:   .text
		start: start
		end:   p.index
		raw:   raw
		data:  decode_character_references(raw, false)
	})
}

const windows_1252 = [8364, 129, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338,
	141, 381, 143, 144, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 157,
	382, 376]

// entity_index lists, for each first byte, the indexes of the entity names that start with it,
// in order.
const entity_index = build_entity_index()

fn build_entity_index() [][]int {
	mut idx := [][]int{len: 128}
	for k, name in entity_names {
		idx[name[0]] << k
	}
	return idx
}

// decode_character_references is the compiler's decode_character_references: the first
// alternative of the entity regex that matches at each `&` (numeric, then the names in order;
// in attribute values a name without `;` must be followed by a non-word character other than
// `=`).
fn decode_character_references(html string, is_attr bool) string {
	if !html.contains('&') {
		return html
	}
	mut out := []u8{cap: html.len}
	mut i := 0
	for i < html.len {
		c := html[i]
		if c != `&` {
			out << c
			i++
			continue
		}
		mut matched := false
		mut code := i64(0)
		mut mend := 0
		j := i + 1
		if j < html.len && html[j] == `#` {
			mut k := j + 1
			if k < html.len && html[k] == `x` && k + 1 < html.len && is_hex(html[k + 1]) {
				k++
				ds := k
				for k < html.len && is_hex(html[k]) {
					k++
				}
				code = parse_int_saturated(html[ds..k], 16)
				matched = true
			} else if k < html.len && html[k].is_digit() {
				ds := k
				for k < html.len && html[k].is_digit() {
					k++
				}
				code = parse_int_saturated(html[ds..k], 10)
				matched = true
			}
			if matched {
				if k < html.len && html[k] == `;` {
					k++
				}
				mend = k
			}
		}
		if !matched && j < html.len && html[j] < 0x80 {
			for e in entity_index[html[j]] {
				name := entity_names[e]
				if html.len - j < name.len || html[j..j + name.len] != name {
					continue
				}
				if is_attr && !name.ends_with(';') {
					after := j + name.len
					if after < html.len && (is_word_char(html[after]) || html[after] == `=`) {
						continue
					}
				}
				matched = true
				code = entity_codes[e]
				mend = j + name.len
				break
			}
		}
		if !matched || code == 0 {
			out << c
			i++
			if matched {
				// The whole match is kept as it is.
				for i < mend {
					out << html[i]
					i++
				}
			}
			continue
		}
		cp := validate_code(code)
		out << utf8_of(cp).bytes()
		i = mend
	}
	return out.bytestr()
}

fn is_hex(c u8) bool {
	return c.is_digit() || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

fn is_word_char(c u8) bool {
	return c.is_letter() || c.is_digit() || c == `_`
}

fn parse_int_saturated(digits string, base int) i64 {
	mut v := i64(0)
	for d in digits {
		dv := if d.is_digit() {
			int(d - `0`)
		} else if d >= `a` {
			int(d - `a`) + 10
		} else {
			int(d - `A`) + 10
		}
		v = v * base + dv
		if v > 0x7fffffff {
			return 0x7fffffff
		}
	}
	return v
}

fn validate_code(code i64) u32 {
	if code == 10 {
		return 32
	}
	if code < 128 {
		return u32(code)
	}
	if code <= 159 {
		return u32(windows_1252[code - 128])
	}
	if code < 55296 {
		return u32(code)
	}
	if code <= 57343 {
		return 0
	}
	if code <= 65535 {
		return u32(code)
	}
	if code >= 65536 && code <= 131071 {
		return u32(code)
	}
	if code >= 131072 && code <= 196607 {
		return u32(code)
	}
	if (code >= 917504 && code <= 917631) || (code >= 917760 && code <= 917999) {
		return u32(code)
	}
	return 0
}

fn utf8_of(cp u32) string {
	if cp == 0 {
		return '\0'
	}
	return rune(cp).str()
}

// ---------------------------------------------------------------------------------------------
// Expressions (read/expression.js, acorn.js).

// read_expression reads an expression at the parser's index: its extent up to a closing
// bracket at depth 0 (or a stop word), without the wrapping parentheses, with the comments
// the compiler attaches to it. `kind_needed` makes it classify the expression.
fn (mut p CParser) read_expression(stop_words []string) !int {
	start := p.index
	sc := p.js.scan_expression(start, stop_words, [])
	return p.expr_from_scan(sc)
}

fn (mut p CParser) expr_from_scan(sc ExprScan) !int {
	if sc.invalid {
		at := sc.invalid_at
		msg := if sc.stop_tok.kind == .invalid && at < p.src.len && p.src[at] in [`"`, `'`] {
			'Unterminated string constant'
		} else if sc.stop_tok.kind == .invalid && at < p.src.len && p.src[at] == `\`` {
			'Unterminated template'
		} else if sc.stop_tok.kind == .invalid && at < p.src.len && p.src[at] == `/` {
			'Unterminated regular expression'
		} else {
			'Unexpected token'
		}
		return compile_error('js_parse_error', msg, at)
	}
	if sc.tokens.len == 0 {
		at := if sc.stop_tok.kind == .eof { p.src.len } else { sc.stop }
		return compile_error('js_parse_error', 'Unexpected token', at)
	}
	idx := p.expr_of_tokens(sc.tokens, sc.comments)
	// The index after the expression, or after its last comment.
	mut index := p.ast.exprs[idx].outer_end(sc)
	if sc.comments.len > 0 && sc.comments.last().end > index {
		index = sc.comments.last().end
	}
	for c in sc.comments {
		p.ast.comments << c
	}
	p.index = index
	return idx
}

// outer_end is the end of the last token of the scanned expression (with its parentheses).
fn (e &CExpr) outer_end(sc ExprScan) int {
	return sc.tokens.last().end
}

// expr_of_tokens builds the CExpr of a token list: parentheses that wrap all of it are
// removed (remove_parens), the kind is classified, and the comments attached as
// get_comment_handlers' add_comments does for the root.
fn (mut p CParser) expr_of_tokens(tokens []Tok, comments []CComment) int {
	src := p.src
	mut lo := 0
	mut hi := tokens.len - 1
	mut layers := []int{} // start offsets of the wrapping parenthesized expressions
	for hi > lo && tok_is(src, tokens[lo], '(') && tok_is(src, tokens[hi], ')')
		&& matching_close(src, tokens, lo) == hi {
		layers << tokens[lo].start
		lo++
		hi--
	}
	inner := tokens[lo..hi + 1]
	mut e := CExpr{
		start: inner[0].start
		end:   inner.last().end
	}
	e.kind, e.name = classify_tokens(src, inner)
	if e.kind == .sequence {
		e.elems = p.sequence_elems(inner)
	}
	// Comments: the outermost node gets those before it; each parenthesized layer those before
	// its own start; the inner node those after the innermost `(`.
	base := p.ast.comments.len
	outer_start := tokens[0].start
	mut leading_from := if layers.len > 0 { layers.last() } else { -1 }
	for k, c in comments {
		if c.start < e.start && (layers.len == 0 || c.start > leading_from) {
			e.leading << base + k
		}
	}
	_ = outer_start
	// Trailing: with no parentheses, every comment after the end; else only the first comment
	// after the end if only `,`, `)`, spaces and tabs come between.
	if layers.len == 0 {
		for k, c in comments {
			if c.start >= e.end {
				e.trailing << base + k
			}
		}
	} else {
		for k, c in comments {
			if c.start >= e.end {
				between := src[e.end..c.start]
				mut ok := true
				for ch in between {
					if ch !in [`,`, `)`, ` `, `\t`] {
						ok = false
						break
					}
				}
				if ok {
					e.trailing << base + k
				}
				break
			}
		}
	}
	return p.ast.add_expr(e)
}

// sequence_elems splits a sequence at its depth-0 commas into CExprs.
fn (mut p CParser) sequence_elems(tokens []Tok) []int {
	src := p.src
	mut out := []int{}
	mut depth := 0
	mut from := 0
	for k, t in tokens {
		if t.kind == .punct && t.end - t.start == 1 {
			ch := src[t.start]
			if ch in [`(`, `[`, `{`] {
				depth++
			} else if ch in [`)`, `]`, `}`] {
				depth--
			} else if ch == `,` && depth == 0 {
				if k > from {
					out << p.expr_of_tokens(tokens[from..k], [])
				}
				from = k + 1
			}
		}
	}
	if from < tokens.len {
		out << p.expr_of_tokens(tokens[from..], [])
	}
	return out
}

// classify_tokens tells the kind of an expression from its tokens (no wrapping parentheses).
fn classify_tokens(src string, tokens []Tok) (ExprKind, string) {
	if tokens.len == 1 && tokens[0].kind == .ident {
		word := src[tokens[0].start..tokens[0].end]
		if word !in ['this', 'null', 'true', 'false', 'super', 'new', 'typeof', 'void', 'delete'] {
			return .identifier, word
		}
		return .other, ''
	}
	// Operators at depth 0 decide: a comma makes a sequence, an assignment or an arrow…
	mut depth := 0
	mut has_comma := false
	mut has_assign := false
	mut has_arrow := false
	mut has_binary := false
	mut has_as := false
	for k, t in tokens {
		if t.kind == .punct {
			text := src[t.start..t.end]
			if text in ['(', '[', '{'] {
				depth++
				continue
			}
			if text in [')', ']', '}'] {
				depth--
				continue
			}
			if depth != 0 {
				continue
			}
			match text {
				',' {
					has_comma = true
				}
				'=>' {
					has_arrow = true
				}
				'=', '+=', '-=', '*=', '/=', '%=', '**=', '<<=', '>>=', '>>>=', '&=', '|=', '^=',
				'&&=', '||=', '??=' {
					has_assign = true
				}
				'.', '?.', '!' {}
				else {
					if k > 0 {
						has_binary = true
					}
				}
			}
		} else if t.kind == .ident && depth == 0 && k > 0 {
			word := src[t.start..t.end]
			if word in ['as', 'satisfies'] && ends_expression(src, tokens[k - 1]) {
				has_as = true
			}
			if word in ['in', 'instanceof'] {
				has_binary = true
			}
		}
	}
	if has_comma {
		return .sequence, ''
	}
	if has_arrow {
		return .arrow, ''
	}
	if has_assign {
		return .assignment, ''
	}
	if has_as {
		return .ts_as, ''
	}
	if has_binary {
		return .other, ''
	}
	first := src[tokens[0].start..tokens[0].end]
	if first in ['new', 'typeof', 'void', 'delete', 'await', 'yield', '!', '-', '+', '~', '++',
		'--', '<', 'function', 'class', 'async'] {
		return .other, ''
	}
	last := tokens.last()
	if tok_is(src, last, ')') {
		// A call when the `(` of the last group follows an expression (a callee).
		mut d := 0
		mut k := tokens.len - 1
		for k >= 0 {
			t := tokens[k]
			if t.kind == .punct {
				text := src[t.start..t.end]
				if text in [')', ']', '}'] {
					d++
				} else if text in ['(', '[', '{'] {
					d--
					if d == 0 {
						break
					}
				}
			}
			k--
		}
		if k > 0 {
			before := tokens[k - 1]
			// `?.(` or a callee that ends an expression (an identifier, `)`, `]`, `>` of type
			// arguments).
			if tok_is(src, before, '?.') {
				return .chain_call, ''
			}
			if ends_expression(src, before) || tok_is(src, before, '>') || tok_is(src, before, '!') {
				for kk in 0 .. k {
					if tok_is(src, tokens[kk], '?.') {
						return .chain_call, ''
					}
				}
				return .call, ''
			}
		}
		return .other, ''
	}
	if tokens.len >= 3 && tokens.last().kind in [.ident, .private_name]
		&& (tok_is(src, tokens[tokens.len - 2], '.') || tok_is(src, tokens[tokens.len - 2], '?.')) {
		return .member, ''
	}
	if tok_is(src, last, ']') && tokens.len > 1 && tokens[0].kind != .punct {
		return .member, ''
	}
	return .other, ''
}

// read_pattern is read/context.js: an identifier (with an optional type annotation) or a
// `{…}`/`[…]` pattern.
fn (mut p CParser) read_pattern() !int {
	start := p.index
	name, s, e := p.read_identifier()!
	if name != '' {
		mut ex := CExpr{
			kind:  .identifier
			start: s
			end:   e
			name:  name
		}
		p.read_type_annotation(mut ex)!
		return p.ast.add_expr(ex)
	}
	if start >= p.src.len || (p.src[start] != `{` && p.src[start] != `[`) {
		return compile_error('expected_pattern', 'Expected identifier or destructure pattern',
			start)
	}
	end := p.match_bracket(start)!
	p.index = end
	mut ex := CExpr{
		kind:  if p.src[start] == `{` { ExprKind.object_pattern } else { ExprKind.array_pattern }
		start: start
		end:   end
	}
	p.read_type_annotation(mut ex)!
	if ex.ann_start >= 0 {
		ex.end = ex.ann_end
	}
	return p.ast.add_expr(ex)
}

// read_type_annotation reads `: Type` after a pattern (up to the first depth-0 `,`, `)`, `}`
// or `=` that is not `=>`). The compiler parses `_ as Type` and keeps where it ended.
fn (mut p CParser) read_type_annotation(mut ex CExpr) ! {
	start := p.index
	p.allow_whitespace()
	if !p.eat(':') {
		p.index = start
		return
	}
	sc := p.js.scan_expression(p.index, [], [])
	// The type ends at a depth-0 `,` or `=` (an assignment of the `_ as` expression).
	mut end_tok := sc.tokens.len
	for k, t in sc.tokens {
		if tok_is(p.src, t, ',') || tok_is(p.src, t, '=') {
			// A depth-0 `,` or `=`: scan_expression only reports depth via commas; recompute.
			if depth_at(p.src, sc.tokens, k) == 0 {
				end_tok = k
				break
			}
		}
	}
	if end_tok == 0 {
		return compile_error('js_parse_error', 'Unexpected token', p.index)
	}
	p.index = sc.tokens[end_tok - 1].end
	ex.ann_start = start
	ex.ann_end = p.index
}

fn depth_at(src string, tokens []Tok, k int) int {
	mut d := 0
	for i in 0 .. k {
		t := tokens[i]
		if t.kind == .punct && t.end - t.start == 1 {
			ch := src[t.start]
			if ch in [`(`, `[`, `{`] {
				d++
			} else if ch in [`)`, `]`, `}`] {
				d--
			}
		}
	}
	return d
}

// match_bracket is utils/bracket.js match_bracket: the index after the bracket closing the one
// at `start` (strings skipped; template substitutions matched).
fn (mut p CParser) match_bracket(start int) !int {
	mut stack := []u8{}
	mut i := start
	for i < p.src.len {
		c := p.src[i]
		i++
		if c == `'` || c == `"` || c == `\`` {
			i = p.match_quote(i, c)!
			continue
		}
		if c == `{` || c == `(` || c == `[` {
			stack << c
		} else if c == `}` || c == `)` || c == `]` {
			popped := if stack.len > 0 { stack.pop() } else { u8(0) }
			expected := match popped {
				`{` { u8(`}`) }
				`(` { u8(`)`) }
				`[` { u8(`]`) }
				else { u8(0) }
			}
			if c != expected {
				return compile_error('expected_token', 'Expected token ${if expected == 0 {
					'undefined'
				} else {
					expected.ascii_str()
				}}', i - 1)
			}
			if stack.len == 0 {
				return i
			}
		}
	}
	return compile_error('unexpected_eof', 'Unexpected end of input', p.src.len)
}

fn (mut p CParser) match_quote(start int, quote u8) !int {
	mut escaped := false
	mut i := start
	for i < p.src.len {
		c := p.src[i]
		i++
		if escaped {
			escaped = false
			continue
		}
		if c == quote {
			return i
		}
		if c == `\\` {
			escaped = true
		}
		if quote == `\`` && c == `$` && i < p.src.len && p.src[i] == `{` {
			i = p.match_bracket(i)!
		}
	}
	return compile_error('unterminated_string_constant', 'Unterminated string constant',
		start)
}

// ---------------------------------------------------------------------------------------------
// Elements (state/element.js).

const root_only_meta_tags = ['svelte:head', 'svelte:options', 'svelte:window', 'svelte:document',
	'svelte:body']

const meta_tag_names = ['svelte:head', 'svelte:options', 'svelte:window', 'svelte:document',
	'svelte:body', 'svelte:element', 'svelte:component', 'svelte:self', 'svelte:fragment',
	'svelte:boundary']

const meta_tag_types = [CType.svelte_head, .svelte_options, .svelte_window, .svelte_document,
	.svelte_body, .svelte_element, .svelte_component, .svelte_self, .svelte_fragment, .svelte_boundary]

const void_element_names = ['area', 'base', 'br', 'col', 'command', 'embed', 'hr', 'img', 'input',
	'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr']

fn is_void(name string) bool {
	return name in void_element_names || name.to_lower() == '!doctype'
}

// closing_tag_omitted is html-tree-validation.js closing_tag_omitted.
fn closing_tag_omitted(current string, next string) bool {
	direct := match current {
		'li' { ['li'] }
		'thead', 'tbody' { ['tbody', 'tfoot'] }
		'tfoot' { ['tbody'] }
		'tr' { ['tr', 'tbody'] }
		'td', 'th' { ['td', 'th', 'tr'] }
		else { []string{} }
	}
	if direct.len > 0 {
		return next in direct
	}
	descendant := match current {
		'dt', 'dd' {
			['dt', 'dd']
		}
		'p' {
			['address', 'article', 'aside', 'blockquote', 'div', 'dl', 'fieldset', 'footer', 'form',
				'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'main', 'menu', 'nav',
				'ol', 'p', 'pre', 'section', 'table', 'ul']
		}
		'rt', 'rp' {
			['rt', 'rp']
		}
		'optgroup' {
			['optgroup']
		}
		'option' {
			['option', 'optgroup']
		}
		else {
			return false
		}
	}
	return next in descendant
}

// is_valid_element_name: `^![a-zA-Z]+$`, `^[a-zA-Z][a-zA-Z0-9]*:[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$`
// or REGEX_VALID_TAG_NAME.
fn is_valid_element_name(name string) bool {
	if name.len > 1 && name[0] == `!` {
		mut ok := true
		for c in name[1..] {
			if !c.is_letter() {
				ok = false
				break
			}
		}
		if ok {
			return true
		}
	}
	if colon := name.index(':') {
		pre := name[..colon]
		post := name[colon + 1..]
		if pre.len > 0 && pre[0].is_letter() && pre.bytes().all(it.is_alnum()) && post.len >= 2
			&& post[0].is_letter() && post[post.len - 1].is_alnum()
			&& post.bytes().all(it.is_alnum() || it == `-`) {
			return true
		}
	}
	// REGEX_VALID_TAG_NAME: [a-zA-Z][a-zA-Z0-9]* then optionally `-` and name characters.
	if name.len == 0 || !name[0].is_letter() {
		return false
	}
	mut i := 1
	for i < name.len && name[i].is_alnum() {
		i++
	}
	if i == name.len {
		return true
	}
	if name[i] != `-` {
		return false
	}
	i++
	for i < name.len {
		cp, n := code_point_at(name, i)
		ok := (cp < 0x80 && (u8(cp).is_alnum() || u8(cp) in [`.`, `-`, `_`])) || cp == 0xb7
			|| (cp >= 0xc0 && cp <= 0xd6) || (cp >= 0xd8 && cp <= 0xf6)
			|| (cp >= 0xf8 && cp <= 0x37d) || (cp >= 0x37f && cp <= 0x1fff)
			|| (cp >= 0x200c && cp <= 0x200d) || (cp >= 0x203f && cp <= 0x2040)
			|| (cp >= 0x2070 && cp <= 0x218f) || (cp >= 0x2c00 && cp <= 0x2fef)
			|| (cp >= 0x3001 && cp <= 0xd7ff) || (cp >= 0xf900 && cp <= 0xfdcf)
			|| (cp >= 0xfdf0 && cp <= 0xfffd) || (cp >= 0x10000 && cp <= 0xeffff)
		if !ok {
			return false
		}
		i += n
	}
	return true
}

// is_valid_component_name is regex_valid_component_name: an upper-case letter then identifier
// characters and dots, or identifier segments joined by dots (at least two).
fn is_valid_component_name(name string) bool {
	if name.len == 0 {
		return false
	}
	cp, n := code_point_at(name, 0)
	if is_upper_letter(cp) {
		mut i := n
		for i < name.len {
			c, l := code_point_at(name, i)
			if !(c == `.` || c == `$` || is_id_part(c)) {
				return false
			}
			i += l
		}
		return true
	}
	if !is_id_start(cp) || cp == `$` {
		return false
	}
	parts := name.split('.')
	if parts.len < 2 {
		return false
	}
	for k, part in parts {
		if part == '' {
			return false
		}
		mut i := 0
		for i < part.len {
			c, l := code_point_at(part, i)
			if !(c == `$` || is_id_part(c)) {
				return false
			}
			if k == 0 && i == 0 && !is_id_start(c) {
				return false
			}
			i += l
		}
	}
	return true
}

fn is_upper_letter(cp u32) bool {
	if cp < 0x80 {
		return cp >= `A` && cp <= `Z`
	}
	r := rune(cp)
	s := r.str()
	return s.to_lower() != s && s.to_upper() == s
}

fn (p &CParser) parent_is_head() bool {
	mut i := p.stack.len
	for i > 0 {
		i--
		idx := p.stack[i]
		if idx < 0 {
			continue
		}
		t := p.ast.nodes[idx].typ
		if t == .svelte_head {
			return true
		}
		if t == .regular_element || t == .component {
			return false
		}
	}
	return false
}

fn (p &CParser) parent_is_shadowroot_template() bool {
	mut i := p.stack.len
	for i > 0 {
		i--
		idx := p.stack[i]
		if idx < 0 {
			continue
		}
		n := p.ast.nodes[idx]
		if n.typ == .regular_element {
			for a in n.attributes {
				an := p.ast.nodes[a]
				if an.typ == .attribute && an.name == 'shadowrootmode' {
					return true
				}
			}
		}
	}
	return false
}

fn (mut p CParser) element() ! {
	start := p.index
	p.index++
	mut parent := p.current()
	if p.eat('!--') {
		data := p.read_until_any(['-->'])!
		p.eat_required('-->')!
		p.append(CNode{
			typ:   .comment
			start: start
			end:   p.index
			data:  data
		})
		return
	}
	if p.eat('/') {
		name := p.read_until_ws_slash_gt()!
		p.allow_whitespace()
		p.eat_required('>')!
		if is_void(name) {
			return compile_error('void_element_invalid_content', 'Void elements cannot have children or closing tags',
				start)
		}
		for {
			pn := if parent < 0 {
				CNode{
					typ: .root
				}
			} else {
				p.ast.nodes[parent]
			}
			if pn.typ.is_element() && pn.name == name {
				break
			}
			if pn.typ != .regular_element {
				if p.has_auto && p.auto_tag == name {
					return compile_error('element_invalid_closing_tag_autoclosed', '`</${name}>` attempted to close element that was already automatically closed by `<${p.auto_reason}>` (cannot nest `<${p.auto_reason}>` inside `<${name}>`)',
						start)
				}
				return compile_error('element_invalid_closing_tag', '`</${name}>` attempted to close an element that was not open',
					start)
			}
			p.ast.nodes[parent].end = start
			p.pop()
			parent = p.current()
		}
		p.ast.nodes[parent].end = p.index
		p.pop()
		if p.has_auto && p.stack.len < p.auto_depth {
			p.has_auto = false
		}
		return
	}
	name_start := p.index
	name := p.read_until_ws_slash_gt()!
	if name.starts_with('svelte:') && name !in meta_tag_names {
		return compile_error('svelte_meta_invalid_tag', 'Valid `<svelte:...>` tag names are ${js_list(meta_tag_names)}',
			name_start)
	}
	if !is_valid_element_name(name) && !is_valid_component_name(name) {
		return compile_error('tag_invalid_name', 'Expected a valid element or component name. Components must have a valid variable name or dot notation expression',
			name_start)
	}
	parent_type := p.current_type()
	if name in root_only_meta_tags {
		if name in p.meta_tags {
			return compile_error('svelte_meta_duplicate', 'A component can only have one `<${name}>` element',
				start)
		}
		if parent_type != .root {
			return compile_error('svelte_meta_invalid_placement', '`<${name}>` tags cannot be inside elements or blocks',
				start)
		}
		p.meta_tags[name] = true
	}
	mi := meta_tag_names.index(name)
	typ := if mi >= 0 {
		meta_tag_types[mi]
	} else if is_valid_component_name(name) {
		CType.component
	} else if name == 'title' && p.parent_is_head() {
		CType.title_element
	} else if name == 'slot' && !p.parent_is_shadowroot_template() {
		CType.slot_element
	} else {
		CType.regular_element
	}
	mut el := CNode{
		typ:      typ
		start:    start
		end:      -1
		name:     name
		fragment: p.ast.new_fragment()
	}
	p.allow_whitespace()
	if parent >= 0 && p.ast.nodes[parent].typ == .regular_element
		&& closing_tag_omitted(p.ast.nodes[parent].name, name) {
		p.ast.nodes[parent].end = start
		p.pop()
		p.auto_tag = p.ast.nodes[parent].name
		p.auto_reason = name
		p.auto_depth = p.stack.len
		p.has_auto = true
	}
	mut unique_names := []string{}
	current := p.current()
	top_script_or_style := (name == 'script' || name == 'style') && current < 0
	for {
		attr := if top_script_or_style {
			p.read_static_attribute()!
		} else {
			p.read_attribute()!
		}
		if attr < 0 {
			break
		}
		an := p.ast.nodes[attr]
		if an.typ in [.attribute, .bind_directive, .style_directive, .class_directive] {
			t := if an.typ == .bind_directive { CType.attribute } else { an.typ }
			key := '${int(t)}:${an.name}'
			if key in unique_names {
				return compile_error('attribute_duplicate', 'Attributes need to be unique',
					an.start)
			} else if an.name != 'this' {
				unique_names << key
			}
		}
		el.attributes << attr
		p.allow_whitespace()
	}
	if el.typ == .svelte_component {
		mut found := -1
		for k, a in el.attributes {
			if p.ast.nodes[a].typ == .attribute && p.ast.nodes[a].name == 'this' {
				found = k
				break
			}
		}
		if found < 0 {
			return compile_error('svelte_component_missing_this', "`<svelte:component>` must have a 'this' attribute",
				start)
		}
		def := el.attributes[found]
		el.attributes.delete(found)
		dn := p.ast.nodes[def]
		if !p.is_expression_attribute(dn) {
			return compile_error('svelte_component_invalid_this', 'Invalid component definition — must be an `{expression}`',
				dn.start)
		}
		el.expression = p.attribute_expression(dn)
	}
	if el.typ == .svelte_element {
		mut found := -1
		for k, a in el.attributes {
			if p.ast.nodes[a].typ == .attribute && p.ast.nodes[a].name == 'this' {
				found = k
				break
			}
		}
		if found < 0 {
			return compile_error('svelte_element_missing_this', "`<svelte:element>` must have a 'this' attribute with a value",
				start)
		}
		def := el.attributes[found]
		el.attributes.delete(found)
		dn := p.ast.nodes[def]
		if dn.value_kind == .true_ {
			return compile_error('svelte_element_missing_this', "`<svelte:element>` must have a 'this' attribute with a value",
				dn.start)
		}
		if !p.is_expression_attribute(dn) {
			chunk := p.ast.nodes[dn.value[0]]
			if chunk.typ == .text {
				el.expression = p.ast.add_expr(CExpr{
					kind:      .literal
					start:     chunk.start
					end:       chunk.end
					raw:       "'${chunk.raw}'"
					name:      chunk.data
					synthetic: true
				})
			} else {
				el.expression = chunk.expression
			}
		} else {
			el.expression = p.attribute_expression(dn)
		}
	}
	if top_script_or_style {
		p.eat_required('>')!
		if name == 'script' {
			script := p.read_script(start, el.attributes)!
			sn := p.ast.nodes[script]
			if sn.script_module {
				if p.ast.module >= 0 {
					return compile_error('script_duplicate', 'A component can have a single top-level `<script>` element and/or a single top-level `<script module>` element',
						start)
				}
				p.ast.module = script
			} else {
				if p.ast.instance >= 0 {
					return compile_error('script_duplicate', 'A component can have a single top-level `<script>` element and/or a single top-level `<script module>` element',
						start)
				}
				p.ast.instance = script
			}
		} else {
			style := p.read_style(start, el.attributes)!
			if p.ast.css >= 0 {
				return compile_error('style_duplicate', 'A component can have a single top-level `<style>` element',
					start)
			}
			p.ast.css = style
		}
		return
	}
	idx := p.append(el)
	self_closing := p.eat('/') || is_void(name)
	p.eat_required('>')!
	if self_closing {
		p.ast.nodes[idx].end = p.index
	} else if name == 'textarea' {
		nodes := p.read_sequence_textarea()!
		p.ast.fragments[p.ast.nodes[idx].fragment] = nodes
		p.read_closing_textarea()
		p.ast.nodes[idx].end = p.index
	} else if name == 'script' || name == 'style' {
		cstart := p.index
		close_tag := '</${name}>'
		close_index := p.src.index_after(close_tag, p.index) or { -1 }
		cend := if close_index == -1 { p.src.len } else { close_index }
		data := p.src[cstart..cend]
		p.index = cend
		text := p.ast.add(CNode{
			typ:   .text
			start: cstart
			end:   cend
			data:  data
			raw:   data
		})
		p.ast.fragments[p.ast.nodes[idx].fragment] << text
		p.eat_required(close_tag)!
		p.ast.nodes[idx].end = p.index
	} else {
		p.stack << idx
		p.fragments << p.ast.nodes[idx].fragment
	}
}

fn js_list(items []string) string {
	if items.len == 1 {
		return items[0]
	}
	if items.len == 2 {
		return '${items[0]} or ${items[1]}'
	}
	return '${items[..items.len - 1].join(', ')} or ${items.last()}'
}

// is_expression_attribute: an Attribute whose value is one ExpressionTag (alone, or the only
// item of an array).
fn (p &CParser) is_expression_attribute(n CNode) bool {
	if n.typ != .attribute {
		return false
	}
	if n.value_kind == .node {
		return true
	}
	return n.value_kind == .array && n.value.len == 1
		&& p.ast.nodes[n.value[0]].typ == .expression_tag
}

fn (p &CParser) attribute_expression(n CNode) int {
	return p.ast.nodes[n.value[0]].expression
}

// read_closing_textarea reads /<\/textarea(\s[^>]*)?>/iy.
fn (mut p CParser) closing_textarea_at(i int) int {
	if p.src.len - i < 11 || p.src[i..i + 11].to_lower() != '</textarea' {
		return -1
	}
	mut k := i + 10
	if k < p.src.len && p.src[k] == `>` {
		return k + 1
	}
	ok, _ := is_js_ws(p.src, k)
	if k < p.src.len && ok {
		gt := p.src.index_after('>', k) or { return -1 }
		return gt + 1
	}
	return -1
}

fn (mut p CParser) read_closing_textarea() {
	e := p.closing_textarea_at(p.index)
	if e >= 0 {
		p.index = e
	}
}

fn (mut p CParser) read_sequence_textarea() ![]int {
	return p.read_sequence(fn (mut p CParser) bool {
		return p.closing_textarea_at(p.index) >= 0
	}, 'inside <textarea>')
}

fn (mut p CParser) read_static_attribute() !int {
	start := p.index
	name := p.read_until_token_end()!
	if name == '' {
		return -1
	}
	mut kind := AttrValue.true_
	mut value := []int{}
	if p.eat('=') {
		p.allow_whitespace()
		// /(?:"([^"]*)"|'([^'])*'|([^>\s]+))/y
		mut raw := ''
		if p.index < p.src.len && p.src[p.index] == `"` {
			e := p.src.index_after('"', p.index + 1) or { -1 }
			if e >= 0 {
				raw = p.src[p.index..e + 1]
			}
		} else if p.index < p.src.len && p.src[p.index] == `'` {
			e := p.src.index_after("'", p.index + 1) or { -1 }
			if e >= 0 {
				raw = p.src[p.index..e + 1]
			}
		}
		if raw == '' {
			mut e := p.index
			for e < p.src.len && p.src[e] != `>` {
				ok, n := is_js_ws(p.src, e)
				if ok {
					break
				}
				e += n
			}
			raw = p.src[p.index..e]
		}
		if raw == '' {
			return compile_error('expected_attribute_value', 'Expected attribute value',
				p.index)
		}
		p.index += raw.len
		quoted := raw[0] == `"` || raw[0] == `'`
		inner := if quoted { raw[1..raw.len - 1] } else { raw }
		t := p.ast.add(CNode{
			typ:   .text
			start: p.index - inner.len - if quoted { 1 } else { 0 }
			end:   if quoted { p.index - 1 } else { p.index }
			raw:   inner
			data:  decode_character_references(inner, true)
		})
		kind = .array
		value = [t]
	}
	if p.index < p.src.len && (p.src[p.index] == `"` || p.src[p.index] == `'`) {
		return compile_error('expected_token', 'Expected token =', p.index)
	}
	return p.ast.add(CNode{
		typ:        .attribute
		start:      start
		end:        p.index
		name:       name
		value_kind: kind
		value:      value
	})
}

fn (mut p CParser) read_comment() ?CComment {
	start := p.index
	if p.eat('//') {
		if p.index >= p.src.len {
			// read_until at the end throws unexpected_eof; reported by the caller.
			return none
		}
		e := p.src.index_after('\n', p.index) or { p.src.len }
		value := p.src[p.index..e]
		p.index = e
		return CComment{
			block: false
			start: start
			end:   e
			value: value
		}
	}
	if p.eat('/*') {
		e := p.src.index_after('*/', p.index) or { p.src.len }
		value := p.src[p.index..e]
		p.index = e
		p.eat('*/')
		return CComment{
			block: true
			start: start
			end:   p.index
			value: value
		}
	}
	return none
}

fn get_directive_type(name string) ?CType {
	return match name {
		'use' { CType.use_directive }
		'animate' { CType.animate_directive }
		'bind' { CType.bind_directive }
		'class' { CType.class_directive }
		'style' { CType.style_directive }
		'on' { CType.on_directive }
		'let' { CType.let_directive }
		'in', 'out', 'transition' { CType.transition_directive }
		else { none }
	}
}

fn (mut p CParser) read_attribute() !int {
	for {
		c := p.read_comment() or { break }
		p.ast.comments << c
		p.allow_whitespace()
	}
	start := p.index
	if p.eat('{') {
		p.allow_whitespace()
		if p.eat('@attach') {
			p.require_whitespace()!
			ex := p.read_expression([])!
			p.allow_whitespace()
			p.eat_required('}')!
			return p.ast.add(CNode{
				typ:        .attach_tag
				start:      start
				end:        p.index
				expression: ex
			})
		}
		if p.eat('...') {
			ex := p.read_expression([])!
			p.allow_whitespace()
			p.eat_required('}')!
			return p.ast.add(CNode{
				typ:        .spread_attribute
				start:      start
				end:        p.index
				expression: ex
			})
		}
		name, s, e := p.read_identifier()!
		if name == '' {
			return compile_error('attribute_empty_shorthand', 'Attribute shorthand cannot be empty',
				start)
		}
		p.allow_whitespace()
		p.eat_required('}')!
		ex := p.ast.add_expr(CExpr{
			kind:  .identifier
			start: s
			end:   e
			name:  name
		})
		tag := p.ast.add(CNode{
			typ:        .expression_tag
			start:      s
			end:        e
			expression: ex
		})
		return p.ast.add(CNode{
			typ:        .attribute
			start:      start
			end:        p.index
			name:       name
			value_kind: .node
			value:      [tag]
		})
	}
	name := p.read_until_token_end()!
	if name == '' {
		return -1
	}
	mut end := p.index
	p.allow_whitespace()
	colon := name.index(':') or { -1 }
	dtype := if colon >= 0 { get_directive_type(name[..colon]) } else { none }
	mut kind := AttrValue.true_
	mut value := []int{}
	if p.eat('=') {
		p.allow_whitespace()
		if p.match_('/>') {
			cs := p.index
			p.index++
			value = [
				p.ast.add(CNode{
					typ:   .text
					start: cs
					end:   cs + 1
					raw:   '/'
					data:  '/'
				}),
			]
			kind = .array
			end = p.index
		} else {
			kind, value = p.read_attribute_value()!
			end = p.index
		}
	} else if p.index < p.src.len && (p.src[p.index] == `"` || p.src[p.index] == `'`) {
		return compile_error('expected_token', 'Expected token =', p.index)
	}
	if t := dtype {
		parts := name[colon + 1..].split('|')
		directive_name := parts[0]
		modifiers := parts[1..].clone()
		if directive_name == '' {
			return compile_error('directive_missing_name', '`${name}` name cannot be empty',
				start)
		}
		if t == .style_directive {
			return p.ast.add(CNode{
				typ:        t
				start:      start
				end:        end
				name:       directive_name
				modifiers:  modifiers
				value_kind: kind
				value:      value
			})
		}
		mut expression := -1
		if kind != .true_ && value.len > 0 {
			first := p.ast.nodes[value[0]]
			contains_text := value.len > 1 || first.typ == .text
			if contains_text {
				return compile_error('directive_invalid_value', 'Directive value must be a JavaScript expression enclosed in curly braces',
					first.start)
			}
			expression = first.expression
		}
		mut d := CNode{
			typ:        t
			start:      start
			end:        end
			name:       directive_name
			modifiers:  modifiers
			expression: expression
		}
		if t == .transition_directive {
			dir := name[..colon]
			d.intro = dir == 'in' || dir == 'transition'
			d.outro = dir == 'out' || dir == 'transition'
		}
		if (t == .bind_directive || t == .class_directive) && expression < 0 {
			d.expression = p.ast.add_expr(CExpr{
				kind:      .identifier
				start:     start + colon + 1
				end:       end
				name:      directive_name
				synthetic: true
			})
		}
		return p.ast.add(d)
	}
	return p.ast.add(CNode{
		typ:        .attribute
		start:      start
		end:        end
		name:       name
		value_kind: kind
		value:      value
	})
}

fn (mut p CParser) read_attribute_value() !(AttrValue, []int) {
	quote := if p.eat("'") {
		u8(`'`)
	} else if p.eat('"') {
		u8(`"`)
	} else {
		u8(0)
	}
	if quote != 0 && p.eat(quote.ascii_str()) {
		t := p.ast.add(CNode{
			typ:   .text
			start: p.index - 1
			end:   p.index - 1
		})
		return AttrValue.array, [t]
	}
	value := if quote != 0 {
		p.read_sequence_quoted(quote)!
	} else {
		p.read_sequence(fn (mut p CParser) bool {
			if p.match_('/>') {
				return true
			}
			if p.index >= p.src.len {
				return false
			}
			c := p.src[p.index]
			ok, _ := is_js_ws(p.src, p.index)
			return ok || c in [`"`, `'`, `=`, `<`, `>`, `\``]
		}, 'in attribute value')!
	}
	if value.len == 0 && quote == 0 {
		return compile_error('expected_attribute_value', 'Expected attribute value', p.index)
	}
	if quote != 0 {
		p.index++
	}
	if quote != 0 || value.len > 1 || p.ast.nodes[value[0]].typ == .text {
		return AttrValue.array, value
	}
	return AttrValue.node, value
}

fn (mut p CParser) read_sequence_quoted(quote u8) ![]int {
	if quote == `"` {
		return p.read_sequence(fn (mut p CParser) bool {
			return p.index < p.src.len && p.src[p.index] == `"`
		}, 'in attribute value')
	}
	return p.read_sequence(fn (mut p CParser) bool {
		return p.index < p.src.len && p.src[p.index] == `'`
	}, 'in attribute value')
}

fn (mut p CParser) read_sequence(done fn (mut p CParser) bool, location string) ![]int {
	mut chunk_start := p.index
	mut chunks := []int{}
	for p.index < p.src.len {
		index := p.index
		if done(mut p) {
			if p.index > chunk_start {
				raw := p.src[chunk_start..p.index]
				chunks << p.ast.add(CNode{
					typ:   .text
					start: chunk_start
					end:   p.index
					raw:   raw
					data:  decode_character_references(raw, true)
				})
			}
			return chunks
		} else if p.eat('{') {
			if p.match_('#') {
				i := p.index - 1
				p.index++
				nm := p.read_lower_name()
				return compile_error('block_invalid_placement', '{#${nm} ...} block cannot be ${location}',
					i)
			} else if p.match_('@') {
				i := p.index - 1
				p.index++
				nm := p.read_lower_name()
				return compile_error('tag_invalid_placement', '{@${nm} ...} tag cannot be ${location}',
					i)
			}
			if p.index - 1 > chunk_start {
				raw := p.src[chunk_start..p.index - 1]
				chunks << p.ast.add(CNode{
					typ:   .text
					start: chunk_start
					end:   p.index - 1
					raw:   raw
					data:  decode_character_references(raw, true)
				})
			}
			p.allow_whitespace()
			ex := p.read_expression([])!
			p.allow_whitespace()
			p.eat_required('}')!
			chunks << p.ast.add(CNode{
				typ:        .expression_tag
				start:      index
				end:        p.index
				expression: ex
			})
			chunk_start = p.index
		} else {
			p.index++
		}
	}
	return compile_error('unexpected_eof', 'Unexpected end of input', p.src.len)
}

// read_lower_name is read_until(/[^a-z]/).
fn (mut p CParser) read_lower_name() string {
	start := p.index
	for p.index < p.src.len && p.src[p.index] >= `a` && p.src[p.index] <= `z` {
		p.index++
	}
	return p.src[start..p.index]
}

// read_script is read/script.js (the content is blank: no JavaScript to parse).
fn (mut p CParser) read_script(start int, attributes []int) !int {
	script_start := p.index
	// read_until(/<\/script\s*>/)
	mut i := p.index
	mut close_start := -1
	mut close_end := -1
	for i < p.src.len {
		if p.src[i] == `<` && p.src[i..].starts_with('</script') {
			mut k := i + 8
			for k < p.src.len {
				ok, n := is_js_ws(p.src, k)
				if !ok {
					break
				}
				k += n
			}
			if k < p.src.len && p.src[k] == `>` {
				close_start = i
				close_end = k + 1
				break
			}
		}
		i++
	}
	if close_start < 0 {
		return compile_error('element_unclosed', '`<script>` was left open', p.src.len)
	}
	p.index = close_end
	mut module := false
	for a in attributes {
		an := p.ast.nodes[a]
		if an.name in ['server', 'client', 'worker', 'test', 'default'] {
			return compile_error('script_reserved_attribute', 'The `${an.name}` attribute is reserved and cannot be used',
				an.start)
		}
		if an.name == 'module' {
			if an.value_kind != .true_ {
				return compile_error('script_invalid_attribute_value', 'If the `${an.name}` attribute is supplied, it must be a boolean attribute',
					an.start)
			}
			module = true
		}
		if an.name == 'context' {
			if an.value_kind == .true_ || an.value.len != 1
				|| p.ast.nodes[an.value[0]].typ != .text {
				return compile_error('script_invalid_context', 'If the context attribute is supplied, its value must be "module"',
					an.start)
			}
			if p.ast.nodes[an.value[0]].data != 'module' {
				return compile_error('script_invalid_context', 'If the context attribute is supplied, its value must be "module"',
					an.start)
			}
			module = true
		}
	}
	return p.ast.add(CNode{
		typ:           .script
		start:         start
		end:           p.index
		attributes:    attributes
		script_module: module
		content_start: script_start
		content_end:   close_start
	})
}

// read_style is read/style.js for a blank content: everything up to `</style`, then `\s*>`.
fn (mut p CParser) read_style(start int, attributes []int) !int {
	content_start := p.index
	// The content is blank (svelte-eslint-parser blanks it); whitespace up to `</style`.
	for p.index < p.src.len && !p.match_('</style') {
		ok, n := is_js_ws(p.src, p.index)
		if !ok {
			// Not blank (a <style> the splitter did not take): the CSS parser would read it;
			// what it says is not ported.
			return compile_error('css_expected_identifier', 'Expected a valid CSS identifier',
				p.index)
		}
		p.index += n
	}
	content_end := p.index
	p.eat_required('</style')!
	for p.index < p.src.len {
		ok, n := is_js_ws(p.src, p.index)
		if !ok {
			break
		}
		p.index += n
	}
	if p.index < p.src.len && p.src[p.index] == `>` {
		p.index++
	}
	return p.ast.add(CNode{
		typ:           .style_sheet
		start:         start
		end:           p.index
		attributes:    attributes
		content_start: content_start
		content_end:   content_end
	})
}

// read_options is read/options.js (the checks that can fail on the attributes).
fn (mut p CParser) read_options(idx int) ! {
	n := p.ast.nodes[idx]
	for a in n.attributes {
		an := p.ast.nodes[a]
		if an.typ != .attribute {
			return compile_error('svelte_options_invalid_attribute', '`<svelte:options>` can only receive static attributes',
				an.start)
		}
		match an.name {
			'runes', 'immutable', 'preserveWhitespace', 'accessors' {
				v := p.boolean_value(an)!
				if an.name == 'runes' {
					p.ast.nodes[idx].runes = v
					p.ast.nodes[idx].has_runes = true
				}
			}
			'tag' {
				return compile_error('svelte_options_deprecated_tag', '"tag" option is deprecated — use "customElement" instead',
					an.start)
			}
			'customElement' {
				if an.value_kind == .true_ {
					return compile_error('svelte_options_invalid_customelement', '"customElement" must be a string literal defining a valid custom element name or an object of the form { tag?: string; shadow?: "open" | "none" | `ShadowRootInit`; props?: { [key: string]: { attribute?: string; reflect?: boolean; type: .. } } }',
						an.start)
				}
			}
			'namespace' {
				v := p.static_text(an) or { '' }
				if v !in ['http://www.w3.org/2000/svg', 'http://www.w3.org/1998/Math/MathML', 'html',
					'mathml', 'svg'] {
					return compile_error('svelte_options_invalid_attribute_value', 'Value must be "html", "mathml" or "svg", if specified',
						an.start)
				}
			}
			'css' {
				v := p.static_text(an) or { '' }
				if v != 'injected' {
					return compile_error('svelte_options_invalid_attribute_value', 'Value must be "injected", if specified',
						an.start)
				}
			}
			else {
				return compile_error('svelte_options_unknown_attribute', "`<svelte:options>` unknown attribute '${an.name}'",
					an.start)
			}
		}
	}
	nodes := p.ast.fragments[n.fragment]
	if nodes.len > 0 {
		return compile_error('svelte_meta_invalid_content', '<${n.name}> cannot have children',
			p.ast.nodes[nodes[0]].start)
	}
}

// static_text is get_static_value for a text value.
fn (p &CParser) static_text(an CNode) ?string {
	if an.value_kind == .array && an.value.len == 1 && p.ast.nodes[an.value[0]].typ == .text {
		return p.ast.nodes[an.value[0]].data
	}
	if an.value_kind != .true_ && an.value.len == 1 {
		ex := p.ast.exprs[p.ast.nodes[an.value[0]].expression]
		text := p.src[ex.start..ex.end]
		if text.len >= 2 && (text[0] == `'` || text[0] == `"`) && text[text.len - 1] == text[0] {
			return text[1..text.len - 1]
		}
	}
	return none
}

// boolean_value is get_boolean_value: `true`, `{true}` or `{false}`.
fn (p &CParser) boolean_value(an CNode) !bool {
	if an.value_kind == .true_ {
		return true
	}
	if an.value.len == 1 && p.ast.nodes[an.value[0]].typ == .expression_tag {
		ex := p.ast.exprs[p.ast.nodes[an.value[0]].expression]
		text := p.src[ex.start..ex.end]
		if text == 'true' {
			return true
		}
		if text == 'false' {
			return false
		}
	}
	return compile_error('svelte_options_invalid_attribute_value', 'Value must be true or false, if specified',
		an.start)
}

// ---------------------------------------------------------------------------------------------
// Tags and blocks (state/tag.js).

fn (mut p CParser) tag() ! {
	start := p.index
	p.index++
	p.allow_whitespace()
	if p.eat('#') {
		return p.open()
	}
	if p.eat(':') {
		return p.next()
	}
	if p.eat('@') {
		return p.special()
	}
	if p.match_('/') {
		if !p.match_('/*') && !p.match_('//') {
			p.index++
			return p.close()
		}
	}
	if p.read_declaration(start)! {
		return
	}
	ex := p.read_expression([])!
	p.allow_whitespace()
	p.eat_required('}')!
	p.append(CNode{
		typ:        .expression_tag
		start:      start
		end:        p.index
		expression: ex
	})
}

// read_declaration reads `{let …}` / `{const …}` (and rejects var, interface, enum, type X).
fn (mut p CParser) read_declaration(tag_start int) !bool {
	start := p.index
	src := p.src
	rest := src[start..]
	for kw in ['var', 'interface', 'enum'] {
		if rest.starts_with(kw) && !(rest.len > kw.len && is_word_char(rest[kw.len])) {
			return compile_error('declaration_tag_invalid_type', 'Declaration tags must be `let` or `const` declarations',
				start)
		}
	}
	if rest.starts_with('type') && rest.len > 4 {
		mut k := 4
		mut ws := false
		for k < rest.len {
			ok, n := is_js_ws(rest, k)
			if !ok {
				break
			}
			ws = true
			k += n
		}
		if ws && k < rest.len && rest[k] !in [`?`, `.`, `(`, `\``, `<`, `[`, `&`, `|`, `%`, `^`,
			`}`] {
			return compile_error('declaration_tag_invalid_type', 'Declaration tags must be `let` or `const` declarations',
				start)
		}
	}
	mut kind := ''
	for kw in ['let', 'const'] {
		if rest.starts_with(kw) && !(rest.len > kw.len && is_word_char(rest[kw.len])) {
			kind = kw
			break
		}
	}
	if kind == '' {
		return false
	}
	// parse_statement_at: the statement runs to the matching `}` (trailing `;` removed).
	mut end := find_matching_bracket(src, start, `{`)
	if end < 0 {
		return compile_error('unexpected_eof', 'Unexpected end of input', src.len)
	}
	for end > start && src[end - 1] == `;` {
		end--
	}
	// The statement ends with its last token (comments and whitespace excluded).
	mut js := JsScanner{
		src: src[..end]
	}
	sc := js.scan_expression(start, [], [])
	if sc.tokens.len == 0 {
		return compile_error('js_parse_error', 'Unexpected token', start)
	}
	stmt_end := sc.tokens.last().end
	for c in sc.comments {
		p.ast.comments << c
	}
	p.index = stmt_end
	p.allow_whitespace()
	p.eat_required('}')!
	p.append(CNode{
		typ:        .declaration_tag
		start:      tag_start
		end:        p.index
		decl_kind:  kind
		decl_start: start
		decl_end:   stmt_end
	})
	return true
}

fn (mut p CParser) open() ! {
	mut start := p.index - 2
	for p.src[start] != `{` {
		start--
	}
	if p.eat('if') {
		p.require_whitespace()!
		test := p.read_expression([])!
		consequent := p.ast.new_fragment()
		idx := p.append(CNode{
			typ:        .if_block
			start:      start
			end:        -1
			expression: test
			consequent: consequent
		})
		p.allow_whitespace()
		p.eat_required('}')!
		p.stack << idx
		p.fragments << consequent
		return
	}
	if p.eat('each') {
		p.require_whitespace()!
		expression, context, index, has_index, key := p.read_each_head(start)!
		body := p.ast.new_fragment()
		idx := p.append(CNode{
			typ:        .each_block
			start:      start
			end:        -1
			expression: expression
			body:       body
			context:    context
			index:      index
			has_index:  has_index
			key:        key
		})
		p.stack << idx
		p.fragments << body
		return
	}
	if p.eat('await') {
		p.require_whitespace()!
		expression := p.read_expression(['then', 'catch'])!
		p.allow_whitespace()
		mut n := CNode{
			typ:        .await_block
			start:      start
			end:        -1
			expression: expression
		}
		mut frag := 0
		if p.eat('then') {
			if p.match_ws_curly() {
				p.allow_whitespace()
			} else {
				p.require_whitespace()!
				n.await_value = p.read_pattern()!
				p.allow_whitespace()
			}
			n.then = p.ast.new_fragment()
			frag = n.then
		} else if p.eat('catch') {
			if p.match_ws_curly() {
				p.allow_whitespace()
			} else {
				p.require_whitespace()!
				n.await_error = p.read_pattern()!
				p.allow_whitespace()
			}
			n.catch_ = p.ast.new_fragment()
			frag = n.catch_
		} else {
			n.pending = p.ast.new_fragment()
			frag = n.pending
		}
		p.eat_required('}')!
		idx := p.append(n)
		p.fragments << frag
		p.stack << idx
		return
	}
	if p.eat('key') {
		p.require_whitespace()!
		expression := p.read_expression([])!
		p.allow_whitespace()
		p.eat_required('}')!
		frag := p.ast.new_fragment()
		idx := p.append(CNode{
			typ:        .key_block
			start:      start
			end:        -1
			expression: expression
			body:       frag
		})
		p.stack << idx
		p.fragments << frag
		return
	}
	if p.eat('snippet') {
		p.require_whitespace()!
		name, s, e := p.read_identifier()!
		if name == '' {
			return compile_error('expected_identifier', 'Expected an identifier', p.index)
		}
		id := p.ast.add_expr(CExpr{
			kind:  .identifier
			start: s
			end:   e
			name:  name
		})
		p.allow_whitespace()
		params_start := p.index
		mut type_params := ''
		mut has_type_params := false
		if p.ts && p.match_('<') {
			tp_start := p.index
			tp_end := p.match_pointy(tp_start)!
			type_params = p.src[tp_start + 1..tp_end - 1]
			has_type_params = true
			p.index = tp_end
		}
		p.allow_whitespace()
		mut params := []int{}
		if p.eat('(') {
			paren_start := p.index - 1
			mut parens := 1
			for p.index < p.src.len && (!p.match_(')') || parens != 1) {
				if p.match_('(') {
					parens++
				}
				if p.match_(')') {
					parens--
				}
				p.index++
			}
			p.eat_required(')')!
			params = p.snippet_params(paren_start + 1, p.index - 1)!
		} else {
			return compile_error('expected_token', 'Expected token (', p.index)
		}
		_ = params_start
		p.allow_whitespace()
		p.eat_required('}')!
		body := p.ast.new_fragment()
		idx := p.append(CNode{
			typ:             .snippet_block
			start:           start
			end:             -1
			expression:      id
			type_params:     type_params
			has_type_params: has_type_params
			parameters:      params
			body:            body
		})
		p.stack << idx
		p.fragments << body
		return
	}
	return compile_error('expected_block_type', "Expected 'if', 'each', 'await', 'key' or 'snippet'",
		p.index)
}

// match_ws_curly is /\s*}/y.
fn (p &CParser) match_ws_curly() bool {
	mut k := p.index
	for k < p.src.len {
		ok, n := is_js_ws(p.src, k)
		if !ok {
			break
		}
		k += n
	}
	return k < p.src.len && p.src[k] == `}`
}

// match_pointy is match_bracket with `<` `>` as the only brackets.
fn (mut p CParser) match_pointy(start int) !int {
	mut depth := 0
	mut i := start
	for i < p.src.len {
		c := p.src[i]
		i++
		if c == `'` || c == `"` || c == `\`` {
			i = p.match_quote(i, c)!
			continue
		}
		if c == `<` {
			depth++
		} else if c == `>` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return compile_error('unexpected_eof', 'Unexpected end of input', p.src.len)
}

// snippet_params splits the parameter list of a snippet ([from, to) inside the parentheses)
// into patterns: identifiers (with a type annotation, `?`), `…= default`, `...rest`, `{…}`, `[…]`.
fn (mut p CParser) snippet_params(from int, to int) ![]int {
	mut js := JsScanner{
		src: p.src[..to]
	}
	sc := js.scan_expression(from, [], [])
	if sc.invalid {
		return compile_error('js_parse_error', 'Unexpected token', sc.invalid_at)
	}
	mut out := []int{}
	mut seg := 0
	for k := 0; k <= sc.tokens.len; k++ {
		if k == sc.tokens.len || (tok_is(p.src, sc.tokens[k], ',')
			&& depth_at(p.src, sc.tokens, k) == 0) {
			if k > seg {
				out << p.snippet_param(sc.tokens[seg..k])
			}
			seg = k + 1
		}
	}
	return out
}

fn (mut p CParser) snippet_param(tokens []Tok) int {
	src := p.src
	first := tokens[0]
	mut e := CExpr{
		start: first.start
		end:   tokens.last().end
	}
	if tok_is(src, first, '...') {
		e.kind = .other // RestElement
		e.raw = 'RestElement'
		return p.ast.add_expr(e)
	}
	// A depth-0 `=` makes an AssignmentPattern.
	for k, t in tokens {
		if tok_is(src, t, '=') && depth_at(src, tokens, k) == 0 {
			e.kind = .assignment
			e.raw = 'AssignmentPattern'
			return p.ast.add_expr(e)
		}
	}
	e.kind = if first.kind == .ident {
		ExprKind.identifier
	} else if tok_is(src, first, '{') {
		ExprKind.object_pattern
	} else {
		ExprKind.array_pattern
	}
	if first.kind == .ident {
		e.name = src[first.start..first.end]
	}
	// `name: Type` / `name?: Type`: the annotation (from the `:`).
	for k, t in tokens {
		if (tok_is(src, t, ':') || tok_is(src, t, '?')) && depth_at(src, tokens, k) == 0 && k > 0 {
			mut colon := k
			if tok_is(src, t, '?') && k + 1 < tokens.len && tok_is(src, tokens[k + 1], ':') {
				colon = k + 1
			}
			if tok_is(src, tokens[colon], ':') {
				e.ann_start = tokens[colon].start
				e.ann_end = tokens.last().end
			}
			break
		}
	}
	return p.ast.add_expr(e)
}

// read_each_head reads `expr as context, index (key)}` after `{#each `.
fn (mut p CParser) read_each_head(block_start int) !(int, int, string, bool, int) {
	start := p.index
	sc := p.js.scan_expression(start, [], ['as'])
	if sc.invalid {
		p.expr_from_scan(sc)!
		return error('unreachable')
	}
	// The expression: up to the first depth-0 `as` (the last one in TypeScript mode, where acorn
	// reads `x as T` as an assertion the compiler takes back), else up to the first depth-0
	// comma (a sequence the compiler reduces to its first expression).
	mut cut := sc.tokens.len
	mut has_as := false
	if sc.keywords.len > 0 {
		cut = if p.ts { sc.keywords.last() } else { sc.keywords[0] }
		has_as = true
	} else if sc.commas.len > 0 {
		cut = sc.commas[0]
	}
	if cut == 0 {
		return compile_error('js_parse_error', 'Unexpected token', if cut < sc.tokens.len {
			sc.tokens[cut].start
		} else {
			sc.stop
		})
	}
	expr_tokens := sc.tokens[..cut]
	mut comments := []CComment{}
	cut_end := if cut < sc.tokens.len { sc.tokens[cut].start } else { sc.stop }
	for c in sc.comments {
		if c.start < cut_end {
			comments << c
		}
	}
	expression := p.expr_of_tokens(expr_tokens, comments)
	for c in comments {
		p.ast.comments << c
	}
	p.index = expr_tokens.last().end
	p.allow_whitespace()
	mut context := -1
	mut index := ''
	mut has_index := false
	mut key := -1
	if has_as {
		p.index = sc.tokens[cut].start
		p.eat('as')
		p.require_whitespace()!
		context = p.read_pattern()!
	}
	p.allow_whitespace()
	if p.eat(',') {
		p.allow_whitespace()
		name, _, _ := p.read_identifier()!
		index = name
		has_index = true
		if index == '' {
			return compile_error('expected_identifier', 'Expected an identifier', p.index)
		}
		p.allow_whitespace()
	}
	if p.eat('(') {
		p.allow_whitespace()
		key = p.read_expression([])!
		p.allow_whitespace()
		p.eat_required(')')!
		p.allow_whitespace()
	}
	p.eat_required('}')!
	_ = block_start
	return expression, context, index, has_index, key
}

fn (mut p CParser) next() ! {
	start := p.index - 1
	block := p.current()
	btype := p.current_type()
	if btype == .if_block {
		if !p.eat('else') {
			return compile_error('expected_token', 'Expected token {:else} or {:else if}',
				start)
		}
		if p.eat('if') {
			return compile_error('block_invalid_elseif', "'elseif' should be 'else if'", start)
		}
		p.allow_whitespace()
		p.fragments.pop()
		alt := p.ast.new_fragment()
		p.ast.nodes[block].alternate = alt
		p.fragments << alt
		if p.eat('if') {
			p.require_whitespace()!
			expression := p.read_expression([])!
			p.allow_whitespace()
			p.eat_required('}')!
			mut elseif_start := start - 1
			for p.src[elseif_start] != `{` {
				elseif_start--
			}
			consequent := p.ast.new_fragment()
			child := p.append(CNode{
				typ:        .if_block
				start:      elseif_start
				end:        -1
				elseif:     true
				expression: expression
				consequent: consequent
			})
			p.stack << child
			p.fragments.pop()
			p.fragments << consequent
		} else {
			p.allow_whitespace()
			p.eat_required('}')!
		}
		return
	}
	if btype == .each_block {
		if !p.eat('else') {
			return compile_error('expected_token', 'Expected token {:else}', start)
		}
		p.allow_whitespace()
		p.eat_required('}')!
		fb := p.ast.new_fragment()
		p.ast.nodes[block].fallback = fb
		p.fragments.pop()
		p.fragments << fb
		return
	}
	if btype == .await_block {
		if p.eat('then') {
			if p.ast.nodes[block].then >= 0 {
				return compile_error('block_duplicate_clause', '{:then} cannot appear more than once within a block',
					start)
			}
			if !p.eat('}') {
				p.require_whitespace()!
				p.ast.nodes[block].await_value = p.read_pattern()!
				p.allow_whitespace()
				p.eat_required('}')!
			}
			f := p.ast.new_fragment()
			p.ast.nodes[block].then = f
			p.fragments.pop()
			p.fragments << f
			return
		}
		if p.eat('catch') {
			if p.ast.nodes[block].catch_ >= 0 {
				return compile_error('block_duplicate_clause', '{:catch} cannot appear more than once within a block',
					start)
			}
			if !p.eat('}') {
				p.require_whitespace()!
				p.ast.nodes[block].await_error = p.read_pattern()!
				p.allow_whitespace()
				p.eat_required('}')!
			}
			f := p.ast.new_fragment()
			p.ast.nodes[block].catch_ = f
			p.fragments.pop()
			p.fragments << f
			return
		}
		return compile_error('expected_token', 'Expected token {:then ...} or {:catch ...}',
			start)
	}
	return compile_error('block_invalid_continuation_placement', '{:...} block is invalid at this position (did you forget to close the preceding element or block?)',
		start)
}

fn (mut p CParser) close() ! {
	start := p.index - 1
	mut block := p.current()
	btype := p.current_type()
	match btype {
		.if_block {
			p.eat_required('if')!
			p.allow_whitespace()
			p.eat_required('}')!
			for p.ast.nodes[block].elseif {
				p.ast.nodes[block].end = p.index
				p.stack.pop()
				block = p.current()
			}
			p.ast.nodes[block].end = p.index
			p.pop()
			return
		}
		.each_block {
			p.eat_required('each')!
		}
		.key_block {
			p.eat_required('key')!
		}
		.await_block {
			p.eat_required('await')!
		}
		.snippet_block {
			p.eat_required('snippet')!
		}
		else {
			return compile_error('block_unexpected_close', 'Unexpected block closing tag',
				start)
		}
	}
	p.allow_whitespace()
	p.eat_required('}')!
	p.ast.nodes[block].end = p.index
	p.pop()
}

fn (mut p CParser) special() ! {
	mut start := p.index
	for p.src[start] != `{` {
		start--
	}
	if p.eat('html') {
		p.require_whitespace()!
		expression := p.read_expression([])!
		p.allow_whitespace()
		p.eat_required('}')!
		p.append(CNode{
			typ:        .html_tag
			start:      start
			end:        p.index
			expression: expression
		})
		return
	}
	if p.eat('debug') {
		mut identifiers := []int{}
		if p.match_ws_curly() {
			p.allow_whitespace()
			p.index++
		} else {
			expression := p.read_expression([])!
			ex := p.ast.exprs[expression]
			identifiers = if ex.kind == .sequence { ex.elems } else { [expression] }
			for id in identifiers {
				if p.ast.exprs[id].kind != .identifier {
					return compile_error('debug_tag_invalid_arguments', '{@debug ...} arguments must be identifiers, not arbitrary expressions',
						p.ast.exprs[id].start)
				}
			}
			p.allow_whitespace()
			p.eat_required('}')!
		}
		p.append(CNode{
			typ:         .debug_tag
			start:       start
			end:         p.index
			identifiers: identifiers
		})
		return
	}
	if p.eat('const') {
		p.require_whitespace()!
		id := p.read_pattern()!
		p.allow_whitespace()
		p.eat_required('=')!
		p.allow_whitespace()
		expression_start := p.index
		init := p.read_expression([])!
		ie := p.ast.exprs[init]
		if ie.kind == .sequence && !p.src[expression_start..ie.start].contains('(') {
			return compile_error('const_tag_invalid_expression', '{@const ...} must consist of a single variable declaration',
				ie.start)
		}
		p.allow_whitespace()
		p.eat_required('}')!
		p.append(CNode{
			typ:        .const_tag
			start:      start
			end:        p.index
			decl_id:    id
			decl_init:  init
			decl_start: start + 2
			decl_end:   p.index - 1
		})
		return
	}
	if p.eat('render') {
		p.require_whitespace()!
		expression := p.read_expression([])!
		ex := p.ast.exprs[expression]
		if ex.kind != .call && ex.kind != .chain_call {
			return compile_error('render_tag_invalid_expression', '`{@render ...}` tags can only contain call expressions',
				ex.start)
		}
		p.allow_whitespace()
		p.eat_required('}')!
		p.append(CNode{
			typ:        .render_tag
			start:      start
			end:        p.index
			expression: expression
		})
		return
	}
	return compile_error('expected_tag', "Expected 'html', 'render', 'attach', 'const', or 'debug'",
		p.index)
}
