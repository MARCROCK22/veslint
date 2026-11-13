module jsregexp

// utf16_units are the UTF-16 code units of a (WTF-8) string.
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

// stv_units_string converts UTF-16 units to a V string (a lone surrogate becomes U+FFFD); the
// error messages use it.
fn stv_units_string(units []u16) string {
	mut runes := []rune{cap: units.len}
	mut i := 0
	for i < units.len {
		u := u32(units[i])
		if u >= 0xd800 && u <= 0xdbff && i + 1 < units.len && units[i + 1] >= 0xdc00
			&& units[i + 1] <= 0xdfff {
			runes << rune(0x10000 + ((u - 0xd800) << 10) + (u32(units[i + 1]) - 0xdc00))
			i += 2
			continue
		}
		runes << if u >= 0xd800 && u <= 0xdfff { rune(0xfffd) } else { rune(u) }
		i++
	}
	return runes.string()
}
