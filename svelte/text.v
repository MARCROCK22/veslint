module svelte

// Text helpers. svelte/ works in byte offsets of the UTF-8 file; svelte-eslint-parser and the
// Svelte compiler work in UTF-16 offsets (JavaScript string indexes). TextIndex converts between
// the two; LinesAndColumns is svelte-eslint-parser's line index (src/context/index.ts).

// TextIndex converts between the byte offsets of a UTF-8 text and its UTF-16 offsets. An offset
// inside a character maps to the start of the character.
pub struct TextIndex {
pub:
	ascii   bool
	u16_len int
mut:
	u16_of_byte []int // len: bytes + 1 (empty when ascii)
	byte_of_u16 []int // len: units + 1 (empty when ascii)
}

pub fn new_text_index(src string) TextIndex {
	mut ascii := true
	for c in src {
		if c >= 0x80 {
			ascii = false
			break
		}
	}
	if ascii {
		return TextIndex{
			ascii:   true
			u16_len: src.len
		}
	}
	mut u16_of_byte := []int{len: src.len + 1}
	mut byte_of_u16 := []int{cap: src.len + 1}
	mut u := 0
	mut i := 0
	for i < src.len {
		n := utf8_len(src[i])
		units := if n == 4 { 2 } else { 1 }
		for k in 0 .. n {
			if i + k < src.len {
				u16_of_byte[i + k] = u
			}
		}
		for _ in 0 .. units {
			byte_of_u16 << i
		}
		u += units
		i += n
	}
	u16_of_byte[src.len] = u
	byte_of_u16 << src.len
	return TextIndex{
		ascii:       false
		u16_len:     u
		u16_of_byte: u16_of_byte
		byte_of_u16: byte_of_u16
	}
}

// to_u16 converts a byte offset (clamped to the text) to UTF-16.
pub fn (t &TextIndex) to_u16(b int) int {
	if b <= 0 {
		return 0
	}
	if t.ascii {
		return if b > t.u16_len { t.u16_len } else { b }
	}
	if b >= t.u16_of_byte.len {
		return t.u16_len
	}
	return t.u16_of_byte[b]
}

// to_byte converts a UTF-16 offset (clamped to the text) to a byte offset.
pub fn (t &TextIndex) to_byte(u int) int {
	if u <= 0 {
		return 0
	}
	if t.ascii {
		return if u > t.u16_len { t.u16_len } else { u }
	}
	if u >= t.byte_of_u16.len {
		return t.byte_of_u16[t.byte_of_u16.len - 1]
	}
	return t.byte_of_u16[u]
}

// utf8_len is the length of the UTF-8 sequence that starts with byte `c` (1 for a stray
// continuation byte).
@[inline]
fn utf8_len(c u8) int {
	return if c < 0x80 {
		1
	} else if c >= 0xf0 {
		4
	} else if c >= 0xe0 {
		3
	} else if c >= 0xc0 {
		2
	} else {
		1
	}
}

// code_point_at decodes the character at byte offset i (0 past the end).
fn code_point_at(s string, i int) (u32, int) {
	if i >= s.len {
		return 0, 0
	}
	c := s[i]
	n := utf8_len(c)
	if n == 1 || i + n > s.len {
		return u32(c), 1
	}
	mut cp := u32(c) & (u32(0xff) >> (n + 1))
	for k in 1 .. n {
		cp = (cp << 6) | (u32(s[i + k]) & 0x3f)
	}
	return cp, n
}

// u16_len_of is the number of UTF-16 units of a string.
fn u16_len_of(s string) int {
	mut n := 0
	mut i := 0
	for i < s.len {
		l := utf8_len(s[i])
		n += if l == 4 { 2 } else { 1 }
		i += l
	}
	return n
}

// is_js_space tells whether a code point is whitespace for JavaScript's `\s` and trim (white
// space and line terminators).
fn is_js_space(cp u32) bool {
	return match cp {
		9, 10, 11, 12, 13, 32, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff { true }
		else { cp >= 0x2000 && cp <= 0x200a }
	}
}

// is_space_at tells whether the character at byte offset i is JavaScript whitespace.
fn is_space_at(s string, i int) bool {
	if i >= s.len {
		return false
	}
	c := s[i]
	if c < 0x80 {
		return c == ` ` || (c >= 9 && c <= 13)
	}
	cp, _ := code_point_at(s, i)
	return is_js_space(cp)
}

// js_trim_end_len is the byte length of s.trimEnd().
fn js_trim_end_len(s string) int {
	mut end := s.len
	for end > 0 {
		c := s[end - 1]
		if c < 0x80 {
			if c == ` ` || (c >= 9 && c <= 13) {
				end--
				continue
			}
			break
		}
		// Back to the start of the character.
		mut st := end - 1
		for st > 0 && s[st] & 0xc0 == 0x80 {
			st--
		}
		cp, _ := code_point_at(s, st)
		if !is_js_space(cp) {
			break
		}
		end = st
	}
	return end
}

// js_trim_start_len is the byte length of what s.trimStart() removes.
fn js_trim_start_len(s string) int {
	mut start := 0
	for start < s.len && is_space_at(s, start) {
		_, n := code_point_at(s, start)
		start += n
	}
	return start
}

// js_trim is s.trim() (JavaScript whitespace).
fn js_trim(s string) string {
	start := js_trim_start_len(s)
	end := js_trim_end_len(s)
	if start >= end {
		return ''
	}
	return s[start..end]
}

// is_blank tells whether a string is only JavaScript whitespace (`!s.trim()`).
fn is_blank(s string) bool {
	return js_trim_start_len(s) == s.len
}

// LinesAndColumns is svelte-eslint-parser's line index: a line starts after `\n`, after a `\r`
// not followed by `\n` and after `\r\n`. Offsets are UTF-16.
struct LinesAndColumns {
	line_starts []int
}

fn new_lines_and_columns(src string, index &TextIndex) LinesAndColumns {
	mut starts := [0]
	mut i := 0
	for i < src.len {
		c := src[i]
		if c == `\r` {
			if i + 1 < src.len && src[i + 1] == `\n` {
				i++
			}
			starts << index.to_u16(i + 1)
		} else if c == `\n` {
			starts << index.to_u16(i + 1)
		}
		i++
	}
	return LinesAndColumns{starts}
}

// Loc is a line (from 1) and a column (UTF-16 units from 0).
pub struct Loc {
pub:
	line   int
	column int
}

// loc_u16 is getLocFromIndex of a UTF-16 offset.
fn (l &LinesAndColumns) loc_u16(u int) Loc {
	line := sorted_last_index(l.line_starts, u)
	if line == 0 {
		// A negative offset (never reached by the corpus).
		return Loc{0, u}
	}
	return Loc{line, u - l.line_starts[line - 1]}
}

// sorted_last_index is lodash's sortedLastIndex for a sorted array of ints: the number of
// items <= v.
fn sorted_last_index(a []int, v int) int {
	mut lo := 0
	mut hi := a.len
	for lo < hi {
		mid := (lo + hi) / 2
		if a[mid] <= v {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// blank_bytes replaces every byte but `\n`, `\r` and ` ` by a space: the template and script
// codes of svelte-eslint-parser in bytes (JavaScript replaces each UTF-16 unit; in bytes the
// offsets stay the file's).
fn blank_bytes(s string) string {
	mut out := []u8{len: s.len}
	for i, c in s {
		out[i] = if c == `\n` || c == `\r` { c } else { ` ` }
	}
	return out.bytestr()
}

// blank_u16 is the same blanking as JavaScript does it (one space per UTF-16 unit): the text of
// the code svelte-eslint-parser hands the script parser.
fn blank_u16(s string) string {
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		c := s[i]
		if c < 0x80 {
			out << if c == `\n` || c == `\r` { c } else { ` ` }
			i++
			continue
		}
		n := utf8_len(c)
		out << ` `
		if n == 4 {
			out << ` `
		}
		i += n
	}
	return out.bytestr()
}

// ascii_lower lower-cases ASCII letters only (byte offsets stay).
fn ascii_lower(s string) string {
	mut out := []u8{len: s.len}
	for i, c in s {
		out[i] = if c >= `A` && c <= `Z` { c + 32 } else { c }
	}
	return out.bytestr()
}

// at_ tells whether `prefix` is at offset i of s (s[i..].starts_with without the copy).
@[inline]
fn at_(s string, i int, prefix string) bool {
	if i < 0 || s.len - i < prefix.len {
		return false
	}
	for k in 0 .. prefix.len {
		if s[i + k] != prefix[k] {
			return false
		}
	}
	return true
}

// last_byte_before is s[..end].last_index_u8(b) without the copy (-1 if absent).
fn last_byte_before(s string, b u8, end int) int {
	mut i := if end > s.len { s.len } else { end } - 1
	for i >= 0 {
		if s[i] == b {
			return i
		}
		i--
	}
	return -1
}
