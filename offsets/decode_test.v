module offsets

import encoding.hex
import json2
import os

struct DecodeCases {
	node  string
	cases [][]string
}

// decode_utf8 gives, for every case of tests/utf8_decode_cases.json, the text Node decodes from
// those bytes (tools/gen_utf8_decode_cases.mjs): each byte alone and between letters, every pair
// and triple of bytes of each class, the four-byte sequences, sample texts and random bytes.
fn test_decode_utf8_like_node() {
	text := os.read_file(os.join_path(@VMODROOT, 'tests/utf8_decode_cases.json')) or { panic(err) }
	data := json2.decode[DecodeCases](text) or { panic(err) }
	assert data.cases.len > 20000
	mut changed := 0
	for c in data.cases {
		raw := (hex.decode(c[0]) or { panic(err) }).bytestr()
		expected := (hex.decode(c[1]) or { panic(err) }).bytestr()
		decoded, differs := decode_utf8(raw)
		assert decoded == expected, 'bytes ${c[0]}: got ${hex.encode(decoded.bytes())}, Node gives ${c[1]}'
		assert differs == (raw != expected), 'bytes ${c[0]}'
		if differs {
			changed++
		}
	}
	assert changed > 20000
}

// replaced is the decoded text of bytes that are not valid UTF-8.
fn replaced(raw string) string {
	decoded, differs := decode_utf8(raw)
	assert differs, 'valid UTF-8: ${raw.bytes().hex()}'
	return decoded
}

// The sequences of the fixtures, with what Node makes of each.
fn test_decode_utf8_samples() {
	fffd := '\xEF\xBF\xBD'
	// Valid text comes back as it is, with no copy made.
	for valid in ['', 'plain', 'é€😀', '\xEF\xBB\xBFbom'] {
		decoded, differs := decode_utf8(valid)
		assert decoded == valid && !differs
	}
	// Latin-1 `é`, and bytes that start nothing.
	assert replaced('caf\xE9!') == 'caf${fffd}!'
	assert replaced('\xFF\x80') == '${fffd}${fffd}'
	// A truncated sequence is one U+FFFD, also at the end of the file.
	assert replaced('a\xE2\x82b') == 'a${fffd}b'
	assert replaced('a\xF0\x9F\x98b') == 'a${fffd}b'
	assert replaced('a\xF0\x9F\x98') == 'a${fffd}'
	// Overlong forms, a surrogate and a code point above U+10FFFF: one U+FFFD per byte.
	assert replaced('\xC0\xAF') == '${fffd}${fffd}'
	assert replaced('\xE0\x80\xAF') == '${fffd}${fffd}${fffd}'
	assert replaced('\xED\xA0\x80') == '${fffd}${fffd}${fffd}'
	assert replaced('\xF4\x90\x80\x80') == '${fffd}${fffd}${fffd}${fffd}'
	// A UTF-16 BOM is two bytes that start nothing; the text after it is kept, NULs included.
	assert replaced('\xFF\xFEa\x00') == '${fffd}${fffd}a\x00'
}
