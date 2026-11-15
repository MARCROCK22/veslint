module collation

import os
import strconv

// The cases come from tools/gen_collation_cases.mjs: strings sorted by Node's localeCompare
// (tests/collation_cases.txt). compare must give, for each string and the `window` strings after
// it and for `far` pairs chosen by the LCG of the generator, in both orders, what their order in
// the file gives (which the generator checked against localeCompare).

struct CaseFile {
	strings []string
	rank    []int
	window  int
	far     int
	seed    u32
}

fn read_cases() CaseFile {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'collation_cases.txt')) or { panic(err) }
	mut strings := []string{}
	mut rank := []int{}
	mut window := 0
	mut far := 0
	mut seed := u32(0)
	for line in raw.split('\n') {
		if line == '' {
			continue
		}
		if line.starts_with('#') {
			if line.starts_with('# window ') {
				fields := line.replace(',', '').replace(':', '').split(' ')
				window = fields[2].int()
				far = fields[4].int()
				seed = u32(fields[6].u64())
			}
			continue
		}
		strings << unescape(line[1..])
		rank << if line[0] == `=` { rank[rank.len - 1] } else { rank.len }
	}
	return CaseFile{
		strings: strings
		rank:    rank
		window:  window
		far:     far
		seed:    seed
	}
}

// unescape reads `\u{X}` as the WTF-8 bytes of code point X (3 bytes for a lone surrogate).
fn unescape(s string) string {
	if !s.contains('\\') {
		return s
	}
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `\\` {
			end := s.index_after('}', i) or { panic(s) }
			cp := u32(strconv.parse_uint(s[i + 3..end], 16, 32) or { panic(s) })
			if cp < 0x80 {
				out << u8(cp)
			} else if cp < 0x800 {
				out << u8(0xc0 | (cp >> 6))
				out << u8(0x80 | (cp & 0x3f))
			} else if cp < 0x10000 {
				out << u8(0xe0 | (cp >> 12))
				out << u8(0x80 | ((cp >> 6) & 0x3f))
				out << u8(0x80 | (cp & 0x3f))
			} else {
				out << u8(0xf0 | (cp >> 18))
				out << u8(0x80 | ((cp >> 12) & 0x3f))
				out << u8(0x80 | ((cp >> 6) & 0x3f))
				out << u8(0x80 | (cp & 0x3f))
			}
			i = end + 1
			continue
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

fn hex_points(s string) string {
	return code_points(s).map('${it:04X}').join(' ')
}

fn sign(n int) int {
	return if n < 0 {
		-1
	} else if n > 0 {
		1
	} else {
		0
	}
}

fn test_compare_like_node() {
	c := read_cases()
	assert c.strings.len > 100000
	assert c.window > 0 && c.far > 0
	mut failures := []string{}
	mut pairs := 0
	check := fn [c] (i int, j int, mut failures []string) {
		want := sign(c.rank[i] - c.rank[j])
		got := compare(c.strings[i], c.strings[j])
		back := compare(c.strings[j], c.strings[i])
		if got != want || back != -want {
			failures << '[${hex_points(c.strings[i])}] vs [${hex_points(c.strings[j])}]: ${got} (back ${back}), Node ${want}'
		}
	}
	for i in 0 .. c.strings.len {
		for d in 1 .. c.window + 1 {
			if i + d < c.strings.len {
				check(i, i + d, mut failures)
				pairs++
			}
		}
	}
	mut state := c.seed
	for _ in 0 .. c.far {
		state = state * 1103515245 + 12345
		i := int((state >> 8) % u32(c.strings.len))
		state = state * 1103515245 + 12345
		j := int((state >> 8) % u32(c.strings.len))
		check(i, j, mut failures)
		pairs++
	}
	if failures.len > 0 {
		eprintln('${failures.len} of ${pairs} pairs differ from Node:')
		for f in failures[..if failures.len < 60 { failures.len } else { 60 }] {
			eprintln('  ${f}')
		}
	}
	assert failures.len == 0
}

// Strings that are not ASCII and ASCII strings compare the same way: the fast way of two ASCII
// strings agrees with their collation elements.
fn test_ascii_fast_path_agrees_with_elements() {
	t := tables()
	mut strings := []string{}
	for a in 0 .. 128 {
		strings << [u8(a)].bytestr()
		for b in [u8(`a`), `A`, `-`] {
			strings << [u8(a), b].bytestr()
		}
	}
	for a in strings {
		for b in strings {
			slow := compare_elements(t.elements(t.fcd(code_points(a))), t.elements(t.fcd(code_points(b))))
			assert compare_ascii(a, b) == slow, '${a.bytes()} vs ${b.bytes()}'
		}
	}
}

fn test_code_points_wtf8() {
	assert code_points('a\xed\xa0\x80b') == [u32(`a`), 0xd800, `b`]
	assert code_points('\xed\xa0\xbd\xed\xb8\x80') == [u32(0x1f600)]
	assert code_points('\xed\xb8\x80\xed\xa0\xbd') == [u32(0xde00), 0xd83d]
	assert code_points('\xf0\x9f\x98\x80') == [u32(0x1f600)]
}
