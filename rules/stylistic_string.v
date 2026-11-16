module rules

import jsregexp

// sty_string_length ports getStringLength of @stylistic/eslint-plugin 6.0.1
// (shared/utils/string.ts): the length of a string of printable ASCII characters, else its number
// of graphemes as Intl.Segmenter counts them (the extended grapheme clusters of UAX #29, without
// the Indic conjunct rule GB9c).
fn sty_string_length(value string) int {
	if value.bytes().all(it >= 0x20 && it <= 0x7f) {
		return value.len
	}
	classes := StyGraphemeClasses{
		extend:  jsregexp.regexp_compile('^[\\p{Grapheme_Extend}\\p{Emoji_Modifier}]$') or {
			return value.runes().len
		}
		spacing: jsregexp.regexp_compile('^\\p{Mc}$') or { return value.runes().len }
		control: jsregexp.regexp_compile('^[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]$') or {
			return value.runes().len
		}
		pict:    jsregexp.regexp_compile('^\\p{Extended_Pictographic}$') or {
			return value.runes().len
		}
	}
	points := value.runes()
	kinds := points.map(classes.kind(it))
	mut count := 0
	// The regional indicators right before the current point, and whether the current point ends
	// an Extended_Pictographic Extend* ZWJ sequence.
	mut regional := 0
	mut pict_sequence := false
	mut pict_before := false
	for i, kind in kinds {
		if i == 0 || sty_grapheme_break(kinds[i - 1], kind, regional, pict_before) {
			count++
		}
		regional = if kind == .regional { regional + 1 } else { 0 }
		// GB11: an Extended_Pictographic, then Extend*, then a ZWJ.
		pict_before = pict_sequence && kind == .zwj
		pict_sequence = kind == .pict || (pict_sequence && kind == .extend)
	}
	return count
}

enum StyGrapheme {
	other
	cr
	lf
	control
	extend
	zwj
	regional
	prepend
	spacing
	l
	v
	t
	lv
	lvt
	pict
}

struct StyGraphemeClasses {
	extend  jsregexp.RegexpProgram
	spacing jsregexp.RegexpProgram
	control jsregexp.RegexpProgram
	pict    jsregexp.RegexpProgram
}

// kind is the Grapheme_Cluster_Break of a code point (with Extended_Pictographic).
fn (classes &StyGraphemeClasses) kind(r rune) StyGrapheme {
	code := u32(r)
	text := r.str()
	match true {
		code == 0x0d { return .cr }
		code == 0x0a { return .lf }
		code == 0x200d { return .zwj }
		code >= 0x1f1e6 && code <= 0x1f1ff { return .regional }
		code >= 0x1100 && code <= 0x115f, code >= 0xa960 && code <= 0xa97c { return .l }
		code >= 0x1160 && code <= 0x11a7, code >= 0xd7b0 && code <= 0xd7c6 { return .v }
		code >= 0x11a8 && code <= 0x11ff, code >= 0xd7cb && code <= 0xd7fb { return .t }
		code >= 0xac00 && code <= 0xd7a3 { return if (code - 0xac00) % 28 == 0 { .lv } else { .lvt } }
		else {}
	}
	if code in sty_grapheme_prepend || (code >= 0x0600 && code <= 0x0605)
		|| (code >= 0x0890 && code <= 0x0891) || (code >= 0x111c2 && code <= 0x111c3)
		|| (code >= 0x11a84 && code <= 0x11a89) {
		return .prepend
	}
	if jsregexp.regexp_test(classes.extend, text) or { false } {
		return .extend
	}
	if jsregexp.regexp_test(classes.control, text) or { false } {
		return .control
	}
	if code in [u32(0x0e33), 0x0eb3] {
		return .spacing
	}
	if code !in sty_grapheme_not_spacing && (jsregexp.regexp_test(classes.spacing, text) or { false }) {
		return .spacing
	}
	if jsregexp.regexp_test(classes.pict, text) or { false } {
		return .pict
	}
	return .other
}

// The Prepend code points that are not in the ranges of StyGraphemeClasses.kind.
const sty_grapheme_prepend = [u32(0x06dd), 0x070f, 0x08e2, 0x0d4e, 0x110bd, 0x110cd, 0x1193f, 0x11941,
	0x11a3a, 0x11d46, 0x11f02]

// The spacing marks (Mc) that are not SpacingMark.
const sty_grapheme_not_spacing = [u32(0x102b), 0x102c, 0x1038, 0x1062, 0x1063, 0x1064, 0x1067, 0x1068,
	0x1069, 0x106a, 0x106b, 0x106c, 0x106d, 0x1083, 0x1087, 0x1088, 0x1089, 0x108a, 0x108b, 0x108c,
	0x108f, 0x109a, 0x109b, 0x109c, 0x1a61, 0x1a63, 0x1a64, 0xaa7b, 0xaa7d, 0x11720, 0x11721]

// sty_grapheme_break tells whether UAX #29 breaks between two code points of these kinds.
fn sty_grapheme_break(before StyGrapheme, after StyGrapheme, regional int, pict_before bool) bool {
	if before == .cr && after == .lf {
		return false
	}
	if before in [.cr, .lf, .control] || after in [.cr, .lf, .control] {
		return true
	}
	if before == .l && after in [.l, .v, .lv, .lvt] {
		return false
	}
	if before in [.lv, .v] && after in [.v, .t] {
		return false
	}
	if before in [.lvt, .t] && after == .t {
		return false
	}
	if after in [.extend, .zwj, .spacing] || before == .prepend {
		return false
	}
	if pict_before && after == .pict {
		return false
	}
	if before == .regional && after == .regional && regional % 2 == 1 {
		return false
	}
	return true
}
