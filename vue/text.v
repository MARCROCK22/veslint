module vue

// TextIndex converts between the byte offsets of a UTF-8 text and its UTF-16 offsets (JavaScript's
// string indexes, which vue-eslint-parser computes with). An offset inside a character maps to
// the start of the character.
struct TextIndex {
	ascii       bool
	u16_len     int
	u16_of_byte []int // len: bytes + 1 (empty when ascii)
	byte_of_u16 []int // len: units + 1 (empty when ascii)
}

fn new_text_index(src string) TextIndex {
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
fn (t &TextIndex) to_u16(b int) int {
	if t.ascii {
		return if b < 0 {
			0
		} else if b > t.u16_len {
			t.u16_len
		} else {
			b
		}
	}
	if b <= 0 {
		return 0
	}
	if b >= t.u16_of_byte.len {
		return t.u16_of_byte[t.u16_of_byte.len - 1]
	}
	return t.u16_of_byte[b]
}

// to_byte converts a UTF-16 offset to bytes; one past the end maps past the end by as many bytes.
fn (t &TextIndex) to_byte(u int) int {
	if t.ascii {
		return u
	}
	if u < 0 {
		return u
	}
	if u >= t.byte_of_u16.len {
		return t.byte_of_u16[t.byte_of_u16.len - 1] + (u - (t.byte_of_u16.len - 1))
	}
	return t.byte_of_u16[u]
}

// utf8_len is the length of the UTF-8 sequence that starts with that byte (1 for a stray
// continuation byte).
@[inline]
fn utf8_len(c u8) int {
	return if c < 0xc0 {
		1
	} else if c < 0xe0 {
		2
	} else if c < 0xf0 {
		3
	} else {
		4
	}
}

// decode_cp decodes the code point at byte `i` and gives its length in bytes.
@[inline]
fn decode_cp(s string, i int) (u32, int) {
	c := s[i]
	if c < 0x80 {
		return u32(c), 1
	}
	n := utf8_len(c)
	if i + n > s.len {
		return u32(c), 1
	}
	mut cp := u32(0)
	match n {
		2 { cp = u32(c & 0x1f) }
		3 { cp = u32(c & 0x0f) }
		4 { cp = u32(c & 0x07) }
		else { return u32(c), 1 }
	}
	for k in 1 .. n {
		cp = (cp << 6) | u32(s[i + k] & 0x3f)
	}
	return cp, n
}

// cp_utf16_len is the number of UTF-16 units of a code point.
@[inline]
fn cp_utf16_len(cp u32) int {
	return if cp >= 0x10000 { 2 } else { 1 }
}

// utf16_length is the length of a UTF-8 string in UTF-16 units.
fn utf16_length(s string) int {
	mut n := 0
	mut i := 0
	for i < s.len {
		l := utf8_len(s[i])
		n += if l == 4 { 2 } else { 1 }
		i += l
	}
	return n
}

// cp_to_string encodes a code point as UTF-8 (a lone surrogate as its 3-byte WTF-8 form).
fn cp_to_string(cp u32) string {
	mut b := []u8{cap: 4}
	append_cp(mut b, cp)
	return b.bytestr()
}

@[inline]
fn append_cp(mut b []u8, cp u32) {
	if cp < 0x80 {
		b << u8(cp)
	} else if cp < 0x800 {
		b << u8(0xc0 | (cp >> 6))
		b << u8(0x80 | (cp & 0x3f))
	} else if cp < 0x10000 {
		b << u8(0xe0 | (cp >> 12))
		b << u8(0x80 | ((cp >> 6) & 0x3f))
		b << u8(0x80 | (cp & 0x3f))
	} else {
		b << u8(0xf0 | (cp >> 18))
		b << u8(0x80 | ((cp >> 12) & 0x3f))
		b << u8(0x80 | ((cp >> 6) & 0x3f))
		b << u8(0x80 | (cp & 0x3f))
	}
}

// sorted_last_index is lodash's sortedLastIndex: the number of items <= value.
fn sorted_last_index(a []int, value int) int {
	mut lo := 0
	mut hi := a.len
	for lo < hi {
		mid := (lo + hi) >> 1
		if a[mid] <= value {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// is_js_space is `\s` of a JavaScript regular expression (WhiteSpace and LineTerminator).
fn is_js_space(cp u32) bool {
	return cp in [u32(0x09), 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f,
		0x205f, 0x3000, 0xfeff] || (cp >= 0x2000 && cp <= 0x200a)
}

// js_trim is String.prototype.trim.
fn js_trim(s string) string {
	return js_trim_end(js_trim_start(s))
}

fn js_trim_start(s string) string {
	mut i := 0
	for i < s.len {
		cp, n := decode_cp(s, i)
		if !is_js_space(cp) {
			break
		}
		i += n
	}
	return s[i..]
}

fn js_trim_end(s string) string {
	mut end := s.len
	for end > 0 {
		mut start := end - 1
		for start > 0 && (s[start] & 0xc0) == 0x80 {
			start--
		}
		cp, _ := decode_cp(s, start)
		if !is_js_space(cp) {
			break
		}
		end = start
	}
	return s[..end]
}

// is_word_char is `\w`.
@[inline]
fn is_word_char(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_`
}
