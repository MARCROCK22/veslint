module rules

import jsregexp
import math

// More callAllowed functions for static_value.v, with their exceptions (`none`, which ends the
// evaluation like eslint-utils' try/catch): the URI functions and escape/unescape (ECMA-262's
// Encode and Decode, and Annex B), String.fromCodePoint, String.raw called as a function,
// Array.prototype.flat, Object.prototype.isPrototypeOf, Math.f16round and
// Number.prototype.toString (V8's DoubleToRadixCString for a radix other than 10).

// What encodeURIComponent leaves as it is: the ASCII word characters and `-.!~*'()`.
const stv_uri_unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.!~*'()"

// What encodeURI also leaves as it is, and what decodeURI does not decode.
const stv_uri_reserved = ';/?:@&=+$,#'

// What escape leaves as it is: the ASCII word characters and `@*+-./`.
const stv_escape_unescaped = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@*+-./'

const stv_hex_digits = '0123456789ABCDEF'

const stv_radix_digits = '0123456789abcdefghijklmnopqrstuvwxyz'

fn stv_ascii_in(c u16, set string) bool {
	return c < 0x80 && set.contains_u8(u8(c))
}

// stv_hex_value is the value of a hexadecimal digit, or -1.
fn stv_hex_value(c u16) int {
	if c >= u16(`0`) && c <= u16(`9`) {
		return int(c) - int(`0`)
	}
	if c >= u16(`a`) && c <= u16(`f`) {
		return int(c) - int(`a`) + 10
	}
	if c >= u16(`A`) && c <= u16(`F`) {
		return int(c) - int(`A`) + 10
	}
	return -1
}

// stv_append_percent appends `%XX`, the byte in uppercase hexadecimal.
fn stv_append_percent(mut out []u16, b u32) {
	out << u16(`%`)
	out << u16(stv_hex_digits[int((b >> 4) & 0xf)])
	out << u16(stv_hex_digits[int(b & 0xf)])
}

// stv_uri_encode ports Encode: the code points that are not unreserved (nor in `extra`) are
// written as the `%XX` of each byte of their UTF-8 encoding; a lone surrogate is a URIError.
fn stv_uri_encode(s []u16, extra string) ?[]u16 {
	mut out := []u16{cap: s.len}
	mut k := 0
	for k < s.len {
		c := s[k]
		if stv_ascii_in(c, stv_uri_unreserved) || stv_ascii_in(c, extra) {
			out << c
			k++
			continue
		}
		if c >= 0xDC00 && c <= 0xDFFF {
			return none
		}
		mut cp := u32(c)
		if c >= 0xD800 && c <= 0xDBFF {
			if k + 1 >= s.len || s[k + 1] < 0xDC00 || s[k + 1] > 0xDFFF {
				return none
			}
			cp = 0x10000 + ((u32(c) - 0xD800) << 10) + (u32(s[k + 1]) - 0xDC00)
			k++
		}
		k++
		if cp < 0x80 {
			stv_append_percent(mut out, cp)
		} else if cp < 0x800 {
			stv_append_percent(mut out, 0xC0 | (cp >> 6))
			stv_append_percent(mut out, 0x80 | (cp & 0x3f))
		} else if cp < 0x10000 {
			stv_append_percent(mut out, 0xE0 | (cp >> 12))
			stv_append_percent(mut out, 0x80 | ((cp >> 6) & 0x3f))
			stv_append_percent(mut out, 0x80 | (cp & 0x3f))
		} else {
			stv_append_percent(mut out, 0xF0 | (cp >> 18))
			stv_append_percent(mut out, 0x80 | ((cp >> 12) & 0x3f))
			stv_append_percent(mut out, 0x80 | ((cp >> 6) & 0x3f))
			stv_append_percent(mut out, 0x80 | (cp & 0x3f))
		}
	}
	return out
}

// stv_percent_byte is ParseHexOctet(s, k + 1) for the `%` at s[k]: the byte its two hexadecimal
// digits write, or -1 when there are not two.
fn stv_percent_byte(s []u16, k int) int {
	if k + 2 >= s.len {
		return -1
	}
	hi := stv_hex_value(s[k + 1])
	lo := stv_hex_value(s[k + 2])
	if hi < 0 || lo < 0 {
		return -1
	}
	return hi * 16 + lo
}

// stv_uri_decode ports Decode: each run of `%XX` sequences is the UTF-8 encoding of a code point,
// except an ASCII character of `preserve`, whose sequence stays as it is; anything else (a `%`
// without two hexadecimal digits, a byte that cannot start or continue the encoding, an overlong
// form, a surrogate, a code point beyond U+10FFFF) is a URIError.
fn stv_uri_decode(s []u16, preserve string) ?[]u16 {
	mut out := []u16{cap: s.len}
	mut k := 0
	for k < s.len {
		c := s[k]
		if c != u16(`%`) {
			out << c
			k++
			continue
		}
		start := k
		b := stv_percent_byte(s, k)
		if b < 0 {
			return none
		}
		k += 2
		if b < 0x80 {
			if stv_ascii_in(u16(b), preserve) {
				out << s[start..k + 1]
			} else {
				out << u16(b)
			}
			k++
			continue
		}
		mut n := 0
		if b & 0xE0 == 0xC0 {
			n = 2
		} else if b & 0xF0 == 0xE0 {
			n = 3
		} else if b & 0xF8 == 0xF0 {
			n = 4
		} else {
			return none
		}
		mut cp := u32(b) & (u32(0x7f) >> u32(n))
		for _ in 1 .. n {
			k++
			if k >= s.len || s[k] != u16(`%`) {
				return none
			}
			next := stv_percent_byte(s, k)
			if next < 0 || next & 0xC0 != 0x80 {
				return none
			}
			k += 2
			cp = (cp << 6) | u32(next & 0x3f)
		}
		minimum := [u32(0), 0, 0x80, 0x800, 0x10000][n]
		if cp < minimum || (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF {
			return none
		}
		jsregexp.append_utf16(mut out, cp)
		k++
	}
	return out
}

// stv_escape ports escape (Annex B): `%XX` for a code unit below 256, `%uXXXX` for the others.
fn stv_escape(s []u16) []u16 {
	mut out := []u16{cap: s.len}
	for c in s {
		if stv_ascii_in(c, stv_escape_unescaped) {
			out << c
		} else if c < 256 {
			stv_append_percent(mut out, u32(c))
		} else {
			out << u16(`%`)
			out << u16(`u`)
			for shift := 12; shift >= 0; shift -= 4 {
				out << u16(stv_hex_digits[int((u32(c) >> u32(shift)) & 0xf)])
			}
		}
	}
	return out
}

// stv_unescape ports unescape (Annex B): `%uXXXX` when there is room for it after a `%` followed
// by `u` (and nothing else then), `%XX` otherwise; what is not a valid escape stays as it is.
fn stv_unescape(s []u16) []u16 {
	mut out := []u16{cap: s.len}
	mut k := 0
	for k < s.len {
		mut c := s[k]
		if c == u16(`%`) {
			if k + 6 <= s.len && s[k + 1] == u16(`u`) {
				mut value := 0
				mut valid := true
				for j in 2 .. 6 {
					h := stv_hex_value(s[k + j])
					if h < 0 {
						valid = false
						break
					}
					value = value * 16 + h
				}
				if valid {
					c = u16(value)
					k += 5
				}
			} else if k + 3 <= s.len {
				b := stv_percent_byte(s, k)
				if b >= 0 {
					c = u16(b)
					k += 2
				}
			}
		}
		out << c
		k++
	}
	return out
}

// stv_from_code_point ports String.fromCodePoint: what is not an integral number from 0 to
// 0x10FFFF is a RangeError.
fn stv_from_code_point(args []JsAny) ?[]u16 {
	mut out := []u16{cap: args.len}
	for a in args {
		n := stv_to_number(a)?
		if math.is_nan(n) || math.is_inf(n, 0) || n != math.trunc(n) || n < 0 || n > 0x10FFFF {
			return none
		}
		jsregexp.append_utf16(mut out, u32(n))
	}
	return out
}

// stv_length_of_array_like ports LengthOfArrayLike: ToLength(Get(object, "length")).
fn stv_length_of_array_like(object JsAny) ?f64 {
	length := stv_to_integer(stv_get(object, js_any_text('length'))?)?
	return if length <= 0 { 0.0 } else { math.min(length, 9007199254740991.0) }
}

// stv_string_raw_call ports String.raw(template, ...substitutions) called as a function: the
// `raw` strings of the template with the substitutions between them. A result of more than
// stv_string_max_length units is not evaluated (the long-string limit).
fn stv_string_raw_call(args []JsAny) ?[]u16 {
	// ToObject(template) is a TypeError for undefined and null; a primitive has no `raw`, and
	// ToObject(undefined) is a TypeError too.
	if args.len == 0 || stv_is_nullish(args[0]) {
		return none
	}
	raw := stv_get(args[0], js_any_text('raw'))?
	if stv_is_nullish(raw) {
		return none
	}
	count := stv_length_of_array_like(raw)?
	if count > f64(stv_string_max_length) {
		return none
	}
	mut out := []u16{}
	for i := 0; i < int(count); i++ {
		out << stv_to_string(stv_get(raw, js_any_number(i))?)?
		if i + 1 == int(count) {
			break
		}
		if i + 1 < args.len {
			out << stv_to_string(args[i + 1])?
		}
		if out.len > stv_string_max_length {
			return none
		}
	}
	return out
}

// stv_flatten ports FlattenIntoArray: holes are left out, and the arrays among the elements are
// flattened `depth` more levels.
fn stv_flatten(mut out []JsAny, elements []JsAny, depth f64, level int) ? {
	if level > stv_max_depth {
		return none
	}
	for e in elements {
		if e.kind == .hole_ {
			continue
		}
		if depth > 0 && e.kind == .array_ {
			stv_flatten(mut out, e.elements, depth - 1, level + 1)?
		} else {
			out << e
		}
	}
}

// stv_is_prototype_of ports Object.prototype.isPrototypeOf(value): false for a value that is not
// an object, a TypeError for an undefined or null receiver, and false otherwise, since no value
// veslint models is the prototype of another (the prototype objects, like `Array.prototype`, are
// the builtin-property limit).
fn stv_is_prototype_of(this JsAny, has_receiver bool, value JsAny) ?bool {
	if !stv_is_object(value) {
		return false
	}
	if !has_receiver || stv_is_nullish(this) {
		return none
	}
	return false
}

// stv_f16round ports Math.f16round: the nearest IEEE 754 binary16 value, ties to even, as a
// double. From 65520 (the largest one, 65504, and half a unit) on, it is an infinity.
fn stv_f16round(x f64) f64 {
	if math.is_nan(x) || math.is_inf(x, 0) || x == 0 {
		return x
	}
	a := math.abs(x)
	if a >= 65520 {
		return if x > 0 { math.inf(1) } else { math.inf(-1) }
	}
	// a = m * 2^e with 0.5 <= m < 1: the binary16 exponent is e - 1, at least -14 (below it the
	// numbers are subnormal), and 10 bits of fraction follow the leading one.
	_, e := math.frexp(a)
	exponent := if e - 1 < -14 { -14 } else { e - 1 }
	quantum := math.ldexp(1.0, exponent - 10)
	scaled := a / quantum
	mut rounded := math.floor(scaled)
	rest := scaled - rounded
	if rest > 0.5 || (rest == 0.5 && math.fmod(rounded, 2) != 0) {
		rounded += 1
	}
	result := rounded * quantum
	return if x < 0 { -result } else { result }
}

// stv_number_to_string ports Number.prototype.toString(radix) on the number `x`: ToString for no
// radix and for 10, a RangeError for a radix outside 2..36, and V8's DoubleToRadixCString for the
// others.
fn stv_number_to_string(x f64, radix JsAny) ?string {
	if radix.kind == .undefined_ {
		return js_number_to_string(x)
	}
	r := stv_to_integer(radix)?
	if r == 10 {
		return js_number_to_string(x)
	}
	if r < 2 || r > 36 {
		return none
	}
	return stv_number_to_radix(x, int(r))
}

// stv_double_exponent ports V8's Double::Exponent: the exponent of the double as an integer
// significand times a power of two (-1074 for zero and the subnormals).
fn stv_double_exponent(d f64) int {
	biased := int((math.f64_bits(d) >> 52) & 0x7ff)
	return if biased == 0 { -1074 } else { biased - 1075 }
}

// stv_number_to_radix ports V8's DoubleToRadixCString: the fraction digits go only as far as the
// precision of the double, the last one rounded to even, with the carry going up through the
// digits already written; the integer digits beyond the precision of the double are zeros.
fn stv_number_to_radix(value f64, radix int) string {
	if math.is_nan(value) {
		return 'NaN'
	}
	if math.is_inf(value, 0) {
		return if value > 0 { 'Infinity' } else { '-Infinity' }
	}
	// V8 answers a one-digit integer, zero included, before DoubleToRadixCString.
	if value == 0 {
		return '0'
	}
	negative := value < 0
	v := if negative { -value } else { value }
	mut integer := math.floor(v)
	mut fraction := v - integer
	mut delta := 0.5 * (math.nextafter(v, math.inf(1)) - v)
	delta = math.max(math.nextafter(0.0, 1.0), delta)
	mut fraction_digits := []u8{}
	if fraction >= delta {
		for {
			fraction *= radix
			delta *= radix
			digit := int(fraction)
			fraction_digits << stv_radix_digits[digit]
			fraction -= digit
			if fraction > 0.5 || (fraction == 0.5 && digit & 1 == 1) {
				if fraction + delta > 1 {
					// Round up, carrying over the digits already written; past the first one, into
					// the integer part.
					for {
						if fraction_digits.len == 0 {
							integer += 1
							break
						}
						last := stv_radix_digits.index_u8(fraction_digits.pop())
						if last + 1 < radix {
							fraction_digits << stv_radix_digits[last + 1]
							break
						}
					}
					break
				}
			}
			if fraction < delta {
				break
			}
		}
	}
	mut integer_digits := []u8{}
	for stv_double_exponent(integer / radix) > 0 {
		integer /= radix
		integer_digits << u8(`0`)
	}
	for {
		remainder := math.fmod(integer, radix)
		integer_digits << stv_radix_digits[int(remainder)]
		integer = (integer - remainder) / radix
		if integer <= 0 {
			break
		}
	}
	mut out := []u8{cap: integer_digits.len + fraction_digits.len + 2}
	if negative {
		out << u8(`-`)
	}
	for i := integer_digits.len - 1; i >= 0; i-- {
		out << integer_digits[i]
	}
	if fraction_digits.len > 0 {
		out << u8(`.`)
		out << fraction_digits
	}
	return out.bytestr()
}
