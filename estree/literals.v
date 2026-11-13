module estree

import math
import math.big
import strings

// Values of literals as TypeScript's scanner computes them (the `text` of the node), which
// typescript-estree puts in `Literal.value`, `TemplateElement.value.cooked`, `Identifier.name`
// and `JSXText.value`. Strings are WTF-8: a lone UTF-16 surrogate (`'\ud800'`) is kept as its
// 3-byte encoding, so that every JavaScript string has a V string.

// Units collects UTF-16 code units and encodes them as WTF-8 (a pair of surrogates is one
// 4-byte character).
struct Units {
mut:
	units []u16
}

fn (mut u Units) add_code_point(cp u32) {
	if cp >= 0x10000 {
		v := cp - 0x10000
		u.units << u16(0xd800 + (v >> 10))
		u.units << u16(0xdc00 + (v & 0x3ff))
	} else {
		u.units << u16(cp)
	}
}

// add_utf8 adds the characters of a UTF-8 (or WTF-8) text.
fn (mut u Units) add_utf8(s string) {
	mut i := 0
	for i < s.len {
		cp, n := decode_wtf8(s, i)
		u.add_code_point(cp)
		i += n
	}
}

fn (u &Units) wtf8() string {
	mut b := strings.new_builder(u.units.len + 8)
	mut i := 0
	for i < u.units.len {
		c := u32(u.units[i])
		if c >= 0xd800 && c <= 0xdbff && i + 1 < u.units.len && u.units[i + 1] >= 0xdc00
			&& u.units[i + 1] <= 0xdfff {
			cp := 0x10000 + ((c - 0xd800) << 10) + (u32(u.units[i + 1]) - 0xdc00)
			write_wtf8(mut b, cp)
			i += 2
			continue
		}
		write_wtf8(mut b, c)
		i++
	}
	return b.str()
}

fn write_wtf8(mut b strings.Builder, cp u32) {
	if cp < 0x80 {
		b.write_u8(u8(cp))
	} else if cp < 0x800 {
		b.write_u8(u8(0xc0 | (cp >> 6)))
		b.write_u8(u8(0x80 | (cp & 0x3f)))
	} else if cp < 0x10000 {
		b.write_u8(u8(0xe0 | (cp >> 12)))
		b.write_u8(u8(0x80 | ((cp >> 6) & 0x3f)))
		b.write_u8(u8(0x80 | (cp & 0x3f)))
	} else {
		b.write_u8(u8(0xf0 | (cp >> 18)))
		b.write_u8(u8(0x80 | ((cp >> 12) & 0x3f)))
		b.write_u8(u8(0x80 | ((cp >> 6) & 0x3f)))
		b.write_u8(u8(0x80 | (cp & 0x3f)))
	}
}

// decode_wtf8 decodes the character at `i`: its code point and its length in bytes. An invalid
// byte counts as one character with its own value.
fn decode_wtf8(s string, i int) (u32, int) {
	c := u32(s[i])
	if c < 0x80 {
		return c, 1
	}
	if c >= 0xf0 && i + 3 < s.len {
		return ((c & 0x07) << 18) | ((u32(s[i + 1]) & 0x3f) << 12) | ((u32(s[i + 2]) & 0x3f) << 6) | (u32(s[i + 3]) & 0x3f), 4
	}
	if c >= 0xe0 && i + 2 < s.len {
		return ((c & 0x0f) << 12) | ((u32(s[i + 1]) & 0x3f) << 6) | (u32(s[i + 2]) & 0x3f), 3
	}
	if c >= 0xc0 && i + 1 < s.len {
		return ((c & 0x1f) << 6) | (u32(s[i + 1]) & 0x3f), 2
	}
	return c, 1
}

// utf16_units are the UTF-16 code units of a WTF-8 string.
pub fn utf16_units(s string) []u16 {
	mut u := Units{}
	u.add_utf8(s)
	return u.units
}

fn is_hex(c u8) bool {
	return (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

fn hex_value(c u8) u32 {
	return if c <= `9` {
		u32(c - `0`)
	} else if c >= `a` {
		u32(c - `a` + 10)
	} else {
		u32(c - `A` + 10)
	}
}

fn is_octal(c u8) bool {
	return c >= `0` && c <= `7`
}

// cook ports TypeScript's scanString and scanTemplateAndSetTokenValue: the value of the text
// between the delimiters of a string literal or of a template part. In a template, a line break
// (CR, CRLF or LF) is a LF. Without `report` (a tagged template), an invalid escape is kept as
// written, as TypeScript does; with it, TypeScript reported an error and the value is what it
// gives then.
fn cook(raw string, template bool, report bool) string {
	if !raw.contains_u8(`\\`) && !(template && raw.contains_u8(`\r`)) {
		return raw
	}
	mut u := Units{}
	mut i := 0
	mut seg := 0
	for i < raw.len {
		ch := raw[i]
		if ch == `\r` && template {
			u.add_utf8(raw[seg..i])
			i++
			if i < raw.len && raw[i] == `\n` {
				i++
			}
			u.units << `\n`
			seg = i
			continue
		}
		if ch != `\\` {
			i++
			continue
		}
		u.add_utf8(raw[seg..i])
		start := i
		i++
		if i >= raw.len {
			seg = i
			break
		}
		e := raw[i]
		i++
		match e {
			`0`, `1`, `2`, `3`, `4`, `5`, `6`, `7` {
				if e == `0` && (i >= raw.len || !raw[i].is_digit()) {
					u.units << 0
				} else {
					if e <= `3` && i < raw.len && is_octal(raw[i]) {
						i++
					}
					if i < raw.len && is_octal(raw[i]) {
						i++
					}
					if report {
						mut code := u32(0)
						for k in start + 1 .. i {
							code = code * 8 + u32(raw[k] - `0`)
						}
						u.units << u16(code)
					} else {
						u.add_utf8(raw[start..i])
					}
				}
			}
			`8`, `9` {
				if report {
					u.units << u16(e)
				} else {
					u.add_utf8(raw[start..i])
				}
			}
			`b` {
				u.units << 8
			}
			`t` {
				u.units << 9
			}
			`n` {
				u.units << 10
			}
			`v` {
				u.units << 11
			}
			`f` {
				u.units << 12
			}
			`r` {
				u.units << 13
			}
			`u` {
				if i < raw.len && raw[i] == `{` {
					mut j := i + 1
					mut value := u64(0)
					for j < raw.len && is_hex(raw[j]) {
						if value <= 0x10ffff {
							value = value * 16 + hex_value(raw[j])
						}
						j++
					}
					mut invalid := j == i + 1 || value > 0x10ffff
					if j < raw.len && raw[j] == `}` {
						j++
					} else {
						invalid = true
					}
					i = j
					if invalid {
						u.add_utf8(raw[start..i])
					} else {
						u.add_code_point(u32(value))
					}
				} else {
					mut j := i
					for j < start + 6 && j < raw.len && is_hex(raw[j]) {
						j++
					}
					if j < start + 6 {
						i = j
						u.add_utf8(raw[start..i])
					} else {
						mut value := u32(0)
						for k in i .. j {
							value = value * 16 + hex_value(raw[k])
						}
						u.units << u16(value)
						i = j
					}
				}
			}
			`x` {
				if i + 1 < raw.len && is_hex(raw[i]) && is_hex(raw[i + 1]) {
					u.units << u16(hex_value(raw[i]) * 16 + hex_value(raw[i + 1]))
					i += 2
				} else {
					if i < raw.len && is_hex(raw[i]) {
						i++
					}
					u.add_utf8(raw[start..i])
				}
			}
			`\r` {
				if i < raw.len && raw[i] == `\n` {
					i++
				}
			}
			`\n` {}
			else {
				// Any other character stands for itself; U+2028 and U+2029 continue the line.
				cp, n := decode_wtf8(raw, i - 1)
				i += n - 1
				if cp != 0x2028 && cp != 0x2029 {
					u.add_code_point(cp)
				}
			}
		}
		seg = i
	}
	if seg < raw.len {
		u.add_utf8(raw[seg..])
	}
	return u.wtf8()
}

// valid_template_escapes ports typescript-estree's #isValidEscape: whether the raw text of a
// template part has only well-formed `\x` and `\u` escapes (else, in a tagged template, `cooked`
// is null).
fn valid_template_escapes(raw string) bool {
	for i := 0; i + 1 < raw.len; i++ {
		if raw[i] != `\\` {
			continue
		}
		// The regular expressions of #isValidEscape do not skip escaped backslashes: `\\x` has
		// `\x` too.
		match raw[i + 1] {
			`u` {
				if i + 2 < raw.len && raw[i + 2] == `{` {
					continue
				}
				if i + 6 > raw.len {
					return false
				}
				for k in i + 2 .. i + 6 {
					if !is_hex(raw[k]) {
						return false
					}
				}
			}
			`x` {
				if i + 4 > raw.len || !is_hex(raw[i + 2]) || !is_hex(raw[i + 3]) {
					return false
				}
			}
			else {}
		}
	}
	return true
}

// identifier_name is the text of an identifier with its `\uXXXX` and `\u{…}` escapes applied.
fn identifier_name(raw string) string {
	if !raw.contains_u8(`\\`) {
		return raw
	}
	return cook(raw, false, true)
}

// jsx_unescape ports typescript-estree's unescapeStringLiteralText: it replaces the XHTML
// entities (`&amp;`, `&#123;`, `&#x7B;`) of a JSX text or attribute value.
fn jsx_unescape(text string) string {
	if !text.contains_u8(`&`) {
		return text
	}
	mut b := strings.new_builder(text.len)
	mut i := 0
	for i < text.len {
		if text[i] != `&` {
			b.write_u8(text[i])
			i++
			continue
		}
		semi := text.index_after_(';', i + 1)
		if semi < 0 {
			b.write_string(text[i..])
			break
		}
		item := text[i + 1..semi]
		mut ok := false
		mut cp := u32(0)
		if item.len > 1 && item[0] == `#` {
			if item[1] == `x` {
				digits := item[2..]
				if digits.len > 0 && digits.bytes().all(is_hex(it)) {
					ok = true
					mut v := u64(0)
					for d in digits {
						if v <= 0x10ffff {
							v = v * 16 + hex_value(d)
						}
					}
					if v > 0x10ffff {
						ok = false
						// `&#x110000;` matches the pattern and stays as written.
						b.write_string(text[i..semi + 1])
						i = semi + 1
						continue
					}
					cp = u32(v)
				}
			} else {
				digits := item[1..]
				if digits.len > 0 && digits.bytes().all(it.is_digit()) {
					ok = true
					mut v := u64(0)
					for d in digits {
						if v <= 0x10ffff {
							v = v * 10 + u64(d - `0`)
						}
					}
					if v > 0x10ffff {
						b.write_string(text[i..semi + 1])
						i = semi + 1
						continue
					}
					cp = u32(v)
				}
			}
		} else if item.len > 0 && item.bytes().all(it.is_alnum()) {
			if item in xhtml_entities {
				ok = true
				cp = xhtml_entities[item]
			} else {
				// A name the table does not have stays as written.
				b.write_string(text[i..semi + 1])
				i = semi + 1
				continue
			}
		}
		if ok {
			write_wtf8(mut b, cp)
			i = semi + 1
		} else {
			// Not an entity: the `&` is text, and the search goes on after it.
			b.write_u8(`&`)
			i++
		}
	}
	return b.str()
}

// NumberLiteral is the value of a numeric literal: a double, or the decimal digits of a BigInt.
struct NumberLiteral {
	value   f64
	is_big  bool
	decimal string
}

fn number_literal(raw string) NumberLiteral {
	t := if raw.contains_u8(`_`) { raw.replace('_', '') } else { raw }
	if t.ends_with('n') {
		n := integer_literal(t[..t.len - 1]) or { big.integer_from_int(0) }
		return NumberLiteral{
			is_big:  true
			decimal: n.str()
		}
	}
	return NumberLiteral{
		value: number_value(t)
	}
}

// number_value is Number(text) of a numeric literal without separators.
fn number_value(t string) f64 {
	if t.len > 1 && t[0] == `0` {
		c := t[1] | 0x20
		if c == `x` || c == `o` || c == `b` || t.bytes().all(it.is_digit()) {
			if n := integer_literal(t) {
				return integer_to_f64(n)
			}
		}
	}
	// Decimal: digits, fraction and exponent.
	mut digits := strings.new_builder(t.len)
	mut exp := 0
	mut i := 0
	for i < t.len && t[i].is_digit() {
		digits.write_u8(t[i])
		i++
	}
	if i < t.len && t[i] == `.` {
		i++
		for i < t.len && t[i].is_digit() {
			digits.write_u8(t[i])
			exp--
			i++
		}
	}
	if i < t.len && (t[i] == `e` || t[i] == `E`) {
		i++
		mut neg := false
		if i < t.len && (t[i] == `+` || t[i] == `-`) {
			neg = t[i] == `-`
			i++
		}
		mut e := 0
		for i < t.len && t[i].is_digit() {
			if e < 100000 {
				e = e * 10 + int(t[i] - `0`)
			}
			i++
		}
		exp += if neg { -e } else { e }
	}
	return decimal_to_f64(digits.str(), exp)
}

// integer_literal is the value of an integer literal: decimal, hexadecimal, octal, binary or
// legacy octal (`017`; with an 8 or a 9 it is decimal).
fn integer_literal(t string) ?big.Integer {
	digits, radix := if t.len > 1 && t[0] == `0` && (t[1] | 0x20) == `x` {
		t[2..], u32(16)
	} else if t.len > 1 && t[0] == `0` && (t[1] | 0x20) == `o` {
		t[2..], u32(8)
	} else if t.len > 1 && t[0] == `0` && (t[1] | 0x20) == `b` {
		t[2..], u32(2)
	} else if t.len > 1 && t[0] == `0` && t.bytes().all(it >= `0` && it <= `7`) {
		t[1..], u32(8)
	} else {
		t, u32(10)
	}
	if digits.len == 0 {
		return none
	}
	return big.integer_from_radix(digits.to_lower(), radix) or { return none }
}

const pow10_exact = [1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13,
	1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22]!

// decimal_to_f64 is the double nearest to digits × 10^exp10 (ties to even), as Number() reads a
// decimal literal.
fn decimal_to_f64(all_digits string, exp10 int) f64 {
	mut digits := all_digits.trim_left('0')
	mut exp := exp10
	// Trailing zeros only scale the value.
	for digits.len > 0 && digits[digits.len - 1] == `0` {
		digits = digits[..digits.len - 1]
		exp++
	}
	if digits.len == 0 {
		return 0
	}
	if digits.len <= 15 && exp >= -22 && exp <= 22 {
		mut v := u64(0)
		for d in digits {
			v = v * 10 + u64(d - `0`)
		}
		return if exp >= 0 { f64(v) * pow10_exact[exp] } else { f64(v) / pow10_exact[-exp] }
	}
	if digits.len + exp > 310 {
		return math.inf(1)
	}
	if digits.len + exp < -330 {
		return 0
	}
	num := big.integer_from_string(digits) or { return math.nan() }
	ten := big.integer_from_int(10)
	if exp >= 0 {
		return integer_to_f64(num * ten.pow(u32(exp)))
	}
	return ratio_to_f64(num, ten.pow(u32(-exp)))
}

// integer_to_f64 converts a non-negative integer to the nearest double, ties to even.
fn integer_to_f64(n big.Integer) f64 {
	return ratio_to_f64(n, big.integer_from_int(1))
}

// ratio_to_f64 is the double nearest to num / den (both positive), ties to even, with gradual
// underflow and overflow to Infinity.
fn ratio_to_f64(num big.Integer, den big.Integer) f64 {
	nb := num.bit_len()
	if nb == 0 {
		return 0
	}
	db := den.bit_len()
	// q = num × 2^s / den has 56 or 57 bits.
	s := 56 - (nb - db)
	mut n2 := num
	mut d2 := den
	if s >= 0 {
		n2 = num.left_shift(u32(s))
	} else {
		d2 = den.left_shift(u32(-s))
	}
	q, r := n2.div_mod(d2)
	qb := q.bit_len()
	// Position of the lowest bit the double keeps (2^lb), at most 53 bits, not below 2^-1074.
	mut lb := (qb - 1 - s) - 52
	if lb < -1074 {
		lb = -1074
	}
	drop := lb + s
	if drop <= 0 {
		// Exact in 53 bits (s is large enough that this only happens for small integers).
		return math.ldexp(f64(q.str().u64()), -s)
	}
	mut mant := q.right_shift(u32(drop))
	rem := q - mant.left_shift(u32(drop))
	half := big.integer_from_int(1).left_shift(u32(drop - 1))
	if half < rem || (rem == half && (r.bit_len() > 0 || mant.is_odd())) {
		mant = mant + big.integer_from_int(1)
	}
	return math.ldexp(f64(mant.str().u64()), lb)
}

// js_parse_float ports parseFloat of a text of decimal digits with at most one `.` (the numbers
// of esquery selectors): the nearest double, ties to even.
pub fn js_parse_float(text string) f64 {
	int_part, frac := if dot := text.index('.') {
		text[..dot], text[dot + 1..]
	} else {
		text, ''
	}
	return decimal_to_f64(int_part + frac, -frac.len)
}

// js_decimal is the double nearest to digits × 10^exp10 (ties to even), as JavaScript reads a
// decimal number.
pub fn js_decimal(digits string, exp10 int) f64 {
	return decimal_to_f64(digits, exp10)
}
