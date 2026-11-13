module jsregexp

// Syntax of JavaScript regular expressions as V8 (the engine ESLint runs on, Node 26) accepts
// it: ECMAScript 2025 with Annex B, the `u` and `v` modes, named groups (duplicates only in
// different alternatives), lookbehind and modifiers. Unicode property names and group name
// characters come from regexp_unicode.v (generated from V8). There is no matcher: the rules only
// need to know whether `new RegExp(pattern, flags)` throws, the `source` and `flags` of the
// RegExp, and the top-level structure @eslint-community/regexpp 4.12.2 gives a valid pattern
// (alternatives, and per alternative whether each element is a Character and its value).
// Patterns are UTF-16 units, like JavaScript strings.

// RegexpMode is how a pattern is parsed: Annex B (no `u` nor `v` flag), `u` or `v`.
pub enum RegexpMode {
	annex_b
	unicode
	unicode_sets
}

// RegexpElementKind is what regexpp makes of an element of an alternative, as the rules tell
// them apart.
pub enum RegexpElementKind {
	character       // a Character
	assertion_start // `^`
	assertion_end   // `$`
	other           // quantifier, group, class, set, backreference or another assertion
}

pub struct RegexpElement {
pub:
	kind  RegexpElementKind
	value u32 // code point of a Character (a UTF-16 unit outside the `u` and `v` modes)
}

// RegexpPattern is a parsed pattern: whether V8 accepts it and, if so, its top-level
// alternatives.
pub struct RegexpPattern {
pub:
	valid        bool
	alternatives [][]RegexpElement
}

// RegexpValue is a RegExp object: its `source` (escaped like V8's EscapeRegExpSource) and its
// `flags` (in V8's order).
pub struct RegexpValue {
pub:
	pattern []u16 // the pattern it was created with
	source  []u16
	flags   string
}

// regexp_flag_order is the order of RegExp.prototype.flags in V8: hasIndices, global,
// ignoreCase, multiline, dotAll, unicode, unicodeSets, sticky.
const regexp_flag_order = 'dgimsuvy'

// regexp_new ports `new RegExp(pattern, flags)` with string arguments: none when V8 throws.
pub fn regexp_new(pattern []u16, flags string) ?RegexpValue {
	if !regexp_flags_valid(flags) {
		return none
	}
	if !regexp_parse(pattern, regexp_mode(flags)).valid {
		return none
	}
	mut canonical := []u8{}
	for f in regexp_flag_order {
		if flags.contains_u8(f) {
			canonical << f
		}
	}
	return RegexpValue{
		pattern: pattern
		source:  regexp_escape_source(pattern)
		flags:   canonical.bytestr()
	}
}

// regexp_flags_valid: only `dgimsuvy`, without repeats, and not both `u` and `v`.
fn regexp_flags_valid(flags string) bool {
	for i, f in flags {
		if !regexp_flag_order.contains_u8(f) || flags.index_u8(f) != i {
			return false
		}
	}
	return !(flags.contains_u8(`u`) && flags.contains_u8(`v`))
}

pub fn regexp_mode(flags string) RegexpMode {
	return if flags.contains_u8(`v`) {
		.unicode_sets
	} else if flags.contains_u8(`u`) {
		.unicode
	} else {
		.annex_b
	}
}

// regexp_escape_source ports V8's EscapeRegExpSource: `/` outside a class is escaped, line
// terminators become escapes (a `\` before one is dropped) and the empty pattern is `(?:)`.
pub fn regexp_escape_source(pattern []u16) []u16 {
	if pattern.len == 0 {
		return [u16(`(`), `?`, `:`, `)`]
	}
	mut out := []u16{cap: pattern.len}
	mut in_class := false
	mut i := 0
	for i < pattern.len {
		c := pattern[i]
		if c == `\\` {
			if i + 1 < pattern.len && regexp_is_line_terminator(pattern[i + 1]) {
				i++
				continue
			}
			out << c
			i++
			if i < pattern.len {
				out << pattern[i]
				i++
			}
			continue
		}
		match c {
			`/` {
				if !in_class {
					out << u16(`\\`)
				}
			}
			`[` {
				in_class = true
			}
			`]` {
				in_class = false
			}
			`\n` {
				out << [u16(`\\`), `n`]
				i++
				continue
			}
			`\r` {
				out << [u16(`\\`), `r`]
				i++
				continue
			}
			0x2028, 0x2029 {
				out << [u16(`\\`), `u`, `2`, `0`, `2`, if c == 0x2028 { u16(`8`) } else { u16(`9`) }]
				i++
				continue
			}
			else {}
		}
		out << c
		i++
	}
	return out
}

fn regexp_is_line_terminator(c u16) bool {
	return c == `\n` || c == `\r` || c == 0x2028 || c == 0x2029
}

// RegexpGroup is a named capture group, with the alternative it is in at each enclosing
// disjunction (to allow the same name in different alternatives).
struct RegexpGroup {
	name string
	path []u64 // disjunction id << 32 | alternative index, from the outermost
}

// RegexpParser walks a pattern: `chars` are its code points in the `u` and `v` modes (a pair of
// surrogates is one) and its UTF-16 units in Annex B.
struct RegexpParser {
	chars []u32
	mode  RegexpMode
mut:
	pos         int
	captures    int      // capturing groups of the whole pattern (V8 counts them first)
	names       []string // group names of the whole pattern
	groups      []RegexpGroup
	path        []u64 // current disjunction/alternative path
	disjunction int   // ids of the disjunctions
	depth       int
}

// regexp_parse parses a pattern in a mode, like V8 (validity) and regexpp (structure).
pub fn regexp_parse(pattern []u16, mode RegexpMode) RegexpPattern {
	mut p := RegexpParser{
		chars: regexp_chars(pattern, mode)
		mode:  mode
	}
	p.prescan()
	alternatives := p.parse_pattern() or { return RegexpPattern{} }
	return RegexpPattern{
		valid:        true
		alternatives: alternatives
	}
}

fn regexp_chars(pattern []u16, mode RegexpMode) []u32 {
	mut chars := []u32{cap: pattern.len}
	mut i := 0
	for i < pattern.len {
		c := u32(pattern[i])
		if mode != .annex_b && c >= 0xd800 && c <= 0xdbff && i + 1 < pattern.len
			&& pattern[i + 1] >= 0xdc00 && pattern[i + 1] <= 0xdfff {
			chars << 0x10000 + ((c - 0xd800) << 10) + (u32(pattern[i + 1]) - 0xdc00)
			i += 2
			continue
		}
		chars << c
		i++
	}
	return chars
}

fn (p &RegexpParser) unicode_mode() bool {
	return p.mode != .annex_b
}

fn (p &RegexpParser) at(offset int) u32 {
	i := p.pos + offset
	return if i < p.chars.len { p.chars[i] } else { u32(0xffffffff) }
}

fn (p &RegexpParser) at_end() bool {
	return p.pos >= p.chars.len
}

fn (mut p RegexpParser) eat(c u32) bool {
	if p.at(0) == c {
		p.pos++
		return true
	}
	return false
}

fn (mut p RegexpParser) expect(c u32) ! {
	if !p.eat(c) {
		return error('expected ${c}')
	}
}

// prescan counts the capturing groups and collects the group names of the whole pattern, as V8
// does before parsing: they decide what `\1` and `\k` mean.
fn (mut p RegexpParser) prescan() {
	mut i := 0
	mut class_depth := 0
	for i < p.chars.len {
		c := p.chars[i]
		if c == `\\` {
			i += 2
			continue
		}
		if class_depth > 0 {
			if c == `]` {
				class_depth--
			} else if c == `[` && p.mode == .unicode_sets {
				class_depth++
			}
			i++
			continue
		}
		if c == `[` {
			class_depth = 1
		} else if c == `(` {
			if i + 1 < p.chars.len && p.chars[i + 1] == `?` {
				if i + 3 < p.chars.len && p.chars[i + 2] == `<` && p.chars[i + 3] != `=`
					&& p.chars[i + 3] != `!` {
					p.captures++
					mut scanner := RegexpParser{
						chars: p.chars
						mode:  p.mode
						pos:   i + 3
					}
					if name := scanner.group_name() {
						p.names << name
					}
				}
			} else {
				p.captures++
			}
		}
		i++
	}
}

fn (mut p RegexpParser) parse_pattern() ![][]RegexpElement {
	alternatives := p.parse_disjunction(true)!
	if !p.at_end() {
		return error('unmatched )')
	}
	return alternatives
}

// parse_disjunction parses alternatives up to the end or a `)`; only the top level keeps them.
fn (mut p RegexpParser) parse_disjunction(top bool) ![][]RegexpElement {
	p.depth++
	if p.depth > 1000 {
		return error('too deep')
	}
	p.disjunction++
	id := u64(p.disjunction)
	mut alternatives := [][]RegexpElement{}
	mut index := u64(0)
	for {
		p.path << (id << 32) | index
		elements := p.parse_alternative()!
		p.path.delete_last()
		if top {
			alternatives << elements
		}
		if !p.eat(`|`) {
			break
		}
		index++
	}
	p.depth--
	return alternatives
}

fn (mut p RegexpParser) parse_alternative() ![]RegexpElement {
	mut elements := []RegexpElement{}
	for !p.at_end() && p.at(0) != `|` && p.at(0) != `)` {
		elements << p.parse_term()!
	}
	return elements
}

fn (mut p RegexpParser) parse_term() !RegexpElement {
	c := p.at(0)
	if c == `^` || c == `$` {
		p.pos++
		p.no_quantifier()!
		return RegexpElement{
			kind: if c == `^` { .assertion_start } else { .assertion_end }
		}
	}
	if c == `\\` && (p.at(1) == `b` || p.at(1) == `B`) {
		p.pos += 2
		p.no_quantifier()!
		return RegexpElement{
			kind: .other
		}
	}
	if c == `(` && p.at(1) == `?` {
		k := p.at(2)
		lookbehind := k == `<` && (p.at(3) == `=` || p.at(3) == `!`)
		if k == `=` || k == `!` || lookbehind {
			p.pos += if lookbehind { 4 } else { 3 }
			p.parse_disjunction(false)!
			p.expect(`)`)!
			if lookbehind || p.unicode_mode() {
				p.no_quantifier()!
			} else {
				p.parse_quantifier()!
			}
			return RegexpElement{
				kind: .other
			}
		}
	}
	element := p.parse_atom()!
	if p.parse_quantifier()! {
		return RegexpElement{
			kind: .other
		}
	}
	return element
}

// no_quantifier fails when a quantifier follows something that cannot have one.
fn (mut p RegexpParser) no_quantifier() ! {
	c := p.at(0)
	if c == `*` || c == `+` || c == `?` {
		return error('nothing to repeat')
	}
	if c == `{` && p.braced_quantifier_end(p.pos) > 0 {
		return error('nothing to repeat')
	}
}

// braced_quantifier_end gives the position after a `{n}`, `{n,}` or `{n,m}` starting at `start`,
// or 0 if there is none there.
fn (p &RegexpParser) braced_quantifier_end(start int) int {
	mut i := start + 1
	digits := i
	for i < p.chars.len && p.chars[i] >= `0` && p.chars[i] <= `9` {
		i++
	}
	if i == digits {
		return 0
	}
	if i < p.chars.len && p.chars[i] == `,` {
		i++
		for i < p.chars.len && p.chars[i] >= `0` && p.chars[i] <= `9` {
			i++
		}
	}
	if i < p.chars.len && p.chars[i] == `}` {
		return i + 1
	}
	return 0
}

// parse_quantifier reads an optional quantifier (and its lazy `?`).
fn (mut p RegexpParser) parse_quantifier() !bool {
	c := p.at(0)
	if c == `*` || c == `+` || c == `?` {
		p.pos++
	} else if c == `{` {
		end := p.braced_quantifier_end(p.pos)
		if end == 0 {
			return false
		}
		body := p.chars[p.pos + 1..end - 1].clone()
		comma := body.index(u32(`,`))
		if comma >= 0 && comma + 1 < body.len {
			if regexp_compare_digits(body[..comma], body[comma + 1..]) > 0 {
				return error('numbers out of order')
			}
		}
		p.pos = end
	} else {
		return false
	}
	p.eat(`?`)
	return true
}

// regexp_compare_digits compares two decimal numbers of any size: -1, 0 or 1.
fn regexp_compare_digits(a []u32, b []u32) int {
	mut x := a.clone()
	mut y := b.clone()
	for x.len > 1 && x[0] == `0` {
		x.delete(0)
	}
	for y.len > 1 && y[0] == `0` {
		y.delete(0)
	}
	if x.len != y.len {
		return if x.len < y.len { -1 } else { 1 }
	}
	for i in 0 .. x.len {
		if x[i] != y[i] {
			return if x[i] < y[i] { -1 } else { 1 }
		}
	}
	return 0
}

fn regexp_character(value u32) RegexpElement {
	return RegexpElement{
		kind:  .character
		value: value
	}
}

fn (mut p RegexpParser) parse_atom() !RegexpElement {
	c := p.at(0)
	match c {
		`.` {
			p.pos++
			return RegexpElement{
				kind: .other
			}
		}
		`(` {
			p.parse_group()!
			return RegexpElement{
				kind: .other
			}
		}
		`[` {
			if p.mode == .unicode_sets {
				p.parse_class_v()!
			} else {
				p.parse_class()!
			}
			return RegexpElement{
				kind: .other
			}
		}
		`\\` {
			p.pos++
			return p.parse_atom_escape()!
		}
		`*`, `+`, `?` {
			return error('nothing to repeat')
		}
		`{` {
			if p.unicode_mode() || p.braced_quantifier_end(p.pos) > 0 {
				return error('lone quantifier brackets')
			}
			p.pos++
			return regexp_character(c)
		}
		`}`, `]` {
			if p.unicode_mode() {
				return error('lone quantifier brackets')
			}
			p.pos++
			return regexp_character(c)
		}
		else {
			p.pos++
			return regexp_character(c)
		}
	}
}

fn (mut p RegexpParser) parse_group() ! {
	p.pos++
	if !p.eat(`?`) {
		p.parse_disjunction(false)!
		p.expect(`)`)!
		return
	}
	match p.at(0) {
		`:` {
			p.pos++
		}
		`<` {
			p.pos++
			name := p.group_name()!
			for g in p.groups {
				if g.name == name && !regexp_exclusive(g.path, p.path) {
					return error('duplicate capture group name')
				}
			}
			p.groups << RegexpGroup{
				name: name
				path: p.path.clone()
			}
		}
		else {
			p.parse_modifiers()!
		}
	}
	p.parse_disjunction(false)!
	p.expect(`)`)!
}

// regexp_exclusive: two groups are in different alternatives of some disjunction that contains
// both, so they cannot both participate in a match.
fn regexp_exclusive(a []u64, b []u64) bool {
	for x in a {
		for y in b {
			if x >> 32 == y >> 32 && x != y {
				return true
			}
		}
	}
	return false
}

// parse_modifiers reads the flags of `(?ims-ims:`: only i, m and s, none repeated, not both
// empty.
fn (mut p RegexpParser) parse_modifiers() ! {
	mut seen := []u32{}
	mut count := 0
	for p.at(0) in [u32(`i`), `m`, `s`] {
		if p.at(0) in seen {
			return error('repeated flag')
		}
		seen << p.at(0)
		count++
		p.pos++
	}
	if p.eat(`-`) {
		mut removed := 0
		for p.at(0) in [u32(`i`), `m`, `s`] {
			if p.at(0) in seen {
				return error('repeated flag')
			}
			seen << p.at(0)
			removed++
			p.pos++
		}
		if count == 0 && removed == 0 {
			return error('invalid flag group')
		}
		count += removed
	} else if count == 0 {
		return error('invalid group')
	}
	p.expect(`:`)!
}

// group_name reads `name>` after `<`: a RegExpIdentifierName, escapes and surrogate pairs
// included.
fn (mut p RegexpParser) group_name() !string {
	mut runes := []rune{}
	for {
		if p.at_end() {
			return error('invalid capture group name')
		}
		if p.eat(`>`) {
			break
		}
		mut c := p.at(0)
		if c == `\\` {
			p.pos++
			if !p.eat(`u`) {
				return error('invalid capture group name')
			}
			c = p.unicode_escape_value(true) or { return error('invalid capture group name') }
		} else {
			p.pos++
			if c >= 0xd800 && c <= 0xdbff && p.at(0) >= 0xdc00 && p.at(0) <= 0xdfff {
				c = 0x10000 + ((c - 0xd800) << 10) + (p.at(0) - 0xdc00)
				p.pos++
			}
		}
		table := if runes.len == 0 { regexp_group_name_start } else { regexp_group_name_part }
		if !regexp_in_ranges(table, c) {
			return error('invalid capture group name')
		}
		runes << rune(c)
	}
	if runes.len == 0 {
		return error('invalid capture group name')
	}
	return runes.string()
}

// regexp_in_ranges searches inclusive [first, last] pairs.
fn regexp_in_ranges(ranges []u32, c u32) bool {
	mut lo := 0
	mut hi := ranges.len / 2
	for lo < hi {
		mid := (lo + hi) / 2
		if c < ranges[2 * mid] {
			hi = mid
		} else if c > ranges[2 * mid + 1] {
			lo = mid + 1
		} else {
			return true
		}
	}
	return false
}

// unicode_escape_value reads what follows `\u`: `{hex}` (when `braces`) or four hex digits,
// joining an escaped surrogate pair (`😀`) when `braces` (the `u` and `v` modes and
// group names). none when it is not a valid escape.
fn (mut p RegexpParser) unicode_escape_value(braces bool) ?u32 {
	if braces && p.at(0) == `{` {
		mut i := p.pos + 1
		mut value := u64(0)
		for i < p.chars.len && regexp_hex_value(p.chars[i]) >= 0 {
			value = value * 16 + u64(regexp_hex_value(p.chars[i]))
			if value > 0x10ffff {
				return none
			}
			i++
		}
		if i == p.pos + 1 || i >= p.chars.len || p.chars[i] != `}` {
			return none
		}
		p.pos = i + 1
		return u32(value)
	}
	lead := p.hex_digits(p.pos, 4)?
	p.pos += 4
	if braces && lead >= 0xd800 && lead <= 0xdbff && p.at(0) == `\\` && p.at(1) == `u` {
		if trail := p.hex_digits(p.pos + 2, 4) {
			if trail >= 0xdc00 && trail <= 0xdfff {
				p.pos += 6
				return 0x10000 + ((lead - 0xd800) << 10) + (trail - 0xdc00)
			}
		}
	}
	return lead
}

fn (p &RegexpParser) hex_digits(start int, count int) ?u32 {
	if start + count > p.chars.len {
		return none
	}
	mut value := u32(0)
	for i in start .. start + count {
		digit := regexp_hex_value(p.chars[i])
		if digit < 0 {
			return none
		}
		value = value * 16 + u32(digit)
	}
	return value
}

pub fn regexp_hex_value(c u32) int {
	return if c >= `0` && c <= `9` {
		int(c - `0`)
	} else if c >= `a` && c <= `f` {
		int(c - `a` + 10)
	} else if c >= `A` && c <= `F` {
		int(c - `A` + 10)
	} else {
		-1
	}
}

fn regexp_is_syntax_character(c u32) bool {
	return c in [u32(`^`), `$`, `\\`, `.`, `*`, `+`, `?`, `(`, `)`, `[`, `]`, `{`, `}`, `|`]
}

fn regexp_is_ascii_letter(c u32) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

// parse_atom_escape reads what follows a `\` outside a class.
fn (mut p RegexpParser) parse_atom_escape() !RegexpElement {
	if p.at_end() {
		return error('\\ at end of pattern')
	}
	c := p.at(0)
	if c in [u32(`d`), `D`, `s`, `S`, `w`, `W`] {
		p.pos++
		return RegexpElement{
			kind: .other
		}
	}
	if c == `p` || c == `P` {
		if p.unicode_mode() {
			p.pos++
			p.property_escape(c == `P`)!
			return RegexpElement{
				kind: .other
			}
		}
		p.pos++
		return regexp_character(c)
	}
	if c == `k` {
		if p.unicode_mode() || p.names.len > 0 {
			p.pos++
			if !p.eat(`<`) {
				return error('invalid named reference')
			}
			name := p.group_name()!
			if name !in p.names {
				return error('invalid named capture referenced')
			}
			return RegexpElement{
				kind: .other
			}
		}
		p.pos++
		return regexp_character(c)
	}
	if c >= `1` && c <= `9` {
		start := p.pos
		mut n := u64(0)
		for p.at(0) >= `0` && p.at(0) <= `9` {
			n = n * 10 + u64(p.at(0) - `0`)
			if n > 1 << 31 {
				n = 1 << 31
			}
			p.pos++
		}
		if n <= u64(p.captures) {
			return RegexpElement{
				kind: .other
			}
		}
		if p.unicode_mode() {
			return error('invalid escape')
		}
		p.pos = start
		if c >= `8` {
			p.pos++
			return regexp_character(c)
		}
		return regexp_character(p.legacy_octal())
	}
	return regexp_character(p.character_escape(false)!)
}

// legacy_octal reads an Annex B octal escape (`\377` at most) at an octal digit.
fn (mut p RegexpParser) legacy_octal() u32 {
	first := p.at(0) - `0`
	p.pos++
	mut value := first
	max_digits := if first <= 3 { 2 } else { 1 }
	for _ in 0 .. max_digits {
		d := p.at(0)
		if d < `0` || d > `7` {
			break
		}
		value = value * 8 + (d - `0`)
		p.pos++
	}
	return value
}

// character_escape reads a CharacterEscape (control, `\c`, `\0`, `\x`, `\u` or an identity
// escape) and gives its value; `in_class` selects the class variants of Annex B.
fn (mut p RegexpParser) character_escape(in_class bool) !u32 {
	c := p.at(0)
	match c {
		`f` {
			p.pos++
			return 12
		}
		`n` {
			p.pos++
			return 10
		}
		`r` {
			p.pos++
			return 13
		}
		`t` {
			p.pos++
			return 9
		}
		`v` {
			p.pos++
			return 11
		}
		`c` {
			next := p.at(1)
			if regexp_is_ascii_letter(next) {
				p.pos += 2
				return next % 32
			}
			if p.unicode_mode() {
				return error('invalid unicode escape')
			}
			if in_class && ((next >= `0` && next <= `9`) || next == `_`) {
				p.pos += 2
				return next % 32
			}
			// Annex B: the `\` is a character and the `c` is read next.
			return u32(`\\`)
		}
		`0` {
			next := p.at(1)
			if next >= `0` && next <= `9` {
				if p.unicode_mode() {
					return error('invalid decimal escape')
				}
				return p.legacy_octal()
			}
			p.pos++
			return 0
		}
		`x` {
			if value := p.hex_digits(p.pos + 1, 2) {
				p.pos += 3
				return value
			}
			if p.unicode_mode() {
				return error('invalid escape')
			}
			p.pos++
			return c
		}
		`u` {
			p.pos++
			if value := p.unicode_escape_value(p.unicode_mode()) {
				return value
			}
			if p.unicode_mode() {
				return error('invalid unicode escape')
			}
			return c
		}
		else {
			if p.unicode_mode() {
				if regexp_is_syntax_character(c) || c == `/` || (in_class && c == `-`) {
					p.pos++
					return c
				}
				return error('invalid escape')
			}
			if c == `k` && p.names.len > 0 {
				return error('invalid escape')
			}
			if in_class && c >= `1` && c <= `7` {
				return p.legacy_octal()
			}
			p.pos++
			return c
		}
	}
}

// property_escape reads `{name}` or `{name=value}` after `\p`/`\P`; it tells whether the
// property is one of strings (only with `v`, not negated).
fn (mut p RegexpParser) property_escape(negated bool) !bool {
	if !p.eat(`{`) {
		return error('invalid property name')
	}
	mut name := []u8{}
	mut value := []u8{}
	mut has_value := false
	for !p.at_end() && p.at(0) != `}` {
		c := p.at(0)
		if c == `=` && !has_value {
			has_value = true
		} else if regexp_is_ascii_letter(c) || (c >= `0` && c <= `9`) || c == `_` {
			if has_value {
				value << u8(c)
			} else {
				name << u8(c)
			}
		} else {
			return error('invalid property name')
		}
		p.pos++
	}
	p.expect(`}`)!
	n := name.bytestr()
	if has_value {
		v := value.bytestr()
		ok := match n {
			'General_Category', 'gc' { v in regexp_gc_values }
			'Script', 'sc' { v in regexp_script_values }
			'Script_Extensions', 'scx' { v in regexp_script_extensions_values }
			else { false }
		}
		if !ok {
			return error('invalid property name')
		}
		return false
	}
	if n in regexp_gc_values || n in regexp_binary_properties {
		return false
	}
	if p.mode == .unicode_sets && !negated && n in regexp_string_properties {
		return true
	}
	return error('invalid property name')
}

// RegexpClassAtom is an atom of a class without `v`: a character or a set (`\d`, `\p{…}`).
struct RegexpClassAtom {
	set   bool
	value u32
}

// parse_class parses a class without the `v` flag.
fn (mut p RegexpParser) parse_class() ! {
	p.pos++
	p.eat(`^`)
	for {
		if p.at_end() {
			return error('unterminated character class')
		}
		if p.eat(`]`) {
			return
		}
		from := p.class_atom()!
		if p.at(0) == `-` && p.pos + 1 < p.chars.len && p.at(1) != `]` {
			p.pos++
			to := p.class_atom()!
			if from.set || to.set {
				if p.unicode_mode() {
					return error('invalid character class')
				}
				continue
			}
			if from.value > to.value {
				return error('range out of order in character class')
			}
		}
	}
}

fn (mut p RegexpParser) class_atom() !RegexpClassAtom {
	c := p.at(0)
	if c != `\\` {
		p.pos++
		return RegexpClassAtom{
			value: c
		}
	}
	p.pos++
	if p.at_end() {
		return error('\\ at end of pattern')
	}
	e := p.at(0)
	if e in [u32(`d`), `D`, `s`, `S`, `w`, `W`] {
		p.pos++
		return RegexpClassAtom{
			set: true
		}
	}
	if e == `p` || e == `P` {
		p.pos++
		if p.unicode_mode() {
			p.property_escape(e == `P`)!
			return RegexpClassAtom{
				set: true
			}
		}
		return RegexpClassAtom{
			value: e
		}
	}
	if e == `b` {
		p.pos++
		return RegexpClassAtom{
			value: 8
		}
	}
	if e == `-` && p.unicode_mode() {
		p.pos++
		return RegexpClassAtom{
			value: e
		}
	}
	if p.unicode_mode() && e >= `1` && e <= `9` {
		return error('invalid class escape')
	}
	return RegexpClassAtom{
		value: p.character_escape(true)!
	}
}

// RegexpSetOperand is a ClassSetOperand of the `v` mode: whether it may contain strings and
// whether it is a single character (which may start a range).
struct RegexpSetOperand {
	strings   bool
	character bool
	value     u32
}

// regexp_double_punctuators are the ClassSetReservedDoublePunctuator characters.
const regexp_double_punctuators = [u32(`&`), `!`, `#`, `$`, `%`, `*`, `+`, `,`, `.`, `:`, `;`,
	`<`, `=`, `>`, `?`, `@`, `^`, `\``, `~`]

// regexp_set_syntax are the ClassSetSyntaxCharacter characters.
const regexp_set_syntax = [u32(`(`), `)`, `[`, `]`, `{`, `}`, `/`, `-`, `\\`, `|`]

// regexp_set_reserved are the ClassSetReservedPunctuator characters, which may be escaped.
const regexp_set_reserved = [u32(`&`), `-`, `!`, `#`, `%`, `,`, `:`, `;`, `<`, `=`, `>`, `@`, `\``,
	`~`]

// parse_class_v parses a class with the `v` flag (ClassSetExpression) and tells whether it may
// contain strings.
fn (mut p RegexpParser) parse_class_v() !bool {
	p.depth++
	if p.depth > 1000 {
		return error('too deep')
	}
	p.pos++
	negated := p.eat(`^`)
	strings := p.class_set_expression()!
	p.expect(`]`)!
	p.depth--
	if negated && strings {
		return error('negated character class may contain strings')
	}
	return !negated && strings
}

fn (mut p RegexpParser) is_operator(op u32) bool {
	return p.at(0) == op && p.at(1) == op
}

fn (mut p RegexpParser) class_set_expression() !bool {
	if p.at(0) == `]` {
		return false
	}
	first := p.class_set_operand()!
	if p.is_operator(`&`) || p.is_operator(`-`) {
		op := p.at(0)
		mut strings := first.strings
		for p.is_operator(op) {
			p.pos += 2
			if op == `&` && p.at(0) == `&` {
				return error('invalid character in character class')
			}
			operand := p.class_set_operand()!
			if op == `&` {
				strings = strings && operand.strings
			}
		}
		if p.at(0) != `]` {
			return error('invalid set operation in character class')
		}
		return strings
	}
	mut strings := first.strings
	mut previous := first
	for {
		if p.at(0) == `]` || p.at_end() {
			return strings
		}
		if p.at(0) == `-` && p.at(1) != `-` {
			if !previous.character {
				return error('invalid set operation in character class')
			}
			p.pos++
			to := p.class_set_operand()!
			if !to.character {
				return error('invalid character class')
			}
			if previous.value > to.value {
				return error('range out of order in character class')
			}
			previous = RegexpSetOperand{}
			continue
		}
		if p.is_operator(`&`) || p.is_operator(`-`) {
			return error('invalid set operation in character class')
		}
		operand := p.class_set_operand()!
		strings = strings || operand.strings
		previous = operand
	}
	return strings
}

fn (mut p RegexpParser) class_set_operand() !RegexpSetOperand {
	if p.at_end() {
		return error('unterminated character class')
	}
	c := p.at(0)
	if c == `[` {
		return RegexpSetOperand{
			strings: p.parse_class_v()!
		}
	}
	if c == `\\` {
		p.pos++
		if p.at_end() {
			return error('\\ at end of pattern')
		}
		e := p.at(0)
		if e in [u32(`d`), `D`, `s`, `S`, `w`, `W`] {
			p.pos++
			return RegexpSetOperand{}
		}
		if e == `p` || e == `P` {
			p.pos++
			return RegexpSetOperand{
				strings: p.property_escape(e == `P`)!
			}
		}
		if e == `q` {
			p.pos++
			return RegexpSetOperand{
				strings: p.class_string_disjunction()!
			}
		}
		value := p.class_set_escape()!
		return RegexpSetOperand{
			character: true
			value:     value
		}
	}
	if c in regexp_set_syntax {
		return error('invalid character in character class')
	}
	if c in regexp_double_punctuators && p.at(1) == c {
		return error('invalid set operation in character class')
	}
	p.pos++
	return RegexpSetOperand{
		character: true
		value:     c
	}
}

// class_set_escape reads the escape of a ClassSetCharacter after `\`: `\b`, a reserved
// punctuator or a CharacterEscape of the `u` mode.
fn (mut p RegexpParser) class_set_escape() !u32 {
	e := p.at(0)
	if e == `b` {
		p.pos++
		return 8
	}
	if e in regexp_set_reserved {
		p.pos++
		return e
	}
	if e >= `1` && e <= `9` {
		return error('invalid class escape')
	}
	return p.character_escape(false)!
}

// class_string_disjunction reads `{a|bc|}` after `\q`; it tells whether some string does not
// have exactly one character.
fn (mut p RegexpParser) class_string_disjunction() !bool {
	p.expect(`{`)!
	mut strings := false
	mut length := 0
	for {
		if p.at_end() {
			return error('unterminated class string disjunction')
		}
		c := p.at(0)
		if c == `}` {
			p.pos++
			break
		}
		if c == `|` {
			p.pos++
			strings = strings || length != 1
			length = 0
			continue
		}
		if c == `\\` {
			p.pos++
			p.class_set_escape()!
		} else {
			if c in regexp_set_syntax {
				return error('invalid character in class string disjunction')
			}
			if c in regexp_double_punctuators && p.at(1) == c {
				return error('invalid set operation in class string disjunction')
			}
			p.pos++
		}
		length++
	}
	return strings || length != 1
}
