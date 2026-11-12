module rules

import math
import math.big
import strconv
import strings

// Values of JavaScript literals as typescript-estree computes them (`Literal.value`) and their
// string conversion (`String(value)`), to compare property names with TypeScript's.

// cooked_string is the value of a string or of a template without substitutions; `raw` comes
// without the delimiters. It applies the escapes and, in a template, normalizes CRLF and CR to LF.
// none for an invalid escape, a legacy octal (`\1`) or a lone UTF-16 surrogate.
fn cooked_string(raw string, template bool) ?string {
	src := if template { raw.replace('\r\n', '\n').replace('\r', '\n') } else { raw }
	mut out := strings.new_builder(src.len)
	mut i := 0
	for i < src.len {
		if src[i] != `\\` {
			out.write_u8(src[i])
			i++
			continue
		}
		if i + 1 >= src.len {
			return none
		}
		e := src[i + 1]
		i += 2
		match e {
			`n` {
				out.write_u8(`\n`)
			}
			`t` {
				out.write_u8(`\t`)
			}
			`r` {
				out.write_u8(`\r`)
			}
			`b` {
				out.write_u8(8)
			}
			`f` {
				out.write_u8(12)
			}
			`v` {
				out.write_u8(11)
			}
			`0` {
				if i < src.len && src[i].is_digit() {
					return none
				}
				out.write_u8(0)
			}
			`1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9` {
				return none
			}
			`x` {
				if i + 2 > src.len {
					return none
				}
				code := strconv.parse_uint(src[i..i + 2], 16, 8) or { return none }
				out.write_rune(rune(code))
				i += 2
			}
			`u` {
				mut code, next := unicode_escape(src, i)?
				i = next
				// A UTF-16 surrogate pair (`😀`) is a single character.
				if code >= 0xd800 && code <= 0xdbff {
					if i + 1 >= src.len || src[i] != `\\` || src[i + 1] != `u` {
						return none
					}
					low, after := unicode_escape(src, i + 2)?
					if low < 0xdc00 || low > 0xdfff {
						return none
					}
					code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00)
					i = after
				} else if code >= 0xdc00 && code <= 0xdfff {
					return none
				}
				out.write_rune(rune(code))
			}
			`\r` {
				// Line continuation: `\` followed by a line break adds nothing.
				if i < src.len && src[i] == `\n` {
					i++
				}
			}
			`\n` {}
			else {
				// Identity escape (`\'`, `\a`…), or continuation with U+2028/U+2029.
				start := i - 1
				end := start + utf8_char_len(e)
				if end > src.len {
					return none
				}
				ch := src[start..end]
				if ch != ' ' && ch != ' ' {
					out.write_string(ch)
				}
				i = end
			}
		}
	}
	return out.str()
}

// cooked_units is cooked_string in UTF-16 units, which is what a JavaScript string is: it also
// gives the value of a literal with a surrogate that has no pair (`'\ud800'`), which a V string
// cannot hold. Each escape of a surrogate is one unit, and the text between them is cooked as it
// is.
fn cooked_units(raw string, template bool) ?[]u16 {
	if value := cooked_string(raw, template) {
		return utf16_units(value)
	}
	mut out := []u16{}
	mut start := 0
	mut i := 0
	for i < raw.len {
		if raw[i] != `\\` || i + 1 >= raw.len {
			i++
			continue
		}
		if raw[i + 1] != `u` {
			// Any other escape: the character after the backslash is part of it.
			i += 2
			continue
		}
		code, next := unicode_escape(raw, i + 2)?
		if code >= 0xd800 && code <= 0xdfff {
			out << utf16_units(cooked_string(raw[start..i], template)?)
			out << u16(code)
			start = next
		}
		i = next
	}
	out << utf16_units(cooked_string(raw[start..], template)?)
	return out
}

// unicode_escape reads what follows `\u` at `i`: four hex digits or `{…}`. Returns the code point
// and the next position.
fn unicode_escape(src string, i int) ?(u32, int) {
	if i < src.len && src[i] == `{` {
		end := src.index_after_('}', i)
		if end < 0 || end == i + 1 {
			return none
		}
		code := strconv.parse_uint(src[i + 1..end], 16, 32) or { return none }
		if code > 0x10ffff {
			return none
		}
		return u32(code), end + 1
	}
	if i + 4 > src.len {
		return none
	}
	code := strconv.parse_uint(src[i..i + 4], 16, 16) or { return none }
	return u32(code), i + 4
}

// js_number_string is String(value) of a JavaScript numeric literal: `0x10` → "16",
// `1.50` → "1.5", `1e21` → "1e+21", `.5` → "0.5", and a BigInt `0x10n` → "16".
fn js_number_string(text string) ?string {
	t := text.replace('_', '')
	if t.ends_with('n') {
		return integer_literal(t[..t.len - 1])?.str()
	}
	value := if is_integer_literal(t) {
		integer_to_f64(integer_literal(t)?)
	} else {
		// strconv.atof64 gets ordinary literals right, but does not always round a halfway case with 17
		// or more digits correctly.
		js_atof64(t) or { return none }
	}
	return js_number_to_string(value)
}

// js_atof64 parses a decimal number as JavaScript reads it: one too large for a double is
// Infinity. strconv.atof64 gave it too, and reports an error since V 3c0fc3e (2026-10-10).
fn js_atof64(text string) !f64 {
	return strconv.atof64(text) or {
		if err.msg().ends_with('value out of range') {
			return math.inf(if text.starts_with('-') { -1 } else { 1 })
		}
		return err
	}
}

fn is_integer_literal(t string) bool {
	lower := t.to_lower()
	if lower.starts_with('0x') || lower.starts_with('0o') || lower.starts_with('0b') {
		return true
	}
	return t.len > 0 && t.bytes().all(it.is_digit())
}

// number_literal_value is the value of a number literal as written (`1_000`, `0x1F`, `017`, `.5`,
// `1e3`); none for a BigInt literal (`0n`, whose value is no number) or what is not a number.
fn number_literal_value(text string) ?f64 {
	t := text.replace('_', '')
	if t.ends_with('n') {
		return none
	}
	if small := small_decimal_literal(t) {
		return small
	}
	if is_integer_literal(t) {
		return integer_to_f64(integer_literal(t)?)
	}
	return js_atof64(t) or { return none }
}

// small_decimal_literal is the value of a decimal integer literal of at most 15 digits without a
// leading zero (`0` itself is one), which a double holds exactly: what integer_to_f64 of
// integer_literal gives, without math.big. Any other literal is none.
fn small_decimal_literal(t string) ?f64 {
	if t.len == 0 || t.len > 15 || (t.len > 1 && t[0] == `0`) {
		return none
	}
	mut value := u64(0)
	for ch in t {
		if !ch.is_digit() {
			return none
		}
		value = value * 10 + u64(ch - `0`)
	}
	return f64(value)
}

// integer_literal is the value of an integer literal: decimal, hexadecimal, octal, binary or
// legacy octal (`017`; with an 8 or a 9 it is decimal).
fn integer_literal(t string) ?big.Integer {
	lower := t.to_lower()
	digits, radix := if lower.starts_with('0x') {
		lower[2..], u32(16)
	} else if lower.starts_with('0o') {
		lower[2..], u32(8)
	} else if lower.starts_with('0b') {
		lower[2..], u32(2)
	} else if t.len > 1 && t[0] == `0` && t.bytes().all(it >= `0` && it <= `7`) {
		t[1..], u32(8)
	} else {
		t, u32(10)
	}
	if digits.len == 0 {
		return none
	}
	return big.integer_from_radix(digits, radix) or { return none }
}

// integer_to_f64 converts an integer to the nearest double, ties to even, like JavaScript.
fn integer_to_f64(n big.Integer) f64 {
	bits := n.bit_len()
	if bits <= 53 {
		return f64(strconv.parse_uint(n.str(), 10, 64) or { 0 })
	}
	shift := u32(bits - 53)
	mut mant := n.right_shift(shift)
	low := n - mant.left_shift(shift)
	half := big.integer_from_int(1).left_shift(shift - 1)
	if half < low || (low == half && mant.is_odd()) {
		mant = mant + big.integer_from_int(1)
	}
	return math.ldexp(f64(strconv.parse_uint(mant.str(), 10, 64) or { 0 }), int(shift))
}

// js_number_to_string ports ECMAScript Number::toString(10) from the shortest digits that keep
// the value (strconv.ftoa_64, with the Ryu algorithm).
fn js_number_to_string(x f64) string {
	if math.is_nan(x) {
		return 'NaN'
	}
	if x == 0 {
		return '0'
	}
	if x < 0 {
		return '-' + js_number_to_string(-x)
	}
	if math.is_inf(x, 1) {
		return 'Infinity'
	}
	sci := strconv.ftoa_64(x)
	mantissa, exponent := sci.split_once('e') or { return sci }
	digits := mantissa.replace('.', '')
	k := digits.len
	n := exponent.int() + 1
	if k <= n && n <= 21 {
		return digits + '0'.repeat(n - k)
	}
	if 0 < n && n <= 21 {
		return '${digits[..n]}.${digits[n..]}'
	}
	if -6 < n && n <= 0 {
		return '0.${'0'.repeat(-n)}${digits}'
	}
	sign := if n - 1 < 0 { '-' } else { '+' }
	e := math.abs(n - 1)
	if k == 1 {
		return '${digits}e${sign}${e}'
	}
	return '${digits[..1]}.${digits[1..]}e${sign}${e}'
}
