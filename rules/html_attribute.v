module rules

import strings

// Port of decodeHTMLAttribute of the `entities` package 8.1.0 (decodeWithTrie of src/decode.ts,
// not strict, in an attribute), which eslint-plugin-unicorn imports: the character references
// of an HTML attribute value decoded. A named reference is the longest name of html_entities
// followed by `;`, or of html_legacy_entities without it; one without `;` followed by `=` or an
// ASCII letter or digit stays as it is. A numeric reference (`&#65`, `&#x41;`) is always decoded.
// tools/gen_html_entities.mjs checks it (tests/html_attribute_cases.json).

// html_c1 are the characters of the numeric references 0x80 to 0x9F (0: the code point itself).
const html_c1 = [8364, 0, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 0, 381,
	0, 0, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 0, 382, 376]

fn html_is_alpha(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

fn html_is_digit(c u8) bool {
	return c >= `0` && c <= `9`
}

fn html_is_alphanumeric(c u8) bool {
	return html_is_alpha(c) || html_is_digit(c)
}

// html_code_point_string ports codePointToString: a code point that HTML replaces (0, a
// surrogate, one past U+10FFFF or a C1 control) becomes its replacement.
fn html_code_point_string(cp u32) string {
	mut c := cp
	if c == 0 || (c >= 0xd800 && c <= 0xdfff) || c > 0x10ffff {
		c = 0xfffd
	} else if c >= 0x80 && c <= 0x9f && html_c1[c - 0x80] != 0 {
		c = u32(html_c1[c - 0x80])
	}
	return rune(c).str()
}

// html_numeric_reference ports parseNumericEntity: the length after the `&` of the numeric
// reference at `start` (its `#`), 0 when there is none, and its characters.
fn html_numeric_reference(input string, start int) (int, string) {
	mut offset := start + 1
	mut cp := u64(0)
	mut digit_start := offset
	if offset < input.len && (input[offset] | 0x20) == `x` {
		offset++
		digit_start = offset
		for offset < input.len {
			c := input[offset]
			digit := if html_is_digit(c) {
				u64(c - `0`)
			} else if (c | 0x20) >= `a` && (c | 0x20) <= `f` {
				u64((c | 0x20) - `a` + 10)
			} else {
				break
			}
			cp = if cp > 0x10ffff { cp } else { cp * 16 + digit }
			offset++
		}
	} else {
		for offset < input.len && html_is_digit(input[offset]) {
			cp = if cp > 0x10ffff { cp } else { cp * 10 + u64(input[offset] - `0`) }
			offset++
		}
	}
	if offset == digit_start {
		return 0, ''
	}
	if offset < input.len && input[offset] == `;` {
		offset++
	}
	if cp > 0x10ffff {
		cp = 0x110000
	}
	return offset - start, html_code_point_string(u32(cp))
}

// html_named_reference finds the named reference at `start` (after the `&`): the length it takes
// (with its `;`, 0 when there is none) and its characters.
fn html_named_reference(input string, start int) (int, string) {
	mut consumed := 0
	mut value := ''
	mut end := start
	for end < input.len && html_is_alphanumeric(input[end]) {
		end++
		name := input[start..end]
		if entity := html_entities[name] {
			if end < input.len && input[end] == `;` {
				return end - start + 1, entity
			}
			if name in html_legacy_entities {
				consumed = end - start
				value = entity
			}
		}
	}
	return consumed, value
}

// html_decode_attribute ports decodeHTMLAttribute.
fn html_decode_attribute(input string) string {
	mut offset := input.index_u8(`&`)
	if offset < 0 {
		return input
	}
	mut out := strings.new_builder(input.len)
	mut chunk_start := 0
	for offset >= 0 {
		entity_start := offset + 1
		first := if entity_start < input.len { input[entity_start] } else { u8(0) }
		mut consumed := 0
		mut value := ''
		if first == `#` {
			consumed, value = html_numeric_reference(input, entity_start)
		} else if html_is_alpha(first) {
			consumed, value = html_named_reference(input, entity_start)
		}
		if consumed == 0 || (first != `#` && input[entity_start + consumed - 1] != `;`
			&& entity_start + consumed < input.len
			&& (input[entity_start + consumed] == `=`
				|| html_is_alphanumeric(input[entity_start + consumed]))) {
			// Not a reference: the `&` stays, and the search goes on after it.
			offset = entity_start
		} else {
			out.write_string(input[chunk_start..offset])
			out.write_string(value)
			offset = entity_start + consumed
			chunk_start = offset
		}
		next := input[offset..].index_u8(`&`)
		offset = if next < 0 { -1 } else { offset + next }
	}
	out.write_string(input[chunk_start..])
	return out.str()
}
