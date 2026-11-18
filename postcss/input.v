module postcss

// A port of the parts of postcss 8.5.33, postcss-safe-parser 7.1.0, postcss-scss 4.0.9 and
// postcss-selector-parser 7.2.1 that eslint-plugin-svelte 3.24.1 and svelte-eslint-parser 1.10.1
// use: the tokenizers, the parsers (with the safe parser and the template tokenizer of
// eslint-plugin-svelte's css-utils) and the selector parser. The text is a string of UTF-16 code
// units, as in JavaScript: every offset, length and column is one of those units, and the
// strings of the nodes are the units decoded (`units` and `text` convert).

// units is the UTF-16 code units of a string.
pub fn units(s string) []u16 {
	mut out := []u16{cap: s.len}
	for r in s.runes() {
		c := u32(r)
		if c >= 0x10000 {
			v := c - 0x10000
			out << u16(0xD800 + (v >> 10))
			out << u16(0xDC00 + (v & 0x3FF))
		} else {
			out << u16(c)
		}
	}
	return out
}

// text is the string of UTF-16 code units (a lone surrogate becomes U+FFFD).
pub fn text(u []u16) string {
	mut out := []u8{cap: u.len}
	mut i := 0
	for i < u.len {
		mut c := u32(u[i])
		if c >= 0xD800 && c <= 0xDBFF && i + 1 < u.len && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF {
			c = 0x10000 + ((c - 0xD800) << 10) + (u32(u[i + 1]) - 0xDC00)
			i++
		} else if c >= 0xD800 && c <= 0xDFFF {
			c = 0xFFFD
		}
		i++
		out << rune(c).bytes()
	}
	return out.bytestr()
}

// u16_len is a string's JavaScript `length`.
pub fn u16_len(s string) int {
	mut n := 0
	for r in s.runes() {
		n += if u32(r) >= 0x10000 { 2 } else { 1 }
	}
	return n
}

// Input is postcss's Input: the CSS (without a leading byte order mark) and its file (`from`).
pub struct Input {
pub:
	css  []u16
	file string
mut:
	line_starts []int
}

// new_input is `new Input(css, {from})`.
pub fn new_input(css []u16, from string) Input {
	mut c := css.clone()
	if c.len > 0 && (c[0] == 0xFEFF || c[0] == 0xFFFE) {
		c = c[1..].clone()
	}
	mut starts := [0]
	for i, u in c {
		if u == `\n` {
			starts << i + 1
		}
	}
	return Input{
		css:         c
		file:        from
		line_starts: starts
	}
}

// Position is a position of a node: offset (from 0), line and column (from 1).
pub struct Position {
pub mut:
	offset int
	line   int
	column int
}

// from_offset is Input.fromOffset: the line and column of an offset (lines end at `\n` only).
pub fn (i &Input) from_offset(offset int) (int, int) {
	starts := i.line_starts
	mut min := 0
	if offset >= starts[starts.len - 1] {
		min = starts.len - 1
	} else {
		mut max := starts.len - 2
		for min < max {
			mid := min + ((max - min) >> 1)
			if offset < starts[mid] {
				max = mid - 1
			} else if offset >= starts[mid + 1] {
				min = mid + 1
			} else {
				min = mid
				break
			}
		}
	}
	return min + 1, offset - starts[min] + 1
}

// position is Parser.getPosition.
pub fn (i &Input) position(offset int) Position {
	line, column := i.from_offset(offset)
	return Position{
		offset: offset
		line:   line
		column: column
	}
}

// CssSyntaxError is the error postcss throws: msg() is what JavaScript's error.message says
// (`<file or <css input>>:<line>:<column>: <reason>`).
pub struct CssSyntaxError {
	Error
pub:
	reason string
	line   int
	column int
	file   string
}

pub fn (e CssSyntaxError) msg() string {
	file := if e.file != '' { e.file } else { '<css input>' }
	return '${file}:${e.line}:${e.column}: ${e.reason}'
}

// error_at is Input.error(message, {offset}) (and the tokenizer's `input.error(message, pos)`).
fn (i &Input) error_at(reason string, offset int) IError {
	line, column := i.from_offset(offset)
	return CssSyntaxError{
		reason: reason
		line:   line
		column: column
		file:   i.file
	}
}

// error_line is Input.error(message, line, column).
fn (i &Input) error_line(reason string, line int, column int) IError {
	return CssSyntaxError{
		reason: reason
		line:   line
		column: column
		file:   i.file
	}
}
