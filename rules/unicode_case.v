module rules

// String.prototype.toUpperCase and toLowerCase as V8 does them: the case mappings of Unicode that
// do not depend on a language (the tables of unicode_case_data.v, which come from V8 itself),
// over the code points of a string in UTF-16. typescript-eslint and ESLint ask them of one UTF-16
// unit of a name (`name[0] === name[0].toUpperCase()`), so they take and give units: half of a
// surrogate pair is a code point by itself, which no conversion changes.

const greek_capital_sigma = u32(0x3a3)
const greek_small_final_sigma = u16(0x3c2)

// js_to_upper ports String.prototype.toUpperCase.
fn js_to_upper(units []u16) []u16 {
	return js_convert_case(units, unicode_upper_simple, unicode_upper_special, false)
}

// js_to_lower ports String.prototype.toLowerCase.
fn js_to_lower(units []u16) []u16 {
	return js_convert_case(units, unicode_lower_simple, unicode_lower_special, true)
}

fn js_convert_case(units []u16, simple []u32, special []u32, lower bool) []u16 {
	points := utf16_code_points(units)
	mut out := []u16{cap: units.len}
	// What the final sigma asks of its neighbours, read only when there is a sigma.
	mut cased := []u32{}
	mut ignorable := []u32{}
	for i, c in points {
		if c < 0x80 {
			// ASCII, the usual case.
			out << if lower && c >= `A` && c <= `Z` {
				u16(c + 32)
			} else if !lower && c >= `a` && c <= `z` {
				u16(c - 32)
			} else {
				u16(c)
			}
			continue
		}
		if lower && c == greek_capital_sigma {
			if cased.len == 0 {
				cased = regexp_property_ranges('Cased') or { []u32{} }
				ignorable = regexp_property_ranges('Case_Ignorable') or { []u32{} }
			}
			if cased_letter_next(points, i, -1, cased, ignorable)
				&& !cased_letter_next(points, i, 1, cased, ignorable) {
				out << greek_small_final_sigma
				continue
			}
		}
		group := unicode_case_entry(special, 4, c)
		if group >= 0 {
			for mapped in special[group + 1..group + 4] {
				if mapped != 0 {
					append_utf16(mut out, mapped)
				}
			}
			continue
		}
		pair := unicode_case_entry(simple, 2, c)
		append_utf16(mut out, if pair >= 0 { simple[pair + 1] } else { c })
	}
	return out
}

// cased_letter_next ports the two halves of Unicode's Final_Sigma condition as ICU applies them:
// whether the first character before (step -1) or after (step 1) the one at `at` that case does
// not ignore is a cased letter. A character that is both cased and ignored is skipped.
fn cased_letter_next(points []u32, at int, step int, cased []u32, ignorable []u32) bool {
	mut i := at + step
	for i >= 0 && i < points.len {
		if !rx_in_ranges(ignorable, points[i]) {
			return rx_in_ranges(cased, points[i])
		}
		i += step
	}
	return false
}

// unicode_case_entry finds the entry of a code point in a table of entries of `size` numbers
// sorted by their first one: its index, or -1.
fn unicode_case_entry(table []u32, size int, c u32) int {
	mut low := 0
	mut high := table.len / size - 1
	for low <= high {
		mid := (low + high) / 2
		key := table[size * mid]
		if key == c {
			return size * mid
		}
		if key < c {
			low = mid + 1
		} else {
			high = mid - 1
		}
	}
	return -1
}

// utf16_code_points reads the code points of a string in UTF-16: a surrogate without its pair is
// a code point by itself.
fn utf16_code_points(units []u16) []u32 {
	mut out := []u32{cap: units.len}
	mut i := 0
	for i < units.len {
		unit := u32(units[i])
		if unit >= 0xd800 && unit <= 0xdbff && i + 1 < units.len && units[i + 1] >= 0xdc00
			&& units[i + 1] <= 0xdfff {
			out << 0x10000 + ((unit - 0xd800) << 10) + (u32(units[i + 1]) - 0xdc00)
			i += 2
			continue
		}
		out << unit
		i++
	}
	return out
}

fn append_utf16(mut out []u16, c u32) {
	if c > 0xffff {
		out << u16(0xd800 + ((c - 0x10000) >> 10))
		out << u16(0xdc00 + ((c - 0x10000) & 0x3ff))
	} else {
		out << u16(c)
	}
}
