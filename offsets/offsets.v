module offsets

import treesitter { Ident }

// UTF-8 BOM. tsgo drops it when reading the file and does not count it in positions, so veslint
// strips it before parsing so both sides agree.
pub const utf8_bom = '\xEF\xBB\xBF'

// strip_bom returns `src` without the leading BOM and tells whether it had one.
pub fn strip_bom(src string) (string, bool) {
	if src.starts_with(utf8_bom) {
		return src[utf8_bom.len..], true
	}
	return src, false
}

struct OffsetRef {
	off int
	idx int
}

// utf16_offsets converts UTF-8 byte offsets (tree-sitter's) into UTF-16 unit offsets (what tsgo
// expects) with a single pass over `src`. The first byte of each character adds 1 unit, or 2 if
// the character takes 4 bytes (in UTF-16 it is a surrogate pair). Valid UTF-8 is assumed. An
// offset inside a character of 4 bytes stands for its second unit (the low surrogate): ESLint
// reports some problems there (no-misleading-character-class).
pub fn utf16_offsets(src string, byte_offsets []int) []int {
	mut refs := []OffsetRef{cap: byte_offsets.len}
	for i, off in byte_offsets {
		refs << OffsetRef{
			off: off
			idx: i
		}
	}
	refs.sort(a.off < b.off)
	mut result := []int{len: byte_offsets.len}
	mut units := 0
	mut pos := 0
	for r in refs {
		for pos < r.off && pos < src.len {
			b := src[pos]
			if (b & 0xC0) != 0x80 {
				units += if b >= 0xF0 { 2 } else { 1 }
			}
			pos++
		}
		mut at := units
		if r.off < src.len && (src[r.off] & 0xC0) == 0x80 {
			mut lead := r.off
			for lead > 0 && r.off - lead < 3 && (src[lead] & 0xC0) == 0x80 {
				lead--
			}
			if src[lead] >= 0xF0 {
				at--
			}
		}
		result[r.idx] = at
	}
	return result
}

// LineStarts are the byte offsets where the lines of a text start. A line ends at `\r\n`, `\n`, a
// lone `\r`, U+2028 or U+2029: the line breaks TypeScript (computeLineStarts) and ESLint
// (`/\r\n|[\r\n\u2028\u2029]/`) count, wherever they are (code, a string, a comment or a
// template). tree-sitter's rows only count `\n`, so no displayed line comes from them.
pub struct LineStarts {
	starts []int // increasing; the first one is 0
}

// line_break_len is the length in bytes of the line break that starts at `pos`, or 0.
fn line_break_len(src string, pos int) int {
	b := src[pos]
	if b == `\n` {
		return 1
	}
	if b == `\r` {
		return if pos + 1 < src.len && src[pos + 1] == `\n` { 2 } else { 1 }
	}
	// U+2028 is E2 80 A8 and U+2029 is E2 80 A9.
	if b == 0xE2 && pos + 2 < src.len && src[pos + 1] == 0x80
		&& (src[pos + 2] == 0xA8 || src[pos + 2] == 0xA9) {
		return 3
	}
	return 0
}

// line_starts finds the lines of `src` (BOM already stripped) in a single pass.
pub fn line_starts(src string) LineStarts {
	mut starts := [0]
	mut pos := 0
	for pos < src.len {
		n := line_break_len(src, pos)
		if n == 0 {
			pos++
			continue
		}
		pos += n
		starts << pos
	}
	return LineStarts{
		starts: starts
	}
}

// line_index is the 0-based line a byte offset is in: the last one that starts at it or before.
pub fn (l &LineStarts) line_index(offset int) int {
	mut lo := 0
	mut hi := l.starts.len
	for lo < hi {
		mid := (lo + hi) / 2
		if l.starts[mid] <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return if lo == 0 { 0 } else { lo - 1 }
}

// line_start is the byte offset where the line of a byte offset starts.
pub fn (l &LineStarts) line_start(offset int) int {
	if l.starts.len == 0 {
		return 0
	}
	return l.starts[l.line_index(offset)]
}

// line_start_before is line_start without the table, for a single offset: it goes back from
// `offset` to the end of the previous line break.
pub fn line_start_before(src string, offset int) int {
	mut pos := offset
	for pos > 0 {
		b := src[pos - 1]
		if b == `\n` || b == `\r` {
			break
		}
		if (b == 0xA8 || b == 0xA9) && pos >= 3 && src[pos - 2] == 0x80 && src[pos - 3] == 0xE2 {
			break
		}
		pos--
	}
	return pos
}

// DisplayPos is the printed position: 1-based line and 1-based column in UTF-16 units, as tsc and
// ESLint show it.
pub struct DisplayPos {
pub:
	line int
	col  int
}

// utf16_positions returns, for each identifier, its UTF-16 offset (the one sent to tsgo) and its
// display position, both from its byte offset alone. An identifier with a negative row is a
// report without a place in the file (ESLint's line 0 and column 0, which it prints as `0:1`).
pub fn utf16_positions(src string, idents []Ident) ([]int, []DisplayPos) {
	lines := line_starts(src)
	mut byte_offsets := []int{cap: idents.len * 2}
	mut line_of := []int{cap: idents.len}
	for id in idents {
		line := lines.line_index(id.start_byte)
		line_of << line
		byte_offsets << id.start_byte
		byte_offsets << lines.starts[line]
	}
	units := utf16_offsets(src, byte_offsets)
	mut utf16 := []int{cap: idents.len}
	mut display := []DisplayPos{cap: idents.len}
	for i, id in idents {
		start := units[2 * i]
		line_start := units[2 * i + 1]
		utf16 << start
		display << DisplayPos{
			line: if id.row < 0 { 0 } else { line_of[i] + 1 }
			col:  start - line_start + 1
		}
	}
	return utf16, display
}
