module postcss

// The parsers: postcss's lib/parser.js, postcss-safe-parser's SafeParser (`safe`: it never
// throws a CssSyntaxError), eslint-plugin-svelte's TemplateSafeParser (`safe` with the template
// tokenizer) and postcss-scss's ScssParser (`syntax: .scss`).

pub enum NodeType {
	root
	rule
	atrule
	decl
	comment
}

// Node is a node of the tree (Root.nodes[0] is the root): the fields of its type, its `source`
// (start, and end when has_end) and the raws the parsers read back.
pub struct Node {
pub mut:
	typ       NodeType
	parent    int = -1
	nodes     []int
	has_nodes bool // `node.nodes` is defined
	start     Position
	end       Position
	has_end   bool
	// decl: prop, value, important (nested: postcss-scss's NestedDeclaration, with nodes)
	prop      string
	value     string
	important bool
	nested    bool
	// rule: selector; atrule: name, params; comment: text
	selector string
	name     string
	params   string
	text     string
	// raws
	before        string
	between       string
	after         string
	own_semicolon string
	semicolon     bool
	// raws[prop] (value, selector or params): {raw, value} when the value is not clean
	has_raw bool
	raw     string
}

// Root is the result of a parse.
pub struct Root {
pub mut:
	nodes []Node
	input Input
}

pub struct ParseOptions {
pub:
	syntax   Syntax
	safe     bool
	template bool
	from     string
}

struct Parser {
	safe   bool
	syntax Syntax
mut:
	input     &Input = unsafe { nil }
	tok       Tokenizer
	nodes     []Node
	current   int
	spaces    string
	semicolon bool
}

// parse is postcss.parse(css, {from}) and the other parsers (see ParseOptions).
pub fn parse(css []u16, opts ParseOptions) !Root {
	mut root := Root{
		input: new_input(css, opts.from)
	}
	mut p := &Parser{
		safe:   opts.safe
		syntax: opts.syntax
		input:  &root.input
	}
	p.tok = new_tokenizer(p.input, opts.syntax, opts.safe, opts.template)
	p.nodes << Node{
		typ:       .root
		has_nodes: true
		start:     Position{
			offset: 0
			line:   1
			column: 1
		}
	}
	p.parse()!
	root.nodes = p.nodes
	return root
}

fn (mut p Parser) parse() ! {
	for !p.tok.end_of_file() {
		token := p.tok.next_token(false)!
		match token.typ {
			'space' { p.spaces += token.text }
			';' { p.free_semicolon(token) }
			'}' { p.end(token)! }
			'comment' { p.comment(token) }
			'at-word' { p.atrule(token)! }
			'{' { p.empty_rule(token) }
			else { p.other(token)! }
		}
	}
	p.end_file()!
}

fn (mut p Parser) new_node(typ NodeType) int {
	p.nodes << Node{
		typ:       typ
		has_nodes: typ == .rule
	}
	return p.nodes.len - 1
}

fn (mut p Parser) init(node int, offset int) {
	p.nodes[node].parent = p.current
	p.nodes[p.current].nodes << node
	p.nodes[node].start = p.input.position(offset)
	p.nodes[node].before = p.spaces
	p.spaces = ''
	if p.nodes[node].typ != .comment {
		p.semicolon = false
	}
}

fn (mut p Parser) set_end(node int, offset int, plus_one bool) {
	mut pos := p.input.position(offset)
	if plus_one {
		pos.offset++
	}
	p.nodes[node].end = pos
	p.nodes[node].has_end = true
}

fn tokens_to_string(tokens []Token, from int, to int) string {
	mut out := []string{}
	for i in from .. to {
		out << tokens[i].text
	}
	return out.join('')
}

fn find_last_with_position(tokens []Token) int {
	for i := tokens.len - 1; i >= 0; i-- {
		pos := or_pos(tokens[i].end, tokens[i].start)
		if pos > 0 {
			return pos
		}
	}
	return -1
}

fn (mut p Parser) atrule(token_in Token) ! {
	mut token := token_in
	if p.syntax == .scss {
		// ScssParser.atrule: the words right after the at-word are part of its name.
		mut name := token.text
		mut prev := token
		for !p.tok.end_of_file() {
			next := p.tok.next_token(false)!
			if next.typ == 'word' && next.start == prev.end + 1 {
				name += next.text
				prev = next
			} else {
				p.tok.back(next)
				break
			}
		}
		token = Token{
			typ:   'at-word'
			text:  name
			start: token.start
			end:   prev.end
		}
	}
	node := p.new_node(.atrule)
	p.nodes[node].name = text(units(token.text)[1..])
	if p.nodes[node].name == '' {
		if !p.safe {
			return p.input.error_at('At-rule without name', token.start)
		}
		p.nodes[node].name = ''
	}
	p.init(node, token.start)
	mut last := false
	mut open := false
	mut params := []Token{}
	mut brackets := []string{}
	for !p.tok.end_of_file() {
		token = p.tok.next_token(false)!
		typ := token.typ
		if typ == '(' || typ == '[' {
			brackets << if typ == '(' { ')' } else { ']' }
		} else if typ == '{' && brackets.len > 0 {
			brackets << '}'
		} else if brackets.len > 0 && typ == brackets.last() {
			brackets.pop()
		}
		if brackets.len == 0 {
			if typ == ';' {
				p.set_end(node, token.start, true)
				p.semicolon = true
				break
			} else if typ == '{' {
				open = true
				break
			} else if typ == '}' {
				if params.len > 0 {
					mut shift := params.len - 1
					mut prev := params[shift]
					mut found := true
					for prev.typ == 'space' {
						shift--
						if shift < 0 {
							found = false
							break
						}
						prev = params[shift]
					}
					if found {
						p.set_end(node, or_pos(prev.end, prev.start), true)
					}
				}
				p.end(token)!
				break
			} else {
				params << token
			}
		} else {
			params << token
		}
		if p.tok.end_of_file() {
			last = true
			break
		}
	}
	p.nodes[node].between = spaces_and_comments_from_end(mut params)
	if params.len > 0 {
		spaces_and_comments_from_start(mut params)
		p.raw(node, 'params', params, false)
		if last {
			token = params.last()
			p.set_end(node, or_pos(token.end, token.start), true)
			p.spaces = p.nodes[node].between
			p.nodes[node].between = ''
		}
	} else {
		p.nodes[node].params = ''
	}
	if open {
		p.nodes[node].has_nodes = true
		p.current = node
	}
}

fn (mut p Parser) check_missed_semicolon(tokens []Token) ! {
	if p.safe {
		return
	}
	colon := p.colon(tokens)!
	if colon < 0 {
		return
	}
	mut founded := 0
	mut token := Token{}
	for j := colon - 1; j >= 0; j-- {
		token = tokens[j]
		if token.typ != 'space' {
			founded++
			if founded == 2 {
				break
			}
		}
	}
	return p.input.error_at('Missed semicolon', if token.typ == 'word' {
		token.end + 1
	} else {
		token.start
	})
}

// colon is the index of the declaration's colon, or -1.
fn (mut p Parser) colon(tokens []Token) !int {
	mut brackets := 0
	mut prev := Token{}
	for i, token in tokens {
		typ := token.typ
		if typ == '(' {
			brackets++
		}
		if typ == ')' {
			brackets--
		}
		if brackets == 0 && typ == ':' {
			if prev.is_none() {
				if !p.safe {
					return p.input.error_at('Double colon', token.start)
				}
			} else if prev.typ == 'word' && prev.text == 'progid' {
				continue
			} else {
				return i
			}
		}
		prev = token
	}
	return -1
}

fn (mut p Parser) comment(token Token) {
	node := p.new_node(.comment)
	p.init(node, token.start)
	if p.safe || (p.syntax == .scss && token.inline) {
		line, column := p.input.from_offset(token.end)
		p.nodes[node].end = Position{
			offset: token.end + 1
			line:   line
			column: column
		}
		p.nodes[node].has_end = true
		mut t := units(token.text)[2..].clone()
		if !token.inline && t.len >= 2 && t[t.len - 2] == `*` && t[t.len - 1] == `/` {
			t = t[..t.len - 2].clone()
		}
		p.nodes[node].text = js_trim(text(t))
		return
	}
	p.set_end(node, or_pos(token.end, token.start), true)
	u := units(token.text)
	p.nodes[node].text = js_trim(text(u[2..u.len - 2]))
}

// js_trim is String.prototype.trim.
pub fn js_trim(s string) string {
	u := units(s)
	mut a := 0
	mut b := u.len
	for a < b && is_js_space(u[a]) {
		a++
	}
	for b > a && is_js_space(u[b - 1]) {
		b--
	}
	return text(u[a..b])
}

// is_js_space is JavaScript's WhiteSpace or LineTerminator (`\s`).
pub fn is_js_space(c u16) bool {
	return c in [u16(9), 10, 11, 12, 13, 32, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
		0xFEFF] || (c >= 0x2000 && c <= 0x200A)
}

fn (mut p Parser) decl(tokens_in []Token, custom_property_in bool) ! {
	mut custom_property := custom_property_in
	mut tokens := tokens_in.clone()
	if p.safe {
		// SafeParser.decl(tokens): only with a word, and without customProperty.
		if !(tokens.len > 1 && tokens.any(it.typ == 'word')) {
			return
		}
		custom_property = false
	}
	node := p.new_node(.decl)
	p.init(node, tokens[0].start)
	last := tokens.last()
	if last.typ == ';' {
		p.semicolon = true
		tokens.pop()
	}
	p.set_end(node, or_pos(last.end, or_pos(last.start, find_last_with_position(tokens))),
		true)
	mut start := 0
	for tokens[start].typ != 'word' {
		if start == tokens.len - 1 {
			p.unknown_word([tokens[start]])!
		}
		start++
		if start >= tokens.len {
			// JavaScript reads tokens[start][0] of undefined: a TypeError.
			return error('TypeError')
		}
	}
	p.nodes[node].before += tokens_to_string(tokens, 0, start)
	p.nodes[node].start = p.input.position(tokens[start].start)
	prop_start := start
	for start < tokens.len {
		typ := tokens[start].typ
		if typ == ':' || typ == 'space' || typ == 'comment' {
			break
		}
		start++
	}
	p.nodes[node].prop = tokens_to_string(tokens, prop_start, start)
	between_start := start
	for start < tokens.len {
		token := tokens[start]
		start++
		if token.typ == ':' {
			break
		}
		if token.typ == 'word' && has_word_char(token.text) {
			p.unknown_word([token])!
		}
	}
	p.nodes[node].between = tokens_to_string(tokens, between_start, start)
	prop := p.nodes[node].prop
	if prop.len > 0 && (prop[0] == `_` || prop[0] == `*`) {
		p.nodes[node].before += prop[..1]
		p.nodes[node].prop = prop[1..]
	}
	first_spaces_start := start
	for start < tokens.len {
		next := tokens[start].typ
		if next != 'space' && next != 'comment' {
			break
		}
		start++
	}
	mut first_spaces := tokens[first_spaces_start..start].clone()
	tokens = tokens[start..].clone()
	p.precheck_missed_semicolon(mut tokens)!
	for i := tokens.len - 1; i >= 0; i-- {
		token := tokens[i]
		lower := token.text.to_lower()
		if lower == '!important' {
			p.nodes[node].important = true
			mut s := string_from(mut tokens, i)
			s = spaces_from_end(mut tokens) + s
			break
		} else if lower == 'important' {
			mut cache := tokens.clone()
			mut str := ''
			for j := i; j > 0; j-- {
				typ := cache[j].typ
				if js_trim(str).starts_with('!') && typ != 'space' {
					break
				}
				str = cache.pop().text + str
			}
			if js_trim(str).starts_with('!') {
				p.nodes[node].important = true
				tokens = cache.clone()
			}
		}
		if token.typ != 'space' && token.typ != 'comment' {
			break
		}
	}
	has_word := tokens.any(it.typ != 'space' && it.typ != 'comment')
	if has_word {
		p.nodes[node].between += tokens_to_string(first_spaces, 0, first_spaces.len)
		first_spaces = []
	}
	mut value_tokens := first_spaces.clone()
	value_tokens << tokens
	p.raw(node, 'value', value_tokens, custom_property)
	if p.nodes[node].value.contains(':') && !custom_property {
		p.check_missed_semicolon(tokens)!
	}
}

// has_word_char is /\w/.test(s).
fn has_word_char(s string) bool {
	for c in s {
		if c.is_letter() || c.is_digit() || c == `_` {
			return true
		}
	}
	return false
}

fn (mut p Parser) empty_rule(token Token) {
	node := p.new_node(.rule)
	p.init(node, token.start)
	p.nodes[node].selector = ''
	p.nodes[node].between = ''
	p.current = node
}

fn (mut p Parser) end(token Token) ! {
	cur := p.current
	if p.nodes[cur].nodes.len > 0 {
		p.nodes[cur].semicolon = p.semicolon
	}
	p.semicolon = false
	p.nodes[cur].after += p.spaces
	p.spaces = ''
	if p.nodes[cur].parent >= 0 {
		p.set_end(cur, token.start, true)
		p.current = p.nodes[cur].parent
	} else {
		if !p.safe {
			return p.input.error_at('Unexpected }', token.start)
		}
		p.nodes[cur].after += '}'
	}
}

fn (mut p Parser) end_file() ! {
	if p.safe {
		if p.nodes[p.current].nodes.len > 0 {
			p.nodes[p.current].semicolon = p.semicolon
		}
		p.nodes[p.current].after += p.spaces
		for p.nodes[p.current].parent >= 0 {
			p.current = p.nodes[p.current].parent
			p.nodes[p.current].after = ''
		}
	} else {
		if p.nodes[p.current].parent >= 0 {
			pos := p.nodes[p.current].start
			return p.input.error_line('Unclosed block', pos.line, pos.column)
		}
		if p.nodes[p.current].nodes.len > 0 {
			p.nodes[p.current].semicolon = p.semicolon
		}
		p.nodes[p.current].after += p.spaces
	}
	p.set_end(0, p.tok.position(), false)
}

fn (mut p Parser) free_semicolon(token Token) {
	p.spaces += token.text
	if p.nodes[p.current].has_nodes {
		kids := p.nodes[p.current].nodes
		if kids.len > 0 {
			prev := kids.last()
			if p.nodes[prev].typ == .rule && p.nodes[prev].own_semicolon == '' {
				p.nodes[prev].own_semicolon = p.spaces
				p.spaces = ''
				p.set_end(prev, token.start, true)
			}
		}
	}
}

fn (mut p Parser) other(start Token) ! {
	mut end := false
	mut colon := false
	mut bracket := Token{}
	mut brackets := []string{}
	custom_property := start.text.starts_with('--')
	mut tokens := []Token{}
	mut token := start
	for !token.is_none() {
		typ := token.typ
		tokens << token
		if typ == '(' || typ == '[' {
			if bracket.is_none() {
				bracket = token
			}
			brackets << if typ == '(' { ')' } else { ']' }
		} else if custom_property && colon && typ == '{' {
			if bracket.is_none() {
				bracket = token
			}
			brackets << '}'
		} else if brackets.len == 0 {
			if typ == ';' {
				if colon {
					p.decl(tokens, custom_property)!
					return
				} else {
					break
				}
			} else if typ == '{' {
				p.rule(mut tokens)!
				return
			} else if typ == '}' {
				p.tok.back(tokens.pop())
				end = true
				break
			} else if typ == ':' {
				colon = true
			}
		} else if typ == brackets.last() {
			brackets.pop()
			if brackets.len == 0 {
				bracket = Token{}
			}
		}
		token = p.tok.next_token(false)!
	}
	if p.tok.end_of_file() {
		end = true
	}
	if brackets.len > 0 && !p.safe {
		return p.input.error_at('Unclosed bracket', bracket.start)
	}
	if end && colon {
		if !custom_property {
			for tokens.len > 0 {
				typ := tokens.last().typ
				if typ != 'space' && typ != 'comment' {
					break
				}
				p.tok.back(tokens.pop())
			}
		}
		p.decl(tokens, custom_property)!
	} else {
		p.unknown_word(tokens)!
	}
}

fn (mut p Parser) precheck_missed_semicolon(mut tokens []Token) ! {
	if !p.safe {
		return
	}
	colon := p.colon(tokens)!
	if colon < 0 {
		return
	}
	mut next_start := colon - 1
	for next_start >= 0 {
		if tokens[next_start].typ == 'word' {
			break
		}
		next_start--
	}
	if next_start <= 0 {
		return
	}
	mut prev_end := next_start - 1
	for prev_end >= 0 {
		if tokens[prev_end].typ != 'space' {
			prev_end++
			break
		}
		prev_end--
	}
	if prev_end < 0 {
		// JavaScript's slice(-1, …) and splice(-1, …) count from the end; tokens[0] is never a
		// space here (decl dropped the spaces before the value).
		prev_end = tokens.len - 1
	}
	other := tokens[next_start..].clone()
	spaces := tokens_to_string(tokens, prev_end, next_start)
	tokens.trim(prev_end)
	p.spaces = spaces
	p.decl(other, false)!
}

fn (mut p Parser) raw(node int, prop string, tokens []Token, custom_property bool) {
	mut value := []string{}
	mut last := ''
	mut clean := true
	for i, token in tokens {
		typ := token.typ
		if typ == 'space' && i == tokens.len - 1 && !custom_property {
			clean = false
		} else if typ == 'comment' {
			prev := if i > 0 { tokens[i - 1].typ } else { 'empty' }
			next := if i + 1 < tokens.len { tokens[i + 1].typ } else { 'empty' }
			if prev !in ['empty', 'space'] && next !in ['empty', 'space'] {
				if last == ',' {
					clean = false
				} else {
					value << token.text
					last = last_unit(token.text)
				}
			} else {
				clean = false
			}
		} else {
			value << token.text
			last = last_unit(token.text)
		}
	}
	v := value.join('')
	if !clean {
		p.nodes[node].has_raw = true
		p.nodes[node].raw = tokens_to_string(tokens, 0, tokens.len)
	}
	match prop {
		'value' { p.nodes[node].value = v }
		'selector' { p.nodes[node].selector = v }
		else { p.nodes[node].params = v }
	}
}

fn last_unit(s string) string {
	return if s.len > 0 { s[s.len - 1..] } else { '' }
}

fn (mut p Parser) rule(mut tokens []Token) ! {
	if p.syntax == .scss && !p.scss_rule(mut tokens)! {
		return
	}
	tokens.pop()
	node := p.new_node(.rule)
	p.init(node, tokens[0].start)
	p.nodes[node].between = spaces_and_comments_from_end(mut tokens)
	p.raw(node, 'selector', tokens, false)
	p.current = node
}

// scss_rule is ScssParser.rule up to `super.rule(tokens)` (true: go on as a rule) or a nested
// declaration (`a: b { … }`).
fn (mut p Parser) scss_rule(mut tokens []Token) !bool {
	mut with_colon := false
	mut brackets := 0
	mut value := ''
	for i in tokens {
		if with_colon {
			if i.typ != 'comment' && i.typ != '{' {
				value += i.text
			}
		} else if i.typ == 'space' && i.text.contains('\n') {
			break
		} else if i.typ == '(' {
			brackets++
		} else if i.typ == ')' {
			brackets--
		} else if brackets == 0 && i.typ == ':' {
			with_colon = true
		}
	}
	if !with_colon || js_trim(value) == '' || (value.len > 0 && (value[0] == `#` || value[0] == `:`
		|| value[0] == `-` || value[0].is_letter())) {
		return true
	}
	tokens.pop()
	node := p.new_node(.decl)
	p.nodes[node].nested = true
	p.nodes[node].has_nodes = true
	p.init(node, tokens[0].start)
	mut last := Token{}
	for i := tokens.len - 1; i >= 0; i-- {
		if tokens[i].typ != 'space' {
			last = tokens[i]
			break
		}
	}
	end_at := if last.end > 0 { last.end } else { last.start }
	line, column := p.input.from_offset(end_at)
	p.nodes[node].end = Position{
		offset: end_at + 1
		line:   line
		column: column
	}
	p.nodes[node].has_end = true
	for tokens[0].typ != 'word' {
		p.nodes[node].before += tokens[0].text
		tokens.delete(0)
	}
	if tokens[0].start > 0 {
		p.nodes[node].start = p.input.position(tokens[0].start)
	}
	mut prop := ''
	for tokens.len > 0 {
		typ := tokens[0].typ
		if typ == ':' || typ == 'space' || typ == 'comment' {
			break
		}
		prop += tokens[0].text
		tokens.delete(0)
	}
	mut between := ''
	for tokens.len > 0 {
		token := tokens[0]
		tokens.delete(0)
		between += token.text
		if token.typ == ':' {
			break
		}
	}
	if prop.len > 0 && (prop[0] == `_` || prop[0] == `*`) {
		p.nodes[node].before += prop[..1]
		prop = prop[1..]
	}
	p.nodes[node].prop = prop
	between += spaces_and_comments_from_start(mut tokens)
	p.nodes[node].between = between
	p.precheck_missed_semicolon(mut tokens)!
	for i := tokens.len - 1; i > 0; i-- {
		token := tokens[i]
		if token.text == '!important' {
			p.nodes[node].important = true
			mut s := string_from(mut tokens, i)
			s = spaces_from_end(mut tokens) + s
			break
		} else if token.text == 'important' {
			mut cache := tokens.clone()
			mut str := ''
			for j := i; j > 0; j-- {
				typ := cache[j].typ
				if js_trim(str).starts_with('!') && typ != 'space' {
					break
				}
				str = cache.pop().text + str
			}
			if js_trim(str).starts_with('!') {
				p.nodes[node].important = true
				tokens = cache.clone()
			}
		}
		if token.typ != 'space' && token.typ != 'comment' {
			break
		}
	}
	p.raw(node, 'value', tokens, false)
	if p.nodes[node].value.contains(':') {
		p.check_missed_semicolon(tokens)!
	}
	p.current = node
	return false
}

fn spaces_and_comments_from_end(mut tokens []Token) string {
	mut spaces := ''
	for tokens.len > 0 {
		typ := tokens.last().typ
		if typ != 'space' && typ != 'comment' {
			break
		}
		spaces = tokens.pop().text + spaces
	}
	return spaces
}

fn spaces_and_comments_from_start(mut tokens []Token) string {
	mut spaces := ''
	for tokens.len > 0 {
		typ := tokens[0].typ
		if typ != 'space' && typ != 'comment' {
			break
		}
		spaces += tokens[0].text
		tokens.delete(0)
	}
	return spaces
}

fn spaces_from_end(mut tokens []Token) string {
	mut spaces := ''
	for tokens.len > 0 {
		if tokens.last().typ != 'space' {
			break
		}
		spaces = tokens.pop().text + spaces
	}
	return spaces
}

fn string_from(mut tokens []Token, from int) string {
	result := tokens_to_string(tokens, from, tokens.len)
	tokens.trim(from)
	return result
}

fn (mut p Parser) unknown_word(tokens []Token) ! {
	if p.safe {
		p.spaces += tokens_to_string(tokens, 0, tokens.len)
		return
	}
	return p.input.error_at('Unknown word ${tokens[0].text}', tokens[0].start)
}
