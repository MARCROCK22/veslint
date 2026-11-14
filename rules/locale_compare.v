module rules

// js_locale_compare ports `a.localeCompare(b)` of Node, whose ICU collation for the en-US locale
// is CLDR's root one, with punctuation that is not ignorable, at three levels:
// - primary: each character by its base letter (the compatibility decomposition, NFKD), without
//   its case or accents: white space, then punctuation and symbols in CLDR's order, then digits,
//   then the letters (Latin first, the other scripts after it by code point);
// - secondary: the accents (combining marks) of each letter;
// - tertiary: the case (a lowercase letter before its uppercase one; a compatibility character
//   after both).
// Format characters (U+200D ZERO WIDTH JOINER…) are ignored at every level. Approximations of the
// port: punctuation and symbols outside ASCII all weigh the same, just before the digits, and the
// order of the scripts is that of their code points; the type names typescript-eslint sorts this
// way (switch-exhaustiveness-check) seldom have them.
fn js_locale_compare(a string, b string) int {
	ea := collation_elements(a)
	eb := collation_elements(b)
	for level in 0 .. 3 {
		wa := ea.filter(it[level] != 0).map(it[level])
		wb := eb.filter(it[level] != 0).map(it[level])
		for i in 0 .. if wa.len < wb.len { wa.len } else { wb.len } {
			if wa[i] != wb[i] {
				return if wa[i] < wb[i] { -1 } else { 1 }
			}
		}
		if wa.len != wb.len {
			return if wa.len < wb.len { -1 } else { 1 }
		}
	}
	return 0
}

// collation_ascii_order is the order of the printable ASCII characters that are not letters
// in ICU's root collation, before the letters (as `localeCompare` sorts them in Node).
const collation_ascii_order = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789"

// collation_elements are the [primary, secondary, tertiary] weights of the characters of a string
// (0 where a character has none at that level).
fn collation_elements(s string) [][]int {
	mut out := [][]int{}
	for r in s.runes() {
		canonical := unicode_decompose([u32(r)], false)
		compatible := unicode_decompose([u32(r)], true)
		is_compat := canonical != compatible
		for cp in compatible {
			if collation_is_ignorable(cp) {
				continue
			}
			if unicode_class_rank(cp) != 0 {
				// A combining mark: an accent of the letter before it.
				out << [0, 2 + int(cp), 0]
				continue
			}
			tertiary := if is_compat {
				3
			} else if cp >= `A` && cp <= `Z` {
				2
			} else {
				1
			}
			out << [collation_primary(cp), 1, tertiary]
		}
	}
	return out
}

// collation_is_ignorable: a control or format character, which DUCET ignores.
fn collation_is_ignorable(cp u32) bool {
	return (cp < 0x20 && cp !in [0x09, 0x0a, 0x0b, 0x0c, 0x0d]) || (cp >= 0x7f && cp < 0xa0)
		|| cp == 0xad || (cp >= 0x200b && cp <= 0x200f) || (cp >= 0x202a && cp <= 0x202e)
		|| (cp >= 0x2060 && cp <= 0x2064) || cp == 0xfeff
}

fn collation_primary(cp u32) int {
	if cp >= `a` && cp <= `z` {
		return 1000 + int(cp - `a`)
	}
	if cp >= `A` && cp <= `Z` {
		return 1000 + int(cp - `A`)
	}
	if cp in [0x09, 0x0a, 0x0b, 0x0c, 0x0d] {
		return 1
	}
	digits := collation_ascii_order.index_u8(`0`)
	if cp < 128 {
		index := collation_ascii_order.index_u8(u8(cp))
		return if index >= 0 { 2 + 2 * index } else { 2 }
	}
	// Punctuation and symbols outside ASCII (Latin-1, General Punctuation, CJK punctuation…).
	if (cp >= 0xa0 && cp <= 0xbf) || cp == 0xd7 || cp == 0xf7 || (cp >= 0x2000 && cp <= 0x2bff)
		|| (cp >= 0x3000 && cp <= 0x303f) {
		return 2 + 2 * digits - 1
	}
	return 2000 + int(cp)
}
