module rules

// Matcher of JavaScript regular expressions in the `u` mode, for the rule options that are
// patterns: ESLint builds them with `new RegExp(pattern, 'u')` and calls `test(text)`
// (dot-notation's allowPattern, switch-exhaustiveness-check's defaultCaseCommentPattern, and
// naming-convention's custom and filter).
// regexp_new (regexp_syntax.v) tells whether V8 accepts the pattern; regexp_compile turns a valid
// one into a backtracking program, which regexp_test runs over the code points of the text with
// the semantics of the specification: greedy and lazy quantifiers, an optional iteration that
// matches nothing fails, the captures of a quantified atom are cleared on every iteration,
// lookbehind matches backwards, and a lookaround is not backtracked into.
// Unicode property escapes (`\p{…}`) and the `i` flag of a modifier (`(?i:…)`) use the data of
// regexp_property_data.v, which comes from V8 itself. With `i`, a character matches a set if one
// of the members of the set has its canonical form (Canonicalize of the specification, the
// simple case folding): the parser adds to every set the code points of the case classes of its
// members, so the matcher only folds for a backreference.
// V8 14.6 has two more ways of answering a pattern with the `i` flag in a modifier, which depend
// on whether it optimized the pattern (see tools/gen_regexp_match_cases.mjs); this matcher gives
// the answer of the specification, except for what RxParser.last_group_icase describes.

enum RxKind {
	empty
	char_
	any_
	set_
	start_
	end_
	boundary
	not_boundary
	group_
	backref_
	look_
	alt_
	seq_
	repeat_
}

struct RxNode {
	kind      RxKind
	value     u32   // char_: the code point
	ranges    []u32 // set_: pairs of first and last code point
	negated   bool  // set_: the complement; look_: a negative lookaround
	behind    bool  // look_: a lookbehind
	index     int   // group_: its capture number, 0 for a group that does not capture
	indexes   []int // backref_: the groups it may refer to (several with duplicate names)
	min       int
	max       int // repeat_: -1 for no limit
	lazy      bool
	icase     bool     // backref_: compared ignoring case
	multiline bool     // start_ and end_: also at the line terminators
	dot_all   bool     // any_: also the line terminators
	children  []RxNode // seq_ and alt_: the items; group_, look_ and repeat_: the body
	first     int      // repeat_: the captures inside the body are first..last
	last      int
}

enum RxOp {
	char_
	any_
	set_
	start_
	end_
	boundary
	not_boundary
	split // try x, then y
	jmp
	save
	backref
	look
	mark  // remember the position in register x
	check // fail if the position is the one of register x
	clear // forget the captures x..y
	match_
}

struct RxInst {
	op        RxOp
	value     u32
	ranges    []u32 // set_: its code points; boundary and not_boundary: the word characters
	negated   bool
	backward  bool
	icase     bool
	multiline bool
	dot_all   bool
	x         int
	y         int
	indexes   []int
}

// RegexpProgram is a compiled pattern.
struct RegexpProgram {
	insts  []RxInst
	groups int // capturing groups
	slots  int // capture positions and loop registers
}

const rx_max_insts = 20000
const rx_max_steps = 2000000
const rx_last_code_point = u32(0x10ffff)
const rx_digit = [u32(`0`), `9`]
const rx_word = [u32(`0`), `9`, `A`, `Z`, `_`, `_`, `a`, `z`]
// WhiteSpace and LineTerminator of the specification.
const rx_space = [u32(0x09), 0x0d, 0x20, 0x20, 0xa0, 0xa0, 0x1680, 0x1680, 0x2000, 0x200a, 0x2028,
	0x2029, 0x202f, 0x202f, 0x205f, 0x205f, 0x3000, 0x3000, 0xfeff, 0xfeff]

struct RxParser {
	src   []u32
	names map[string][]int // group name -> capture numbers
mut:
	pos   int
	group int // capture numbers given so far
	// The flags in effect, all off at the start: `(?ims-ims:…)` changes them for its body.
	icase     bool
	multiline bool
	dot_all   bool
	// The `i` flag of the last group that was opened, which stays after the group is closed.
	// The specification only knows the flag in effect, but V8 14.6 (the engine of ESLint) asks
	// this one in two places, and veslint does what V8 does:
	// - `\w` and `\W` get the letters that are word characters only when case is ignored (U+017F
	//   and U+212A) by this flag: `/(?i:x)|\w/u` matches U+017F and `/(?i:x)|(?:\w)/u` does not;
	// - a class in brackets ignores case only if both flags are set: `/(?i:(?-i:x)|[a])/u` does
	//   not match `A`, and `/(?i:(?-i:x)|a)/u` and `/(?i:(?-i:x)|(?:[a]))/u` do.
	last_group_icase bool
}

// regexp_compile compiles `pattern` as `new RegExp(pattern, 'u')`. It fails for a pattern V8
// rejects and for the constructs this matcher does not support.
fn regexp_compile(pattern string) !RegexpProgram {
	units := utf16_units(pattern)
	regexp_new(units, 'u') or { return error('invalid regular expression /${pattern}/u') }
	src := regexp_chars(units, .unicode)
	mut p := RxParser{
		src:   src
		names: rx_group_names(src)
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

// rx_group_names numbers the capturing groups in the order of their `(` and maps each name to its
// numbers, so a `\k<name>` before the group resolves.
fn rx_group_names(src []u32) map[string][]int {
	mut by_name := map[string][]int{}
	mut group := 0
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
				group++
			} else if i + 3 < src.len && src[i + 2] == `<` && src[i + 3] != `=` && src[i + 3] != `!` {
				group++
				mut end := i + 3
				for end < src.len && src[end] != `>` {
					end++
				}
				by_name[rx_text(src[i + 3..end])] << group
			}
		}
		i++
	}
	return by_name
}

fn rx_text(chars []u32) string {
	return chars.map(rune(it)).string()
}

fn (p &RxParser) peek(offset int) u32 {
	return if p.pos + offset < p.src.len { p.src[p.pos + offset] } else { u32(0xffffffff) }
}

fn (mut p RxParser) eat(c u32) bool {
	if p.peek(0) == c {
		p.pos++
		return true
	}
	return false
}

fn (mut p RxParser) disjunction() !RxNode {
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

fn (mut p RxParser) alternative() !RxNode {
	mut items := []RxNode{}
	for p.pos < p.src.len && p.peek(0) != `|` && p.peek(0) != `)` {
		items << p.term()!
	}
	return RxNode{
		kind:     .seq_
		children: items
	}
}

fn (mut p RxParser) term() !RxNode {
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

// quantifier reads `*`, `+`, `?`, `{n}`, `{n,}` or `{n,m}`; none when there is no quantifier.
fn (mut p RxParser) quantifier() ?(int, int) {
	if p.eat(`*`) {
		return 0, -1
	}
	if p.eat(`+`) {
		return 1, -1
	}
	if p.eat(`?`) {
		return 0, 1
	}
	if p.peek(0) != `{` {
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

// decimal reads digits; a number too large to count is as good as the largest one.
fn (mut p RxParser) decimal() int {
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

fn (mut p RxParser) atom() !RxNode {
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

// char_node is the atom of one code point: with the `i` flag, the set of its case class.
fn (p &RxParser) char_node(c u32) RxNode {
	if p.icase {
		class := rx_case_closure([c, c])
		if class != [c, c] {
			return rx_set(class, false)
		}
	}
	return RxNode{
		kind:  .char_
		value: c
	}
}

// set_node is the atom of a set of code points: ignoring case, with the case classes of its
// members.
fn set_node(ranges []u32, negated bool, icase bool) RxNode {
	return rx_set(if icase { rx_case_closure(ranges) } else { ranges }, negated)
}

// rx_word_chars are the characters of `\w` (WordCharacters of the specification): ignoring case,
// also the ones of the case classes of a letter (U+017F and U+212A).
fn rx_word_chars(icase bool) []u32 {
	return if icase { rx_case_closure(rx_word) } else { rx_word.clone() }
}

// group_body reads the disjunction of a group that was just opened.
fn (mut p RxParser) group_body() !RxNode {
	p.last_group_icase = p.icase
	return p.disjunction()
}

fn (mut p RxParser) group_atom() !RxNode {
	mut node := RxNode{}
	if !p.eat(`?`) {
		p.group++
		index := p.group
		node = RxNode{
			kind:     .group_
			index:    index
			children: [p.group_body()!]
		}
	} else if p.eat(`:`) {
		node = RxNode{
			kind:     .group_
			children: [p.group_body()!]
		}
	} else if p.peek(0) == `=` || p.peek(0) == `!` {
		negated := p.peek(0) == `!`
		p.pos++
		node = RxNode{
			kind:     .look_
			negated:  negated
			children: [p.group_body()!]
		}
	} else if p.peek(0) == `<` && (p.peek(1) == `=` || p.peek(1) == `!`) {
		negated := p.peek(1) == `!`
		p.pos += 2
		node = RxNode{
			kind:     .look_
			negated:  negated
			behind:   true
			children: [p.group_body()!]
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
			children: [p.group_body()!]
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
			children: [p.group_body()!]
		}
		p.icase = icase
		p.multiline = multiline
		p.dot_all = dot_all
	}
	p.pos++ // `)`
	return node
}

// rx_set is the node of a set: its ranges sorted and disjoint, as the matcher expects them.
fn rx_set(ranges []u32, negated bool) RxNode {
	return RxNode{
		kind:    .set_
		ranges:  rx_normalize(ranges)
		negated: negated
	}
}

// class_escape is the set of `\d`, `\D`, `\w`, `\W`, `\s`, `\S`, `\p{…}` or `\P{…}`, if `c` (the
// character after the `\`, already read) is one of those letters. The capital letters are the
// complement (CharacterComplement of the specification).
fn (mut p RxParser) class_escape(c u32) !(bool, []u32) {
	mut set := []u32{}
	match c {
		`d`, `D` { set = rx_digit.clone() }
		`w`, `W` { set = rx_word_chars(p.last_group_icase) }
		`s`, `S` { set = rx_space.clone() }
		`p`, `P` { set = p.property()! }
		else { return false, set }
	}
	return true, if c in [u32(`D`), `W`, `S`, `P`] { rx_complement(set) } else { set }
}

// property reads the `{…}` of `\p{…}`: the code points of the property.
fn (mut p RxParser) property() ![]u32 {
	p.pos++ // `{`
	start := p.pos
	for p.pos < p.src.len && p.peek(0) != `}` {
		p.pos++
	}
	text := rx_text(p.src[start..p.pos])
	p.pos++
	return regexp_property_ranges(text) or {
		return error('veslint has no data for the Unicode property `${text}`')
	}
}

// regexp_property_ranges gives the code points of `\p{text}` as sorted [first, last] pairs:
// `Name=Value` for General_Category, Script and Script_Extensions (or gc, sc and scx), or alone a
// value of General_Category or a binary property.
fn regexp_property_ranges(text string) ?[]u32 {
	mut keys := []string{}
	if text.contains('=') {
		prefix := match text.all_before('=') {
			'General_Category', 'gc' { 'gc' }
			'Script', 'sc' { 'sc' }
			'Script_Extensions', 'scx' { 'scx' }
			else { return none }
		}
		keys << '${prefix}=${text.all_after('=')}'
	} else {
		keys << 'gc=${text}'
		keys << text
	}
	for i, set_keys in regexp_property_keys {
		for key in set_keys.split(' ') {
			if key in keys {
				return rx_decode_ranges(regexp_property_sets[i])
			}
		}
	}
	return none
}

// rx_decode_ranges reads a set of regexp_property_sets.
fn rx_decode_ranges(data string) []u32 {
	mut out := []u32{cap: data.len}
	mut next := u32(0)
	mut first := u32(0)
	mut is_first := true
	mut value := u32(0)
	mut shift := u32(0)
	for c in data {
		group := u32(regexp_property_alphabet.index_u8(c))
		value |= (group & 31) << shift
		if group & 32 != 0 {
			shift += 5
			continue
		}
		if is_first {
			first = next + value
		} else {
			out << [first, first + value]
			next = first + value + 1
		}
		is_first = !is_first
		value = 0
		shift = 0
	}
	return out
}

// rx_fold gives the code point that stands for the case class of `c` (the lowest of the class):
// `c` itself when no other code point is equal to it ignoring case.
fn rx_fold(c u32) u32 {
	mut low := 0
	mut high := regexp_case_folds.len / 2 - 1
	for low <= high {
		mid := (low + high) / 2
		key := regexp_case_folds[2 * mid]
		if key == c {
			return regexp_case_folds[2 * mid + 1]
		}
		if key < c {
			low = mid + 1
		} else {
			high = mid - 1
		}
	}
	return c
}

// rx_case_closure adds to a set the code points that are equal to one of its members ignoring
// case.
fn rx_case_closure(ranges []u32) []u32 {
	set := rx_normalize(ranges)
	// The classes with a member in the set, by the code point that stands for them.
	mut classes := map[u32]bool{}
	for i := 0; i < regexp_case_folds.len; i += 2 {
		if rx_in_ranges(set, regexp_case_folds[i]) || rx_in_ranges(set, regexp_case_folds[i + 1]) {
			classes[regexp_case_folds[i + 1]] = true
		}
	}
	if classes.len == 0 {
		return set
	}
	mut out := set.clone()
	for i := 0; i < regexp_case_folds.len; i += 2 {
		if classes[regexp_case_folds[i + 1]] {
			out << [regexp_case_folds[i], regexp_case_folds[i]]
			out << [regexp_case_folds[i + 1], regexp_case_folds[i + 1]]
		}
	}
	return rx_normalize(out)
}

// rx_normalize sorts the ranges of a set and joins the ones that overlap or touch.
fn rx_normalize(ranges []u32) []u32 {
	mut pairs := []u64{cap: ranges.len / 2}
	for i := 0; i < ranges.len; i += 2 {
		pairs << (u64(ranges[i]) << 32) | u64(ranges[i + 1])
	}
	pairs.sort()
	mut out := []u32{cap: ranges.len}
	for pair in pairs {
		first := u32(pair >> 32)
		last := u32(pair & 0xffffffff)
		if out.len > 0 && first <= out[out.len - 1] + 1 {
			if last > out[out.len - 1] {
				out[out.len - 1] = last
			}
			continue
		}
		out << [first, last]
	}
	return out
}

fn (mut p RxParser) atom_escape() !RxNode {
	c := p.peek(0)
	p.pos++
	is_set, ranges := p.class_escape(c)!
	if is_set {
		return set_node(ranges, false, p.icase)
	}
	if c >= `1` && c <= `9` {
		p.pos--
		return RxNode{
			kind:    .backref_
			indexes: [p.decimal()]
			icase:   p.icase
		}
	}
	match c {
		`b` {
			return RxNode{
				kind:   .boundary
				ranges: rx_word_chars(p.icase)
			}
		}
		`B` {
			return RxNode{
				kind:   .not_boundary
				ranges: rx_word_chars(p.icase)
			}
		}
		`k` {
			p.pos++ // `<`
			start := p.pos
			for p.peek(0) != `>` {
				p.pos++
			}
			name := rx_text(p.src[start..p.pos])
			p.pos++
			return RxNode{
				kind:    .backref_
				indexes: p.names[name] or { []int{} }
				icase:   p.icase
			}
		}
		else {
			p.pos--
			return p.char_node(p.character_escape())
		}
	}
}

// character_escape reads, after the `\`, an escape that stands for one code point.
fn (mut p RxParser) character_escape() u32 {
	c := p.peek(0)
	p.pos++
	match c {
		`f` {
			return 0x0c
		}
		`n` {
			return 0x0a
		}
		`r` {
			return 0x0d
		}
		`t` {
			return 0x09
		}
		`v` {
			return 0x0b
		}
		`0` {
			return 0
		}
		`c` {
			letter := p.peek(0)
			p.pos++
			return letter % 32
		}
		`x` {
			return p.hex(2)
		}
		`u` {
			if p.eat(`{`) {
				mut value := u32(0)
				for p.peek(0) != `}` {
					value = value * 16 + u32(regexp_hex_value(p.peek(0)))
					p.pos++
				}
				p.pos++
				return value
			}
			lead := p.hex(4)
			// A lead surrogate followed by an escaped trail surrogate is one code point.
			if lead >= 0xd800 && lead <= 0xdbff && p.peek(0) == `\\` && p.peek(1) == `u` {
				saved := p.pos
				p.pos += 2
				if p.peek(0) != `{` {
					trail := p.hex(4)
					if trail >= 0xdc00 && trail <= 0xdfff {
						return 0x10000 + ((lead - 0xd800) << 10) + (trail - 0xdc00)
					}
				}
				p.pos = saved
			}
			return lead
		}
		else {
			// An identity escape: a syntax character or `/`.
			return c
		}
	}
}

fn (mut p RxParser) hex(count int) u32 {
	mut value := u32(0)
	for _ in 0 .. count {
		value = value * 16 + u32(regexp_hex_value(p.peek(0)))
		p.pos++
	}
	return value
}

// class reads a character class after its `[`.
fn (mut p RxParser) class() !RxNode {
	negated := p.eat(`^`)
	mut ranges := []u32{}
	for p.peek(0) != `]` {
		is_set, low := p.class_atom(mut ranges)!
		if is_set {
			continue
		}
		if p.peek(0) == `-` && p.peek(1) != `]` {
			p.pos++
			other_set, high := p.class_atom(mut ranges)!
			if !other_set {
				ranges << [low, high]
				continue
			}
			// Not reachable in the `u` mode (V8 rejects a range with a class escape).
			ranges << [u32(`-`), `-`]
		}
		ranges << [low, low]
	}
	p.pos++
	return set_node(ranges, negated, p.icase && p.last_group_icase)
}

// class_atom reads one atom of a class: a class escape adds its set to `ranges` and returns true;
// anything else returns its code point.
fn (mut p RxParser) class_atom(mut ranges []u32) !(bool, u32) {
	c := p.peek(0)
	p.pos++
	if c != `\\` {
		return false, c
	}
	e := p.peek(0)
	p.pos++
	is_set, set := p.class_escape(e)!
	if is_set {
		ranges << set
		return true, u32(0)
	}
	p.pos--
	if e == `b` {
		p.pos++
		return false, u32(0x08)
	}
	if e == `-` {
		p.pos++
		return false, u32(`-`)
	}
	return false, p.character_escape()
}

// rx_complement gives the code points outside sorted, disjoint ranges.
fn rx_complement(ranges []u32) []u32 {
	mut out := []u32{}
	mut next := u32(0)
	for i := 0; i < ranges.len; i += 2 {
		if ranges[i] > next {
			out << [next, ranges[i] - 1]
		}
		next = ranges[i + 1] + 1
	}
	if next <= rx_last_code_point {
		out << [next, rx_last_code_point]
	}
	return out
}

struct RxCompiler {
mut:
	insts []RxInst
	slots int
}

fn (mut c RxCompiler) add(inst RxInst) !int {
	if c.insts.len >= rx_max_insts {
		return error('the regular expression is too large for veslint')
	}
	c.insts << inst
	return c.insts.len - 1
}

// patch sets the targets of a split or a jmp emitted before its destination was known.
fn (mut c RxCompiler) patch(at int, x int, y int) {
	c.insts[at] = RxInst{
		...c.insts[at]
		x: x
		y: y
	}
}

// emit appends the program of `node`. `backward` is the direction of a lookbehind: the items of a
// sequence go in reverse and each step reads the code point before the position.
fn (mut c RxCompiler) emit(node RxNode, backward bool) ! {
	match node.kind {
		.empty {}
		.char_ {
			c.add(RxInst{ op: .char_, value: node.value, backward: backward })!
		}
		.any_ {
			c.add(RxInst{ op: .any_, backward: backward, dot_all: node.dot_all })!
		}
		.set_ {
			c.add(RxInst{
				op:       .set_
				ranges:   node.ranges
				negated:  node.negated
				backward: backward
			})!
		}
		.start_ {
			c.add(RxInst{ op: .start_, multiline: node.multiline })!
		}
		.end_ {
			c.add(RxInst{ op: .end_, multiline: node.multiline })!
		}
		.boundary {
			c.add(RxInst{ op: .boundary, ranges: node.ranges })!
		}
		.not_boundary {
			c.add(RxInst{ op: .not_boundary, ranges: node.ranges })!
		}
		.seq_ {
			if backward {
				for i := node.children.len - 1; i >= 0; i-- {
					c.emit(node.children[i], backward)!
				}
			} else {
				for child in node.children {
					c.emit(child, backward)!
				}
			}
		}
		.alt_ {
			mut jumps := []int{}
			for i, child in node.children {
				if i == node.children.len - 1 {
					c.emit(child, backward)!
					break
				}
				split := c.add(RxInst{ op: .split })!
				c.emit(child, backward)!
				jumps << c.add(RxInst{ op: .jmp })!
				c.patch(split, split + 1, c.insts.len)
			}
			for jump in jumps {
				c.patch(jump, c.insts.len, 0)
			}
		}
		.group_ {
			if node.index == 0 {
				c.emit(node.children[0], backward)!
				return
			}
			// Backwards, the end of the capture is found first.
			first := if backward { 2 * node.index + 1 } else { 2 * node.index }
			c.add(RxInst{ op: .save, x: first })!
			c.emit(node.children[0], backward)!
			c.add(RxInst{ op: .save, x: first ^ 1 })!
		}
		.backref_ {
			c.add(RxInst{
				op:       .backref
				indexes:  node.indexes
				backward: backward
				icase:    node.icase
			})!
		}
		.look_ {
			// look x: the sub-program starts at the next instruction and ends in a match_; x is
			// where the program continues.
			look := c.add(RxInst{ op: .look, negated: node.negated })!
			c.emit(node.children[0], node.behind)!
			c.add(RxInst{ op: .match_ })!
			c.patch(look, c.insts.len, 0)
		}
		.repeat_ {
			c.emit_repeat(node, backward)!
		}
	}
}

// emit_iteration appends one iteration of a quantified atom: its captures are cleared first.
fn (mut c RxCompiler) emit_iteration(node RxNode, backward bool) ! {
	if node.last >= node.first {
		c.add(RxInst{ op: .clear, x: node.first, y: node.last })!
	}
	c.emit(node.children[0], backward)!
}

// emit_optional appends an iteration beyond the minimum: it fails if it matches nothing.
fn (mut c RxCompiler) emit_optional(node RxNode, backward bool) ! {
	register := c.slots
	c.slots++
	c.add(RxInst{ op: .mark, x: register })!
	c.emit_iteration(node, backward)!
	c.add(RxInst{ op: .check, x: register })!
}

fn (mut c RxCompiler) emit_repeat(node RxNode, backward bool) ! {
	for _ in 0 .. node.min {
		c.emit_iteration(node, backward)!
	}
	if node.max == -1 {
		// L: split body, end; body; jmp L
		split := c.add(RxInst{ op: .split })!
		c.emit_optional(node, backward)!
		c.add(RxInst{ op: .jmp, x: split })!
		c.patch_split(split, split + 1, c.insts.len, node.lazy)
		return
	}
	// Each optional iteration can only follow the previous one.
	mut splits := []int{}
	for _ in node.min .. node.max {
		splits << c.add(RxInst{ op: .split })!
		c.emit_optional(node, backward)!
	}
	for split in splits {
		c.patch_split(split, split + 1, c.insts.len, node.lazy)
	}
}

// patch_split sets a split that prefers `body` (greedy) or `end` (lazy).
fn (mut c RxCompiler) patch_split(at int, body int, end int, lazy bool) {
	if lazy {
		c.patch(at, end, body)
	} else {
		c.patch(at, body, end)
	}
}

struct RxMatcher {
	prog  RegexpProgram
	input []u32
mut:
	steps   int
	aborted bool
	end     int // where the last match_ was reached
}

// regexp_test ports `regexp.test(text)` for a regular expression without the `g` and `y` flags:
// whether the pattern matches somewhere in the text. It fails if the search takes too long (V8
// would keep going).
fn regexp_test(prog RegexpProgram, text string) !bool {
	found, _, _ := regexp_search(prog, text)!
	return found
}

// regexp_search ports `regexp.exec(text)` for the position of the match: whether there is one,
// and its start and end as indexes of code points of the text.
fn regexp_search(prog RegexpProgram, text string) !(bool, int, int) {
	mut m := RxMatcher{
		prog:  prog
		input: text.runes().map(u32(it))
	}
	for start in 0 .. m.input.len + 1 {
		mut slots := []int{len: prog.slots, init: -1}
		if m.run(0, start, mut slots) {
			return true, start, m.end
		}
		if m.aborted {
			return error('the regular expression takes too long on `${text}`')
		}
	}
	return false, 0, 0
}

// regexp_exec ports `regexp.exec(text)` from the code point `from` (a `lastIndex`): whether there
// is a match, its start and end, and the capture slots (2 per group, group 0 unused, -1 when the
// group did not take part), as indexes of code points.
fn regexp_exec(prog RegexpProgram, input []rune, from int) !(bool, int, int, []int) {
	mut m := RxMatcher{
		prog:  prog
		input: input.map(u32(it))
	}
	for start in from .. m.input.len + 1 {
		mut slots := []int{len: prog.slots, init: -1}
		if m.run(0, start, mut slots) {
			return true, start, m.end, slots[..2 * (prog.groups + 1)]
		}
		if m.aborted {
			return error('the regular expression takes too long')
		}
	}
	return false, 0, 0, []int{}
}

// rx_in_ranges: whether a code point is in sorted, disjoint ranges.
fn rx_in_ranges(ranges []u32, c u32) bool {
	mut low := 0
	mut high := ranges.len / 2 - 1
	for low <= high {
		mid := (low + high) / 2
		if c < ranges[2 * mid] {
			high = mid - 1
		} else if c > ranges[2 * mid + 1] {
			low = mid + 1
		} else {
			return true
		}
	}
	return false
}

fn rx_is_line_terminator(c u32) bool {
	return c in [u32(0x0a), 0x0d, 0x2028, 0x2029]
}

fn (m &RxMatcher) is_word_at(pos int, word []u32) bool {
	return pos >= 0 && pos < m.input.len && rx_in_ranges(word, m.input[pos])
}

// is_line_start: whether a line terminator ends before `pos`; is_line_end, whether one starts at it.
fn (m &RxMatcher) is_line_start(pos int) bool {
	return pos > 0 && rx_is_line_terminator(m.input[pos - 1])
}

fn (m &RxMatcher) is_line_end(pos int) bool {
	return pos < m.input.len && rx_is_line_terminator(m.input[pos])
}

// run executes the program from `pc` at `pos`; true when it reaches a match_. `slots` holds the
// captures and the loop registers, and is restored when an alternative fails.
fn (mut m RxMatcher) run(pc_start int, pos_start int, mut slots []int) bool {
	mut pc := pc_start
	mut pos := pos_start
	for {
		m.steps++
		if m.steps > rx_max_steps {
			m.aborted = true
			return false
		}
		inst := m.prog.insts[pc]
		match inst.op {
			.char_, .any_, .set_ {
				at := if inst.backward { pos - 1 } else { pos }
				if at < 0 || at >= m.input.len {
					return false
				}
				c := m.input[at]
				ok := match inst.op {
					.char_ { c == inst.value }
					.any_ { inst.dot_all || !rx_is_line_terminator(c) }
					else { rx_in_ranges(inst.ranges, c) != inst.negated }
				}
				if !ok {
					return false
				}
				pos = if inst.backward { pos - 1 } else { pos + 1 }
				pc++
			}
			.start_ {
				if pos != 0 && !(inst.multiline && m.is_line_start(pos)) {
					return false
				}
				pc++
			}
			.end_ {
				if pos != m.input.len && !(inst.multiline && m.is_line_end(pos)) {
					return false
				}
				pc++
			}
			.boundary, .not_boundary {
				at_boundary := m.is_word_at(pos - 1, inst.ranges) != m.is_word_at(pos, inst.ranges)
				if at_boundary != (inst.op == .boundary) {
					return false
				}
				pc++
			}
			.split {
				saved := slots.clone()
				if m.run(inst.x, pos, mut slots) {
					return true
				}
				if m.aborted {
					return false
				}
				for i, value in saved {
					slots[i] = value
				}
				pc = inst.y
			}
			.jmp {
				pc = inst.x
			}
			.save {
				slots[inst.x] = pos
				pc++
			}
			.mark {
				slots[inst.x] = pos
				pc++
			}
			.check {
				if slots[inst.x] == pos {
					return false
				}
				pc++
			}
			.clear {
				for group in inst.x .. inst.y + 1 {
					slots[2 * group] = -1
					slots[2 * group + 1] = -1
				}
				pc++
			}
			.backref {
				// The group that took part in the match; one that did not matches the empty string.
				mut from := -1
				mut to := -1
				for group in inst.indexes {
					if slots[2 * group] >= 0 && slots[2 * group + 1] >= 0 {
						from = slots[2 * group]
						to = slots[2 * group + 1]
						break
					}
				}
				len := to - from
				if from >= 0 {
					start := if inst.backward { pos - len } else { pos }
					if start < 0 || start + len > m.input.len {
						return false
					}
					for i in 0 .. len {
						a := m.input[start + i]
						b := m.input[from + i]
						if a != b && !(inst.icase && rx_fold(a) == rx_fold(b)) {
							return false
						}
					}
					pos = if inst.backward { pos - len } else { pos + len }
				}
				pc++
			}
			.look {
				mut inner := slots.clone()
				matched := m.run(pc + 1, pos, mut inner)
				if m.aborted {
					return false
				}
				if matched == inst.negated {
					return false
				}
				if matched {
					// The captures of a lookaround that matched stay.
					for i, value in inner {
						slots[i] = value
					}
				}
				pc = inst.x
			}
			.match_ {
				m.end = pos
				return true
			}
		}
	}
	return false
}
