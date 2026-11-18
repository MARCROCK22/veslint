module rules

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
