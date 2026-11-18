module svelte

// A JavaScript (and TypeScript) token scanner for the compiler's parser. The compiler reads a
// template expression with acorn's parseExpressionAt, which stops at the first token that
// cannot continue the expression; svelte-eslint-parser only uses the extent of what it read
// (it re-parses that text with the script parser), its kind and its comments. For the input
// the compiler accepts, the extent is: the tokens up to the first closing bracket that was not
// opened inside (the `}` of a mustache, the `)` of an each key), or up to a contextual keyword
// (`then`/`catch` of an await block, `as` of an each block). The scanner finds it without a
// parser: it knows tokens, brackets and comments, and tells a regular expression from a
// division by the token before.

enum TokKind as u8 {
	eof
	punct
	ident
	number
	str
	template
	regex
	private_name
	invalid // an unterminated string, template, regular expression or comment
}

struct Tok {
	kind  TokKind
	start int
	end   int
}

// The words after which a `/` starts a regular expression, and which do not end an expression.
const js_operator_words = ['typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'return',
	'case', 'do', 'else', 'yield', 'await', 'throw', 'extends', 'as', 'satisfies', 'keyof']

struct JsScanner {
	src string
mut:
	// comments collected by the last scan (in order).
	comments []CComment
}

fn is_ident_start_byte(c u8) bool {
	return c.is_letter() || c == `_` || c == `$` || c == `\\` || c >= 0x80
}

fn is_ident_part_byte(c u8) bool {
	return c.is_letter() || c.is_digit() || c == `_` || c == `$` || c == `\\` || c >= 0x80
}

// skip_trivia skips whitespace and comments from i (recording the comments) and gives the
// offset of the next token, or -1 for an unterminated block comment.
fn (mut s JsScanner) skip_trivia(i0 int) int {
	mut i := i0
	src := s.src
	for i < src.len {
		c := src[i]
		if c == ` ` || c == `\t` || c == `\n` || c == `\r` || c == 0x0b || c == 0x0c {
			i++
			continue
		}
		if c >= 0x80 {
			cp, n := code_point_at(src, i)
			if is_js_space(cp) {
				i += n
				continue
			}
			return i
		}
		if c == `/` && i + 1 < src.len {
			if src[i + 1] == `/` {
				mut e := i + 2
				for e < src.len && src[e] != `\n` && src[e] != `\r` && !is_line_sep(src, e) {
					e++
				}
				s.comments << CComment{
					block: false
					start: i
					end:   e
					value: src[i + 2..e]
				}
				i = e
				continue
			}
			if src[i + 1] == `*` {
				e := src.index_after('*/', i + 2) or { return -1 }
				s.comments << CComment{
					block: true
					start: i
					end:   e + 2
					value: block_comment_value(src, i, src[i + 2..e])
				}
				i = e + 2
				continue
			}
		}
		return i
	}
	return i
}

// block_comment_value is the value the compiler records for a block comment: a multi-line one
// loses the indentation of its first line at the start of each line (get_comment_handlers).
fn block_comment_value(src string, start int, value string) string {
	if !value.contains('\n') {
		return value
	}
	mut a := start
	for a > 0 && src[a - 1] != `\n` {
		a--
	}
	mut b := a
	for b < src.len && (src[b] == ` ` || src[b] == `\t`) {
		b++
	}
	indentation := src[a..b]
	if indentation == '' {
		return value
	}
	mut out := []string{}
	for k, line in value.split('\n') {
		_ = k
		if line.starts_with(indentation) {
			out << line[indentation.len..]
		} else {
			out << line
		}
	}
	return out.join('\n')
}

// is_line_sep: U+2028 or U+2029 at i (line terminators that end a `//` comment).
fn is_line_sep(src string, i int) bool {
	return i + 2 < src.len && src[i] == 0xe2 && src[i + 1] == 0x80
		&& (src[i + 2] == 0xa8 || src[i + 2] == 0xa9)
}

const js_puncts = ['>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=',
	'=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=', '*=', '/=', '%=',
	'&=', '|=', '^=', '**', '<<', '>>']

// scan gives the token at i (after trivia). `regex_ok`: a `/` there starts a regular expression.
fn (mut s JsScanner) scan(i int, regex_ok bool) Tok {
	src := s.src
	if i < 0 {
		return Tok{.invalid, src.len, src.len}
	}
	if i >= src.len {
		return Tok{.eof, src.len, src.len}
	}
	c := src[i]
	if is_ident_start_byte(c) {
		mut e := i
		for e < src.len {
			b := src[e]
			if b >= 0x80 {
				cp, n := code_point_at(src, e)
				if is_js_space(cp) {
					break
				}
				e += n
				continue
			}
			if !is_ident_part_byte(b) {
				break
			}
			e++
		}
		return Tok{.ident, i, e}
	}
	if c == `#` && i + 1 < src.len && is_ident_start_byte(src[i + 1]) {
		t := s.scan(i + 1, false)
		return Tok{.private_name, i, t.end}
	}
	if c.is_digit() || (c == `.` && i + 1 < src.len && src[i + 1].is_digit()) {
		mut e := i + 1
		for e < src.len {
			b := src[e]
			if b.is_alnum() || b == `_` || b == `.` {
				e++
				continue
			}
			if (b == `+` || b == `-`) && (src[e - 1] == `e` || src[e - 1] == `E`)
				&& !src[i..e].starts_with('0x') && !src[i..e].starts_with('0X') {
				e++
				continue
			}
			break
		}
		return Tok{.number, i, e}
	}
	if c == `"` || c == `'` {
		mut e := i + 1
		for e < src.len {
			b := src[e]
			if b == `\\` {
				e += 2
				continue
			}
			if b == c {
				return Tok{.str, i, e + 1}
			}
			if b == `\n` || b == `\r` {
				break
			}
			e++
		}
		return Tok{.invalid, i, if e > src.len { src.len } else { e }}
	}
	if c == `\`` {
		e := s.template_end(i + 1)
		if e < 0 {
			return Tok{.invalid, i, src.len}
		}
		return Tok{.template, i, e}
	}
	if c == `/` && regex_ok {
		mut e := i + 1
		mut in_class := false
		for e < src.len {
			b := src[e]
			if b == `\\` {
				e += 2
				continue
			}
			if b == `\n` || b == `\r` {
				return Tok{.invalid, i, e}
			}
			if in_class {
				if b == `]` {
					in_class = false
				}
			} else if b == `[` {
				in_class = true
			} else if b == `/` {
				e++
				for e < src.len && is_ident_part_byte(src[e]) {
					e++
				}
				return Tok{.regex, i, e}
			}
			e++
		}
		return Tok{.invalid, i, src.len}
	}
	for p in js_puncts {
		if at_(src, i, p) {
			if p == '?.' && i + 2 < src.len && src[i + 2].is_digit() {
				continue
			}
			return Tok{.punct, i, i + p.len}
		}
	}
	return Tok{.punct, i, i + 1}
}

// template_end gives the offset after the closing backtick of a template literal whose
// characters start at i, scanning the substitutions as code; -1 if unterminated.
fn (mut s JsScanner) template_end(i0 int) int {
	src := s.src
	mut i := i0
	for i < src.len {
		c := src[i]
		if c == `\\` {
			i += 2
			continue
		}
		if c == `\`` {
			return i + 1
		}
		if c == `$` && i + 1 < src.len && src[i + 1] == `{` {
			// The substitution: tokens up to the matching `}`.
			mut depth := 0
			mut j := i + 2
			mut prev := Tok{.punct, i + 1, i + 2}
			for {
				j = s.skip_trivia(j)
				t := s.scan(j, regex_allowed(src, prev))
				if t.kind == .eof || t.kind == .invalid {
					return -1
				}
				if t.kind == .punct {
					ch := src[t.start]
					if t.end - t.start == 1 && (ch == `{` || ch == `(` || ch == `[`) {
						depth++
					} else if t.end - t.start == 1 && (ch == `}` || ch == `)` || ch == `]`) {
						if depth == 0 {
							if ch == `}` {
								i = t.end
								break
							}
							return -1
						}
						depth--
					}
				}
				prev = t
				j = t.end
			}
			continue
		}
		i++
	}
	return -1
}

// ends_expression tells whether a token can end an expression (a `/` after it is a division).
fn ends_expression(src string, t Tok) bool {
	match t.kind {
		.number, .str, .template, .regex, .private_name {
			return true
		}
		.ident {
			return src[t.start..t.end] !in js_operator_words
		}
		.punct {
			text := src[t.start..t.end]
			return text in [')', ']', '}', '++', '--']
		}
		else {
			return false
		}
	}
}

fn regex_allowed(src string, prev Tok) bool {
	return !ends_expression(src, prev)
}

// ExprScan is the result of scanning an expression.
struct ExprScan {
	// The tokens of the expression (no comments), in order.
	tokens []Tok
	// The offset where the scan stopped (the start of the token that ends the expression, or the
	// end of the source).
	stop int
	// The stop token (eof when none).
	stop_tok Tok
	// The comments met from the start to the stop token.
	comments []CComment
	// The tokens at depth 0 that are the contextual keywords asked for (indexes in tokens).
	keywords []int
	// commas at depth 0 (indexes in tokens).
	commas []int
	// invalid: an unterminated token or comment, or brackets that do not match.
	invalid    bool
	invalid_at int
}

// scan_expression scans the tokens of an expression from i: up to a closing bracket at depth
// 0, or (with stop_words) a word of stop_words at depth 0 after a token that ends an
// expression. `keywords` records the depth-0 words of `track` (after an expression end).
fn (mut s JsScanner) scan_expression(i0 int, stop_words []string, track []string) ExprScan {
	src := s.src
	s.comments = []
	mut tokens := []Tok{}
	mut keywords := []int{}
	mut commas := []int{}
	mut stack := []u8{}
	mut i := i0
	mut prev := Tok{.eof, i0, i0}
	mut have_prev := false
	for {
		i = s.skip_trivia(i)
		if i < 0 {
			return ExprScan{
				tokens:     tokens
				stop:       src.len
				stop_tok:   Tok{.invalid, src.len, src.len}
				comments:   s.comments
				keywords:   keywords
				commas:     commas
				invalid:    true
				invalid_at: src.len
			}
		}
		t := s.scan(i, !have_prev || regex_allowed(src, prev))
		if t.kind == .eof {
			return ExprScan{
				tokens:   tokens
				stop:     src.len
				stop_tok: t
				comments: s.comments
				keywords: keywords
				commas:   commas
			}
		}
		if t.kind == .invalid {
			return ExprScan{
				tokens:     tokens
				stop:       t.start
				stop_tok:   t
				comments:   s.comments
				keywords:   keywords
				commas:     commas
				invalid:    true
				invalid_at: t.start
			}
		}
		if t.kind == .punct && t.end - t.start == 1 {
			ch := src[t.start]
			if ch == `{` || ch == `(` || ch == `[` {
				stack << ch
			} else if ch == `}` || ch == `)` || ch == `]` {
				if stack.len == 0 {
					return ExprScan{
						tokens:   tokens
						stop:     t.start
						stop_tok: t
						comments: s.comments
						keywords: keywords
						commas:   commas
					}
				}
				open := stack.pop()
				if (open == `{` && ch != `}`) || (open == `(` && ch != `)`)
					|| (open == `[` && ch != `]`) {
					return ExprScan{
						tokens:     tokens
						stop:       t.start
						stop_tok:   t
						comments:   s.comments
						keywords:   keywords
						commas:     commas
						invalid:    true
						invalid_at: t.start
					}
				}
			} else if ch == `,` && stack.len == 0 {
				commas << tokens.len
			}
		}
		if t.kind == .ident && stack.len == 0 && have_prev && ends_expression(src, prev) {
			word := src[t.start..t.end]
			if word in stop_words {
				return ExprScan{
					tokens:   tokens
					stop:     t.start
					stop_tok: t
					comments: s.comments
					keywords: keywords
					commas:   commas
				}
			}
			if word in track {
				keywords << tokens.len
			}
		}
		tokens << t
		prev = t
		have_prev = true
		i = t.end
	}
	return ExprScan{}
}

// matching_paren gives, for the token at index `open` (a `(`), the index of its `)`, or -1.
fn matching_close(src string, tokens []Tok, open int) int {
	mut depth := 0
	for k in open .. tokens.len {
		t := tokens[k]
		if t.kind != .punct || t.end - t.start != 1 {
			continue
		}
		ch := src[t.start]
		if ch == `(` || ch == `[` || ch == `{` {
			depth++
		} else if ch == `)` || ch == `]` || ch == `}` {
			depth--
			if depth == 0 {
				return k
			}
		}
	}
	return -1
}

fn tok_is(src string, t Tok, text string) bool {
	return t.end - t.start == text.len && src[t.start..t.end] == text
}

// find_matching_bracket is the compiler's utils/bracket.js find_matching_bracket: the index of
// the bracket closing the one before `index`, ignoring brackets in strings, comments and
// regular expressions (any `/` not starting a comment starts one); -1 if none.
fn find_matching_bracket(template string, index int, open u8) int {
	close := match open {
		`{` { u8(`}`) }
		`(` { u8(`)`) }
		else { u8(`]`) }
	}
	mut brackets := 1
	mut i := index
	for brackets > 0 && i < template.len {
		c := template[i]
		match c {
			`'`, `"`, `\`` {
				i = find_string_end(template, i + 1, c) + 1
				continue
			}
			`/` {
				if i + 1 >= template.len {
					// `if (!next_char) continue;` loops forever upstream; never reached as the
					// template is trimmed and ends with the closing tag.
					return -1
				}
				next := template[i + 1]
				if next == `/` {
					nl := template.index_after('\n', i + 1) or { return -1 }
					i = nl + 1
					continue
				}
				if next == `*` {
					e := template.index_after('*/', i + 1) or { return -1 }
					i = e + 2
					continue
				}
				e := find_unescaped(template, i + 1, `/`, template.len)
				if e < 0 {
					return -1
				}
				i = e + 1
				continue
			}
			else {
				if c == open {
					brackets++
				} else if c == close {
					brackets--
				}
				if brackets == 0 {
					return i
				}
				i++
			}
		}
	}
	return -1
}

// find_string_end: the closing quote of a string (on its line, except for a template);
// a very large number when not found.
fn find_string_end(s string, from int, quote u8) int {
	mut limit := s.len
	if quote != `\`` {
		nl := s.index_after('\n', from) or { -1 }
		if nl >= 0 {
			limit = nl
		}
	}
	e := find_unescaped(s, from, quote, limit)
	return if e < 0 { s.len + 1 } else { e }
}

fn find_unescaped(s string, from int, ch u8, limit int) int {
	mut i := from
	for i < limit {
		if s[i] == ch {
			mut k := i - 1
			mut count := 0
			for k >= 0 && s[k] == `\\` {
				count++
				k--
			}
			if count % 2 == 0 {
				return i
			}
		}
		i++
	}
	return -1
}
