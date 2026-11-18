module svelte_compiler

import svelte

// phases/1-parse/read/style.js: the compiler's CSS parser (svelte-eslint-parser hands the
// compiler a blank <style>, so svelte/ does not parse it).

struct CssParser {
mut:
	t     &Tree
	src   string
	index int
}

fn css_error(d Diag, pos int) IError {
	return compile_err(d, pos, pos)
}

fn (p &CssParser) match_(s string) bool {
	return p.src[p.index..].starts_with(s)
}

fn (mut p CssParser) eat(s string, required bool) !bool {
	if p.match_(s) {
		p.index += s.len
		return true
	}
	if required {
		return css_error(e_expected_token(s), p.index)
	}
	return false
}

fn (mut p CssParser) allow_whitespace() {
	for p.index < p.src.len && is_js_space(p.src, p.index) {
		p.index += js_space_len(p.src, p.index)
	}
}

// read_until moves to the first match of `needle` (or the end) and returns what it skipped.
fn (mut p CssParser) read_until(needle string) !string {
	if p.index >= p.src.len {
		return css_error(e_unexpected_eof(), p.src.len)
	}
	start := p.index
	i := p.src.index_after(needle, start) or { p.src.len }
	p.index = i
	return p.src[start..i]
}

// build_stylesheet parses the <style> element `css` of the compiler AST.
fn (mut b Builder) stylesheet(css svelte.CNode) !int {
	// The parser reads the source (trimmed at the end), from the start of the content.
	src := b.c.src[..js_trim_end_len(b.c.src)]
	mut p := CssParser{
		t:     &b.c.t
		src:   src
		index: css.content_start
	}
	children := p.read_body(fn (p &CssParser) bool {
		return p.match_('</style') || p.index >= p.src.len
	})!
	i := b.c.t.new_node('StyleSheet', css.start, css.end)
	mut attrs := []int{}
	for a in css.attributes {
		attrs << b.template_node(a)!
	}
	b.c.t.set_list(i, .attributes, attrs)
	b.c.t.set_list(i, .children, children)
	b.c.css_content_start = css.content_start
	b.c.css_content_end = p.index
	return i
}

fn js_trim_end_len(s string) int {
	mut e := s.len
	for e > 0 {
		// Step back over one character if it is white space.
		mut k := e - 1
		for k > 0 && s[k] & 0xc0 == 0x80 {
			k--
		}
		if !is_js_space(s, k) {
			break
		}
		e = k
	}
	return e
}

fn (mut p CssParser) read_body(finished fn (p &CssParser) bool) ![]int {
	mut children := []int{}
	for {
		p.allow_comment_or_whitespace()!
		if finished(p) {
			break
		}
		if p.match_('@') {
			children << p.read_at_rule()!
		} else {
			children << p.read_rule()!
		}
	}
	return children
}

fn (mut p CssParser) read_at_rule() !int {
	start := p.index
	p.eat('@', true)!
	name := p.read_identifier()!
	prelude := p.read_value()!
	mut block := -1
	if p.match_('{') {
		block = p.read_block()!
	} else {
		p.eat(';', true)!
	}
	i := p.t.new_node('Atrule', start, p.index)
	p.t.set_str(i, .name, name)
	p.t.set_str(i, .prelude, prelude)
	p.t.set_node(i, .block, block)
	return i
}

fn (mut p CssParser) read_rule() !int {
	start := p.index
	prelude := p.read_selector_list(false)!
	block := p.read_block()!
	i := p.t.new_node('Rule', start, p.index)
	p.t.set_node(i, .prelude, prelude)
	p.t.set_node(i, .block, block)
	return i
}

fn (mut p CssParser) read_selector_list(inside_pseudo_class bool) !int {
	mut children := []int{}
	p.allow_comment_or_whitespace()!
	start := p.index
	for p.index < p.src.len {
		children << p.read_selector(inside_pseudo_class)!
		end := p.index
		p.allow_comment_or_whitespace()!
		if (inside_pseudo_class && p.match_(')')) || (!inside_pseudo_class && p.match_('{')) {
			i := p.t.new_node('SelectorList', start, end)
			p.t.set_list(i, .children, children)
			return i
		} else {
			p.eat(',', true)!
			p.allow_comment_or_whitespace()!
		}
	}
	return css_error(e_unexpected_eof(), p.src.len)
}

fn (mut p CssParser) new_relative(combinator int, start int) int {
	i := p.t.new_node('RelativeSelector', start, -1)
	p.t.set_node(i, .combinator, combinator)
	p.t.set_list(i, .selectors, [])
	return i
}

fn (mut p CssParser) push_selector(rel int, sel int) {
	mut sels := p.t.list(rel, .selectors)
	sels << sel
	p.t.set_list(rel, .selectors, sels)
}

fn (mut p CssParser) simple(typ string, name string, start int) int {
	i := p.t.new_node(typ, start, p.index)
	p.t.set_str(i, .name, name)
	return i
}

fn (mut p CssParser) read_selector(inside_pseudo_class bool) !int {
	list_start := p.index
	mut children := []int{}
	mut rel := p.new_relative(-1, p.index)
	for p.index < p.src.len {
		start := p.index
		if p.eat('&', false)! {
			p.push_selector(rel, p.simple('NestingSelector', '&', start))
		} else if p.eat('*', false)! {
			mut name := '*'
			if p.eat('|', false)! {
				name = p.read_identifier()!
			}
			p.push_selector(rel, p.simple('TypeSelector', name, start))
		} else if p.eat('#', false)! {
			name := p.read_identifier()!
			p.push_selector(rel, p.simple('IdSelector', name, start))
		} else if p.eat('.', false)! {
			name := p.read_identifier()!
			p.push_selector(rel, p.simple('ClassSelector', name, start))
		} else if p.eat('::', false)! {
			name := p.read_identifier()!
			sel := p.simple('PseudoElementSelector', name, start)
			p.push_selector(rel, sel)
			if p.eat('(', false)! {
				p.read_selector_list(true)!
				p.eat(')', true)!
				p.t.nodes[sel].end = p.index
			}
		} else if p.eat(':', false)! {
			name := p.read_identifier()!
			mut args := -1
			if p.eat('(', false)! {
				args = p.read_selector_list(true)!
				p.eat(')', true)!
			}
			sel := p.simple('PseudoClassSelector', name, start)
			p.t.set_node(sel, .args, args)
			p.push_selector(rel, sel)
		} else if p.eat('[', false)! {
			p.allow_whitespace()
			name := p.read_identifier()!
			p.allow_whitespace()
			mut value := ''
			mut has_value := false
			matcher := p.read_matcher()
			if matcher != '' {
				p.allow_whitespace()
				value = p.read_attribute_value()!
				has_value = true
			}
			p.allow_whitespace()
			flags := p.read_letters()
			p.allow_whitespace()
			p.eat(']', true)!
			sel := p.simple('AttributeSelector', name, start)
			if matcher != '' {
				p.t.set_str(sel, .matcher, matcher)
			}
			if has_value {
				p.t.set_str(sel, .value, value)
			}
			if flags != '' {
				p.t.set_str(sel, .flags, flags)
			}
			p.push_selector(rel, sel)
		} else if inside_pseudo_class && p.nth_of_len() > 0 {
			n := p.nth_of_len()
			value := p.src[p.index..p.index + n]
			p.index += n
			sel := p.simple('Nth', '', start)
			p.t.set_str(sel, .value, value)
			p.push_selector(rel, sel)
		} else if p.percentage_len() > 0 {
			n := p.percentage_len()
			value := p.src[p.index..p.index + n]
			p.index += n
			sel := p.simple('Percentage', '', start)
			p.t.set_str(sel, .value, value)
			p.push_selector(rel, sel)
		} else if p.combinator_len(p.index) == 0 {
			mut name := p.read_identifier()!
			if p.eat('|', false)! {
				name = p.read_identifier()!
			}
			p.push_selector(rel, p.simple('TypeSelector', name, start))
		}
		index := p.index
		p.allow_comment_or_whitespace()!
		if p.match_(',') || (inside_pseudo_class && p.match_(')'))
			|| (!inside_pseudo_class && p.match_('{')) {
			p.index = index
			p.t.nodes[rel].end = index
			children << rel
			i := p.t.new_node('ComplexSelector', list_start, index)
			p.t.set_list(i, .children, children)
			return i
		}
		p.index = index
		combinator := p.read_combinator()
		if combinator >= 0 {
			if p.t.list(rel, .selectors).len > 0 {
				p.t.nodes[rel].end = index
				children << rel
			}
			rel = p.new_relative(combinator, p.t.nodes[combinator].start)
			p.allow_whitespace()
			if p.match_(',') || (inside_pseudo_class && p.match_(')'))
				|| (!inside_pseudo_class && p.match_('{')) {
				return css_error(e_css_selector_invalid(), p.index)
			}
		}
	}
	return css_error(e_unexpected_eof(), p.src.len)
}

// read_matcher is /[~^$*|]?=/y.
fn (mut p CssParser) read_matcher() string {
	if p.index < p.src.len && p.src[p.index] == `=` {
		p.index++
		return '='
	}
	if p.index + 1 < p.src.len && p.src[p.index] in [`~`, `^`, `$`, `*`, `|`]
		&& p.src[p.index + 1] == `=` {
		p.index += 2
		return p.src[p.index - 2..p.index]
	}
	return ''
}

// read_letters is /[a-zA-Z]+/y.
fn (mut p CssParser) read_letters() string {
	start := p.index
	for p.index < p.src.len && ((p.src[p.index] >= `a` && p.src[p.index] <= `z`)
		|| (p.src[p.index] >= `A` && p.src[p.index] <= `Z`)) {
		p.index++
	}
	return p.src[start..p.index]
}

// combinator_len is /(\+|~|>|\|\|)/y at i.
fn (p &CssParser) combinator_len(i int) int {
	if i >= p.src.len {
		return 0
	}
	c := p.src[i]
	if c == `+` || c == `~` || c == `>` {
		return 1
	}
	if c == `|` && i + 1 < p.src.len && p.src[i + 1] == `|` {
		return 2
	}
	return 0
}

// percentage_len is /\d+(\.\d+)?%/y.
fn (p &CssParser) percentage_len() int {
	s := p.src
	mut i := p.index
	for i < s.len && s[i] >= `0` && s[i] <= `9` {
		i++
	}
	if i == p.index {
		return 0
	}
	if i + 1 < s.len && s[i] == `.` && s[i + 1] >= `0` && s[i + 1] <= `9` {
		i++
		for i < s.len && s[i] >= `0` && s[i] <= `9` {
			i++
		}
	}
	if i < s.len && s[i] == `%` {
		return i + 1 - p.index
	}
	return 0
}

// nth_of_len is
// /(even|odd|\+?(\d+|\d*n(\s*[+-]\s*\d+)?)|-\d*n(\s*\+\s*\d+))((?=\s*[,)])|\s+of\s+)/y.
fn (p &CssParser) nth_of_len() int {
	s := p.src
	start := p.index
	mut heads := []int{}
	for kw in ['even', 'odd'] {
		if s[start..].starts_with(kw) {
			heads << start + kw.len
		}
	}
	// \+?(\d+|\d*n(\s*[+-]\s*\d+)?)
	mut i := start
	if i < s.len && s[i] == `+` {
		i++
	}
	mut j := i
	for j < s.len && s[j] >= `0` && s[j] <= `9` {
		j++
	}
	// The alternatives in order: \d+ first (backtracking may then try \d*n…).
	if j > i {
		heads << j
	}
	if j < s.len && s[j] == `n` {
		mut k := j + 1
		heads << nth_offset(s, k, `+`, `-`) or { k }
		// (…)? is greedy: with the offset first, then without.
		if off := nth_offset(s, k, `+`, `-`) {
			_ = off
			heads << k
		}
	}
	// -\d*n(\s*\+\s*\d+)
	if start < s.len && s[start] == `-` {
		mut k := start + 1
		for k < s.len && s[k] >= `0` && s[k] <= `9` {
			k++
		}
		if k < s.len && s[k] == `n` {
			if off := nth_offset(s, k + 1, `+`, `+`) {
				heads << off
			}
		}
	}
	for h in heads {
		if t := nth_tail(s, h) {
			return t - start
		}
	}
	return 0
}

// nth_offset matches \s*[ab]\s*\d+ at i.
fn nth_offset(s string, i int, a u8, b u8) ?int {
	mut k := i
	for k < s.len && is_js_space(s, k) {
		k += js_space_len(s, k)
	}
	if k >= s.len || (s[k] != a && s[k] != b) {
		return none
	}
	k++
	for k < s.len && is_js_space(s, k) {
		k += js_space_len(s, k)
	}
	d := k
	for k < s.len && s[k] >= `0` && s[k] <= `9` {
		k++
	}
	if k == d {
		return none
	}
	return k
}

// nth_tail matches ((?=\s*[,)])|\s+of\s+) at i: the end of the match.
fn nth_tail(s string, i int) ?int {
	mut k := i
	for k < s.len && is_js_space(s, k) {
		k += js_space_len(s, k)
	}
	if k < s.len && (s[k] == `,` || s[k] == `)`) {
		return i
	}
	if k > i && s[k..].starts_with('of') {
		mut m := k + 2
		w := m
		for m < s.len && is_js_space(s, m) {
			m += js_space_len(s, m)
		}
		if m > w {
			return m
		}
	}
	return none
}

fn (mut p CssParser) read_combinator() int {
	start := p.index
	p.allow_whitespace()
	index := p.index
	n := p.combinator_len(p.index)
	if n > 0 {
		name := p.src[p.index..p.index + n]
		p.index += n
		end := p.index
		p.allow_whitespace()
		i := p.t.new_node('Combinator', index, end)
		p.t.set_str(i, .name, name)
		return i
	}
	if p.index != start {
		i := p.t.new_node('Combinator', start, p.index)
		p.t.set_str(i, .name, ' ')
		return i
	}
	return -1
}

fn (mut p CssParser) read_block() !int {
	start := p.index
	p.eat('{', true)!
	mut children := []int{}
	for p.index < p.src.len {
		p.allow_comment_or_whitespace()!
		if p.match_('}') {
			break
		} else {
			children << p.read_block_item()!
		}
	}
	p.eat('}', true)!
	i := p.t.new_node('Block', start, p.index)
	p.t.set_list(i, .children, children)
	return i
}

fn (mut p CssParser) read_block_item() !int {
	if p.match_('@') {
		return p.read_at_rule()!
	}
	start := p.index
	p.read_value()!
	c := if p.index < p.src.len { p.src[p.index] } else { 0 }
	p.index = start
	return if c == `{` { p.read_rule()! } else { p.read_declaration()! }
}

fn (mut p CssParser) read_declaration() !int {
	start := p.index
	// read_until(/[\s:]/)
	mut k := p.index
	for k < p.src.len && p.src[k] != `:` && !is_js_space(p.src, k) {
		k += if p.src[k] < 0x80 { 1 } else { utf8_char_len(p.src[k]) }
	}
	if p.index >= p.src.len {
		return css_error(e_unexpected_eof(), p.src.len)
	}
	property := p.src[p.index..k]
	p.index = k
	p.allow_whitespace()
	p.eat(':', false)!
	index := p.index
	p.allow_whitespace()
	value := p.read_value()!
	if value == '' && !property.starts_with('--') {
		return compile_err(e_css_empty_declaration(), start, index)
	}
	end := p.index
	if !p.match_('}') {
		p.eat(';', true)!
	}
	i := p.t.new_node('Declaration', start, end)
	p.t.set_str(i, .property_name, property)
	p.t.set_str(i, .value, value)
	return i
}

fn (mut p CssParser) read_value() !string {
	mut value := []u8{}
	mut escaped := false
	mut in_url := false
	mut quote := u8(0)
	s := p.src
	for p.index < s.len {
		c := s[p.index]
		if escaped {
			value << `\\`
			n := if c < 0x80 { 1 } else { utf8_char_len(c) }
			value << s[p.index..p.index + n].bytes()
			escaped = false
			p.index += n
			continue
		} else if c == `\\` {
			escaped = true
			p.index++
			continue
		} else if quote != 0 && c == quote {
			quote = 0
		} else if c == `)` {
			in_url = false
		} else if quote == 0 && (c == `"` || c == `'`) {
			quote = c
		} else if c == `(` && value.len >= 3 && value[value.len - 3..].bytestr() == 'url' {
			in_url = true
		} else if (c == `;` || c == `{` || c == `}`) && !in_url && quote == 0 {
			return value.bytestr().trim_space()
		} else if c == `/` && !in_url && quote == 0 && p.index + 1 < s.len && s[p.index + 1] == `*` {
			p.index += 2
			for p.index < s.len {
				if s[p.index] == `*` && p.index + 1 < s.len && s[p.index + 1] == `/` {
					p.index += 2
					break
				}
				p.index++
			}
			continue
		}
		value << c
		p.index++
	}
	return css_error(e_unexpected_eof(), s.len)
}

fn (mut p CssParser) read_attribute_value() !string {
	mut value := []u8{}
	mut escaped := false
	mut quote := u8(0)
	if p.eat('"', false)! {
		quote = `"`
	} else if p.eat("'", false)! {
		quote = `'`
	}
	s := p.src
	for p.index < s.len {
		c := s[p.index]
		if escaped {
			value << `\\`
			value << c
			escaped = false
		} else if c == `\\` {
			escaped = true
		} else if (quote != 0 && c == quote) || (quote == 0 && (c == `]` || is_js_space(s, p.index))) {
			if quote != 0 {
				p.eat(quote.ascii_str(), true)!
			}
			return value.bytestr().trim_space()
		} else {
			value << c
		}
		p.index++
	}
	return css_error(e_unexpected_eof(), s.len)
}

fn (mut p CssParser) read_identifier() !string {
	start := p.index
	s := p.src
	// /-?\d/y
	if p.index < s.len && ((s[p.index] >= `0` && s[p.index] <= `9`) || (s[p.index] == `-`
		&& p.index + 1 < s.len && s[p.index + 1] >= `0` && s[p.index + 1] <= `9`)) {
		return css_error(e_css_expected_identifier(), start)
	}
	mut identifier := []u8{}
	for p.index < s.len {
		c := s[p.index]
		if c == `\\` {
			// /\\[0-9a-fA-F]{1,6}(\r\n|\s)?/y
			mut k := p.index + 1
			for k < s.len && k - p.index - 1 < 6 && is_hex_digit(s[k]) {
				k++
			}
			if k > p.index + 1 {
				cp := u32(s[p.index + 1..k].parse_uint(16, 32) or { 0 })
				if k + 1 < s.len && s[k] == `\r` && s[k + 1] == `\n` {
					k += 2
				} else if k < s.len && is_js_space(s, k) {
					k += js_space_len(s, k)
				}
				identifier << utf8_encode(cp).bytes()
				p.index = k
			} else {
				identifier << `\\`
				if p.index + 1 < s.len {
					n := if s[p.index + 1] < 0x80 { 1 } else { utf8_char_len(s[p.index + 1]) }
					identifier << s[p.index + 1..p.index + 1 + n].bytes()
					p.index += 1 + n
				} else {
					p.index += 2
				}
			}
		} else if c >= 0x80 {
			// codePointAt >= 160 (and the C1 range below it is not an identifier).
			r, n := rune_at(s, p.index)
			if r >= 160 {
				identifier << s[p.index..p.index + n].bytes()
				p.index += n
			} else {
				break
			}
		} else if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
			|| c == `_` || c == `-` {
			identifier << c
			p.index++
		} else {
			break
		}
	}
	if identifier.len == 0 {
		return css_error(e_css_expected_identifier(), start)
	}
	return identifier.bytestr()
}

fn is_hex_digit(c u8) bool {
	return (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

fn utf8_encode(cp u32) string {
	if cp == 0 || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff) {
		// String.fromCodePoint throws for > 0x10ffff; a lone surrogate stays as is.
		return rune(cp).str()
	}
	return rune(cp).str()
}

fn (mut p CssParser) allow_comment_or_whitespace() ! {
	p.allow_whitespace()
	for p.match_('/*') || p.match_('<!--') {
		if p.eat('/*', false)! {
			p.read_until('*/')!
			p.eat('*/', true)!
		}
		if p.eat('<!--', false)! {
			p.read_until('-->')!
			p.eat('-->', true)!
		}
		p.allow_whitespace()
	}
}
