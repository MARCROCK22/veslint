module estree

// Positions as ESLint gives them to rules: `range` in UTF-16 units, and `loc` (lines from 1,
// columns in UTF-16 units from 0). Lines end at LF, CRLF, CR, U+2028 and U+2029, as TypeScript's
// getLineAndCharacterOfPosition (which typescript-estree's `loc` comes from) counts them.

// line_index gives the byte and UTF-16 offsets of the start of every line.
fn line_index(src string) ([]int, []int) {
	mut starts := [0]
	mut units := [0]
	mut u := 0
	mut i := 0
	for i < src.len {
		c := src[i]
		mut n := 1
		mut break_after := false
		if c == `\n` {
			break_after = true
		} else if c == `\r` {
			if i + 1 < src.len && src[i + 1] == `\n` {
				n = 2
			}
			break_after = true
		} else if c >= 0xf0 {
			n = 4
		} else if c >= 0xe0 {
			n = 3
			if c == 0xe2 && i + 2 < src.len && src[i + 1] == 0x80
				&& (src[i + 2] == 0xa8 || src[i + 2] == 0xa9) {
				break_after = true
			}
		} else if c >= 0xc0 {
			n = 2
		}
		u += if n == 4 && c >= 0xf0 {
			2
		} else if c == `\r` && n == 2 {
			2
		} else {
			1
		}
		i += n
		if break_after {
			starts << i
			units << u
		}
	}
	return starts, units
}

// line_of is the index of the line that holds the byte offset.
fn (t &EsTree) line_of(offset int) int {
	mut lo := 0
	mut hi := t.line_starts.len
	for lo + 1 < hi {
		mid := (lo + hi) / 2
		if t.line_starts[mid] <= offset {
			lo = mid
		} else {
			hi = mid
		}
	}
	return lo
}

// column_units counts the UTF-16 units from the start of the line to the byte offset.
fn (t &EsTree) column_units(line int, offset int) int {
	mut u := 0
	mut i := t.line_starts[line]
	for i < offset && i < t.src.len {
		c := t.src[i]
		if c >= 0xf0 {
			u += 2
			i += 4
		} else {
			u++
			i += if c >= 0xe0 {
				3
			} else if c >= 0xc0 {
				2
			} else {
				1
			}
		}
	}
	return u
}

// utf16_offset converts a byte offset of the source to UTF-16 units (an index of `range`).
pub fn (t &EsTree) utf16_offset(offset int) int {
	if t.line_starts.len == 0 {
		return offset
	}
	line := t.line_of(offset)
	return t.line_units[line] + t.column_units(line, offset)
}

// line_column gives the `loc` of a byte offset: its line from 1 and its column in UTF-16 units.
pub fn (t &EsTree) line_column(offset int) (int, int) {
	if t.line_starts.len == 0 {
		return 1, offset
	}
	line := t.line_of(offset)
	return line + 1, t.column_units(line, offset)
}
