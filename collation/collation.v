module collation

import sync

// The order of strings of ICU's root collation, which Node's `a.localeCompare(b)` gives with its
// default locale (en-US, the same as the root: ICU 78.3, CLDR 48, Unicode 17), at its default
// strength (tertiary), with variable characters not ignored, no backwards secondary, and with
// ICU's normalization mode on (V8 turns it on): what eslint-plugin-perfectionist's alphabetical
// order (and natural-orderby, for what is not a number) and typescript-eslint's
// switch-exhaustiveness-check compare with.
//
// Strings are compared as ICU compares them (RuleBasedCollator::compare, CollationCompare::
// compareUpToQuaternary): each one becomes a list of collation elements, which are compared level
// by level: the primary weights that are not 0, then the secondary ones, then the tertiary ones
// (without the case bits); the end of a list weighs less than any weight; equal at the three
// levels is 0. The code points are read as ICU's FCDUTF16CollationIterator reads them: as they
// are where the text passes the FCD check, the segments that fail it replaced by their NFD (so
// canonically equivalent strings are equal, but for the few mappings of FractionalUCA.txt that are
// not canonically closed, such as U+FDD1 U+AC00). Their elements are found as ICU's
// CollationIterator finds them: the longest contraction at each position, extended by the
// non-starters after it that are not blocked (discontiguous contractions), the prefix contexts
// (L·), the elements of each other code point from the table (Hangul syllables: those of their
// jamo), or the implicit one (Han characters in radical-stroke order, then the unassigned code
// points, lone surrogates included, by code point). table.v (tools/gen_collation_table.mjs) holds
// the data, read from ICU's FractionalUCA.txt with the weights replaced by their ranks.
//
// The strings are WTF-8, as veslint keeps JavaScript strings: a lone surrogate is a code point of
// its own (3 bytes, ED A0..BF xx). Two ASCII strings take a faster way (ascii_primary), which
// gives the same as the elements: their primary weights, then, at the tertiary level, the case
// (a lowercase letter or another character before an uppercase letter); ASCII has no secondary
// differences.

const ascii_primary = [
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(1),
	u8(2),
	u8(3),
	u8(4),
	u8(5),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(0),
	u8(6),
	u8(12),
	u8(16),
	u8(28),
	u8(38),
	u8(29),
	u8(27),
	u8(15),
	u8(17),
	u8(18),
	u8(24),
	u8(32),
	u8(9),
	u8(8),
	u8(14),
	u8(25),
	u8(39),
	u8(40),
	u8(41),
	u8(42),
	u8(43),
	u8(44),
	u8(45),
	u8(46),
	u8(47),
	u8(48),
	u8(11),
	u8(10),
	u8(33),
	u8(34),
	u8(35),
	u8(13),
	u8(23),
	u8(49),
	u8(50),
	u8(51),
	u8(52),
	u8(53),
	u8(54),
	u8(55),
	u8(56),
	u8(57),
	u8(58),
	u8(59),
	u8(60),
	u8(61),
	u8(62),
	u8(63),
	u8(64),
	u8(65),
	u8(66),
	u8(67),
	u8(68),
	u8(69),
	u8(70),
	u8(71),
	u8(72),
	u8(73),
	u8(74),
	u8(19),
	u8(26),
	u8(20),
	u8(31),
	u8(7),
	u8(30),
	u8(49),
	u8(50),
	u8(51),
	u8(52),
	u8(53),
	u8(54),
	u8(55),
	u8(56),
	u8(57),
	u8(58),
	u8(59),
	u8(60),
	u8(61),
	u8(62),
	u8(63),
	u8(64),
	u8(65),
	u8(66),
	u8(67),
	u8(68),
	u8(69),
	u8(70),
	u8(71),
	u8(72),
	u8(73),
	u8(74),
	u8(21),
	u8(36),
	u8(22),
	u8(37),
	u8(0),
]!

// compare is `Math.sign(a.localeCompare(b))` of Node (en-US): -1, 0 or 1.
pub fn compare(a string, b string) int {
	if a == b {
		return 0
	}
	if is_ascii(a) && is_ascii(b) {
		return compare_ascii(a, b)
	}
	t := tables()
	return compare_elements(t.elements(t.fcd(code_points(a))), t.elements(t.fcd(code_points(b))))
}

fn is_ascii(s string) bool {
	for c in s {
		if c >= 0x80 {
			return false
		}
	}
	return true
}

fn compare_ascii(a string, b string) int {
	mut i := 0
	mut j := 0
	for {
		for i < a.len && ascii_primary[a[i]] == 0 {
			i++
		}
		for j < b.len && ascii_primary[b[j]] == 0 {
			j++
		}
		if i >= a.len || j >= b.len {
			break
		}
		pa := ascii_primary[a[i]]
		pb := ascii_primary[b[j]]
		if pa != pb {
			return if pa < pb { -1 } else { 1 }
		}
		i++
		j++
	}
	// One is a prefix of the other at the primary level: the shorter first.
	if i < a.len || j < b.len {
		return if i >= a.len { -1 } else { 1 }
	}
	// Tertiary: the case of each character with a weight, in order.
	i = 0
	j = 0
	for {
		for i < a.len && ascii_primary[a[i]] == 0 {
			i++
		}
		for j < b.len && ascii_primary[b[j]] == 0 {
			j++
		}
		if i >= a.len || j >= b.len {
			return 0
		}
		ua := a[i] >= `A` && a[i] <= `Z`
		ub := b[j] >= `A` && b[j] <= `Z`
		if ua != ub {
			return if ua { 1 } else { -1 }
		}
		i++
		j++
	}
	return 0
}

// A collation element is a u64: the primary weight (a rank, see table.v) above bit 14, the rank
// of the secondary weight in bits 5..13 and the one of the tertiary weight in bits 0..4.
const st_bits = 14

@[inline]
fn secondary(e u64) u64 {
	return (e >> 5) & 0x1ff
}

@[inline]
fn tertiary(e u64) u64 {
	return e & 0x1f
}

// compare_elements compares the elements of two strings level by level (the end of a list is
// below any weight).
fn compare_elements(a []u64, b []u64) int {
	mut i := 0
	mut j := 0
	for {
		for i < a.len && a[i] >> st_bits == 0 {
			i++
		}
		for j < b.len && b[j] >> st_bits == 0 {
			j++
		}
		if i >= a.len || j >= b.len {
			if i < a.len || j < b.len {
				return if i >= a.len { -1 } else { 1 }
			}
			break
		}
		pa := a[i] >> st_bits
		pb := b[j] >> st_bits
		if pa != pb {
			return if pa < pb { -1 } else { 1 }
		}
		i++
		j++
	}
	for level in 0 .. 2 {
		i = 0
		j = 0
		for {
			mut wa := u64(0)
			for i < a.len {
				wa = if level == 0 { secondary(a[i]) } else { tertiary(a[i]) }
				if wa != 0 {
					break
				}
				i++
			}
			mut wb := u64(0)
			for j < b.len {
				wb = if level == 0 { secondary(b[j]) } else { tertiary(b[j]) }
				if wb != 0 {
					break
				}
				j++
			}
			if i >= a.len || j >= b.len {
				if i < a.len || j < b.len {
					return if i >= a.len { -1 } else { 1 }
				}
				break
			}
			if wa != wb {
				return if wa < wb { -1 } else { 1 }
			}
			i++
			j++
		}
	}
	return 0
}

// code_points decodes a WTF-8 string into the code points of its UTF-16 string: a lone surrogate
// is one code point, and a lead surrogate followed by a trail one (each in 3 bytes) is the pair's
// code point. A byte that does not start a sequence is U+FFFD.
fn code_points(s string) []u32 {
	mut out := []u32{cap: s.len}
	mut i := 0
	for i < s.len {
		b := s[i]
		if b < 0x80 {
			out << u32(b)
			i++
			continue
		}
		mut n := 0
		mut cp := u32(0)
		if b & 0xe0 == 0xc0 {
			n = 1
			cp = b & 0x1f
		} else if b & 0xf0 == 0xe0 {
			n = 2
			cp = b & 0x0f
		} else if b & 0xf8 == 0xf0 {
			n = 3
			cp = b & 0x07
		} else {
			out << 0xfffd
			i++
			continue
		}
		if i + n >= s.len {
			out << 0xfffd
			i++
			continue
		}
		mut ok := true
		for k in 1 .. n + 1 {
			if s[i + k] & 0xc0 != 0x80 {
				ok = false
				break
			}
			cp = (cp << 6) | (s[i + k] & 0x3f)
		}
		if !ok {
			out << 0xfffd
			i++
			continue
		}
		i += n + 1
		if cp >= 0xdc00 && cp <= 0xdfff && out.len > 0 && out[out.len - 1] >= 0xd800
			&& out[out.len - 1] <= 0xdbff && i - 6 >= 0 && s[i - 6] == 0xed {
			out[out.len - 1] = 0x10000 + ((out[out.len - 1] - 0xd800) << 10) + (cp - 0xdc00)
			continue
		}
		out << cp
	}
	return out
}

// Tables is the data of table.v, decoded the first time a string that is not ASCII is compared.
struct Tables {
mut:
	palette []u64
	// Canonical combining classes (ranks of the classes), by runs of code points.
	ccc_start []u32
	ccc_end   []u32
	ccc_rank  []u8
	// Canonical decompositions: nfd_data[nfd_index[k]..nfd_index[k + 1]] for nfd_keys[k].
	nfd_keys  []u32
	nfd_index []int
	nfd_data  []u32
	// Han characters: runs of code points of the same group of the radical-stroke order.
	han_start []u32
	han_end   []u32
	han_group []u64
	// Code points: runs; elements ces[run_ce[k]..run_ce[k] + run_count[k]] for each code point of
	// a run of kind 0, ces[run_ce[k]] plus the offset of the code point in the primary for kind 1.
	run_start []u32
	run_end   []u32
	run_kind  []u8
	run_ce    []int
	run_count []int
	ces       []u64
	// Contractions, sorted, by their first code point: con_first[k] starts the contractions
	// con_begin[k]..con_begin[k + 1]; contraction c has the code points
	// con_cps[con_cp[c]..con_cp[c + 1]] after the first one and the elements
	// ces[con_ce[c]..con_ce[c] + con_count[c]]; con_trailing[k]: one of them ends with a
	// non-starter (discontiguous contractions are possible).
	con_first    []u32
	con_begin    []int
	con_trailing []bool
	con_cp       []int
	con_cps      []u32
	con_ce       []int
	con_count    []int
	// Prefix contexts: the elements of pre_cp[k] after the code points pre_cps[pre_at[k]..pre_at[k + 1]].
	pre_cp    []u32
	pre_at    []int
	pre_cps   []u32
	pre_ce    []int
	pre_count []int
}

const tables_data = &Tables{}
const tables_once = sync.new_once()

fn tables() &Tables {
	mut once := tables_once
	once.do(load_tables)
	return tables_data
}

fn load_tables() {
	unsafe {
		mut t := tables_data
		t.load()
	}
}

struct Reader {
	s string
mut:
	i int
}

fn (mut r Reader) num() u64 {
	mut n := u64(0)
	mut shift := u64(0)
	for {
		v := digit(r.s[r.i])
		r.i++
		if v < 0 {
			continue
		}
		n |= u64(v & 31) << shift
		shift += 5
		if v < 32 {
			return n
		}
	}
	return n
}

// digit is the value of a character of the alphabet of table.v (-1 for a line break).
fn digit(c u8) int {
	return match true {
		c >= `A` && c <= `Z` { int(c - `A`) }
		c >= `a` && c <= `z` { int(c - `a`) + 26 }
		c >= `0` && c <= `9` { int(c - `0`) + 52 }
		c == `+` { 62 }
		c == `/` { 63 }
		else { -1 }
	}
}

fn (mut r Reader) int() int {
	return int(r.num())
}

fn (mut r Reader) signed() i64 {
	n := r.num()
	return if n & 1 == 0 { i64(n >> 1) } else { -i64(n >> 1) - 1 }
}

// element reads a collation element (see writeElements of the generator); p is the last primary.
fn (mut t Tables) element(mut r Reader, mut p &u64) u64 {
	a := r.num()
	mut primary := u64(0)
	if a & 1 == 1 {
		primary = t.han_primary(u32(a >> 1))
	} else {
		z := a >> 1
		if z & 1 == 0 {
			primary = *p + (z >> 1)
		} else {
			primary = *p - (z >> 1) - 1
		}
		unsafe {
			*p = primary
		}
	}
	return (primary << st_bits) | t.palette[r.int()]
}

fn (mut t Tables) load() {
	mut r := Reader{
		s: data_palette
	}
	for _ in 0 .. r.int() {
		t.palette << r.num()
	}
	r = Reader{
		s: data_ccc
	}
	mut end := i64(-1)
	for _ in 0 .. r.int() {
		start := u32(end + 1 + i64(r.num()))
		last := start + u32(r.num())
		t.ccc_start << start
		t.ccc_end << last
		t.ccc_rank << u8(r.num())
		end = last
	}
	r = Reader{
		s: data_nfd
	}
	mut previous := i64(-1)
	for _ in 0 .. r.int() {
		cp := u32(previous + 1 + i64(r.num()))
		t.nfd_keys << cp
		t.nfd_index << t.nfd_data.len
		for _ in 0 .. r.int() {
			t.nfd_data << u32(r.num())
		}
		previous = cp
	}
	t.nfd_index << t.nfd_data.len
	r = Reader{
		s: data_han
	}
	end = -1
	mut group := i64(0)
	for _ in 0 .. r.int() {
		start := u32(end + 1 + i64(r.num()))
		last := start + u32(r.num())
		group += r.signed()
		t.han_start << start
		t.han_end << last
		t.han_group << u64(group)
		end = last
	}
	r = Reader{
		s: data_singles
	}
	end = -1
	mut p := u64(0)
	for _ in 0 .. r.int() {
		start := u32(end + 1 + i64(r.num()))
		h := r.num()
		last := start + u32(h >> 1)
		kind := u8(h & 1)
		count := if kind == 0 { r.int() } else { 1 }
		t.run_start << start
		t.run_end << last
		t.run_kind << kind
		t.run_ce << t.ces.len
		t.run_count << count
		for _ in 0 .. count {
			t.ces << t.element(mut r, mut &p)
		}
		end = last
	}
	r = Reader{
		s: data_contractions
	}
	p = 0
	for _ in 0 .. r.int() {
		n := r.int()
		first := u32(r.num())
		if t.con_first.len == 0 || t.con_first[t.con_first.len - 1] != first {
			t.con_first << first
			t.con_begin << t.con_cp.len
			t.con_trailing << false
		}
		t.con_cp << t.con_cps.len
		for _ in 1 .. n {
			t.con_cps << u32(r.num())
		}
		if t.ccc(t.con_cps[t.con_cps.len - 1]) != 0 {
			t.con_trailing[t.con_trailing.len - 1] = true
		}
		count := r.int()
		t.con_ce << t.ces.len
		t.con_count << count
		for _ in 0 .. count {
			t.ces << t.element(mut r, mut &p)
		}
	}
	t.con_begin << t.con_cp.len
	t.con_cp << t.con_cps.len
	r = Reader{
		s: data_prefixes
	}
	p = 0
	for _ in 0 .. r.int() {
		n := r.int()
		t.pre_at << t.pre_cps.len
		for _ in 0 .. n {
			t.pre_cps << u32(r.num())
		}
		t.pre_cp << u32(r.num())
		count := r.int()
		t.pre_ce << t.ces.len
		t.pre_count << count
		for _ in 0 .. count {
			t.ces << t.element(mut r, mut &p)
		}
	}
	t.pre_at << t.pre_cps.len
}

// find_run is the index of the run of starts/ends that holds cp, or -1.
fn find_run(starts []u32, ends []u32, cp u32) int {
	mut low := 0
	mut high := starts.len - 1
	for low <= high {
		mid := (low + high) / 2
		if cp < starts[mid] {
			high = mid - 1
		} else if cp > ends[mid] {
			low = mid + 1
		} else {
			return mid
		}
	}
	return -1
}

// ccc is the rank of the canonical combining class of a code point (0 for a starter).
fn (t &Tables) ccc(cp u32) u8 {
	if cp < 0x300 {
		return 0
	}
	k := find_run(t.ccc_start, t.ccc_end, cp)
	return if k >= 0 { t.ccc_rank[k] } else { 0 }
}

// han_primary is the primary of a Han character: its group of the radical-stroke order, then its
// place in the UCA's implicit order (the core ideographs, then the others, by code point).
fn (t &Tables) han_primary(cp u32) u64 {
	k := find_run(t.han_start, t.han_end, cp)
	core := (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff)
	return han_base + t.han_group[k] * han_group_shift + (if core { u64(0) } else { u64(0x200000) }) +
		u64(cp)
}

const hangul_s_base = u32(0xac00)
const hangul_l_base = u32(0x1100)
const hangul_v_base = u32(0x1161)
const hangul_t_base = u32(0x11a7)
const hangul_t_count = u32(28)
const hangul_n_count = u32(21 * 28)
const hangul_s_count = u32(19 * 21 * 28)

// decomposition is the index of the canonical decomposition of a code point in nfd_keys, or -1.
fn (t &Tables) decomposition(cp u32) int {
	mut low := 0
	mut high := t.nfd_keys.len - 1
	for low <= high {
		mid := (low + high) / 2
		if t.nfd_keys[mid] < cp {
			low = mid + 1
		} else if t.nfd_keys[mid] > cp {
			high = mid - 1
		} else {
			return mid
		}
	}
	return -1
}

// nfd is the canonical decomposition of a string (UAX #15): each code point decomposed, then the
// marks of each run put in the order of their classes (a stable sort).
fn (t &Tables) nfd(cps []u32) []u32 {
	mut out := []u32{cap: cps.len + 4}
	for cp in cps {
		if cp >= hangul_s_base && cp < hangul_s_base + hangul_s_count {
			index := cp - hangul_s_base
			out << hangul_l_base + index / hangul_n_count
			out << hangul_v_base + (index % hangul_n_count) / hangul_t_count
			if index % hangul_t_count != 0 {
				out << hangul_t_base + index % hangul_t_count
			}
			continue
		}
		if cp >= 0xc0 {
			k := t.decomposition(cp)
			if k >= 0 {
				out << t.nfd_data[t.nfd_index[k]..t.nfd_index[k + 1]]
				continue
			}
		}
		out << cp
	}
	for i in 1 .. out.len {
		c := t.ccc(out[i])
		if c == 0 {
			continue
		}
		mut j := i
		for j > 0 && t.ccc(out[j - 1]) > c {
			out[j - 1], out[j] = out[j], out[j - 1]
			j--
		}
	}
	return out
}

// lccc and tccc are the canonical combining classes (ranks) of the first and of the last code
// point of the canonical decomposition of a code point (its FCD16 value).
fn (t &Tables) lccc(cp u32) u8 {
	if cp < 0xc0 || (cp >= hangul_s_base && cp < hangul_s_base + hangul_s_count) {
		return 0
	}
	k := t.decomposition(cp)
	return t.ccc(if k >= 0 { t.nfd_data[t.nfd_index[k]] } else { cp })
}

fn (t &Tables) tccc(cp u32) u8 {
	if cp < 0xc0 || (cp >= hangul_s_base && cp < hangul_s_base + hangul_s_count) {
		return 0
	}
	k := t.decomposition(cp)
	return t.ccc(if k >= 0 { t.nfd_data[t.nfd_index[k + 1] - 1] } else { cp })
}

// is_tibetan_composite_vowel: U+0F73, U+0F75 and U+0F81, which always fail ICU's FCD check.
@[inline]
fn is_tibetan_composite_vowel(cp u32) bool {
	return cp == 0xf73 || cp == 0xf75 || cp == 0xf81
}

// fcd gives the code points of a string as FCDUTF16CollationIterator reads them forward: where a
// code point with a trailing class is followed by one with a leading class (or is a Tibetan
// composite vowel), the segment from it (nextSegment) is read as it is if it passes the FCD check
// (each leading class not below the trailing class before it) up to the next FCD boundary;
// otherwise the segment up to the end of the run of code points with a leading class after the
// one that failed is replaced by its NFD.
fn (t &Tables) fcd(cps []u32) []u32 {
	mut out := []u32{cap: cps.len + 4}
	mut i := 0
	for i < cps.len {
		c := cps[i]
		if t.tccc(c) == 0 || (!is_tibetan_composite_vowel(c)
			&& (i + 1 >= cps.len || t.lccc(cps[i + 1]) == 0)) {
			out << c
			i++
			continue
		}
		mut prev_cc := u8(0)
		mut j := i
		for {
			lead := t.lccc(cps[j])
			if lead == 0 && j != i {
				out << cps[i..j]
				i = j
				break
			}
			if lead != 0 && (prev_cc > lead || is_tibetan_composite_vowel(cps[j])) {
				mut q := j + 1
				for q < cps.len && t.lccc(cps[q]) != 0 {
					q++
				}
				out << t.nfd(cps[i..q])
				i = q
				break
			}
			prev_cc = t.tccc(cps[j])
			j++
			if j == cps.len || prev_cc == 0 {
				out << cps[i..j]
				i = j
				break
			}
		}
	}
	return out
}

// append_single appends the elements of the code point cps[i] alone (with its prefix context).
fn (t &Tables) append_single(cps []u32, i int, mut out []u64) {
	cp := cps[i]
	if t.pre_cp.len > 0 && cp in t.pre_cp {
		mut best := -1
		mut best_len := 0
		for k, c in t.pre_cp {
			if c != cp {
				continue
			}
			prefix := t.pre_cps[t.pre_at[k]..t.pre_at[k + 1]]
			if prefix.len > i || prefix.len <= best_len {
				continue
			}
			if cps[i - prefix.len..i] == prefix {
				best = k
				best_len = prefix.len
			}
		}
		if best >= 0 {
			out << t.ces[t.pre_ce[best]..t.pre_ce[best] + t.pre_count[best]]
			return
		}
	}
	k := find_run(t.run_start, t.run_end, cp)
	if k >= 0 {
		if t.run_kind[k] == 1 {
			out << t.ces[t.run_ce[k]] + (u64(cp - t.run_start[k]) << st_bits)
		} else {
			out << t.ces[t.run_ce[k]..t.run_ce[k] + t.run_count[k]]
		}
		return
	}
	if cp >= hangul_s_base && cp < hangul_s_base + hangul_s_count {
		// A Hangul syllable: the elements of its jamo (Collation::HANGUL_TAG).
		jamo := t.nfd([cp])
		for n in 0 .. jamo.len {
			t.append_single(jamo, n, mut out)
		}
		return
	}
	if find_run(t.han_start, t.han_end, cp) >= 0 {
		out << (t.han_primary(cp) << st_bits) | common_st
		return
	}
	// Unassigned (and lone surrogates): by code point, after the first unassigned primary.
	out << ((unassigned_base + u64(cp) + 1) << st_bits) | common_st
}

// contraction finds the contraction of the code points after the first one (index k of
// con_first): its index or -1, and whether a longer contraction starts with them.
fn (t &Tables) contraction(k int, suffix []u32) (int, bool) {
	mut value := -1
	mut longer := false
	for c in t.con_begin[k] .. t.con_begin[k + 1] {
		cps := t.con_cps[t.con_cp[c]..t.con_cp[c + 1]]
		if cps.len < suffix.len || cps[..suffix.len] != suffix {
			continue
		}
		if cps.len == suffix.len {
			value = c
		} else {
			longer = true
		}
	}
	return value, longer
}

fn (t &Tables) contraction_start(cp u32) int {
	mut low := 0
	mut high := t.con_first.len - 1
	for low <= high {
		mid := (low + high) / 2
		if t.con_first[mid] < cp {
			low = mid + 1
		} else if t.con_first[mid] > cp {
			high = mid - 1
		} else {
			return mid
		}
	}
	return -1
}

// elements are the collation elements of a string in NFD, as ICU's CollationIterator gives them:
// at each position the longest contraction (UCA S2.1), extended by each non-starter after it
// that is not blocked and makes a longer contraction (S2.1.1–S2.1.3: such a mark is removed, the
// marks skipped stay, in order, after the contraction).
fn (t &Tables) elements(input []u32) []u64 {
	mut cps := input.clone()
	mut out := []u64{cap: cps.len + 4}
	mut i := 0
	for i < cps.len {
		k := t.contraction_start(cps[i])
		if k < 0 {
			t.append_single(cps, i, mut out)
			i++
			continue
		}
		// The longest contiguous match S.
		mut suffix := []u32{}
		mut best := -1
		mut best_len := 0
		for j in i + 1 .. cps.len {
			suffix << cps[j]
			value, longer := t.contraction(k, suffix)
			if value >= 0 {
				best = value
				best_len = suffix.len
			}
			if !longer {
				break
			}
		}
		end := i + 1 + best_len
		// Discontiguous: the non-starters after S, from the one after the first that follows S
		// (which did not match), while they are not starters.
		mut matched := []int{}
		if t.con_trailing[k] && end + 1 < cps.len && t.ccc(cps[end]) != 0
			&& t.ccc(cps[end + 1]) != 0 {
			mut s := cps[i + 1..end].clone()
			mut prev_cc := t.ccc(cps[end])
			for m in end + 1 .. cps.len {
				cc := t.ccc(cps[m])
				if cc == 0 {
					break
				}
				if prev_cc < cc {
					s << cps[m]
					value, longer := t.contraction(k, s)
					if value >= 0 {
						best = value
						matched << m
						if !longer {
							break
						}
						continue
					}
					s.delete_last()
				}
				prev_cc = cc
			}
		}
		if best >= 0 {
			out << t.ces[t.con_ce[best]..t.con_ce[best] + t.con_count[best]]
		} else {
			t.append_single(cps, i, mut out)
		}
		for m := matched.len - 1; m >= 0; m-- {
			cps.delete(matched[m])
		}
		i = end
	}
	return out
}
