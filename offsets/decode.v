module offsets

// The text of a file as Node gives it to ESLint (`fs.readFile(path, 'utf8')`): the UTF-8 decoder
// of the WHATWG Encoding Standard, which replaces each ill-formed sequence with U+FFFD. ESLint,
// and through it typescript-eslint and TypeScript, lint that text, so positions and messages
// follow it.

// replacement_character is U+FFFD in UTF-8.
const replacement_character = '\xEF\xBF\xBD'

// is_valid_utf8 tells whether the decoder below would return `raw` unchanged.
fn is_valid_utf8(raw string) bool {
	mut i := 0
	for i < raw.len {
		b := raw[i]
		if b < 0x80 {
			i++
			continue
		}
		needed, lower, upper := lead_byte(b)
		// The sequence is raw[i..i + needed + 1].
		if needed == 0 || i + needed >= raw.len {
			return false
		}
		if raw[i + 1] < lower || raw[i + 1] > upper {
			return false
		}
		for k in 2 .. needed + 1 {
			if raw[i + k] & 0xC0 != 0x80 {
				return false
			}
		}
		i += needed + 1
	}
	return true
}

// lead_byte gives, for the first byte of a sequence, how many continuation bytes follow it and
// the range the first of them must be in (which excludes overlong forms, surrogates and code
// points above U+10FFFF); 0 bytes for a byte that cannot start a sequence.
fn lead_byte(b u8) (int, u8, u8) {
	return match true {
		b >= 0xC2 && b <= 0xDF { 1, u8(0x80), u8(0xBF) }
		b == 0xE0 { 2, u8(0xA0), u8(0xBF) }
		b == 0xED { 2, u8(0x80), u8(0x9F) }
		b >= 0xE1 && b <= 0xEF { 2, u8(0x80), u8(0xBF) }
		b == 0xF0 { 3, u8(0x90), u8(0xBF) }
		b == 0xF4 { 3, u8(0x80), u8(0x8F) }
		b >= 0xF1 && b <= 0xF3 { 3, u8(0x80), u8(0xBF) }
		else { 0, u8(0), u8(0) }
	}
}

// decode_utf8 returns the text Node decodes from the bytes of a file, in UTF-8, and whether it
// differs from them. Each maximal ill-formed sequence becomes one U+FFFD: a byte that cannot
// start a sequence, or a lead byte with the continuation bytes that do follow it when the next
// byte cannot (so a truncated `E2 82` is one U+FFFD, and the overlong `C0 AF` is two).
pub fn decode_utf8(raw string) (string, bool) {
	if is_valid_utf8(raw) {
		return raw, false
	}
	mut out := []u8{cap: raw.len + 16}
	mut i := 0
	for i < raw.len {
		b := raw[i]
		if b < 0x80 {
			out << b
			i++
			continue
		}
		needed, lower, upper := lead_byte(b)
		if needed == 0 {
			out << replacement_character.bytes()
			i++
			continue
		}
		// The continuation bytes that are there and fit.
		mut seen := 0
		for seen < needed && i + 1 + seen < raw.len {
			c := raw[i + 1 + seen]
			if seen == 0 {
				if c < lower || c > upper {
					break
				}
			} else if c & 0xC0 != 0x80 {
				break
			}
			seen++
		}
		if seen == needed {
			out << raw[i..i + needed + 1].bytes()
		} else {
			out << replacement_character.bytes()
		}
		i += seen + 1
	}
	return out.bytestr(), true
}
