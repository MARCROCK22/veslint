module rules

import math
import math.big

// JavaScript values and the semantics of their operators (comparisons, loose and strict
// equality, ToNumber, StringToNumber, StringToBigInt), for rules that evaluate code like
// typescript-eslint does at lint time.

// JsValue is a primitive JavaScript value.
enum JsKind {
	undefined_
	null_
	boolean_
	number_
	string_
	bigint_
}

struct JsValue {
	kind    JsKind
	boolean bool
	number  f64
	text    string // a string, or the decimal digits of a BigInt
}

// js_compare ports booleanComparison: `left <operator> right` with JavaScript semantics.
fn js_compare(left JsValue, operator string, right JsValue) bool {
	return match operator {
		'===' { js_strict_equal(left, right) }
		'!==' { !js_strict_equal(left, right) }
		'==' { js_loose_equal(left, right) }
		'!=' { !js_loose_equal(left, right) }
		'<' { js_less_than(left, right) or { false } }
		'>' { js_less_than(right, left) or { false } }
		'<=' { !(js_less_than(right, left) or { true }) }
		'>=' { !(js_less_than(left, right) or { true }) }
		else { false }
	}
}

fn js_strict_equal(a JsValue, b JsValue) bool {
	if a.kind != b.kind {
		return false
	}
	return match a.kind {
		.undefined_, .null_ { true }
		.boolean_ { a.boolean == b.boolean }
		.number_ { a.number == b.number }
		.string_ { a.text == b.text }
		.bigint_ { js_bigint(a.text) or { return false } == js_bigint(b.text) or { return false } }
	}
}

fn js_loose_equal(a JsValue, b JsValue) bool {
	if a.kind == b.kind {
		return js_strict_equal(a, b)
	}
	nullish := [JsKind.undefined_, .null_]
	if a.kind in nullish || b.kind in nullish {
		return a.kind in nullish && b.kind in nullish
	}
	if a.kind == .boolean_ {
		return js_loose_equal(JsValue{ kind: .number_, number: if a.boolean { 1 } else { 0 } }, b)
	}
	if b.kind == .boolean_ {
		return js_loose_equal(a, JsValue{ kind: .number_, number: if b.boolean { 1 } else { 0 } })
	}
	if a.kind == .number_ && b.kind == .string_ {
		return a.number == js_string_to_number(b.text)
	}
	if a.kind == .string_ && b.kind == .number_ {
		return js_string_to_number(a.text) == b.number
	}
	if a.kind == .bigint_ && b.kind == .string_ {
		n := js_string_to_bigint(b.text) or { return false }
		return js_bigint(a.text) or { return false } == n
	}
	if a.kind == .string_ && b.kind == .bigint_ {
		return js_loose_equal(b, a)
	}
	if a.kind == .bigint_ && b.kind == .number_ {
		return js_compare_bigint_number(js_bigint(a.text) or { return false }, b.number) or {
			return false
		} == 0
	}
	if a.kind == .number_ && b.kind == .bigint_ {
		return js_loose_equal(b, a)
	}
	return false
}

// js_less_than ports IsLessThan for primitives; none is `undefined` (a NaN was involved).
fn js_less_than(a JsValue, b JsValue) ?bool {
	if a.kind == .string_ && b.kind == .string_ {
		return utf16_less(a.text, b.text)
	}
	if a.kind == .bigint_ && b.kind == .string_ {
		n := js_string_to_bigint(b.text)?
		return js_bigint(a.text)? < n
	}
	if a.kind == .string_ && b.kind == .bigint_ {
		n := js_string_to_bigint(a.text)?
		return n < js_bigint(b.text)?
	}
	if a.kind == .bigint_ && b.kind == .bigint_ {
		return js_bigint(a.text)? < js_bigint(b.text)?
	}
	if a.kind == .bigint_ {
		return js_compare_bigint_number(js_bigint(a.text)?, js_to_number(b))? < 0
	}
	if b.kind == .bigint_ {
		return js_compare_bigint_number(js_bigint(b.text)?, js_to_number(a))? > 0
	}
	x := js_to_number(a)
	y := js_to_number(b)
	if math.is_nan(x) || math.is_nan(y) {
		return none
	}
	return x < y
}

// js_to_number ports ToNumber for a primitive that is not a BigInt.
fn js_to_number(v JsValue) f64 {
	return match v.kind {
		.undefined_ { math.nan() }
		.null_ { 0 }
		.boolean_ {
			if v.boolean { 1 } else { 0 }
		}
		.number_ { v.number }
		.string_ { js_string_to_number(v.text) }
		.bigint_ { math.nan() }
	}
}

// js_compare_bigint_number compares a BigInt with a Number exactly: -1, 0 or 1; none for NaN.
fn js_compare_bigint_number(a big.Integer, n f64) ?int {
	if math.is_nan(n) {
		return none
	}
	if math.is_inf(n, 1) {
		return -1
	}
	if math.is_inf(n, -1) {
		return 1
	}
	floor := math.floor(n)
	f := f64_to_bigint(floor)
	if a < f {
		return -1
	}
	if a == f {
		return if n == floor { 0 } else { -1 }
	}
	return 1
}

// f64_to_bigint converts an integral double to a big integer exactly.
fn f64_to_bigint(x f64) big.Integer {
	if x == 0 {
		return big.zero_int
	}
	bits := math.f64_bits(math.abs(x))
	exponent := int((bits >> 52) & 0x7ff) - 1075
	mantissa := (bits & ((u64(1) << 52) - 1)) | (u64(1) << 52)
	mut result := big.integer_from_u64(mantissa)
	if exponent > 0 {
		result = result.left_shift(u32(exponent))
	} else if exponent < 0 {
		result = result.right_shift(u32(-exponent))
	}
	return if x < 0 { result.neg() } else { result }
}

// js_bigint parses the decimal digits tsgo gives for a BigInt literal type.
fn js_bigint(text string) ?big.Integer {
	return big.integer_from_string(text) or { return none }
}

// js_string_to_bigint ports StringToBigInt; none is `undefined`.
fn js_string_to_bigint(s string) ?big.Integer {
	text := js_trim(s)
	if text == '' {
		return big.zero_int
	}
	if text.len > 2 && text[0] == `0` && text[1] in [`x`, `X`, `o`, `O`, `b`, `B`] {
		radix := match text[1] {
			`x`, `X` { 16 }
			`o`, `O` { 8 }
			else { 2 }
		}
		return big.integer_from_radix(text[2..], u32(radix)) or { return none }
	}
	mut digits := text
	if digits.starts_with('+') || digits.starts_with('-') {
		digits = digits[1..]
	}
	if digits == '' || !digits.bytes().all(it.is_digit()) {
		return none
	}
	return big.integer_from_string(text) or { return none }
}

// js_string_to_number ports StringToNumber.
fn js_string_to_number(s string) f64 {
	text := js_trim(s)
	if text == '' {
		return 0
	}
	if text.len > 2 && text[0] == `0` && text[1] in [`x`, `X`, `o`, `O`, `b`, `B`] {
		radix := match text[1] {
			`x`, `X` { 16 }
			`o`, `O` { 8 }
			else { 2 }
		}
		n := big.integer_from_radix(text[2..], u32(radix)) or { return math.nan() }
		return integer_to_f64(n)
	}
	mut body := text
	mut negative := false
	if body.starts_with('+') || body.starts_with('-') {
		negative = body[0] == `-`
		body = body[1..]
	}
	if body == 'Infinity' {
		return if negative { math.inf(-1) } else { math.inf(1) }
	}
	// StrUnsignedDecimalLiteral: digits, an optional fraction and an optional exponent.
	mut i := 0
	mut digits := 0
	for i < body.len && body[i].is_digit() {
		i++
		digits++
	}
	if i < body.len && body[i] == `.` {
		i++
		for i < body.len && body[i].is_digit() {
			i++
			digits++
		}
	}
	if digits == 0 {
		return math.nan()
	}
	if i < body.len && body[i] in [`e`, `E`] {
		i++
		if i < body.len && body[i] in [`+`, `-`] {
			i++
		}
		start := i
		for i < body.len && body[i].is_digit() {
			i++
		}
		if i == start {
			return math.nan()
		}
	}
	if i != body.len {
		return math.nan()
	}
	value := js_atof64(body) or { return math.nan() }
	return if negative { -value } else { value }
}

// js_trim removes JavaScript's white space and line terminators from both ends.
fn js_trim(s string) string {
	runes := s.runes()
	mut start := 0
	mut end := runes.len
	for start < end && is_js_space(runes[start]) {
		start++
	}
	for end > start && is_js_space(runes[end - 1]) {
		end--
	}
	return runes[start..end].string()
}

fn is_js_space(r rune) bool {
	return r in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, ` `, ` `, ` `, ` `, ` `, ` `, `　`,
		`﻿`] || (r >= ` ` && r <= ` `)
}

// utf16_less compares two strings by their UTF-16 code units, like JavaScript.
fn utf16_less(a string, b string) bool {
	x := utf16_units(a)
	y := utf16_units(b)
	for i in 0 .. math.min(x.len, y.len) {
		if x[i] != y[i] {
			return x[i] < y[i]
		}
	}
	return x.len < y.len
}

fn utf16_units(s string) []u16 {
	mut out := []u16{cap: s.len}
	for r in s.runes() {
		if r > 0xffff {
			v := u32(r) - 0x10000
			out << u16(0xd800 + (v >> 10))
			out << u16(0xdc00 + (v & 0x3ff))
		} else {
			out << u16(r)
		}
	}
	return out
}
