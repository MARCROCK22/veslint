module postcss

// The tokenizers: postcss's lib/tokenize.js, postcss-scss's lib/scss-tokenize.js and
// eslint-plugin-svelte's css-utils/template-tokenize.ts (a `{…}` of a Svelte template is one word).

// Token is a token of the tokenizer, `[type, text, start, end]` (start and end -1 when absent;
// `inline` is postcss-scss's fifth element of a `//` comment).
pub struct Token {
pub:
	typ    string
	text   string
	start  int = -1
	end    int = -1
	inline bool
}

// is_none is the tokenizer's `undefined` at the end of the input.
pub fn (t Token) is_none() bool {
	return t.typ == ''
}

// or_pos is JavaScript's `a || b` on two token positions: 0 and an absent one are false.
fn or_pos(a int, b int) int {
	return if a > 0 { a } else { b }
}

pub enum Syntax {
	css
	scss
}

pub struct Tokenizer {
	css      []u16
	syntax   Syntax
	ignore   bool
	template bool
mut:
	input          &Input = unsafe { nil }
	pos            int
	returned       []Token
	last_bad_paren int = -1
	buffer         []Token
}

// new_tokenizer is `tokenizer(input, {ignoreErrors})` (scssTokenize for .scss; with `template`,
// templateTokenize).
pub fn new_tokenizer(input &Input, syntax Syntax, ignore bool, template bool) Tokenizer {
	return Tokenizer{
		css:      input.css
		syntax:   syntax
		ignore:   ignore
		template: template
		input:    unsafe { input }
	}
}

pub fn (t &Tokenizer) position() int {
	return t.pos
}

pub fn (t &Tokenizer) end_of_file() bool {
	return t.returned.len == 0 && t.pos >= t.css.len
}

pub fn (mut t Tokenizer) back(token Token) {
	t.returned << token
}

fn (t &Tokenizer) at(i int) int {
	return if i >= 0 && i < t.css.len { int(t.css[i]) } else { -1 }
}

fn (t &Tokenizer) slice(a int, b int) string {
	start := if a < 0 { 0 } else { a }
	end := if b > t.css.len { t.css.len } else { b }
	if end <= start {
		return ''
	}
	return text(t.css[start..end])
}

fn (t &Tokenizer) index_of(ch u16, from int) int {
	for i in (if from < 0 { 0 } else { from }) .. t.css.len {
		if t.css[i] == ch {
			return i
		}
	}
	return -1
}

// cls tells whether the unit `c` is one of the ASCII characters of `set`.
fn cls(c int, set string) bool {
	return c >= 0 && c < 128 && set.contains_u8(u8(c))
}

fn is_space_code(c int) bool {
	return cls(c, ' \n\t\r\x0c')
}

fn is_hex_code(c int) bool {
	return (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

// is_at_end is RE_AT_END's class.
fn is_at_end(c int) bool {
	return cls(c, '\t\n\x0c\r "#\'()/;[\\]{}')
}

// word_end_after is RE_WORD_END searched from `from`: the index of the first match, or -1.
fn (t &Tokenizer) word_end_after(from int) int {
	for i in from .. t.css.len {
		c := int(t.css[i])
		if cls(c, '\t\n\x0c\r !"#\'():;@[\\]{}') {
			return i
		}
		if t.syntax == .scss && c == `,` {
			return i
		}
		if c == `/` && t.at(i + 1) == `*` {
			return i
		}
	}
	return -1
}

// bad_bracket is RE_BAD_BRACKET (/.[\r\n"'(/\\]/) on css[a..b].
fn (t &Tokenizer) bad_bracket(a int, b int) bool {
	for j in a + 1 .. b {
		c := int(t.css[j])
		p := int(t.css[j - 1])
		if cls(c, '\r\n"\'(/\\') && !cls(p, '\n\r') && p != 0x2028 && p != 0x2029 {
			return true
		}
	}
	return false
}

// url_name is RE_URL_NAME on css.substring(pos - 4, pos).
fn (t &Tokenizer) url_name(pos int) bool {
	start := if pos - 4 < 0 { 0 } else { pos - 4 }
	s := t.css[start..pos]
	if s.len < 3 {
		return false
	}
	tail := s[s.len - 3..]
	if (tail[0] | 0x20) != `u` || (tail[1] | 0x20) != `r` || (tail[2] | 0x20) != `l` {
		return false
	}
	if s.len == 3 {
		return true
	}
	return cls(int(s[0]), '\t\n\x0c\r "\'(),/:;[]{}')
}

// quoted_at is RE_QUOTED (/[\t\n\f\r ]*["']/y) at `i`.
fn (t &Tokenizer) quoted_at(i int) bool {
	mut j := i
	for j < t.css.len && cls(int(t.css[j]), '\t\n\x0c\r ') {
		j++
	}
	return j < t.css.len && (t.css[j] == `"` || t.css[j] == `'`)
}

fn (t &Tokenizer) unclosed(what string) IError {
	return t.input.error_at('Unclosed ${what}', t.pos)
}

// next_token is nextToken({ignoreUnclosed}); a token with an empty type at the end.
pub fn (mut t Tokenizer) next_token(ignore_unclosed bool) !Token {
	if !t.template {
		return t.raw_next_token(ignore_unclosed)!
	}
	// templateTokenize: the tokens from a `{` to its `}` make one word.
	mut returned := []Token{}
	mut token := Token{}
	mut last_pos := -1
	mut depth := 0
	for {
		token = t.raw_next_token(ignore_unclosed)!
		if token.is_none() {
			break
		}
		if token.typ != 'word' {
			if token.typ == '{' {
				depth++
			} else if token.typ == '}' {
				depth--
			}
		}
		if depth != 0 || returned.len > 0 {
			last_pos = or_pos(token.end, or_pos(token.start, last_pos))
			returned << token
		}
		if depth == 0 {
			break
		}
	}
	if returned.len > 0 {
		mut joined := []string{cap: returned.len}
		for r in returned {
			joined << r.text
		}
		token = Token{
			typ:   'word'
			text:  joined.join('')
			start: returned[0].start
			end:   last_pos
		}
	}
	return token
}

fn (mut t Tokenizer) raw_next_token(ignore_unclosed bool) !Token {
	if t.returned.len > 0 {
		return t.returned.pop()
	}
	if t.pos >= t.css.len {
		return Token{}
	}
	if t.syntax == .scss {
		return t.scss_next_token()!
	}
	css := t.css
	length := css.len
	mut code := int(css[t.pos])
	mut next := 0
	mut current := Token{}
	match if code < 128 { u8(code) } else { u8(0x80) } {
		`\n`, ` `, `\t`, `\r`, 0x0C {
			next = t.pos
			for {
				next++
				code = t.at(next)
				if !is_space_code(code) {
					break
				}
			}
			current = Token{
				typ:  'space'
				text: t.slice(t.pos, next)
			}
			t.pos = next - 1
		}
		`[`, `]`, `{`, `}`, `:`, `;`, `)` {
			ch := rune(code).str()
			current = Token{
				typ:   ch
				text:  ch
				start: t.pos
			}
		}
		`(` {
			if t.url_name(t.pos) && !t.quoted_at(t.pos + 1) {
				next = t.pos
				mut escaped := false
				for {
					escaped = false
					next = t.index_of(`)`, next + 1)
					if next == -1 {
						if t.ignore || ignore_unclosed {
							next = t.pos
							break
						} else {
							return t.unclosed('bracket')
						}
					}
					mut escape_pos := next
					for t.at(escape_pos - 1) == `\\` {
						escape_pos--
						escaped = !escaped
					}
					if !escaped {
						break
					}
				}
				current = Token{
					typ:   'brackets'
					text:  t.slice(t.pos, next + 1)
					start: t.pos
					end:   next
				}
				t.pos = next
			} else if t.pos <= t.last_bad_paren {
				current = Token{
					typ:   '('
					text:  '('
					start: t.pos
				}
			} else {
				next = t.index_of(`)`, t.pos + 1)
				if next == -1 || t.bad_bracket(t.pos, next + 1) {
					t.last_bad_paren = if next == -1 { length } else { next }
					current = Token{
						typ:   '('
						text:  '('
						start: t.pos
					}
				} else {
					current = Token{
						typ:   'brackets'
						text:  t.slice(t.pos, next + 1)
						start: t.pos
						end:   next
					}
					t.pos = next
				}
			}
		}
		`'`, `"` {
			quote := u16(code)
			next = t.pos
			for {
				mut escaped := false
				next = t.index_of(quote, next + 1)
				if next == -1 {
					if t.ignore || ignore_unclosed {
						next = t.pos + 1
						break
					} else {
						return t.unclosed('string')
					}
				}
				mut escape_pos := next
				for t.at(escape_pos - 1) == `\\` {
					escape_pos--
					escaped = !escaped
				}
				if !escaped {
					break
				}
			}
			current = Token{
				typ:   'string'
				text:  t.slice(t.pos, next + 1)
				start: t.pos
				end:   next
			}
			t.pos = next
		}
		`@` {
			next = length - 1
			for i in t.pos + 1 .. length {
				if is_at_end(int(css[i])) {
					next = i - 1
					break
				}
			}
			current = Token{
				typ:   'at-word'
				text:  t.slice(t.pos, next + 1)
				start: t.pos
				end:   next
			}
			t.pos = next
		}
		`\\` {
			current = t.backslash_token()
		}
		else {
			if code == `/` && t.at(t.pos + 1) == `*` {
				next = t.comment_end(ignore_unclosed)!
				current = Token{
					typ:   'comment'
					text:  t.slice(t.pos, next + 1)
					start: t.pos
					end:   next
				}
				t.pos = next
			} else {
				current = t.word_token()
				t.pos = current.end
			}
		}
	}
	t.pos++
	return current
}

// comment_end is the end of a `/*` comment at t.pos (css.length when it is not closed and errors
// are ignored).
fn (t &Tokenizer) comment_end(ignore_unclosed bool) !int {
	mut next := -1
	for i in t.pos + 2 .. t.css.len - 1 {
		if t.css[i] == `*` && t.css[i + 1] == `/` {
			next = i
			break
		}
	}
	next++
	if next == 0 {
		if t.ignore || ignore_unclosed {
			next = t.css.len
		} else {
			return t.unclosed('comment')
		}
	}
	return next
}

// word_token is the word at t.pos (RE_WORD_END); it does not move t.pos.
fn (t &Tokenizer) word_token() Token {
	m := t.word_end_after(t.pos + 1)
	next := if m == -1 { t.css.len - 1 } else { m - 1 }
	return Token{
		typ:   'word'
		text:  t.slice(t.pos, next + 1)
		start: t.pos
		end:   next
	}
}

// backslash_token is the word of an escape at t.pos; it moves t.pos to its end.
fn (mut t Tokenizer) backslash_token() Token {
	mut next := t.pos
	mut escape := true
	for t.at(next + 1) == `\\` {
		next++
		escape = !escape
	}
	code := t.at(next + 1)
	if escape && code != `/` && !is_space_code(code) {
		next++
		if is_hex_code(t.at(next)) {
			for is_hex_code(t.at(next + 1)) {
				next++
			}
			if t.at(next + 1) == ` ` {
				next++
			}
		}
	}
	token := Token{
		typ:   'word'
		text:  t.slice(t.pos, next + 1)
		start: t.pos
		end:   next
	}
	t.pos = next
	return token
}

// scss_interpolation is postcss-scss's interpolation(): from the `#{` at `from`, the index of the
// `}` that closes it.
fn (t &Tokenizer) scss_interpolation(from int) !int {
	mut next := from
	mut deep := 1
	mut string_quote := 0
	mut string_escaped := false
	for deep > 0 {
		next++
		if t.css.len <= next {
			return t.unclosed('interpolation')
		}
		code := int(t.css[next])
		n := t.at(next + 1)
		if string_quote != 0 {
			if !string_escaped && code == string_quote {
				string_quote = 0
				string_escaped = false
			} else if code == `\\` {
				string_escaped = !string_escaped
			} else if string_escaped {
				string_escaped = false
			}
		} else if code == `'` || code == `"` {
			string_quote = code
		} else if code == `}` {
			deep--
		} else if code == `#` && n == `{` {
			deep++
		}
	}
	return next
}

fn (mut t Tokenizer) scss_next_token() !Token {
	css := t.css
	length := css.len
	mut code := int(css[t.pos])
	mut next := 0
	mut current := Token{}
	match if code < 128 { u8(code) } else { u8(0x80) } {
		`\n`, ` `, `\t`, `\r`, 0x0C {
			next = t.pos
			for {
				next++
				code = t.at(next)
				if !is_space_code(code) {
					break
				}
			}
			current = Token{
				typ:  'space'
				text: t.slice(t.pos, next)
			}
			t.pos = next - 1
		}
		`[`, `]`, `{`, `}`, `:`, `;`, `)` {
			ch := rune(code).str()
			current = Token{
				typ:   ch
				text:  ch
				start: t.pos
			}
		}
		`,` {
			current = Token{
				typ:   'word'
				text:  ','
				start: t.pos
				end:   t.pos + 1
			}
		}
		`(` {
			prev := if t.buffer.len > 0 { t.buffer.pop().text } else { '' }
			n := t.at(t.pos + 1)
			if prev == 'url' && n != `'` && n != `"` {
				mut brackets := 1
				mut escaped := false
				next = t.pos + 1
				for next <= length - 1 {
					c := int(css[next])
					if c == `\\` {
						escaped = !escaped
					} else if c == `(` {
						brackets++
					} else if c == `)` {
						brackets--
						if brackets == 0 {
							break
						}
					}
					next++
				}
				current = Token{
					typ:   'brackets'
					text:  t.slice(t.pos, next + 1)
					start: t.pos
					end:   next
				}
				t.pos = next
			} else {
				next = t.index_of(`)`, t.pos + 1)
				if next == -1 || t.bad_bracket(t.pos, next + 1) {
					current = Token{
						typ:   '('
						text:  '('
						start: t.pos
					}
				} else {
					current = Token{
						typ:   'brackets'
						text:  t.slice(t.pos, next + 1)
						start: t.pos
						end:   next
					}
					t.pos = next
				}
			}
		}
		`'`, `"` {
			quote := code
			next = t.pos
			mut escaped := false
			for next < length {
				next++
				if next == length {
					return t.unclosed('string')
				}
				c := int(css[next])
				n := t.at(next + 1)
				if !escaped && c == quote {
					break
				} else if c == `\\` {
					escaped = !escaped
				} else if escaped {
					escaped = false
				} else if c == `#` && n == `{` {
					next = t.scss_interpolation(next)!
				}
			}
			current = Token{
				typ:   'string'
				text:  t.slice(t.pos, next + 1)
				start: t.pos
				end:   next
			}
			t.pos = next
		}
		`@` {
			next = length - 1
			for i in t.pos + 1 .. length {
				if is_at_end(int(css[i])) {
					next = i - 1
					break
				}
			}
			current = Token{
				typ:   'at-word'
				text:  t.slice(t.pos, next + 1)
				start: t.pos
				end:   next
			}
			t.pos = next
		}
		`\\` {
			current = t.backslash_token()
		}
		else {
			n := t.at(t.pos + 1)
			if code == `#` && n == `{` {
				next = t.scss_interpolation(t.pos)!
				current = Token{
					typ:   'word'
					text:  t.slice(t.pos, next + 1)
					start: t.pos
					end:   next
				}
				t.pos = next
			} else if code == `/` && n == `*` {
				next = t.comment_end(false)!
				current = Token{
					typ:   'comment'
					text:  t.slice(t.pos, next + 1)
					start: t.pos
					end:   next
				}
				t.pos = next
			} else if code == `/` && n == `/` {
				next = length - 1
				for i in t.pos + 1 .. length {
					if cls(int(css[i]), '\n\x0c\r') {
						next = i - 1
						break
					}
				}
				current = Token{
					typ:    'comment'
					text:   t.slice(t.pos, next + 1)
					start:  t.pos
					end:    next
					inline: true
				}
				t.pos = next
			} else {
				current = t.word_token()
				t.buffer << current
				t.pos = current.end
			}
		}
	}
	t.pos++
	return current
}
