module rules

import jsregexp
import regexpp

// More of the shared code of the `regexp/*` rules (regexp_utils.v), ported from lib/utils of
// eslint-plugin-regexp 3.3.3: mention.ts, regex-syntax.ts, unicode.ts (its code points and the
// predicates, with the digit, space and word sets of regexp-ast-analysis' Chars for the flags
// `{}`), char-ranges.ts, regexp-ast/quantifier.ts and extractCaptures of regexp-ast/common.ts, the
// fixes of index.ts that edit the elements of a pattern (mightCreateNewElement,
// fixRemoveCharacterClassElement, fixRemoveAlternative, fixRemoveStringAlternative, canUnwrapped)
// and toCharSetSource of refa.ts for a single character.

// rx_raw is the `raw` of a node of the pattern.
fn rx_raw(ast &regexpp.Ast, i int) string {
	return regexpp.utf16_to_wtf8(ast.raw16(i))
}

// rx_format_code_point ports formatCodePoint: `U+0000`.
fn rx_format_code_point(value int) string {
	hex := value.hex()
	return 'U+${'0'.repeat(if hex.len < 4 { 4 - hex.len } else { 0 })}${hex}'
}

// rx_mention_char ports mentionChar: a character or a range with its code points.
fn rx_mention_char(ast &regexpp.Ast, i int) string {
	n := ast.nodes[i]
	if n.kind == .character {
		return "'${rx_mention_escape(rx_raw(ast, i))}' (${rx_format_code_point(n.value)})"
	}
	if n.kind == .character_class_range {
		min := rx_format_code_point(ast.nodes[n.min_char].value)
		max := rx_format_code_point(ast.nodes[n.max_char].value)
		return "'${rx_mention_escape(rx_raw(ast, i))}' (${min} - ${max})"
	}
	return rx_mention_node(ast, i)
}

// rx_mention_node ports mention of a node.
fn rx_mention_node(ast &regexpp.Ast, i int) string {
	return rx_mention(rx_raw(ast, i))
}

// rx_mention ports mention of a string.
fn rx_mention(text string) string {
	return "'${rx_mention_escape(text)}'"
}

// rx_mention_escape ports `escape` of mention.ts: the control characters, escaped or not, written
// as escapes (tabs are kept).
fn rx_mention_escape(value string) string {
	runes := value.runes()
	mut first := []rune{}
	mut i := 0
	for i < runes.len {
		if runes[i] == `\\` && i + 1 < runes.len {
			ch := runes[i + 1]
			if ch < 0x20 {
				first << rx_escape_control(ch).runes()
			} else {
				first << runes[i]
				first << ch
			}
			i += 2
			continue
		}
		first << runes[i]
		i++
	}
	mut out := []rune{}
	for r in first {
		if r < 0x20 {
			out << rx_escape_control(r).runes()
		} else {
			out << r
		}
	}
	return out.string()
}

fn rx_escape_control(control rune) string {
	if control == `\t` {
		return '\t'
	}
	if control == `\n` {
		return '\\n'
	}
	if control == `\r` {
		return '\\r'
	}
	hex := int(control).hex()
	return '\\x${if hex.len < 2 { '0' } else { '' }}${hex}'
}

// rx_join_english_list ports joinEnglishList.
fn rx_join_english_list(list []string) string {
	if list.len == 0 {
		return 'none'
	}
	if list.len == 1 {
		return list[0]
	}
	if list.len == 2 {
		return '${list[0]} and ${list[1]}'
	}
	mut result := list[0]
	for i in 1 .. list.len - 1 {
		result += ', ${list[i]}'
	}
	return result + ', and ${list[list.len - 1]}'
}

// The characters of ClassSetReservedDoublePunctuator (RESERVED_DOUBLE_PUNCTUATOR_CHARS).
const rx_reserved_double_punctuators = '&!#$%*+,.:;<=>?@^`~-'

// rx_is_reserved_double_punctuator_pair tells whether the text starts with one of
// RESERVED_DOUBLE_PUNCTUATOR_PATTERN's pairs (`&&`, `!!`…).
fn rx_has_reserved_double_punctuator(text string) bool {
	for i in 0 .. text.len - 1 {
		if text[i] == text[i + 1] && rx_reserved_double_punctuators.contains(text[i..i + 1]) {
			return true
		}
	}
	return false
}

// RxEscapeKind is EscapeSequenceKind (none: not an escape sequence).
enum RxEscapeKind {
	none
	octal
	control
	hexadecimal
	unicode
	unicode_code_point
}

// str is the value of the EscapeSequenceKind.
fn (k RxEscapeKind) str() string {
	return match k {
		.none { '' }
		.octal { 'octal' }
		.control { 'control' }
		.hexadecimal { 'hexadecimal' }
		.unicode { 'unicode' }
		.unicode_code_point { 'unicode code point' }
	}
}

fn rx_all_hex(s string) bool {
	return s.len > 0 && s.bytes().all(it.is_hex_digit())
}

// rx_is_octal_escape ports isOctalEscape: /^\\[0-7]{1,3}$/.
fn rx_is_octal_escape(raw string) bool {
	return raw.len >= 2 && raw.len <= 4 && raw[0] == `\\`
		&& raw[1..].bytes().all(it >= `0` && it <= `7`)
}

// rx_is_control_escape ports isControlEscape: /^\\c[A-Za-z]$/.
fn rx_is_control_escape(raw string) bool {
	return raw.len == 3 && raw.starts_with('\\c') && raw[2].is_letter()
}

// rx_is_hexadecimal_escape ports isHexadecimalEscape: /^\\x[\dA-Fa-f]{2}$/.
fn rx_is_hexadecimal_escape(raw string) bool {
	return raw.len == 4 && raw.starts_with('\\x') && rx_all_hex(raw[2..])
}

// rx_is_unicode_escape ports isUnicodeEscape: /^\\u[\dA-Fa-f]{4}$/.
fn rx_is_unicode_escape(raw string) bool {
	return raw.len == 6 && raw.starts_with('\\u') && rx_all_hex(raw[2..])
}

// rx_is_unicode_code_point_escape ports isUnicodeCodePointEscape: /^\\u\{[\dA-Fa-f]{1,8}\}$/.
fn rx_is_unicode_code_point_escape(raw string) bool {
	return raw.len >= 5 && raw.len <= 12 && raw.starts_with('\\u{') && raw.ends_with('}')
		&& rx_all_hex(raw[3..raw.len - 1])
}

// rx_escape_sequence_kind ports getEscapeSequenceKind.
fn rx_escape_sequence_kind(raw string) RxEscapeKind {
	if raw.len == 0 || raw[0] != `\\` {
		return .none
	}
	if rx_is_octal_escape(raw) {
		return .octal
	}
	if rx_is_control_escape(raw) {
		return .control
	}
	if rx_is_hexadecimal_escape(raw) {
		return .hexadecimal
	}
	if rx_is_unicode_escape(raw) {
		return .unicode
	}
	if rx_is_unicode_code_point_escape(raw) {
		return .unicode_code_point
	}
	return .none
}

// rx_is_escape_sequence ports isEscapeSequence.
fn rx_is_escape_sequence(raw string) bool {
	return rx_escape_sequence_kind(raw) != .none
}

// rx_is_hex_like_escape ports isHexLikeEscape.
fn rx_is_hex_like_escape(raw string) bool {
	return rx_escape_sequence_kind(raw) in [.hexadecimal, .unicode, .unicode_code_point]
}

// The code points of unicode.ts the rules use.
const rx_cp_backspace = 8
const rx_cp_tab = 9
const rx_cp_lf = 10
const rx_cp_vt = 11
const rx_cp_ff = 12
const rx_cp_cr = 13
const rx_cp_nel = 0x85
const rx_cp_mongolian_vowel_separator = 0x180e
const rx_cp_zwsp = 0x200b
const rx_cp_zwnj = 0x200c
const rx_cp_zwj = 0x200d
const rx_cp_lrm = 0x200e
const rx_cp_rlm = 0x200f
const rx_cp_braille_pattern_blank = 0x2800

// rx_is_digit ports isDigit: [0-9].
fn rx_is_digit(cp int) bool {
	return cp >= `0` && cp <= `9`
}

// rx_is_lowercase_letter ports isLowercaseLetter: [a-z].
fn rx_is_lowercase_letter(cp int) bool {
	return cp >= `a` && cp <= `z`
}

// rx_is_uppercase_letter ports isUppercaseLetter: [A-Z].
fn rx_is_uppercase_letter(cp int) bool {
	return cp >= `A` && cp <= `Z`
}

// rx_is_letter ports isLetter.
fn rx_is_letter(cp int) bool {
	return rx_is_lowercase_letter(cp) || rx_is_uppercase_letter(cp)
}

// rx_to_lower_code_point ports toLowerCodePoint.
fn rx_to_lower_code_point(cp int) int {
	return if rx_is_uppercase_letter(cp) { cp + 0x20 } else { cp }
}

// rx_to_upper_code_point ports toUpperCodePoint.
fn rx_to_upper_code_point(cp int) int {
	return if rx_is_lowercase_letter(cp) { cp - 0x20 } else { cp }
}

// rx_is_symbol ports isSymbol: the ASCII punctuation.
fn rx_is_symbol(cp int) bool {
	return (cp >= `!` && cp <= `/`) || (cp >= `:` && cp <= `@`) || (cp >= `[` && cp <= `\``)
		|| (cp >= `{` && cp <= `~`)
}

// rx_is_space ports isSpace: \s (WhiteSpace and LineTerminator).
fn rx_is_space(cp int) bool {
	return cp in [9, 10, 11, 12, 13, 32, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff]
		|| (cp >= 0x2000 && cp <= 0x200a)
}

// rx_is_word ports isWord: [0-9A-Za-z_].
fn rx_is_word(cp int) bool {
	return rx_is_digit(cp) || rx_is_letter(cp) || cp == `_`
}

// rx_is_invisible ports isInvisible.
fn rx_is_invisible(cp int) bool {
	if rx_is_space(cp) {
		return true
	}
	return cp in [rx_cp_mongolian_vowel_separator, rx_cp_nel, rx_cp_zwsp, rx_cp_zwnj, rx_cp_zwj,
		rx_cp_lrm, rx_cp_rlm, rx_cp_braille_pattern_blank]
}

// rx_char_set_source ports toCharSetSource of a single code point, as refa's JS.toLiteral writes
// it whatever the flags: the escapes \t \n \f \r, a printable ASCII character as it is, \xHH below
// U+0100 and \uHHHH up to U+FFFF (refa escapes every invisible character this way; the rules call
// it with those).
fn rx_char_set_source(cp int) string {
	return match cp {
		9 {
			'\\t'
		}
		10 {
			'\\n'
		}
		12 {
			'\\f'
		}
		13 {
			'\\r'
		}
		else {
			if cp >= 0x20 && cp < 0x7f {
				rune(cp).str()
			} else if cp < 0x100 {
				h := cp.hex()
				'\\x${'0'.repeat(2 - h.len)}${h}'
			} else if cp < 0x10000 {
				h := cp.hex()
				'\\u${'0'.repeat(4 - h.len)}${h}'
			} else {
				'\\u{${cp.hex()}}'
			}
		}
	}
}

// RxCharRange is a CharRange of refa.
struct RxCharRange {
	min int
	max int
}

// rx_allowed_char_ranges ports getAllowedCharRanges: the ranges of the option, or else of the
// setting regexp.allowedCharacterRanges, "alphanumeric" by default; an error where it throws.
fn rx_allowed_char_ranges(option []string, settings_value []string) ![]RxCharRange {
	alphanumeric := [RxCharRange{`0`, `9`}, RxCharRange{`A`, `Z`}, RxCharRange{`a`, `z`}]
	target := if option.len > 0 { option } else { settings_value }
	if target.len == 0 {
		return alphanumeric
	}
	mut allowed := []RxCharRange{}
	for range in target {
		if range == 'all' {
			return [RxCharRange{0, 0x10ffff}]
		} else if range == 'alphanumeric' {
			if target.len == 1 {
				return alphanumeric
			}
			allowed << alphanumeric
		} else {
			chars := range.runes()
			if chars.len != 3 || chars[1] != `-` {
				return error('Invalid format: The range ${range} is not of the form `<char>-<char>`.')
			}
			allowed << RxCharRange{int(chars[0]), int(chars[2])}
		}
	}
	return allowed
}

// rx_in_range ports inRange.
fn rx_in_range(ranges []RxCharRange, min int, max int) bool {
	for range in ranges {
		if range.min <= min && max <= range.max {
			return true
		}
	}
	return false
}

// rx_capturing_groups ports extractCaptures: the capturing groups by their start.
fn rx_capturing_groups(ast &regexpp.Ast) []int {
	mut groups := []int{}
	for event in ast.visit_events() {
		if event.enter && ast.nodes[event.node].kind == .capturing_group {
			groups << event.node
		}
	}
	// visitRegExpAST gives no order: by their start.
	mut starts := groups.map(ast.nodes[it].start)
	mut order := []int{len: groups.len, init: index}
	order.sort_with_compare(fn [starts] (a &int, b &int) int {
		return starts[*a] - starts[*b]
	})
	return order.map(groups[it])
}

// rx_capturing_group_names are the names of extractCaptures.
fn rx_capturing_group_names(ast &regexpp.Ast) []string {
	mut out := []string{}
	for g in rx_capturing_groups(ast) {
		n := ast.nodes[g]
		if n.has_name && n.name !in out {
			out << n.name
		}
	}
	return out
}

// rx_test is RegExp#test of a pattern with the flag `u` (the mightCreateNewElement patterns are
// written for it; their `i` is spelled out).
fn rx_test(pattern string, text string) bool {
	prog := jsregexp.regexp_compile(pattern) or { return false }
	return jsregexp.regexp_test(prog, text) or { false }
}

// rx_might_create_new_element ports mightCreateNewElement: whether the concatenation of the two
// texts might make new escape sequences or elements.
fn rx_might_create_new_element(before string, after string) bool {
	// control: \cA
	if before.ends_with('\\c') && rx_test('^[a-zA-Z]', after) {
		return true
	}
	// hexadecimal: \xFF ￿
	if rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\(?:x[\\dA-Fa-f]?|u[\\dA-Fa-f]{0,3})$', before)
		&& rx_test('^[\\da-fA-F]', after) {
		return true
	}
	// unicode: \u{FFFF}
	if (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\u$', before)
		&& rx_test('^\\{[\\da-fA-F]*(?:\\}[\\s\\S]*)?$', after))
		|| (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\u\\{[\\da-fA-F]*$', before)
		&& rx_test('^(?:[\\da-fA-F]+\\}?|\\})', after)) {
		return true
	}
	// octal: \077 \123
	if (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\0[0-7]?$', before) && rx_test('^[0-7]', after))
		|| (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\[1-7]$', before) && rx_test('^[0-7]', after)) {
		return true
	}
	// backreference: \12 \k<foo>
	if (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\[1-9]\\d*$', before) && rx_test('^\\d', after))
		|| (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\k$', before) && after.starts_with('<'))
		|| rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\k<[^<>]*$', before) {
		return true
	}
	// property: \p{L} \P{L}
	if (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\[pP]$', before)
		&& rx_test('^\\{[\\w=]*(?:\\}[\\s\\S]*)?$', after))
		|| (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\\\[pP]\\{[\\w=]*$', before)
		&& rx_test('^[\\w=]+(?:\\}[\\s\\S]*)?$|^\\}', after)) {
		return true
	}
	// quantifier: {1} {2,} {2,3}
	if (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\{\\d*$', before) && rx_test('^[\\d,}]', after))
		|| (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\{\\d+,$', before)
		&& rx_test('^(?:\\d+(?:\\}|$)|\\})', after))
		|| (rx_test('(?:^|[^\\\\])(?:\\\\{2})*\\{\\d+,\\d*$', before) && after.starts_with('}')) {
		return true
	}
	return false
}

// rx_slice is String#slice on the units of a node's raw: [from, to) relative to the node.
fn rx_slice(ast &regexpp.Ast, i int, from int, to int) string {
	raw := ast.raw16(i)
	a := if from < 0 { 0 } else if from > raw.len { raw.len } else { from }
	b := if to < a { a } else if to > raw.len { raw.len } else { to }
	return regexpp.utf16_to_wtf8(raw[a..b])
}

// rx_remove_character_class_element ports fixRemoveCharacterClassElement: the text the element
// is replaced with (none: no fix). The element must be one of a character class.
fn rx_remove_character_class_element(ast &regexpp.Ast, element int) ?string {
	cc := ast.nodes[element].parent
	if ast.nodes[cc].kind != .character_class {
		return none
	}
	n := ast.nodes[element]
	c := ast.nodes[cc]
	text_before := rx_slice(ast, cc, 0, n.start - c.start)
	text_after := rx_slice(ast, cc, n.end - c.start, c.end - c.start)
	if rx_might_create_new_element(text_before, text_after) {
		return none
	}
	index := c.elements.index(element)
	before := if index > 0 { c.elements[index - 1] } else { -1 }
	after := if index + 1 < c.elements.len { c.elements[index + 1] } else { -1 }
	if before >= 0 && after >= 0 && ast.nodes[before].kind == .character && rx_raw(ast, before) == '-'
		&& ast.nodes[after].kind == .character {
		// [\s0-\s9] -> [\s0-9] is wrong
		return none
	}
	if (text_after.starts_with('-') && before >= 0 && ast.nodes[before].kind == .character)
		|| (text_after.starts_with('^') && !c.negate && before < 0) {
		return '\\'
	}
	return ''
}

// rx_remove_alternative ports fixRemoveAlternative: the node to replace and its text (the parent
// without the alternative, or the alternative replaced with `[]` when it is the only one).
fn rx_remove_alternative(ast &regexpp.Ast, alternative int) (int, string) {
	parent := ast.nodes[alternative].parent
	p := ast.nodes[parent]
	if p.alternatives.len == 1 {
		return alternative, '[]'
	}
	mut start := ast.nodes[alternative].start
	mut end := ast.nodes[alternative].end
	if p.alternatives[0] == alternative {
		end++
	} else {
		start--
	}
	return parent, rx_slice(ast, parent, 0, start - p.start) + rx_slice(ast, parent, end - p.start,
		p.end - p.start)
}

// rx_remove_string_alternative ports fixRemoveStringAlternative, like rx_remove_alternative (the
// whole string disjunction replaced with `[]` when it is the only one).
fn rx_remove_string_alternative(ast &regexpp.Ast, alternative int) (int, string) {
	parent := ast.nodes[alternative].parent
	p := ast.nodes[parent]
	if p.alternatives.len == 1 {
		return parent, '[]'
	}
	mut start := ast.nodes[alternative].start
	mut end := ast.nodes[alternative].end
	if p.alternatives[0] == alternative {
		end++
	} else {
		start--
	}
	return parent, rx_slice(ast, parent, 0, start - p.start) + rx_slice(ast, parent, end - p.start,
		p.end - p.start)
}

// rx_can_unwrapped ports canUnwrapped: whether the pattern stays the same when the element is
// replaced with the text, as far as its siblings tell.
fn rx_can_unwrapped(ast &regexpp.Ast, node int, text string) bool {
	parent := ast.nodes[node].parent
	n := ast.nodes[node]
	mut text_before := ''
	mut text_after := ''
	if ast.nodes[parent].kind == .alternative {
		p := ast.nodes[parent]
		text_before = rx_slice(ast, parent, 0, n.start - p.start)
		text_after = rx_slice(ast, parent, n.end - p.start, p.end - p.start)
	} else if ast.nodes[parent].kind == .quantifier {
		alt := ast.nodes[parent].parent
		a := ast.nodes[alt]
		text_before = rx_slice(ast, alt, 0, n.start - a.start)
		text_after = rx_slice(ast, alt, n.end - a.start, a.end - a.start)
	} else {
		return true
	}
	return !rx_might_create_new_element(text_before, text) && !rx_might_create_new_element(text,
		text_after)
}
