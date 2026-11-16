module rules

import estree
import time

// Port of the `@stylistic/type-named-tuple-spacing` rule of @stylistic/eslint-plugin 6.0.1 (no
// options), with its fixes.

const stnts_messages = {
	'expectedSpaceAfter':     "Expected a space after the ':'."
	'unexpectedSpaceBetween': "Unexpected space between '?' and the ':'."
	'unexpectedSpaceBefore':  "Unexpected space before the ':'."
}

// StntsMatch is a match of tupleRe, /^([\w$]+)(\s*)(\?\s*)?:(\s*)(.*)$/, on the text of a member:
// its groups (`optional_mark` is none when the group did not match).
struct StntsMatch {
	label              string
	space_before_colon string
	optional_mark      ?string
	spaces_after_colon string
	element_type       string
}

fn (mut c Checker) lint_stylistic_type_named_tuple_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .ts_named_tuple_member {
			continue
		}
		stats.checked++
		c.stnts_check(t, step.node, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) stnts_check(t &estree.EsTree, node int, mut findings []Finding) {
	start := t.nodes[node].start
	end := t.nodes[node].end
	code := c.src[start..end]
	m := stnts_match(code) or { return }
	label := t.node(node, .label) or { return }
	label_name := t.string_of(label, .name) or { return }
	// getReplaceValue
	mut replace_value := label_name
	if t.flag(node, .optional) or { false } {
		replace_value += '?'
	}
	replace_value += ': '
	replace_value += m.element_type
	fixed := stnts_substitute(replace_value, code, m)
	optional_mark := m.optional_mark or { '' }
	// The lengths are in UTF-16 code units: every `\s` is one.
	if optional_mark.runes().len > 1 {
		findings << c.stnts_report(start, end, 'unexpectedSpaceBetween', fixed)
	}
	if m.space_before_colon.len > 0 {
		findings << c.stnts_report(start, end, 'unexpectedSpaceBefore', fixed)
	}
	if m.spaces_after_colon.runes().len != 1 {
		findings << c.stnts_report(start, end, 'expectedSpaceAfter', fixed)
	}
}

fn (c &Checker) stnts_report(start int, end int, message_id string, text string) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		has_fix:    true
		fix:        fix_replace_range(start, end, text)
	}
}

// stnts_space_end is the end of the JavaScript whitespace (`\s*`) that starts at `from`.
fn stnts_space_end(s string, from int) int {
	mut end := from
	for end < s.len {
		length := utf8_char_len(s[end])
		if end + length > s.len {
			break
		}
		runes := s[end..end + length].runes()
		if runes.len != 1 || !is_js_space(runes[0]) {
			break
		}
		end += length
	}
	return end
}

// stnts_match matches tupleRe on `code`; there is no backtracking to do: each group ends where
// the next one cannot start.
fn stnts_match(code string) ?StntsMatch {
	mut i := 0
	for i < code.len && (code[i].is_letter() || code[i].is_digit() || code[i] in [`_`, `$`]) {
		i++
	}
	if i == 0 {
		return none
	}
	label := code[..i]
	space_end := stnts_space_end(code, i)
	space_before_colon := code[i..space_end]
	i = space_end
	mut optional_mark := ?string(none)
	if i < code.len && code[i] == `?` {
		mark_end := stnts_space_end(code, i + 1)
		optional_mark = code[i..mark_end]
		i = mark_end
	}
	if i >= code.len || code[i] != `:` {
		return none
	}
	i++
	after_end := stnts_space_end(code, i)
	spaces_after_colon := code[i..after_end]
	element_type := code[after_end..]
	// `.` matches no line terminator, and `$` is the end of the text.
	if element_type.contains('\n') || element_type.contains('\r')
		|| element_type.contains(' ') || element_type.contains(' ') {
		return none
	}
	return StntsMatch{
		label:              label
		space_before_colon: space_before_colon
		optional_mark:      optional_mark
		spaces_after_colon: spaces_after_colon
		element_type:       element_type
	}
}

// stnts_substitute ports GetSubstitution of `code.replace(tupleRe, replacement)`: the match is the
// whole of `code`, its groups are those of `m`.
fn stnts_substitute(replacement string, code string, m StntsMatch) string {
	// A group that did not match is the empty string.
	groups := [m.label, m.space_before_colon, m.optional_mark or { '' }, m.spaces_after_colon,
		m.element_type]
	mut out := []u8{cap: replacement.len}
	mut i := 0
	for i < replacement.len {
		ch := replacement[i]
		if ch != `$` || i + 1 >= replacement.len {
			out << ch
			i++
			continue
		}
		next := replacement[i + 1]
		if next == `$` {
			out << `$`
			i += 2
		} else if next == `&` {
			out << code.bytes()
			i += 2
		} else if next in [`\``, `'`] {
			// The text before and after the match: none.
			i += 2
		} else if next.is_digit() {
			mut index := int(next - `0`)
			mut length := 2
			if i + 2 < replacement.len && replacement[i + 2].is_digit() {
				two := index * 10 + int(replacement[i + 2] - `0`)
				if two >= 1 && two <= groups.len {
					index = two
					length = 3
				}
			}
			if index >= 1 && index <= groups.len {
				out << groups[index - 1].bytes()
				i += length
			} else {
				out << ch
				i++
			}
		} else {
			out << ch
			i++
		}
	}
	return out.bytestr()
}
