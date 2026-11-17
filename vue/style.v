module vue

// CSS `v-bind()` in top-level <style> elements (src/style/index.ts and src/style/tokenizer.ts):
// each becomes a VExpressionContainer child of the <style>, its expression parsed as `0(…)`.

enum CssType {
	quoted
	block
	line
	word
	punctuator
}

// CssToken is a token of the simplified CSS tokenizer; offsets are bytes of the style's text.
struct CssToken {
	typ         CssType
	start       int
	end         int
	value_start int
	value_end   int
	quote       u8
	value       string // a punctuator's character
}

struct CssTokenizer {
	text           string
	inline_comment bool
mut:
	cp          int
	offset      int = -1
	next_offset int
	reconsuming bool
	// Tokens given back by the scanner (CSSTokenScanner.reconsume), taken first.
	pending []CssToken
}

fn (mut t CssTokenizer) next_token() ?CssToken {
	if t.pending.len > 0 {
		tok := t.pending[0]
		t.pending.delete(0)
		return tok
	}
	mut cp := 0
	if t.reconsuming {
		cp = t.cp
		t.reconsuming = false
	} else {
		cp = t.consume()
	}
	for is_whitespace(cp) {
		cp = t.consume()
	}
	if cp == eof {
		return none
	}
	return t.consume_token(cp, t.offset)
}

fn (t &CssTokenizer) peek() int {
	if t.next_offset >= t.text.len {
		return eof
	}
	cp, _ := decode_cp(t.text, t.next_offset)
	return int(cp)
}

fn (mut t CssTokenizer) consume() int {
	if t.offset >= t.text.len {
		t.cp = eof
		return eof
	}
	t.offset = t.next_offset
	if t.offset >= t.text.len {
		t.cp = eof
		return eof
	}
	ucp, n := decode_cp(t.text, t.offset)
	mut cp := int(ucp)
	if cp == 0x0d {
		t.next_offset = t.offset + 1
		if t.next_offset < t.text.len && t.text[t.next_offset] == 0x0a {
			t.next_offset++
		}
		cp = 0x0a
	} else {
		t.next_offset = t.offset + n
	}
	t.cp = cp
	return cp
}

fn css_is_punctuator(cp int) bool {
	return cp in [`:`, `;`, `(`, `)`, `{`, `}`, `[`, `]`, `/`, `*`]
}

fn css_is_quote(cp int) bool {
	return cp == `'` || cp == `"`
}

fn (mut t CssTokenizer) consume_token(cp int, start int) CssToken {
	if cp == `/` {
		next := t.peek()
		if next == `*` {
			return t.consume_comment(start)
		}
		if next == `/` && t.inline_comment {
			return t.consume_inline_comment(start)
		}
	}
	if css_is_quote(cp) {
		return t.consume_string(start, cp)
	}
	if css_is_punctuator(cp) {
		return CssToken{
			typ:   .punctuator
			start: start
			end:   start + 1
			value: u8(cp).ascii_str()
		}
	}
	mut c := t.consume()
	for c != eof && !is_whitespace(c) && !css_is_punctuator(c) && !css_is_quote(c) {
		c = t.consume()
	}
	t.reconsuming = true
	end := if t.offset > t.text.len { t.text.len } else { t.offset }
	return CssToken{
		typ:   .word
		start: start
		end:   end
	}
}

fn (mut t CssTokenizer) consume_string(start int, quote int) CssToken {
	mut value_end := -1
	mut cp := t.consume()
	for cp != eof {
		if cp == quote {
			value_end = t.offset
			break
		}
		if cp == `\\` {
			t.consume()
		}
		cp = t.consume()
	}
	return CssToken{
		typ:         .quoted
		start:       start
		end:         t.next_offset
		value_start: start + 1
		value_end:   if value_end >= 0 { value_end } else { t.next_offset }
		quote:       u8(quote)
	}
}

fn (mut t CssTokenizer) consume_comment(start int) CssToken {
	t.consume()
	mut value_end := -1
	mut cp := t.consume()
	for cp != eof {
		if cp == `*` {
			cp = t.consume()
			if cp == `/` {
				value_end = t.offset - 1
				break
			}
		}
		cp = t.consume()
	}
	return CssToken{
		typ:         .block
		start:       start
		end:         t.next_offset
		value_start: start + 2
		value_end:   if value_end >= 0 { value_end } else { t.next_offset }
	}
}

fn (mut t CssTokenizer) consume_inline_comment(start int) CssToken {
	t.consume()
	mut value_end := -1
	mut cp := t.consume()
	for cp != eof {
		if cp == 0x0a {
			value_end = t.offset - 1
			break
		}
		cp = t.consume()
	}
	return CssToken{
		typ:         .line
		start:       start
		end:         t.next_offset
		value_start: start + 2
		value_end:   if value_end >= 0 { value_end } else { t.next_offset }
	}
}

fn (t CssToken) is_comment() bool {
	return t.typ == .block || t.typ == .line
}

// VBind is a `v-bind(…)` of a style: its range, the range of its expression, its quote (0
// without) and the comments that go to the document.
struct VBind {
	start        int
	end          int
	expr_start   int
	expr_end     int
	quote        u8
	paren_offset int
	comments     []CssToken
}

fn iterate_v_bind(code string, inline_comment bool) []VBind {
	mut t := CssTokenizer{
		text:           code
		inline_comment: inline_comment
	}
	mut out := []VBind{}
	for {
		token := t.next_token() or { break }
		if token.typ != .word || code[token.start..token.end] != 'v-bind' {
			continue
		}
		// findVBindOpeningParen
		mut comments := []CssToken{}
		mut paren := CssToken{}
		mut found := false
		for {
			tok := t.next_token() or { break }
			if tok.typ == .punctuator && tok.value == '(' {
				paren = tok
				found = true
				break
			} else if tok.is_comment() {
				comments << tok
				continue
			}
			// CSSTokenScanner.reconsume appends them to what is still to give back.
			t.pending << comments
			t.pending << tok
			break
		}
		if !found {
			continue
		}
		// parseVBindArg
		mut buffer := []CssToken{}
		mut arg_comments := []CssToken{}
		mut toks := []CssToken{}
		mut stack := []string{}
		mut done := false
		for {
			tok := t.next_token() or { break }
			if tok.typ == .punctuator {
				if tok.value == ')' && stack.len == 0 {
					mut all := comments.clone()
					if toks.len == 1 && toks[0].typ == .quoted {
						all << arg_comments
						out << VBind{
							start:        token.start
							end:          tok.end
							expr_start:   toks[0].value_start
							expr_end:     toks[0].value_end
							quote:        toks[0].quote
							paren_offset: paren.start
							comments:     all
						}
					} else {
						first := if buffer.len > 0 { buffer[0] } else { tok }
						out << VBind{
							start:        token.start
							end:          tok.end
							expr_start:   first.start
							expr_end:     tok.start
							paren_offset: paren.start
							comments:     all
						}
					}
					done = true
					break
				}
				if stack.len > 0 && tok.value == stack[0] {
					stack.delete(0)
				} else if tok.value == '(' {
					stack.insert(0, ')')
				}
			}
			buffer << tok
			if tok.is_comment() {
				arg_comments << tok
			} else {
				toks << tok
			}
		}
		if !done {
			t.pending << buffer
		}
	}
	return out
}

// has_v_bind is /v-bind\s*(?:\(|\/)/u.
fn has_v_bind(code string) bool {
	mut from := 0
	for {
		i := code.index_after_('v-bind', from)
		if i < 0 {
			return false
		}
		j := i + 6 + leading_space_len(code[i + 6..])
		if j < code.len && (code[j] == `(` || code[j] == `/`) {
			return true
		}
		from = i + 1
	}
	return false
}

fn (mut c ExprContext) parse_styles() {
	for style in c.doc.top_elements('style') {
		c.doc.nodes[style].style = true
		lang := c.doc.lang_of(style) or { 'css' }
		c.parse_style_element(style, lang != 'css')
	}
}

fn (mut c ExprContext) parse_style_element(style int, inline_comment bool) {
	if c.doc.nodes[style].children.len != 1 {
		return
	}
	text_node := c.doc.nodes[style].children[0]
	if c.doc.nodes[text_node].typ != .v_text {
		return
	}
	code := c.doc.nodes[text_node].text
	if !has_v_bind(code) {
		return
	}
	calc := c.doc.sub_after(c.doc.html_calc(0, 0), c.doc.utf16(c.doc.nodes[text_node].start))
	code_index := new_text_index(code)
	// at maps a byte offset of the text to a UTF-16 offset of the file.
	at := fn [c, calc, code_index] (b int) int {
		return c.doc.offset_with_gap(calc, code_index.to_u16(b))
	}
	mut text_start := 0
	for vb in iterate_v_bind(code, inline_comment) {
		mut comments := []Token{}
		for cm in vb.comments {
			comments << c.simple_token(if cm.typ == .block { 'Block' } else { 'Line' },
				at(cm.start), at(cm.end), code[cm.value_start..cm.value_end])
		}
		c.doc.insert_comments(comments)
		start16 := at(vb.start)
		end16 := at(vb.end)
		container := c.doc.add_node(VNode{
			typ:    .v_expression_container
			start:  c.to_bytes(start16)
			end:    c.to_bytes(end16)
			parent: style
		})
		paren16 := at(vb.paren_offset)
		mut before := [c.simple_token('HTMLRawText', start16, start16 + 6, 'v-bind'),
			c.simple_token('Punctuator', paren16, paren16 + 1, '(')]
		mut after := [c.simple_token('Punctuator', end16 - 1, end16, ')')]
		if vb.quote != 0 {
			q := vb.quote.ascii_str()
			open16 := c.doc.offset_with_gap(calc, code_index.to_u16(vb.expr_start) - 1)
			before << c.simple_token('Punctuator', open16, open16 + 1, q)
			close16 := at(vb.expr_end)
			after.insert(0, c.simple_token('Punctuator', close16, close16 + 1, q))
		}
		before_last := before.last()
		c.doc.replace_and_split_tokens(c.to_bytes(start16), before_last.end, before)
		after_first := after[0]
		c.doc.replace_and_split_tokens(after_first.start, c.to_bytes(end16), after)
		last_child := c.doc.nodes[style].children.last()
		c.doc.nodes[style].children << container
		if c.doc.nodes[last_child].typ == .v_text {
			new_text := c.doc.add_node(VNode{
				typ:    .v_text
				start:  c.to_bytes(end16)
				end:    c.doc.nodes[last_child].end
				parent: style
				text:   code[vb.end..]
			})
			c.doc.nodes[style].children << new_text
			c.doc.nodes[last_child].end = c.to_bytes(start16)
			c.doc.nodes[last_child].text = code[text_start..vb.start]
			text_start = vb.end
		}
		expr_code := code[vb.expr_start..vb.expr_end]
		ret := c.parse_expression(expr_code, c.doc.sub_shift(calc, code_index.to_u16(vb.expr_start)),
			false, false) or {
			if err is ParseErr {
				c.doc.insert_error(err.perr)
				continue
			}
			panic(err)
		}
		if !ret.expression.is_null() {
			c.set_container(container, ret)
		}
		c.doc.replace_and_split_tokens(before_last.end, after_first.start, ret.tokens)
		c.doc.insert_comments(ret.comments)
		for v in ret.variables {
			c.doc.variables << v
			c.doc.nodes[style].variables << c.doc.variables.len - 1
		}
		c.resolve_references(container)
	}
}

// replace_and_split_tokens is replaceAndSplitTokens: like replace_tokens, but a token that
// crosses a bound of the range is split there first.
fn (mut d Document) replace_and_split_tokens(start int, end int, tokens []Token) {
	index := sorted_index_by_start(d.tokens, start)
	if d.tokens.len == index || start < d.tokens[index].start {
		if index > 0 {
			before := d.tokens[index - 1]
			split := start - before.start
			after := Token{
				typ:   before.typ
				start: start
				end:   before.end
				value: safe_slice_from(before.value, split)
			}
			d.tokens[index - 1].end = start
			d.tokens[index - 1].value = safe_slice_to(before.value, split)
			d.tokens.insert(index, after)
		}
	}
	mut last := sorted_last_index_by_end(d.tokens, end)
	if last == 0 || (last < d.tokens.len && end < d.tokens[last].end) {
		if last < d.tokens.len {
			before := d.tokens[last]
			split := (before.end - before.start) - (before.end - end)
			after := Token{
				typ:   before.typ
				start: end
				end:   before.end
				value: safe_slice_from(before.value, split)
			}
			d.tokens[last].end = end
			d.tokens[last].value = safe_slice_to(before.value, split)
			d.tokens.insert(last + 1, after)
			last++
		}
	}
	count := last - index
	if count > 0 {
		d.tokens.delete_many(index, count)
	}
	d.tokens.insert(index, tokens)
}

fn safe_slice_from(s string, i int) string {
	return if i <= 0 {
		s
	} else if i >= s.len {
		''
	} else {
		s[i..]
	}
}

fn safe_slice_to(s string, i int) string {
	return if i <= 0 {
		''
	} else if i >= s.len {
		s
	} else {
		s[..i]
	}
}
