module rules

import jsregexp

// Names made from file names, as eslint-plugin-unicorn 79.0.0 makes them: camelCase of
// change-case 5.4.4 and isIdentifierName (identifier-regex 1.1.0 without reserved words). They run
// the same regular expressions, in the `u` mode, with veslint's port of V8's.

// ucc_regexes are the regular expressions of change-case's `split`, compiled once.
struct UccRegexes {
	lower_upper jsregexp.JsRegex
	upper_upper jsregexp.JsRegex
	strip       jsregexp.JsRegex
	identifier  jsregexp.JsRegex
}

fn ucc_regexes() !UccRegexes {
	return UccRegexes{
		lower_upper: jsregexp.js_regex_new(r'([\p{Ll}\d])(\p{Lu})', 'u')!
		upper_upper: jsregexp.js_regex_new(r'(\p{Lu})([\p{Lu}][\p{Ll}])', 'u')!
		strip:       jsregexp.js_regex_new(r'[^\p{L}\d]+', 'iu')!
		identifier:  jsregexp.js_regex_new(r'^[$_\p{ID_Start}][$_‌‍\p{ID_Continue}]*$', 'u')!
	}
}

// ucc_units are the UTF-16 units of code points.
fn ucc_units(points []rune) []u16 {
	mut out := []u16{cap: points.len}
	for p in points {
		jsregexp.append_utf16(mut out, u32(p))
	}
	return out
}

// ucc_replace_all is `input.replace(re /g, replacement)` where the replacement is `$1\0$2` (with
// `groups`) or `\0`, over code points.
fn ucc_replace_all(re &jsregexp.JsRegex, input []rune, groups bool) []rune {
	units := ucc_units(input)
	mut out := []rune{cap: input.len}
	mut last := 0
	mut from := 0
	for from <= input.len {
		found, start, end, slots := re.exec(units, from) or { break }
		if !found {
			break
		}
		out << input[last..start]
		if groups {
			if slots[2] >= 0 {
				out << input[slots[2]..slots[3]]
			}
			out << rune(0)
			if slots[4] >= 0 {
				out << input[slots[4]..slots[5]]
			}
		} else {
			out << rune(0)
		}
		last = end
		from = if end == start { end + 1 } else { end }
	}
	if last < input.len {
		out << input[last..]
	}
	return out
}

// ucc_split ports `split` of change-case: the words of a string.
fn ucc_split(re &UccRegexes, value string) [][]rune {
	mut result := js_trim(value).runes()
	result = ucc_replace_all(&re.lower_upper, result, true)
	result = ucc_replace_all(&re.upper_upper, result, true)
	result = ucc_replace_all(&re.strip, result, false)
	mut start := 0
	mut end := result.len
	for start < end && result[start] == rune(0) {
		start++
	}
	if start == end {
		return [][]rune{}
	}
	for end > start && result[end - 1] == rune(0) {
		end--
	}
	mut words := [][]rune{}
	mut word := []rune{}
	for r in result[start..end] {
		if r == rune(0) {
			words << word
			word = []rune{}
		} else {
			word << r
		}
	}
	words << word
	return words
}

fn ucc_string(units []u16) string {
	return stv_units_string(units)
}

// ucc_camel_case ports camelCase of change-case (no prefix or suffix characters, the default
// locale): the first word in lower case, the others with their first character in upper case (a
// digit after `_`) and the rest in lower case.
fn ucc_camel_case(value string) string {
	re := ucc_regexes() or { return '' }
	mut out := ''
	for index, word in ucc_split(&re, value) {
		units := ucc_units(word)
		if index == 0 {
			out += ucc_string(jsregexp.js_to_lower(units))
			continue
		}
		first := units[0]
		initial := if first >= `0` && first <= `9` {
			'_' + ucc_string([first])
		} else {
			ucc_string(jsregexp.js_to_upper([first]))
		}
		out += initial + ucc_string(jsregexp.js_to_lower(units[1..]))
	}
	return out
}

// un_is_identifier_name ports isIdentifierName (utils/is-identifier-name.js): an identifier name,
// reserved words included.
fn un_is_identifier_name(name string) bool {
	re := ucc_regexes() or { return false }
	return re.identifier.test(utf16_units(name)) or { false }
}

// un_upper_first ports upperFirst: the first UTF-16 unit in upper case.
fn un_upper_first(name string) string {
	units := utf16_units(name)
	if units.len == 0 {
		return name
	}
	mut out := jsregexp.js_to_upper([units[0]])
	out << units[1..]
	return ucc_string(out)
}
