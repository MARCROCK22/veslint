module rules

// JavaScript regular expressions without flags (`new RegExp(pattern)`), for the `package` of a type
// specifier: typescript-eslint makes one of the name and tests it on the names TypeScript gives the
// files of the packages (see specifiers.v).
// regexp_new (regexp_syntax.v) tells whether V8 accepts a pattern. This reads a valid one as V8
// reads it outside the `u` and `v` modes (the syntax of Annex B of the specification, and V8's
// regexp-parser.cc where it says more) into the nodes regexp_match.v compiles and runs, over the
// UTF-16 units of the text instead of its code points:
// - `{`, `}` and `]` are ordinary characters, unless a `{` starts a quantifier (`{2}`, `{2,}`,
//   `{2,3}`);
// - a lookahead can be repeated;
// - `\1`…`\9` with more digits is a backreference when the pattern has that many groups, and
//   otherwise an octal escape of up to three digits (`\8` and `\9` are those digits); `\0` starts an
//   octal escape too;
// - `\k<name>` is a backreference only in a pattern with named groups; `\x` and `\u` without their
//   digits, and any other escaped character, are the character itself (`\u{…}` and `\p{…}` are not
//   escapes); `\c` without a letter after it is a backslash;
// - in a class, `\c` also takes a digit or `_`, and a range with a class at one end (`[\d-a]`) is
//   that class, a `-` and the other end.
// With the `i` flag of a modifier (`(?i:…)`), two units match when Canonicalize of the
// specification gives the same for both: the one unit `toUpperCase` gives, unless it leaves ASCII.

struct RxLegacyParser {
	src      []u32            // UTF-16 units
	names    map[string][]int // group name -> capture numbers
	captures int              // capturing groups of the whole pattern
mut:
	pos       int
	group     int // capture numbers given so far
	icase     bool
	multiline bool
	dot_all   bool
	canon     []u16 // Canonicalize of every unit, once a modifier asks to ignore case
}

// regexp_compile_annex_b compiles `pattern` as `new RegExp(pattern)`. It fails for a pattern V8
// rejects, and for one too large for the matcher.
fn regexp_compile_annex_b(pattern []u16) !RegexpProgram {
	regexp_new(pattern, '') or {
		return error('invalid regular expression /${stv_units_string(pattern)}/')
	}
	src := pattern.map(u32(it))
	mut p := RxLegacyParser{
		src:      src
		names:    rx_group_names(src)
		captures: rx_count_captures(src)
	}
	root := p.disjunction()!
	mut c := RxCompiler{
		slots: 2 * (p.group + 1)
	}
	c.emit(root, false)!
	c.insts << RxInst{
		op: .match_
	}
	return RegexpProgram{
		insts:  c.insts
		groups: p.group
		slots:  c.slots
	}
}

// regexp_test_annex_b ports `regexp.test(text)` for a regular expression without flags: whether the
// pattern matches somewhere in the UTF-16 units of the text. It fails if the search takes too
// long (V8 would keep going).
fn regexp_test_annex_b(prog RegexpProgram, text []u16) !bool {
	mut m := RxMatcher{
		prog:  prog
		input: text.map(u32(it))
	}
	for start in 0 .. m.input.len + 1 {
		mut slots := []int{len: prog.slots, init: -1}
		if m.run(0, start, mut slots) {
			return true
		}
		if m.aborted {
			return error('the regular expression takes too long on `${stv_units_string(text)}`')
		}
	}
	return false
}

// rx_count_captures counts the capturing groups of a pattern (V8's ScanForCaptures): every `(`
// outside a class that is not followed by `?`, and the named groups.
fn rx_count_captures(src []u32) int {
	mut count := 0
	mut in_class := false
	mut i := 0
	for i < src.len {
		c := src[i]
		if c == `\\` {
			i += 2
			continue
		}
		if in_class {
			in_class = c != `]`
		} else if c == `[` {
			in_class = true
		} else if c == `(` {
			if i + 1 >= src.len || src[i + 1] != `?` {
				count++
			} else if i + 3 < src.len && src[i + 2] == `<` && src[i + 3] != `=` && src[i + 3] != `!` {
				count++
			}
		}
		i++
	}
	return count
}

fn (p &RxLegacyParser) peek(offset int) u32 {
	return if p.pos + offset < p.src.len { p.src[p.pos + offset] } else { u32(0xffffffff) }
}

fn (mut p RxLegacyParser) eat(c u32) bool {
	if p.peek(0) == c {
		p.pos++
		return true
	}
	return false
}

fn (mut p RxLegacyParser) disjunction() !RxNode {
	mut alternatives := [p.alternative()!]
	for p.eat(`|`) {
		alternatives << p.alternative()!
	}
	if alternatives.len == 1 {
		return alternatives[0]
	}
	return RxNode{
		kind:     .alt_
		children: alternatives
	}
}

fn (mut p RxLegacyParser) alternative() !RxNode {
	mut items := []RxNode{}
	for p.pos < p.src.len && p.peek(0) != `|` && p.peek(0) != `)` {
		items << p.term()!
	}
	return RxNode{
		kind:     .seq_
		children: items
	}
}

fn (mut p RxLegacyParser) term() !RxNode {
	first := p.group + 1
	atom := p.atom()!
	min, max := p.quantifier() or { return atom }
	lazy := p.eat(`?`)
	return RxNode{
		kind:     .repeat_
		min:      min
		max:      max
		lazy:     lazy
		children: [atom]
		first:    first
		last:     p.group
	}
}

// quantifier reads `*`, `+`, `?`, `{n}`, `{n,}` or `{n,m}`; none when there is no quantifier: a
// `{` that does not start one of those is a character.
fn (mut p RxLegacyParser) quantifier() ?(int, int) {
	if p.eat(`*`) {
		return 0, -1
	}
	if p.eat(`+`) {
		return 1, -1
	}
	if p.eat(`?`) {
		return 0, 1
	}
	if !p.at_interval() {
		return none
	}
	p.pos++
	min := p.decimal()
	mut max := min
	if p.eat(`,`) {
		max = if p.peek(0) == `}` { -1 } else { p.decimal() }
	}
	p.pos++ // `}`
	return min, max
}

// at_interval: a `{n}`, `{n,}` or `{n,m}` starts here.
fn (p &RxLegacyParser) at_interval() bool {
	if p.peek(0) != `{` {
		return false
	}
	mut i := 1
	mut digits := 0
	for p.peek(i) >= `0` && p.peek(i) <= `9` {
		i++
		digits++
	}
	if digits == 0 {
		return false
	}
	if p.peek(i) == `,` {
		i++
		for p.peek(i) >= `0` && p.peek(i) <= `9` {
			i++
		}
	}
	return p.peek(i) == `}`
}

// decimal reads digits; a number too large to count is as good as the largest one.
fn (mut p RxLegacyParser) decimal() int {
	mut n := i64(0)
	for p.peek(0) >= `0` && p.peek(0) <= `9` {
		n = n * 10 + i64(p.peek(0) - `0`)
		if n > max_i32 {
			n = max_i32
		}
		p.pos++
	}
	return int(n)
}

fn (mut p RxLegacyParser) atom() !RxNode {
	c := p.peek(0)
	p.pos++
	match c {
		`^` {
			return RxNode{
				kind:      .start_
				multiline: p.multiline
			}
		}
		`$` {
			return RxNode{
				kind:      .end_
				multiline: p.multiline
			}
		}
		`.` {
			return RxNode{
				kind:    .any_
				dot_all: p.dot_all
			}
		}
		`[` {
			return p.class()
		}
		`(` {
			return p.group_atom()
		}
		`\\` {
			return p.atom_escape()
		}
		else {
			return p.char_node(c)
		}
	}
}

// char_node is the atom of one unit: ignoring case, the set of the units with its canonical form.
fn (mut p RxLegacyParser) char_node(c u32) RxNode {
	if p.icase {
		return p.set_node([c, c], false)
	}
	return RxNode{
		kind:  .char_
		value: c
	}
}

// set_node is the atom of a set of units: ignoring case, with every unit whose canonical form is
// the one of a member.
fn (mut p RxLegacyParser) set_node(ranges []u32, negated bool) RxNode {
	if !p.icase {
		return rx_set(ranges, negated)
	}
	if p.canon.len == 0 {
		p.canon = []u16{len: 0x10000}
		for unit in 0 .. 0x10000 {
			p.canon[unit] = rx_legacy_canonicalize(u16(unit))
		}
	}
	set := rx_normalize(ranges)
	mut wanted := []bool{len: 0x10000}
	for unit in 0 .. 0x10000 {
		if rx_in_ranges(set, u32(unit)) {
			wanted[p.canon[unit]] = true
		}
	}
	mut closure := []u32{}
	for unit in 0 .. 0x10000 {
		if wanted[p.canon[unit]] {
			closure << [u32(unit), u32(unit)]
		}
	}
	return rx_set(closure, negated)
}

// rx_legacy_canonicalize ports Canonicalize of the specification for a pattern that ignores case
// outside the `u` and `v` modes: the upper case of the unit when that is one unit, and not an
// ASCII one for a unit that is not.
fn rx_legacy_canonicalize(unit u16) u16 {
	upper := js_to_upper([unit])
	if upper.len != 1 || (unit >= 128 && upper[0] < 128) {
		return unit
	}
	return upper[0]
}

fn (mut p RxLegacyParser) group_atom() !RxNode {
	mut node := RxNode{}
	if !p.eat(`?`) {
		p.group++
		index := p.group
		node = RxNode{
			kind:     .group_
			index:    index
			children: [p.disjunction()!]
		}
	} else if p.eat(`:`) {
		node = RxNode{
			kind:     .group_
			children: [p.disjunction()!]
		}
	} else if p.peek(0) == `=` || p.peek(0) == `!` {
		negated := p.peek(0) == `!`
		p.pos++
		node = RxNode{
			kind:     .look_
			negated:  negated
			children: [p.disjunction()!]
		}
	} else if p.peek(0) == `<` && (p.peek(1) == `=` || p.peek(1) == `!`) {
		negated := p.peek(1) == `!`
		p.pos += 2
		node = RxNode{
			kind:     .look_
			negated:  negated
			behind:   true
			children: [p.disjunction()!]
		}
	} else if p.eat(`<`) {
		for p.peek(0) != `>` {
			p.pos++
		}
		p.pos++
		p.group++
		index := p.group
		node = RxNode{
			kind:     .group_
			index:    index
			children: [p.disjunction()!]
		}
	} else {
		// Modifiers: `(?ims-ims:…)` sets the flags before the `-` and clears the ones after it,
		// for its body.
		icase, multiline, dot_all := p.icase, p.multiline, p.dot_all
		mut on := true
		for p.pos < p.src.len && p.peek(0) != `:` {
			match p.peek(0) {
				`-` { on = false }
				`i` { p.icase = on }
				`m` { p.multiline = on }
				else { p.dot_all = on }
			}
			p.pos++
		}
		p.pos++
		node = RxNode{
			kind:     .group_
			children: [p.disjunction()!]
		}
		p.icase = icase
		p.multiline = multiline
		p.dot_all = dot_all
	}
	p.pos++ // `)`
	return node
}

// class_set is the set of `\d`, `\D`, `\w`, `\W`, `\s` or `\S`, if `c` is one of those letters.
fn rx_legacy_class_set(c u32) ?[]u32 {
	set := match c {
		`d`, `D` { rx_digit.clone() }
		`w`, `W` { rx_word.clone() }
		`s`, `S` { rx_space.clone() }
		else { return none }
	}
	return if c in [u32(`D`), `W`, `S`] { rx_complement(set) } else { set }
}

// atom_escape reads what follows a `\` outside a class (V8's ParseDisjunction for an escape).
fn (mut p RxLegacyParser) atom_escape() !RxNode {
	c := p.peek(0)
	if set := rx_legacy_class_set(c) {
		p.pos++
		return p.set_node(set, false)
	}
	match c {
		`b` {
			p.pos++
			return RxNode{
				kind:   .boundary
				ranges: rx_word.clone()
			}
		}
		`B` {
			p.pos++
			return RxNode{
				kind:   .not_boundary
				ranges: rx_word.clone()
			}
		}
		u32(`1`)...u32(`9`) {
			// A backreference when the pattern has that many groups (ParseBackReferenceIndex);
			// otherwise `\8` and `\9` are those digits, and the rest an octal escape.
			start := p.pos
			index := p.decimal()
			if index <= p.captures {
				if p.icase {
					return error('veslint does not match a backreference that ignores case outside the `u` mode')
				}
				return RxNode{
					kind:    .backref_
					indexes: [index]
				}
			}
			p.pos = start
			if c >= `8` {
				p.pos++
				return p.char_node(c)
			}
			return p.char_node(p.octal())
		}
		`0` {
			return p.char_node(p.octal())
		}
		`k` {
			if p.names.len > 0 {
				p.pos += 2 // `k<`
				start := p.pos
				for p.peek(0) != `>` {
					p.pos++
				}
				name := rx_text(p.src[start..p.pos])
				p.pos++
				if p.icase {
					return error('veslint does not match a backreference that ignores case outside the `u` mode')
				}
				return RxNode{
					kind:    .backref_
					indexes: p.names[name] or { []int{} }
				}
			}
			p.pos++
			return p.char_node(c)
		}
		else {
			return p.char_node(p.character_escape(false))
		}
	}
}

// octal ports ParseOctalLiteral: up to three octal digits with a value below 256.
fn (mut p RxLegacyParser) octal() u32 {
	mut value := p.peek(0) - `0`
	p.pos++
	if p.peek(0) >= `0` && p.peek(0) <= `7` {
		value = value * 8 + (p.peek(0) - `0`)
		p.pos++
		if value < 32 && p.peek(0) >= `0` && p.peek(0) <= `7` {
			value = value * 8 + (p.peek(0) - `0`)
			p.pos++
		}
	}
	return value
}

// character_escape ports ParseCharacterEscape outside the `u` mode: the unit an escape stands
// for, after its `\`.
fn (mut p RxLegacyParser) character_escape(in_class bool) u32 {
	c := p.peek(0)
	match c {
		`f` {
			p.pos++
			return 0x0c
		}
		`n` {
			p.pos++
			return 0x0a
		}
		`r` {
			p.pos++
			return 0x0d
		}
		`t` {
			p.pos++
			return 0x09
		}
		`v` {
			p.pos++
			return 0x0b
		}
		`c` {
			letter := p.peek(1)
			if regexp_is_ascii_letter(letter)
				|| (in_class && ((letter >= `0` && letter <= `9`) || letter == `_`)) {
				p.pos += 2
				return letter & 0x1f
			}
			// The backslash is a character, and the `c` after it is read next.
			return u32(`\\`)
		}
		u32(`0`)...u32(`7`) {
			return p.octal()
		}
		`x` {
			p.pos++
			return p.hex(2) or { c }
		}
		`u` {
			p.pos++
			return p.hex(4) or { c }
		}
		else {
			p.pos++
			return c
		}
	}
}

// hex reads exactly `count` hexadecimal digits; none, without moving, when they are not there.
fn (mut p RxLegacyParser) hex(count int) ?u32 {
	mut value := u32(0)
	for i in 0 .. count {
		digit := regexp_hex_value(p.peek(i))
		if digit < 0 {
			return none
		}
		value = value * 16 + u32(digit)
	}
	p.pos += count
	return value
}

// class reads a character class after its `[` (V8's ParseCharacterClass).
fn (mut p RxLegacyParser) class() !RxNode {
	negated := p.eat(`^`)
	mut ranges := []u32{}
	for p.pos < p.src.len && p.peek(0) != `]` {
		first_set, low := p.class_atom(mut ranges)
		if p.peek(0) != `-` {
			if !first_set {
				ranges << [low, low]
			}
			continue
		}
		p.pos++
		if p.peek(0) == `]` {
			if !first_set {
				ranges << [low, low]
			}
			ranges << [u32(`-`), `-`]
			break
		}
		second_set, high := p.class_atom(mut ranges)
		if first_set || second_set {
			// A class at either end: the `-` is a character.
			if !first_set {
				ranges << [low, low]
			}
			ranges << [u32(`-`), `-`]
			if !second_set {
				ranges << [high, high]
			}
			continue
		}
		ranges << [low, high]
	}
	p.pos++
	return p.set_node(ranges, negated)
}

// class_atom reads one atom of a class: a class escape adds its set to `ranges` and returns true;
// anything else returns its unit.
fn (mut p RxLegacyParser) class_atom(mut ranges []u32) (bool, u32) {
	c := p.peek(0)
	p.pos++
	if c != `\\` {
		return false, c
	}
	e := p.peek(0)
	if set := rx_legacy_class_set(e) {
		p.pos++
		ranges << set
		return true, u32(0)
	}
	if e == `b` {
		p.pos++
		return false, u32(0x08)
	}
	return false, p.character_escape(true)
}
