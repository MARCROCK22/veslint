module esquery

import strings
import estree
import jsregexp

// The selector language of esquery 1.7.0 (the parser ESLint runs listener names through), ported
// by hand from its generated PEG.js parser rule by rule, with the same ordered choices and the same
// backtracking. The input is read in UTF-16 units, like JavaScript's charAt.

pub enum SelectorKind {
	empty // the empty selector (only spaces): esquery.parse gives undefined
	wildcard
	identifier
	exact_node // the node a relative selector of `:has` starts from
	field
	matches // also `:is` and a list `A, B`
	compound
	not
	has
	child
	descendant
	sibling
	adjacent
	attribute
	nth_child
	nth_last_child
	class
}

// AttrValueKind is the kind of the value of an attribute selector.
pub enum AttrValueKind {
	none    // `[name]`: no operator
	literal // a string, a number or a name (`[name="x"]`, `[n>2]`, `[name=x]`)
	regexp  // `[name=/x/i]`
	type    // `[name=type(string)]`
}

// Selector is a node of a parsed selector, as esquery's SelectorAST.
pub struct Selector {
pub:
	kind SelectorKind
	// identifier: the type as written; wildcard: `*`.
	value string
	// attribute, field and class: the name as written (`a.b`), and the attribute's and the
	// field's parts.
	name string
	path []string
	// matches, compound, not and has: the selectors; child, descendant, sibling and adjacent:
	// [left, right].
	selectors []Selector
	// attribute: the operator (`=`, `!=`, `<`, `>`, `<=`, `>=`, or '' for none) and the value.
	operator   string
	value_kind AttrValueKind
	// literal: the value; a number keeps its double in num_value and is_number. type: the type
	// name. regexp: the pattern and the flags.
	str_value string
	num_value f64
	is_number bool
	pattern   string
	flags     string
	regex     jsregexp.JsRegex
	// nth_child and nth_last_child: the position (parseInt of the digits, which may not fit in an
	// int).
	index f64
pub mut:
	// subject: the sequence was marked with `!`.
	subject bool
}

// SelectorError is a selector esquery does not parse: `offset` is the position (in UTF-16
// units) of the farthest failure, as in its SyntaxError's location.
pub struct SelectorError {
	Error
pub:
	msg    string
	offset int
}

pub fn (e SelectorError) msg() string {
	return e.msg
}

// parse ports esquery.parse: the selector AST of `source`, or an error when esquery throws (a
// syntax error, or a regular expression `new RegExp` rejects).
pub fn parse(source string) !Selector {
	mut p := Parser{
		input: utf16_units(source)
	}
	result := p.start() or { return p.syntax_error() }
	if p.pos != p.input.len {
		p.fail()
		return p.syntax_error()
	}
	if p.regex_error != '' {
		return SelectorError{
			msg:    p.regex_error
			offset: -1
		}
	}
	return result
}

struct Parser {
	input []u16
mut:
	pos      int
	max_fail int
	// The first regular expression that failed to compile: PEG.js runs the action, so the
	// parse throws, when the rule that builds it succeeds.
	regex_error string
}

fn (mut p Parser) syntax_error() IError {
	found := if p.max_fail < p.input.len {
		'"${units_to_string(p.input[p.max_fail..p.max_fail + 1])}"'
	} else {
		'end of input'
	}
	return SelectorError{
		msg:    'Unexpected ${found} at position ${p.max_fail}.'
		offset: p.max_fail
	}
}

// fail records a failure at the current position (peg$fail).
fn (mut p Parser) fail() {
	if p.pos > p.max_fail {
		p.max_fail = p.pos
	}
}

fn (p &Parser) at(c u8) bool {
	return p.pos < p.input.len && p.input[p.pos] == u16(c)
}

// lit consumes a literal text, or records a failure.
fn (mut p Parser) lit(text string) bool {
	if p.pos + text.len <= p.input.len {
		for i in 0 .. text.len {
			if p.input[p.pos + i] != u16(text[i]) {
				p.fail()
				return false
			}
		}
		p.pos += text.len
		return true
	}
	p.fail()
	return false
}

// start = _ selectors _ / _
fn (mut p Parser) start() ?Selector {
	s0 := p.pos
	p.spaces()
	if ss := p.selectors() {
		p.spaces()
		return if ss.len == 1 {
			ss[0]
		} else {
			Selector{
				kind:      .matches
				selectors: ss
			}
		}
	}
	p.pos = s0
	p.spaces()
	return Selector{
		kind: .empty
	}
}

// _ = " "*
fn (mut p Parser) spaces() {
	for p.at(` `) {
		p.pos++
	}
	p.fail()
}

// identifierName = [^ [\],():#!=><~+.]+
fn (mut p Parser) identifier_name() ?string {
	start := p.pos
	for p.pos < p.input.len && !is_reserved(p.input[p.pos]) {
		p.pos++
	}
	if p.pos == start {
		p.fail()
		return none
	}
	p.fail()
	return units_to_string(p.input[start..p.pos])
}

fn is_reserved(c u16) bool {
	return c < 0x80 && u8(c) in [` `, `[`, `]`, `,`, `(`, `)`, `:`, `#`, `!`, `=`, `>`, `<`, `~`,
		`+`, `.`]
}

// binaryOp = _ ">" _ / _ "~" _ / _ "+" _ / " " _
fn (mut p Parser) binary_op() ?SelectorKind {
	s0 := p.pos
	for op in [u8(`>`), `~`, `+`] {
		p.pos = s0
		p.spaces()
		if p.at(op) {
			p.pos++
			p.spaces()
			return match op {
				`>` { SelectorKind.child }
				`~` { SelectorKind.sibling }
				else { SelectorKind.adjacent }
			}
		}
		p.fail()
	}
	p.pos = s0
	if p.at(` `) {
		p.pos++
		p.spaces()
		return .descendant
	}
	p.fail()
	return none
}

// selectors = selector (_ "," _ selector)*
fn (mut p Parser) selectors() ?[]Selector {
	first := p.selector()?
	mut out := [first]
	for {
		s3 := p.pos
		p.spaces()
		if !p.lit(',') {
			p.pos = s3
			break
		}
		p.spaces()
		s := p.selector() or {
			p.pos = s3
			break
		}
		out << s
	}
	return out
}

// hasSelectors = hasSelector (_ "," _ hasSelector)*
fn (mut p Parser) has_selectors() ?[]Selector {
	first := p.has_selector()?
	mut out := [first]
	for {
		s3 := p.pos
		p.spaces()
		if !p.lit(',') {
			p.pos = s3
			break
		}
		p.spaces()
		s := p.has_selector() or {
			p.pos = s3
			break
		}
		out << s
	}
	return out
}

// hasSelector = binaryOp? selector, a selector relative to the `:has` node (exactNode).
fn (mut p Parser) has_selector() ?Selector {
	s0 := p.pos
	op := p.binary_op()
	s := p.selector() or {
		p.pos = s0
		return none
	}
	if kind := op {
		return Selector{
			kind:      kind
			selectors: [Selector{
				kind: .exact_node
			}, s]
		}
	}
	return s
}

// selector = sequence (binaryOp sequence)*, folded to the left.
fn (mut p Parser) selector() ?Selector {
	mut result := p.sequence()?
	for {
		s3 := p.pos
		op := p.binary_op() or { break }
		right := p.sequence() or {
			p.pos = s3
			break
		}
		result = Selector{
			kind:      op
			selectors: [result, right]
		}
	}
	return result
}

// sequence = "!"? atom+
fn (mut p Parser) sequence() ?Selector {
	s0 := p.pos
	subject := p.at(`!`)
	if subject {
		p.pos++
	} else {
		p.fail()
	}
	mut atoms := []Selector{}
	for {
		a := p.atom() or { break }
		atoms << a
	}
	if atoms.len == 0 {
		p.pos = s0
		return none
	}
	mut b := if atoms.len == 1 {
		atoms[0]
	} else {
		Selector{
			kind:      .compound
			selectors: atoms
		}
	}
	if subject {
		b.subject = true
	}
	return b
}

// atom = wildcard / identifier / attr / field / negation / matches / is / has / firstChild /
// lastChild / nthChild / nthLastChild / class
fn (mut p Parser) atom() ?Selector {
	if p.at(`*`) {
		p.pos++
		return Selector{
			kind:  .wildcard
			value: '*'
		}
	}
	p.fail()
	if s := p.identifier() {
		return s
	}
	if s := p.attr() {
		return s
	}
	if s := p.field() {
		return s
	}
	for prefix in [':not(', ':matches(', ':is(', ':has('] {
		if s := p.pseudo_list(prefix) {
			return s
		}
	}
	if p.lit(':first-child') {
		return nth(.nth_child, 1)
	}
	if p.lit(':last-child') {
		return nth(.nth_last_child, 1)
	}
	if s := p.nth(':nth-child(', .nth_child) {
		return s
	}
	if s := p.nth(':nth-last-child(', .nth_last_child) {
		return s
	}
	return p.class()
}

fn nth(kind SelectorKind, index f64) Selector {
	return Selector{
		kind:  kind
		index: index
	}
}

// identifier = "#"? identifierName
fn (mut p Parser) identifier() ?Selector {
	s0 := p.pos
	if p.at(`#`) {
		p.pos++
	} else {
		p.fail()
	}
	name := p.identifier_name() or {
		p.pos = s0
		return none
	}
	return Selector{
		kind:  .identifier
		value: name
	}
}

// attr = "[" _ attrValue _ "]"
fn (mut p Parser) attr() ?Selector {
	s0 := p.pos
	if !p.lit('[') {
		return none
	}
	p.spaces()
	v := p.attr_value() or {
		p.pos = s0
		return none
	}
	p.spaces()
	if !p.lit(']') {
		p.pos = s0
		return none
	}
	return v
}

// attrName = identifierName ("." identifierName)*
fn (mut p Parser) attr_name() ?string {
	mut name := p.identifier_name()?
	for {
		s3 := p.pos
		if !p.lit('.') {
			break
		}
		part := p.identifier_name() or {
			p.pos = s3
			break
		}
		name += '.' + part
	}
	return name
}

// attrValue = attrName _ attrEqOps _ (type / regex) / attrName _ attrOps _ (string / number /
// path) / attrName
fn (mut p Parser) attr_value() ?Selector {
	s0 := p.pos
	if name := p.attr_name() {
		p.spaces()
		if op := p.attr_eq_ops() {
			p.spaces()
			if v := p.type_value() {
				return attribute(name, op, v)
			}
			if v := p.regex() {
				return attribute(name, op, v)
			}
		}
	}
	p.pos = s0
	if name := p.attr_name() {
		p.spaces()
		if op := p.attr_ops() {
			p.spaces()
			if v := p.string_value() {
				return attribute(name, op, v)
			}
			if v := p.number() {
				return attribute(name, op, v)
			}
			if v := p.path() {
				return attribute(name, op, v)
			}
		}
	}
	p.pos = s0
	name := p.attr_name()?
	return Selector{
		kind: .attribute
		name: name
		path: name.split('.')
	}
}

fn attribute(name string, op string, v Selector) Selector {
	return Selector{
		...v
		kind:     .attribute
		name:     name
		path:     name.split('.')
		operator: op
	}
}

// attrOps = [><!]? "=" / [><]
fn (mut p Parser) attr_ops() ?string {
	s0 := p.pos
	mut prefix := ''
	if p.pos < p.input.len && p.input[p.pos] in [u16(`>`), `<`, `!`] {
		prefix = u8(p.input[p.pos]).ascii_str()
		p.pos++
	} else {
		p.fail()
	}
	if p.lit('=') {
		return prefix + '='
	}
	p.pos = s0
	if p.pos < p.input.len && p.input[p.pos] in [u16(`>`), `<`] {
		op := u8(p.input[p.pos]).ascii_str()
		p.pos++
		return op
	}
	p.fail()
	return none
}

// attrEqOps = "!"? "="
fn (mut p Parser) attr_eq_ops() ?string {
	s0 := p.pos
	mut prefix := ''
	if p.at(`!`) {
		prefix = '!'
		p.pos++
	} else {
		p.fail()
	}
	if p.lit('=') {
		return prefix + '='
	}
	p.pos = s0
	return none
}

// string = '"' ([^\\"] / "\\" .)* '"' / "'" ([^\\'] / "\\" .)* "'", unescaped (strUnescape).
fn (mut p Parser) string_value() ?Selector {
	for quote in [u16(`"`), `'`] {
		s0 := p.pos
		if p.pos >= p.input.len || p.input[p.pos] != quote {
			p.fail()
			continue
		}
		p.pos++
		start := p.pos
		for {
			if p.pos < p.input.len && p.input[p.pos] != `\\` && p.input[p.pos] != quote {
				p.pos++
				continue
			}
			p.fail()
			if p.at(`\\`) && p.pos + 1 < p.input.len {
				p.pos += 2
				continue
			}
			if p.at(`\\`) {
				p.pos++
				p.fail()
				p.pos--
			}
			break
		}
		raw := p.input[start..p.pos].clone()
		if p.pos < p.input.len && p.input[p.pos] == quote {
			p.pos++
			value := units_to_string(str_unescape(raw))
			return Selector{
				value_kind: .literal
				str_value:  value
			}
		}
		p.fail()
		p.pos = s0
	}
	return none
}

// str_unescape ports esquery's strUnescape: `\b`, `\f`, `\n`, `\r`, `\t` and `\v`, and any other
// escaped unit (but a line terminator, which `.` does not match) stands for itself.
fn str_unescape(s []u16) []u16 {
	mut out := []u16{cap: s.len}
	mut i := 0
	for i < s.len {
		c := s[i]
		if c == `\\` && i + 1 < s.len && s[i + 1] !in [u16(`\n`), `\r`, 0x2028, 0x2029] {
			e := s[i + 1]
			out << match e {
				`b` { u16(8) }
				`f` { u16(12) }
				`n` { u16(10) }
				`r` { u16(13) }
				`t` { u16(9) }
				`v` { u16(11) }
				else { e }
			}
			i += 2
			continue
		}
		out << c
		i++
	}
	return out
}

fn is_digit(c u16) bool {
	return c >= `0` && c <= `9`
}

// number = ([0-9]* ".")? [0-9]+, parseFloat of the text.
fn (mut p Parser) number() ?Selector {
	s0 := p.pos
	for p.pos < p.input.len && is_digit(p.input[p.pos]) {
		p.pos++
	}
	p.fail()
	if !p.lit('.') {
		p.pos = s0
	}
	digits_start := p.pos
	for p.pos < p.input.len && is_digit(p.input[p.pos]) {
		p.pos++
	}
	p.fail()
	if p.pos == digits_start {
		p.pos = s0
		return none
	}
	text := units_to_string(p.input[s0..p.pos])
	value := estree.js_parse_float(text)
	return Selector{
		value_kind: .literal
		str_value:  js_number_to_string(value)
		num_value:  value
		is_number:  true
	}
}

// path = identifierName, a literal string.
fn (mut p Parser) path() ?Selector {
	name := p.identifier_name()?
	return Selector{
		value_kind: .literal
		str_value:  name
	}
}

// type = "type(" _ [^ )]+ _ ")"
fn (mut p Parser) type_value() ?Selector {
	s0 := p.pos
	if !p.lit('type(') {
		return none
	}
	p.spaces()
	start := p.pos
	for p.pos < p.input.len && p.input[p.pos] != ` ` && p.input[p.pos] != `)` {
		p.pos++
	}
	p.fail()
	if p.pos == start {
		p.pos = s0
		return none
	}
	name := units_to_string(p.input[start..p.pos])
	p.spaces()
	if !p.lit(')') {
		p.pos = s0
		return none
	}
	return Selector{
		value_kind: .type
		str_value:  name
	}
}

// regex = "/" (re_character_class / re_escape / re_chars)+ "/" flags?
fn (mut p Parser) regex() ?Selector {
	s0 := p.pos
	if !p.lit('/') {
		return none
	}
	start := p.pos
	mut parts := 0
	for {
		if p.re_character_class() || p.re_escape() || p.re_chars() {
			parts++
			continue
		}
		break
	}
	if parts == 0 {
		p.pos = s0
		return none
	}
	pattern := units_to_string(p.input[start..p.pos])
	if !p.lit('/') {
		p.pos = s0
		return none
	}
	flags_start := p.pos
	for p.pos < p.input.len && p.input[p.pos] in [u16(`i`), `m`, `s`, `u`] {
		p.pos++
	}
	p.fail()
	flags := units_to_string(p.input[flags_start..p.pos])
	mut sel := Selector{
		value_kind: .regexp
		pattern:    pattern
		flags:      flags
	}
	if r := compile_regex(pattern, flags) {
		sel = Selector{
			...sel
			regex: r
		}
	} else {
		if p.regex_error == '' {
			p.regex_error = err.msg()
		}
	}
	return sel
}

// re_character_class = "[" ([^\]\\] / re_escape)+ "]"
fn (mut p Parser) re_character_class() bool {
	s0 := p.pos
	if !p.lit('[') {
		return false
	}
	mut parts := 0
	for {
		if p.pos < p.input.len && p.input[p.pos] != `]` && p.input[p.pos] != `\\` {
			p.pos++
			parts++
			continue
		}
		p.fail()
		if p.re_escape() {
			parts++
			continue
		}
		break
	}
	if parts == 0 || !p.lit(']') {
		p.pos = s0
		return false
	}
	return true
}

// re_escape = "\\" .
fn (mut p Parser) re_escape() bool {
	if !p.lit('\\') {
		return false
	}
	if p.pos < p.input.len {
		p.pos++
		return true
	}
	p.fail()
	p.pos--
	return false
}

// re_chars = [^/\\[]+
fn (mut p Parser) re_chars() bool {
	start := p.pos
	for p.pos < p.input.len && p.input[p.pos] !in [u16(`/`), `\\`, `[`] {
		p.pos++
	}
	p.fail()
	return p.pos > start
}

// field = "." identifierName ("." identifierName)*
fn (mut p Parser) field() ?Selector {
	s0 := p.pos
	if !p.lit('.') {
		return none
	}
	name := p.attr_name() or {
		p.pos = s0
		return none
	}
	return Selector{
		kind: .field
		name: name
		path: name.split('.')
	}
}

// pseudo_list parses `:not(…)`, `:matches(…)`, `:is(…)` and `:has(…)`.
fn (mut p Parser) pseudo_list(prefix string) ?Selector {
	s0 := p.pos
	if !p.lit(prefix) {
		return none
	}
	p.spaces()
	has := prefix == ':has('
	ss := if has { p.has_selectors() } else { p.selectors() }
	list := ss or {
		p.pos = s0
		return none
	}
	p.spaces()
	if !p.lit(')') {
		p.pos = s0
		return none
	}
	return Selector{
		kind:      match prefix {
			':not(' { SelectorKind.not }
			':has(' { SelectorKind.has }
			else { SelectorKind.matches }
		}
		selectors: list
	}
}

// nthChild = ":nth-child(" _ [0-9]+ _ ")" (and nthLastChild)
fn (mut p Parser) nth(prefix string, kind SelectorKind) ?Selector {
	s0 := p.pos
	if !p.lit(prefix) {
		return none
	}
	p.spaces()
	start := p.pos
	for p.pos < p.input.len && is_digit(p.input[p.pos]) {
		p.pos++
	}
	p.fail()
	if p.pos == start {
		p.pos = s0
		return none
	}
	digits := units_to_string(p.input[start..p.pos])
	p.spaces()
	if !p.lit(')') {
		p.pos = s0
		return none
	}
	return nth(kind, estree.js_parse_float(digits))
}

// class = ":" identifierName
fn (mut p Parser) class() ?Selector {
	s0 := p.pos
	if !p.lit(':') {
		return none
	}
	name := p.identifier_name() or {
		p.pos = s0
		return none
	}
	return Selector{
		kind: .class
		name: name
	}
}

// units_to_string converts UTF-16 units to WTF-8 (a lone surrogate keeps its 3-byte encoding).
fn units_to_string(units []u16) string {
	mut b := strings.new_builder(units.len)
	mut i := 0
	for i < units.len {
		mut cp := u32(units[i])
		if cp >= 0xd800 && cp <= 0xdbff && i + 1 < units.len && units[i + 1] >= 0xdc00
			&& units[i + 1] <= 0xdfff {
			cp = 0x10000 + ((cp - 0xd800) << 10) + (u32(units[i + 1]) - 0xdc00)
			i++
		}
		i++
		if cp < 0x80 {
			b.write_u8(u8(cp))
		} else if cp < 0x800 {
			b.write_u8(u8(0xc0 | (cp >> 6)))
			b.write_u8(u8(0x80 | (cp & 0x3f)))
		} else if cp < 0x10000 {
			b.write_u8(u8(0xe0 | (cp >> 12)))
			b.write_u8(u8(0x80 | ((cp >> 6) & 0x3f)))
			b.write_u8(u8(0x80 | (cp & 0x3f)))
		} else {
			b.write_u8(u8(0xf0 | (cp >> 18)))
			b.write_u8(u8(0x80 | ((cp >> 12) & 0x3f)))
			b.write_u8(u8(0x80 | ((cp >> 6) & 0x3f)))
			b.write_u8(u8(0x80 | (cp & 0x3f)))
		}
	}
	return b.str()
}
