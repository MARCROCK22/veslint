module rules

import vue

// Small helpers shared by the vue/* rules of batch VR4 (prefix vu4_).

// vu4_slice_units is `text.slice(start, end)` on UTF-16 units (a negative end counts from the end).
fn vu4_slice_units(text string, start int, end int) string {
	units := utf16_units(text)
	mut e := if end < 0 { units.len + end } else { end }
	if e > units.len {
		e = units.len
	}
	if start >= e {
		return ''
	}
	return utf16_to_string(units[start..e])
}

// vu4_trim_end_offset is where `text.slice(0, offset).trimEnd()` ends: `offset` moved back over
// JavaScript's white space and line terminators.
fn vu4_trim_end_offset(text string, offset int) int {
	mut k := offset
	for k > 0 {
		mut b := k - 1
		for b > 0 && text[b] & 0xc0 == 0x80 {
			b--
		}
		r := text[b..k].runes()
		if r.len != 1 || !is_js_space(r[0]) {
			break
		}
		k = b
	}
	return k
}

// vu4_trim_start_offset is where `text.slice(offset).trimStart()` starts.
fn vu4_trim_start_offset(text string, offset int) int {
	mut k := offset
	for k < text.len {
		len := utf8_char_len(text[k])
		r := text[k..k + len].runes()
		if r.len != 1 || !is_js_space(r[0]) {
			break
		}
		k += len
	}
	return k
}

// vu4_token_after is the template token store's getTokenAfter(offset, {includeComments, filter:
// not HTMLWhitespace}) (with `skip_whitespace`): the first token, or comment, that starts at or
// after `offset`.
fn (c &Checker) vu4_token_after(offset int, include_comments bool, skip_whitespace bool) ?vue.Token {
	mut best := ?vue.Token(none)
	tokens := c.vue.doc.tokens
	for i := vue_lower_bound(tokens, offset); i < tokens.len; i++ {
		if skip_whitespace && tokens[i].typ == 'HTMLWhitespace' {
			continue
		}
		best = tokens[i]
		break
	}
	if include_comments {
		comments := c.vue.doc.comments
		j := vue_lower_bound(comments, offset)
		if j < comments.len {
			if b := best {
				if comments[j].start < b.start {
					best = comments[j]
				}
			} else {
				best = comments[j]
			}
		}
	}
	return best
}

// vu4_token_before is getTokenBefore(offset, {includeComments, filter}): the last token, or
// comment, that ends at or before `offset`.
fn (c &Checker) vu4_token_before(offset int, include_comments bool, skip_whitespace bool) ?vue.Token {
	mut best := ?vue.Token(none)
	tokens := c.vue.doc.tokens
	for i := vue_lower_bound(tokens, offset) - 1; i >= 0; i-- {
		if tokens[i].end > offset || (skip_whitespace && tokens[i].typ == 'HTMLWhitespace') {
			continue
		}
		best = tokens[i]
		break
	}
	if include_comments {
		comments := c.vue.doc.comments
		mut j := vue_lower_bound(comments, offset) - 1
		for j >= 0 && comments[j].end > offset {
			j--
		}
		if j >= 0 {
			if b := best {
				if comments[j].start > b.start {
					best = comments[j]
				}
			} else {
				best = comments[j]
			}
		}
	}
	return best
}

// vu4_line is the line (from 1) of a byte offset of the file, as vue-eslint-parser counts them.
fn (c &Checker) vu4_line(offset int) int {
	return c.vue.doc.loc(offset).line
}

// vu4_rune_before is the character that ends at `offset` (0 at the start of the text).
fn vu4_rune_before(text string, offset int) rune {
	if offset <= 0 {
		return 0
	}
	mut b := offset - 1
	for b > 0 && text[b] & 0xc0 == 0x80 {
		b--
	}
	r := text[b..offset].runes()
	return if r.len > 0 { r[0] } else { 0 }
}
