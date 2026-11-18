module postcss

// postcss-selector-parser 7.2.1's tokenizer and parser (`processor.astSync(selector)`), without
// the options (not lossy, not safe) and without the spaces and raws of the nodes: the tree has
// the nodes, their values and their `source` (lines and columns from 1, in UTF-16 units). An
// attribute selector is one node up to its `]` (its parts are not parsed).

pub enum SelType {
	root
	selector
	class
	id
	tag
	pseudo
	attribute
	combinator
	comment
	nesting
	universal
	str
}

pub struct SelNode {
pub mut:
	typ          SelType
	value        string
	nodes        []int
	parent       int = -1
	has_start    bool
	start_line   int
	start_column int
	has_end      bool
	end_line     int
	end_column   int
}

pub struct SelectorRoot {
pub mut:
	nodes []SelNode
}

// The token types: a character code, or one of these.
const st_comment = -1
const st_word = -2
const st_combinator = -3

struct SelToken {
	typ        int
	line       int
	column     int
	end_line   int
	end_column int
	start      int
	end        int
}

fn sel_word_delimiter(c int) bool {
	return cls(c, ' \t\n\r\x0c&*!,:;()[]\'"+|~>=$^/')
}

fn sel_consume_escape(css []u16, start int) int {
	mut next := start
	mut code := if next + 1 < css.len { int(css[next + 1]) } else { -1 }
	if cls(code, '\t\n\r\x0c') {
		// just the backslash
	} else if is_hex_code(code) {
		mut hex_digits := 0
		for {
			next++
			hex_digits++
			code = if next + 1 < css.len { int(css[next + 1]) } else { -1 }
			if !(is_hex_code(code) && hex_digits < 6) {
				break
			}
		}
		if hex_digits < 6 && code == ` ` {
			next++
		}
	} else {
		next++
	}
	return next
}

fn sel_consume_word(css []u16, start int) int {
	mut next := start
	for {
		code := if next < css.len { int(css[next]) } else { -1 }
		if sel_word_delimiter(code) {
			return next - 1
		} else if code == `\\` {
			next = sel_consume_escape(css, next) + 1
		} else {
			next++
		}
		if next >= css.len {
			break
		}
	}
	return next - 1
}

fn sel_index_of(css []u16, s string, from int) int {
	u := units(s)
	mut i := if from < 0 { 0 } else { from }
	for i + u.len <= css.len {
		if css[i..i + u.len] == u {
			return i
		}
		i++
	}
	return -1
}

fn sel_tokenize(css []u16) ![]SelToken {
	mut tokens := []SelToken{}
	length := css.len
	mut offset := -1
	mut line := 1
	mut start := 0
	mut end := 0
	mut next := 0
	mut end_line := 0
	mut end_column := 0
	mut next_offset := 0
	mut has_next_offset := false
	mut token_type := 0
	for start < length {
		mut code := int(css[start])
		if code == `\n` {
			offset = start
			line++
		}
		if cls(code, ' \t\n\r\x0c') {
			next = start
			for {
				next++
				code = if next < length { int(css[next]) } else { -1 }
				if code == `\n` {
					offset = next
					line++
				}
				if !cls(code, ' \n\t\r\x0c') {
					break
				}
			}
			token_type = ` `
			end_line = line
			end_column = next - offset - 1
			end = next
		} else if cls(code, '+>~|') {
			next = start
			for {
				next++
				code = if next < length { int(css[next]) } else { -1 }
				if !cls(code, '+>~|') {
					break
				}
			}
			token_type = st_combinator
			end_line = line
			end_column = start - offset
			end = next
		} else if cls(code, '*&!,=$^[]:;()') {
			next = start
			token_type = code
			end_line = line
			end_column = start - offset
			end = next + 1
		} else if code == `'` || code == `"` {
			quote := u16(code)
			next = start
			for {
				mut escaped := false
				next = sel_next_quote(css, quote, next)
				if next == -1 {
					return error('Unclosed quote')
				}
				mut escape_pos := next
				for escape_pos - 1 >= 0 && css[escape_pos - 1] == `\\` {
					escape_pos--
					escaped = !escaped
				}
				if !escaped {
					break
				}
			}
			token_type = `'`
			end_line = line
			end_column = start - offset
			end = next + 1
		} else {
			if code == `/` && start + 1 < length && css[start + 1] == `*` {
				next = sel_index_of(css, '*/', start + 2) + 1
				if next == 0 {
					return error('Unclosed comment')
				}
				content := css[start..next + 1]
				mut newlines := 0
				mut last_line_len := 0
				for u in content {
					if u == `\n` {
						newlines++
						last_line_len = 0
					} else {
						last_line_len++
					}
				}
				mut next_line := line
				if newlines > 0 {
					next_line = line + newlines
					next_offset = next - last_line_len
					has_next_offset = true
				} else {
					next_offset = offset
					has_next_offset = true
				}
				token_type = st_comment
				line = next_line
				end_line = next_line
				end_column = next - next_offset
			} else if code == `/` {
				next = start
				token_type = code
				end_line = line
				end_column = start - offset
			} else {
				next = sel_consume_word(css, start)
				token_type = st_word
				end_line = line
				end_column = next - offset
			}
			end = next + 1
		}
		tokens << SelToken{
			typ:        token_type
			line:       line
			column:     start - offset
			end_line:   end_line
			end_column: end_column
			start:      start
			end:        end
		}
		// JavaScript's `if (nextOffset)`: 0 is false.
		if has_next_offset {
			if next_offset != 0 {
				offset = next_offset
			}
			has_next_offset = false
		}
		start = end
	}
	return tokens
}

// sel_next_quote is css.indexOf(quote, from + 1).
fn sel_next_quote(css []u16, quote u16, from int) int {
	for i in from + 1 .. css.len {
		if css[i] == quote {
			return i
		}
	}
	return -1
}

struct SelParser {
	css    []u16
	tokens []SelToken
mut:
	nodes    []SelNode
	position int
	current  int
	spaces   string
	depth    int
}

// parse_selector is postcss-selector-parser's `processor.astSync(selector)` on a string.
pub fn parse_selector(selector string) !SelectorRoot {
	css := units(selector)
	tokens := sel_tokenize(css)!
	mut p := SelParser{
		css:    css
		tokens: tokens
	}
	mut root := SelNode{
		typ: .root
	}
	if tokens.len > 0 {
		root.has_start = true
		root.start_line = tokens[0].line
		root.start_column = tokens[0].column
		root.has_end = true
		root.end_line = tokens.last().end_line
		root.end_column = tokens.last().end_column
	}
	p.nodes << root
	p.nodes << SelNode{
		typ:          .selector
		parent:       0
		has_start:    true
		start_line:   1
		start_column: 1
	}
	p.nodes[0].nodes << 1
	p.current = 1
	for p.position < p.tokens.len {
		p.parse(true)!
	}
	p.flush_pending_spaces()
	p.infer_end_position(p.current)
	return SelectorRoot{
		nodes: p.nodes
	}
}

fn (p &SelParser) curr() ?SelToken {
	return if p.position < p.tokens.len { p.tokens[p.position] } else { none }
}

fn (p &SelParser) next_token() ?SelToken {
	return if p.position + 1 < p.tokens.len { p.tokens[p.position + 1] } else { none }
}

fn (p &SelParser) prev_token() ?SelToken {
	return if p.position - 1 >= 0 && p.position - 1 < p.tokens.len {
		p.tokens[p.position - 1]
	} else {
		none
	}
}

fn (p &SelParser) content(t SelToken) string {
	return text(p.css[t.start..t.end])
}

fn (p &SelParser) last_of(container int) int {
	kids := p.nodes[container].nodes
	return if kids.len > 0 { kids.last() } else { -1 }
}

fn (mut p SelParser) append(container int, node SelNode) int {
	mut n := node
	n.parent = container
	p.nodes << n
	idx := p.nodes.len - 1
	p.nodes[container].nodes << idx
	return idx
}

fn (mut p SelParser) new_node(node SelNode) int {
	p.spaces = ''
	return p.append(p.current, node)
}

fn token_node(typ SelType, value string, t SelToken) SelNode {
	return SelNode{
		typ:          typ
		value:        value
		has_start:    true
		start_line:   t.line
		start_column: t.column
		has_end:      true
		end_line:     t.end_line
		end_column:   t.end_column
	}
}

fn (mut p SelParser) infer_end_position(container int) {
	last := p.last_of(container)
	if last >= 0 && p.nodes[last].has_end {
		p.nodes[container].has_end = true
		p.nodes[container].end_line = p.nodes[last].end_line
		p.nodes[container].end_column = p.nodes[last].end_column
	}
}

fn (mut p SelParser) parse(throw_on_parenthesis bool) ! {
	t := p.curr() or { return error('TypeError') }
	c := t.typ
	if c == int(` `) {
		p.space()!
	} else if c == st_comment {
		p.new_node(token_node(.comment, p.content(t), t))
		p.position++
	} else if c == int(`(`) {
		p.parentheses()!
	} else if c == int(`)`) {
		if throw_on_parenthesis {
			return error('Expected an opening parenthesis.')
		}
	} else if c == int(`[`) {
		p.attribute()!
	} else if c in [int(`$`), int(`^`), int(`=`), st_word] {
		p.word()!
	} else if c == int(`:`) {
		p.pseudo()!
	} else if c == int(`,`) {
		p.comma()
	} else if c == int(`*`) {
		p.universal()!
	} else if c == int(`&`) {
		p.nesting()
	} else if c == int(`/`) || c == st_combinator {
		p.combinator()!
	} else if c == int(`'`) {
		p.new_node(token_node(.str, p.content(t), t))
		p.position++
	} else if c == int(`]`) {
		return error('Expected an opening square bracket.')
	} else if c == int(`;`) {
		return error('Expected a backslash preceding the semicolon.')
	} else {
		return error("Unexpected '${p.content(t)}'. Escaping special characters with \\ may help.")
	}
}

fn (mut p SelParser) current_has_only_comments() bool {
	for k in p.nodes[p.current].nodes {
		if p.nodes[k].typ != .comment {
			return false
		}
	}
	return true
}

fn (mut p SelParser) space() ! {
	t := p.curr() or { return }
	content := p.content(t)
	prev := p.prev_token()
	next := p.next_token()
	if p.position == 0 || (prev or { SelToken{} }).typ in [int(`,`), int(`(`)]
		|| p.current_has_only_comments() {
		p.spaces = content
		p.position++
	} else if p.position == p.tokens.len - 1 || (next or { SelToken{} }).typ in [
		int(`,`),
		int(`)`),
	] {
		p.position++
	} else {
		p.combinator()!
	}
}

fn (p &SelParser) locate_next_meaningful_token(start_position int) int {
	mut search := start_position
	for search < p.tokens.len {
		if p.tokens[search].typ == ` ` || p.tokens[search].typ == st_comment {
			search++
			continue
		}
		return search
	}
	return -1
}

// parse_whitespace_equivalent_tokens is parseWhitespaceEquivalentTokens: the comments (and a
// string for spaces without them) up to `stop`.
fn (mut p SelParser) parse_whitespace_equivalent_tokens(stop_in int) []SelNode {
	stop := if stop_in < 0 { p.tokens.len } else { stop_in }
	start_position := p.position
	mut nodes := []SelNode{}
	mut space := ''
	mut last_comment := false
	for {
		t := p.tokens[p.position]
		if t.typ == ` ` {
			space += p.content(t)
		} else if t.typ == st_comment {
			space = ''
			nodes << token_node(.comment, p.content(t), t)
			last_comment = true
		}
		p.position++
		if p.position >= stop {
			break
		}
	}
	if space != '' && !last_comment {
		first := p.tokens[start_position]
		last := p.tokens[p.position - 1]
		nodes << SelNode{
			typ:          .str
			value:        ''
			has_start:    true
			start_line:   first.line
			start_column: first.column
			has_end:      true
			end_line:     last.end_line
			end_column:   last.end_column
		}
	}
	return nodes
}

fn (p &SelParser) is_named_combinator(position int) bool {
	return position + 2 < p.tokens.len && p.tokens[position].typ == `/`
		&& p.tokens[position + 1].typ == st_word && p.tokens[position + 2].typ == `/`
}

fn (mut p SelParser) combinator() ! {
	t := p.curr() or { return error('TypeError') }
	if p.content(t) == '|' {
		return p.namespace()
	}
	next_sig := p.locate_next_meaningful_token(p.position)
	if next_sig < 0 || p.tokens[next_sig].typ == `,` || p.tokens[next_sig].typ == `)` {
		nodes := p.parse_whitespace_equivalent_tokens(next_sig)
		if nodes.len > 0 && p.last_of(p.current) < 0 {
			for n in nodes {
				p.new_node(n)
			}
		}
		return
	}
	first := t
	mut space_nodes := false
	if next_sig > p.position {
		p.parse_whitespace_equivalent_tokens(next_sig)
		space_nodes = true
	}
	mut node := SelNode{}
	mut has_node := false
	if p.is_named_combinator(p.position) {
		a := p.tokens[p.position]
		b := p.tokens[p.position + 2]
		name := sel_unesc(p.content(p.tokens[p.position + 1])).to_lower()
		node = SelNode{
			typ:          .combinator
			value:        '/${name}/'
			has_start:    true
			start_line:   a.line
			start_column: a.column
			has_end:      true
			end_line:     b.end_line
			end_column:   b.end_column
		}
		has_node = true
		p.position += 3
	} else if cur := p.curr() {
		if cur.typ == st_combinator {
			node = token_node(.combinator, p.content(cur), cur)
			has_node = true
			p.position++
		} else if cur.typ == ` ` {
			// a descendant combinator
		} else if !space_nodes {
			return error("Unexpected '${p.content(cur)}'. Escaping special characters with \\ may help.")
		}
	} else if p.is_named_combinator(p.position) {
		has_node = true
	}
	if !has_node {
		last := p.tokens[p.position - 1]
		node = SelNode{
			typ:          .combinator
			value:        ' '
			has_start:    true
			start_line:   first.line
			start_column: first.column
			has_end:      true
			end_line:     last.end_line
			end_column:   last.end_column
		}
	}
	if cur := p.curr() {
		if cur.typ == ` ` {
			p.position++
		}
	}
	p.new_node(node)
}

fn (mut p SelParser) flush_pending_spaces() {
	if p.spaces == '' {
		return
	}
	if p.last_of(p.current) >= 0 {
		p.spaces = ''
		return
	}
	mut node := SelNode{
		typ: .str
	}
	if t := p.curr() {
		node = token_node(.str, '', t)
	} else if t := p.prev_token() {
		node = token_node(.str, '', t)
	}
	p.new_node(node)
}

fn (mut p SelParser) comma() {
	p.flush_pending_spaces()
	if p.position == p.tokens.len - 1 {
		p.position++
		return
	}
	p.infer_end_position(p.current)
	n := p.tokens[p.position + 1]
	sel := p.append(p.nodes[p.current].parent, SelNode{
		typ:          .selector
		has_start:    true
		start_line:   n.line
		start_column: n.column
	})
	p.current = sel
	p.position++
}

fn (mut p SelParser) namespace() ! {
	next := p.next_token() or { return error("Unexpected '|'.") }
	if next.typ == st_word {
		p.position++
		return p.word()
	} else if next.typ == `*` {
		p.position++
		return p.universal()
	}
	return error("Unexpected '|'.")
}

fn (mut p SelParser) nesting() {
	if next := p.next_token() {
		if p.content(next) == '|' {
			p.position++
			return
		}
	}
	t := p.tokens[p.position]
	p.new_node(token_node(.nesting, p.content(t), t))
	p.position++
}

fn (mut p SelParser) universal() ! {
	if next := p.next_token() {
		if p.content(next) == '|' {
			p.position++
			return p.namespace()
		}
	}
	t := p.tokens[p.position]
	p.new_node(token_node(.universal, p.content(t), t))
	p.position++
}

fn (mut p SelParser) attribute() ! {
	starting := p.tokens[p.position]
	p.position++
	for p.position < p.tokens.len && p.tokens[p.position].typ != `]` {
		p.position++
	}
	cur := p.curr() or { return error('Expected a closing square bracket.') }
	if p.position - starting_index(p, starting) == 2 && p.tokens[p.position - 1].typ != st_word {
		return error('Expected an attribute.')
	}
	p.new_node(SelNode{
		typ:          .attribute
		value:        text(p.css[starting.start..cur.end])
		has_start:    true
		start_line:   starting.line
		start_column: starting.column
		has_end:      true
		end_line:     cur.end_line
		end_column:   cur.end_column
	})
	p.position++
}

fn starting_index(p &SelParser, t SelToken) int {
	for i, x in p.tokens {
		if x.start == t.start {
			return i
		}
	}
	return 0
}

fn (mut p SelParser) parentheses() ! {
	last := p.last_of(p.current)
	mut unbalanced := 1
	opening := p.tokens[p.position]
	p.position++
	if last >= 0 && p.nodes[last].typ == .pseudo {
		first := p.curr() or { return error('TypeError') }
		sel := p.append(last, SelNode{
			typ:          .selector
			has_start:    true
			start_line:   first.line
			start_column: first.column
		})
		cache := p.current
		p.current = sel
		p.depth++
		if p.depth > 256 {
			p.depth--
			return error('Cannot parse selector: nesting depth exceeds the maximum of 256.')
		}
		for p.position < p.tokens.len && unbalanced > 0 {
			t := p.tokens[p.position]
			if t.typ == `(` {
				unbalanced++
			}
			if t.typ == `)` {
				unbalanced--
			}
			if unbalanced > 0 {
				p.parse(false) or {
					p.depth--
					return err
				}
			} else {
				p.flush_pending_spaces()
				p.nodes[p.current].has_end = true
				p.nodes[p.current].end_line = t.end_line
				p.nodes[p.current].end_column = t.end_column
				parent := p.nodes[p.current].parent
				p.nodes[parent].has_end = true
				p.nodes[parent].end_line = t.end_line
				p.nodes[parent].end_column = t.end_column
				p.position++
			}
		}
		p.depth--
		p.current = cache
	} else {
		paren_start := opening
		mut paren_value := '('
		mut paren_end := opening
		for {
			for p.position < p.tokens.len && unbalanced > 0 {
				t := p.tokens[p.position]
				if t.typ == `(` {
					unbalanced++
				}
				if t.typ == `)` {
					unbalanced--
				}
				paren_end = t
				paren_value += p.content(t)
				p.position++
			}
			cur := p.curr() or { break }
			if unbalanced > 0 || last < 0 || cur.typ != `(` {
				break
			}
			paren_value += '('
			unbalanced = 1
			p.position++
		}
		if last >= 0 {
			p.nodes[last].value += paren_value
		} else {
			p.new_node(SelNode{
				typ:          .str
				value:        paren_value
				has_start:    true
				start_line:   paren_start.line
				start_column: paren_start.column
				has_end:      true
				end_line:     paren_end.end_line
				end_column:   paren_end.end_column
			})
		}
	}
	if unbalanced > 0 {
		return error('Expected a closing parenthesis.')
	}
}

fn (mut p SelParser) pseudo() ! {
	mut pseudo_str := ''
	starting := p.tokens[p.position]
	for {
		t := p.curr() or { break }
		if t.typ != `:` {
			break
		}
		pseudo_str += p.content(t)
		p.position++
	}
	t := p.curr() or { return error('Expected a pseudo-class or pseudo-element.') }
	if t.typ != st_word {
		return error('Expected a pseudo-class or pseudo-element.')
	}
	p.split_word(true, pseudo_str, starting)!
}

fn sel_is_escaped(word []u16, index int) bool {
	mut escape_start := index
	for escape_start - 1 >= 0 && word[escape_start - 1] == `\\` {
		escape_start--
	}
	return (index - escape_start) % 2 == 1
}

// is_keyframes_percent is /^\d+\.\d+%$/.
fn is_keyframes_percent(w []u16) bool {
	mut i := 0
	for i < w.len && w[i] >= `0` && w[i] <= `9` {
		i++
	}
	if i == 0 || i >= w.len || w[i] != `.` {
		return false
	}
	i++
	start := i
	for i < w.len && w[i] >= `0` && w[i] <= `9` {
		i++
	}
	return i > start && i == w.len - 1 && w[i] == `%`
}

fn (mut p SelParser) word() ! {
	if next := p.next_token() {
		if p.content(next) == '|' {
			p.position++
			return p.namespace()
		}
	}
	p.split_word(false, '', SelToken{})!
}

// split_word is splitWord; with `pseudo`, the first part is the pseudo node (firstCallback of
// pseudo()), starting at `starting`.
fn (mut p SelParser) split_word(pseudo bool, pseudo_str string, starting SelToken) ! {
	mut word := units(p.content(p.tokens[p.position]))
	for {
		next := p.next_token() or { break }
		if next.typ !in [int(`$`), int(`^`), int(`=`), st_word] {
			break
		}
		p.position++
		current := units(p.content(p.tokens[p.position]))
		word << current
		if current.len > 0 && current.last() == `\\` {
			if n := p.next_token() {
				if n.typ == ` ` {
					word << units(p.content(n))
					p.position++
				}
			}
		}
	}
	mut has_class := []int{}
	if !is_keyframes_percent(word) {
		for i, u in word {
			if u == `.` && !sel_is_escaped(word, i) {
				has_class << i
			}
		}
	}
	mut has_id := []int{}
	for i, u in word {
		if u == `#` && !sel_is_escaped(word, i) && !(i + 1 < word.len && word[i + 1] == `{`) {
			has_id << i
		}
	}
	mut indices := [0]
	for i in has_class {
		if i !in indices {
			indices << i
		}
	}
	for i in has_id {
		if i !in indices {
			indices << i
		}
	}
	indices.sort()
	for i, ind in indices {
		index := if i + 1 < indices.len && indices[i + 1] != 0 { indices[i + 1] } else { word.len }
		value := word[ind..index].clone()
		current := p.tokens[p.position]
		if i == 0 && pseudo {
			mut node := SelNode{
				typ:          .pseudo
				value:        pseudo_str + text(value)
				has_start:    true
				start_line:   starting.line
				start_column: starting.column
				has_end:      true
				end_line:     current.end_line
				end_column:   current.end_column
			}
			p.new_node(node)
			if indices.len > 1 {
				if next := p.next_token() {
					if next.typ == `(` {
						return error('Misplaced parenthesis.')
					}
				}
			}
			continue
		}
		mut typ := SelType.tag
		mut v := value.clone()
		if ind in has_class {
			typ = .class
			v = value[1..].clone()
		} else if ind in has_id {
			typ = .id
			v = value[1..].clone()
		}
		p.new_node(SelNode{
			typ:          typ
			value:        sel_unesc(text(v))
			has_start:    true
			start_line:   current.line
			start_column: current.column + ind
			has_end:      true
			end_line:     current.end_line
			end_column:   current.column + (index - 1)
		})
	}
	p.position++
}

// sel_unesc is util/unesc.js.
pub fn sel_unesc(s string) string {
	if !s.contains('\\') {
		return s
	}
	str := units(s)
	mut ret := []u16{}
	mut i := 0
	for i < str.len {
		if str[i] == `\\` {
			end := if i + 9 < str.len { i + 9 } else { str.len }
			if g, consumed := sel_gobble_hex(str[i + 1..end]) {
				ret << units(g)
				i += consumed + 1
				continue
			}
			if i + 1 < str.len && str[i + 1] == `\\` {
				ret << `\\`
				i += 2
				continue
			}
			if str.len == i + 1 {
				ret << str[i]
			}
			i++
			continue
		}
		ret << str[i]
		i++
	}
	return text(ret)
}

fn sel_gobble_hex(s []u16) ?(string, int) {
	mut hex := []u8{}
	for i := 0; i < 6 && i < s.len; i++ {
		mut code := s[i]
		if code >= `A` && code <= `Z` {
			code += 32
		}
		if !((code >= `a` && code <= `f`) || (code >= `0` && code <= `9`)) {
			break
		}
		hex << u8(code)
	}
	if hex.len == 0 {
		return none
	}
	mut consumed := hex.len
	if consumed < s.len {
		next := s[consumed]
		if cls(int(next), ' \t\n\r\x0c') {
			consumed += if next == `\r` && consumed + 1 < s.len && s[consumed + 1] == `\n` {
				2
			} else {
				1
			}
		}
	}
	cp := u32(hex.bytestr().parse_uint(16, 32) or { 0 })
	if (cp >= 0xD800 && cp <= 0xDFFF) || cp == 0 || cp > 0x10FFFF {
		return '�', consumed
	}
	return rune(cp).str(), consumed
}
