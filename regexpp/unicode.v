module regexpp

// Character predicates and Unicode property name tables, ported from regexpp 4.12.2.

pub const latest_ecma_version = 2025

fn is_id_start(cp int) bool {
	if cp < 0x41 {
		return false
	}
	if cp < 0x5b {
		return true
	}
	if cp < 0x61 {
		return false
	}
	if cp < 0x7b {
		return true
	}
	return is_large_id_start(cp)
}

fn is_id_continue(cp int) bool {
	if cp < 0x30 {
		return false
	}
	if cp < 0x3a {
		return true
	}
	if cp < 0x41 {
		return false
	}
	if cp < 0x5b {
		return true
	}
	if cp == 0x5f {
		return true
	}
	if cp < 0x61 {
		return false
	}
	if cp < 0x7b {
		return true
	}
	return is_large_id_start(cp) || is_large_id_continue(cp)
}

fn is_large_id_start(cp int) bool {
	return is_in_range(cp, large_id_start_ranges[..])
}

fn is_large_id_continue(cp int) bool {
	return is_in_range(cp, large_id_continue_ranges[..])
}

fn is_in_range(cp int, ranges []int) bool {
	mut l := 0
	mut r := ranges.len / 2
	for l < r {
		i := (l + r) / 2
		min := ranges[2 * i]
		max := ranges[2 * i + 1]
		if cp < min {
			r = i
		} else if cp > max {
			l = i + 1
		} else {
			return true
		}
	}
	return false
}

// is_valid_unicode_property mirrors isValidUnicodeProperty: General_Category values come from the es2018 set only,
// Script values from the es2018..es2023 sets.
fn is_valid_unicode_property(version int, name string, value string) bool {
	if name == 'General_Category' || name == 'gc' {
		year := gc_value_years[value] or { return false }
		return year == 2018 && version >= 2018
	}
	if name == 'Script' || name == 'Script_Extensions' || name == 'sc' || name == 'scx' {
		year := sc_value_years[value] or { return false }
		return year <= 2023 && version >= year
	}
	return false
}

// is_valid_lone_unicode_property mirrors isValidLoneUnicodeProperty (es2018, es2019 and es2021 sets).
fn is_valid_lone_unicode_property(version int, value string) bool {
	year := bin_property_years[value] or { return false }
	return (year == 2018 || year == 2019 || year == 2021) && version >= year
}

// is_valid_lone_unicode_property_of_string mirrors isValidLoneUnicodePropertyOfString (es2024 set).
fn is_valid_lone_unicode_property_of_string(version int, value string) bool {
	year := bin_property_of_strings_years[value] or { return false }
	return year == 2024 && version >= 2024
}

const backspace = 0x08
const character_tabulation = 0x09
const line_feed = 0x0a
const line_tabulation = 0x0b
const form_feed = 0x0c
const carriage_return = 0x0d
const exclamation_mark = 0x21
const number_sign = 0x23
const dollar_sign = 0x24
const percent_sign = 0x25
const ampersand = 0x26
const left_parenthesis = 0x28
const right_parenthesis = 0x29
const asterisk = 0x2a
const plus_sign = 0x2b
const comma = 0x2c
const hyphen_minus = 0x2d
const full_stop = 0x2e
const solidus = 0x2f
const digit_zero = 0x30
const digit_one = 0x31
const digit_seven = 0x37
const digit_nine = 0x39
const colon = 0x3a
const semicolon = 0x3b
const less_than_sign = 0x3c
const equals_sign = 0x3d
const greater_than_sign = 0x3e
const question_mark = 0x3f
const commercial_at = 0x40
const latin_capital_letter_a = 0x41
const latin_capital_letter_b = 0x42
const latin_capital_letter_d = 0x44
const latin_capital_letter_f = 0x46
const latin_capital_letter_p = 0x50
const latin_capital_letter_s = 0x53
const latin_capital_letter_w = 0x57
const latin_capital_letter_z = 0x5a
const low_line = 0x5f
const latin_small_letter_a = 0x61
const latin_small_letter_b = 0x62
const latin_small_letter_c = 0x63
const latin_small_letter_d = 0x64
const latin_small_letter_f = 0x66
const latin_small_letter_g = 0x67
const latin_small_letter_i = 0x69
const latin_small_letter_k = 0x6b
const latin_small_letter_m = 0x6d
const latin_small_letter_n = 0x6e
const latin_small_letter_p = 0x70
const latin_small_letter_q = 0x71
const latin_small_letter_r = 0x72
const latin_small_letter_s = 0x73
const latin_small_letter_t = 0x74
const latin_small_letter_u = 0x75
const latin_small_letter_v = 0x76
const latin_small_letter_w = 0x77
const latin_small_letter_x = 0x78
const latin_small_letter_y = 0x79
const latin_small_letter_z = 0x7a
const left_square_bracket = 0x5b
const reverse_solidus = 0x5c
const right_square_bracket = 0x5d
const circumflex_accent = 0x5e
const grave_accent = 0x60
const left_curly_bracket = 0x7b
const vertical_line = 0x7c
const right_curly_bracket = 0x7d
const tilde = 0x7e
const zero_width_non_joiner = 0x200c
const zero_width_joiner = 0x200d
const line_separator = 0x2028
const paragraph_separator = 0x2029
const min_code_point = 0x00
const max_code_point = 0x10ffff

fn is_latin_letter(code int) bool {
	return (code >= latin_capital_letter_a && code <= latin_capital_letter_z)
		|| (code >= latin_small_letter_a && code <= latin_small_letter_z)
}

fn is_decimal_digit(code int) bool {
	return code >= digit_zero && code <= digit_nine
}

fn is_octal_digit(code int) bool {
	return code >= digit_zero && code <= digit_seven
}

fn is_hex_digit(code int) bool {
	return (code >= digit_zero && code <= digit_nine)
		|| (code >= latin_capital_letter_a && code <= latin_capital_letter_f)
		|| (code >= latin_small_letter_a && code <= latin_small_letter_f)
}

fn is_line_terminator(code int) bool {
	return code == line_feed || code == carriage_return || code == line_separator
		|| code == paragraph_separator
}

fn is_valid_unicode(code f64) bool {
	return code >= min_code_point && code <= max_code_point
}

fn digit_to_int(code int) int {
	if code >= latin_small_letter_a && code <= latin_small_letter_f {
		return code - latin_small_letter_a + 10
	}
	if code >= latin_capital_letter_a && code <= latin_capital_letter_f {
		return code - latin_capital_letter_a + 10
	}
	return code - digit_zero
}

fn is_lead_surrogate(code int) bool {
	return code >= 0xd800 && code <= 0xdbff
}

fn is_trail_surrogate(code int) bool {
	return code >= 0xdc00 && code <= 0xdfff
}

fn is_lead_surrogate_f(code f64) bool {
	return code >= 0xd800 && code <= 0xdbff
}

fn is_trail_surrogate_f(code f64) bool {
	return code >= 0xdc00 && code <= 0xdfff
}

fn combine_surrogate_pair(lead int, trail int) int {
	return (lead - 0xd800) * 0x400 + (trail - 0xdc00) + 0x10000
}

fn is_syntax_character(cp int) bool {
	return match cp {
		circumflex_accent, dollar_sign, reverse_solidus, full_stop, asterisk, plus_sign,
		question_mark, left_parenthesis, right_parenthesis, left_square_bracket,
		right_square_bracket, left_curly_bracket, right_curly_bracket, vertical_line {
			true
		}
		else {
			false
		}
	}
}

fn is_class_set_reserved_double_punctuator_character(cp int) bool {
	return match cp {
		ampersand, exclamation_mark, number_sign, dollar_sign, percent_sign, asterisk, plus_sign,
		comma, full_stop, colon, semicolon, less_than_sign, equals_sign, greater_than_sign,
		question_mark, commercial_at, circumflex_accent, grave_accent, tilde {
			true
		}
		else {
			false
		}
	}
}

fn is_class_set_syntax_character(cp int) bool {
	return match cp {
		left_parenthesis, right_parenthesis, left_square_bracket, right_square_bracket,
		left_curly_bracket, right_curly_bracket, solidus, hyphen_minus, reverse_solidus,
		vertical_line {
			true
		}
		else {
			false
		}
	}
}

fn is_class_set_reserved_punctuator(cp int) bool {
	return match cp {
		ampersand, hyphen_minus, exclamation_mark, number_sign, percent_sign, comma, colon,
		semicolon, less_than_sign, equals_sign, greater_than_sign, commercial_at, grave_accent,
		tilde {
			true
		}
		else {
			false
		}
	}
}

fn is_identifier_start_char(cp int) bool {
	return is_id_start(cp) || cp == dollar_sign || cp == low_line
}

fn is_identifier_part_char(cp int) bool {
	return is_id_continue(cp) || cp == dollar_sign || cp == zero_width_non_joiner
		|| cp == zero_width_joiner
}

fn is_unicode_property_name_character(cp int) bool {
	return is_latin_letter(cp) || cp == low_line
}

fn is_unicode_property_value_character(cp int) bool {
	return is_unicode_property_name_character(cp) || is_decimal_digit(cp)
}

fn is_regular_expression_modifier(ch int) bool {
	return ch == latin_small_letter_i || ch == latin_small_letter_m || ch == latin_small_letter_s
}

// cp_to_wtf8 encodes a code point like String.fromCodePoint, as UTF-8; a lone surrogate gets its generalized
// (WTF-8) three-byte form so that it survives in a V string.
pub fn cp_to_wtf8(cp int) string {
	mut b := []u8{cap: 4}
	append_wtf8(mut b, cp)
	return b.bytestr()
}

fn append_wtf8(mut b []u8, cp int) {
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

// utf16_to_wtf8 converts UTF-16 units to a V string, joining surrogate pairs and keeping lone surrogates (WTF-8).
pub fn utf16_to_wtf8(s []u16) string {
	mut b := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		c := int(s[i])
		if is_lead_surrogate(c) && i + 1 < s.len && is_trail_surrogate(int(s[i + 1])) {
			append_wtf8(mut b, combine_surrogate_pair(c, int(s[i + 1])))
			i += 2
			continue
		}
		append_wtf8(mut b, c)
		i++
	}
	return b.bytestr()
}

// wtf8_to_utf16 is the inverse of utf16_to_wtf8 (it also accepts plain UTF-8).
pub fn wtf8_to_utf16(s string) []u16 {
	mut out := []u16{cap: s.len}
	mut i := 0
	for i < s.len {
		b0 := int(s[i])
		mut cp := 0
		if b0 < 0x80 {
			cp = b0
			i++
		} else if b0 < 0xe0 && i + 1 < s.len {
			cp = ((b0 & 0x1f) << 6) | (int(s[i + 1]) & 0x3f)
			i += 2
		} else if b0 < 0xf0 && i + 2 < s.len {
			cp = ((b0 & 0x0f) << 12) | ((int(s[i + 1]) & 0x3f) << 6) | (int(s[i + 2]) & 0x3f)
			i += 3
		} else if i + 3 < s.len {
			cp = ((b0 & 0x07) << 18) | ((int(s[i + 1]) & 0x3f) << 12) | ((int(s[i + 2]) & 0x3f) << 6) | (int(s[i +
				3]) & 0x3f)
			i += 4
		} else {
			cp = 0xfffd
			i = s.len
		}
		if cp > 0xffff {
			c := cp - 0x10000
			out << u16(0xd800 + (c >> 10))
			out << u16(0xdc00 + (c & 0x3ff))
		} else {
			out << u16(cp)
		}
	}
	return out
}
