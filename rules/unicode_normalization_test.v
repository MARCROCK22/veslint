module rules

import json2
import jsregexp
import os

// The cases come from tools/gen_unicode_normalization.mjs: what normalize gives in V8 for chosen
// strings (their four forms as UTF-16 units), and FNV-1a digests of what it gives for every code
// point alone, for the strings made from each composition and for random strings from a pool,
// all of them built here as the generator builds them.

const normalization_forms = ['NFC', 'NFD', 'NFKC', 'NFKD']

fn normalization_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'unicode_normalization_cases.json')) or {
		panic(err)
	}
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

fn normalization_units(value json2.Any) []u16 {
	return value.as_array().map(u16(it.int()))
}

fn test_chosen_strings_match_v8() {
	data := normalization_cases()
	mut checked := 0
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		units := normalization_units(entry['units'] or { panic('no units') })
		for form in normalization_forms {
			want := normalization_units(entry[form.to_lower()] or { panic('no ${form}') })
			assert js_normalize(units, form) == want, '${form} of ${units}'
		}
		checked++
	}
	assert checked >= 70
}

// normalization_digest is the generator's FNV-1a over the UTF-16 units of the form of each string,
// with a separator after each one.
fn normalization_digest(strings [][]u32, form string) string {
	mut h := u32(0x811c9dc5)
	for points in strings {
		mut units := []u16{}
		for cp in points {
			jsregexp.append_utf16(mut units, cp)
		}
		for unit in js_normalize(units, form) {
			h = (h ^ u32(unit)) * u32(0x01000193)
		}
		h = (h ^ u32(0x10000)) * u32(0x01000193)
	}
	return '${h:08x}'
}

fn normalization_digests(data map[string]json2.Any, form string, kind string) []string {
	forms := (data['digests'] or { panic('no digests') }).as_map()
	return (forms[form] or { panic('no ${form}') }).as_map()[kind] or { panic('no ${kind}') }.as_array().map(it.str())
}

fn normalization_chunks(strings [][]u32, size int) [][][]u32 {
	mut out := [][][]u32{}
	for start := 0; start < strings.len; start += size {
		end := if start + size < strings.len { start + size } else { strings.len }
		out << strings[start..end]
	}
	return out
}

// normalization_block_digest is the digest of the code points of a block alone, normalized or as
// they are.
fn normalization_block_digest(first int, count int, form string) string {
	mut h := u32(0x811c9dc5)
	mut units := []u16{cap: 2}
	for cp in first .. first + count {
		units.clear()
		jsregexp.append_utf16(mut units, u32(cp))
		for unit in if form == '' { units } else { js_normalize(units, form) } {
			h = (h ^ u32(unit)) * u32(0x01000193)
		}
		h = (h ^ u32(0x10000)) * u32(0x01000193)
	}
	return '${h:08x}'
}

// Every code point alone, in blocks: the lone surrogates too. A block that V8 leaves as it is, and
// where no code point has a class or a decomposition or is a Hangul syllable, is one js_normalize
// leaves as it is too, without asking it (most blocks are unassigned); the others are normalized.
fn test_every_code_point_matches_v8() {
	data := normalization_cases()
	block_size := (data['blockSize'] or { panic('no blockSize') }).int()
	mut normalized := 0
	for form in normalization_forms {
		want := normalization_digests(data, form, 'blocks')
		assert want.len * block_size == 0x110000
		for b, digest in want {
			first := u32(b * block_size)
			last := first + u32(block_size) - 1
			in_block := fn [first, last] (cp u32) bool {
				return cp >= first && cp <= last
			}
			mut plain := !(first < hangul_s_base + hangul_s_count && last >= hangul_s_base)
				&& !unicode_nfd_keys.any(in_block(it)) && !unicode_nfkd_keys.any(in_block(it))
			for i := 0; plain && i < unicode_class_ranks.len; i += 2 {
				plain = !in_block(unicode_class_ranks[i])
			}
			if plain && digest == normalization_block_digest(int(first), block_size, '') {
				continue
			}
			assert normalization_block_digest(int(first), block_size, form) == digest, '${form} of U+${first:04X}..U+${last:04X}'
			normalized++
		}
	}
	assert normalized > 0
}

// Each composition with nothing, a mark of the lowest class (U+0334), one of the highest (U+0345)
// and U+0301 between its two code points, and its composite followed by its second code point and
// by U+0334: what blocks a composition and what does not.
fn test_compositions_match_v8() {
	data := normalization_cases()
	chunk_size := (data['chunkSize'] or { panic('no chunkSize') }).int()
	mut strings := [][]u32{}
	for i := 0; i < unicode_compositions.len; i += 3 {
		a, b, c := unicode_compositions[i], unicode_compositions[i + 1], unicode_compositions[i + 2]
		strings << [a, b]
		strings << [a, u32(0x334), b]
		strings << [a, u32(0x345), b]
		strings << [a, u32(0x301), b]
		strings << [c, b]
		strings << [c, u32(0x334)]
	}
	for form in normalization_forms {
		want := normalization_digests(data, form, 'compositions')
		chunks := normalization_chunks(strings, chunk_size)
		assert chunks.len == want.len
		for i, chunk in chunks {
			assert normalization_digest(chunk, form) == want[i], '${form} of the compositions of chunk ${i}'
		}
	}
}

// Random strings from the generator's pool, with its seed and its linear congruential generator.
fn test_random_strings_match_v8() {
	data := normalization_cases()
	chunk_size := (data['chunkSize'] or { panic('no chunkSize') }).int()
	pool := (data['pool'] or { panic('no pool') }).as_array().map(u32(it.int()))
	count := (data['randomCount'] or { panic('no randomCount') }).int()
	max_length := u32((data['maxLength'] or { panic('no maxLength') }).int())
	mut state := u32((data['seed'] or { panic('no seed') }).i64())
	mut strings := [][]u32{cap: count}
	for _ in 0 .. count {
		state = state * 1103515245 + 12345
		length := 1 + (state >> 8) % max_length
		mut points := []u32{cap: int(length)}
		for _ in 0 .. length {
			state = state * 1103515245 + 12345
			points << pool[(state >> 8) % u32(pool.len)]
		}
		strings << points
	}
	for form in normalization_forms {
		want := normalization_digests(data, form, 'random')
		chunks := normalization_chunks(strings, chunk_size)
		assert chunks.len == want.len
		for i, chunk in chunks {
			assert normalization_digest(chunk, form) == want[i], '${form} of the random strings of chunk ${i}'
		}
	}
}
