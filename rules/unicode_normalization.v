module rules

// String.prototype.normalize as V8 does it with ICU: the algorithm of UAX #15 on the tables of
// unicode_normalization_data.v, which tools/gen_unicode_normalization.mjs takes from V8 itself
// (the full decomposition of each code point, the order of the canonical combining classes and
// the primary composites), and Hangul syllables by arithmetic. A surrogate without its pair is a
// code point by itself, which no form changes.

const hangul_s_base = u32(0xac00)
const hangul_l_base = u32(0x1100)
const hangul_v_base = u32(0x1161)
const hangul_t_base = u32(0x11a7)
const hangul_l_count = u32(19)
const hangul_v_count = u32(21)
const hangul_t_count = u32(28)
const hangul_n_count = hangul_v_count * hangul_t_count
const hangul_s_count = hangul_l_count * hangul_n_count

// The first code point that decomposes in some form (U+00A0, NO-BREAK SPACE).
const unicode_first_decomposable = u32(0xa0)

// js_normalize ports String.prototype.normalize for one of the forms NFC, NFD, NFKC and NFKD.
fn js_normalize(units []u16, form string) []u16 {
	compatible := form == 'NFKC' || form == 'NFKD'
	mut points := unicode_decompose(utf16_code_points(units), compatible)
	if form == 'NFC' || form == 'NFKC' {
		points = unicode_compose(points)
	}
	mut out := []u16{cap: points.len}
	for cp in points {
		append_utf16(mut out, cp)
	}
	return out
}

fn unicode_is_syllable(cp u32) bool {
	return cp >= hangul_s_base && cp < hangul_s_base + hangul_s_count
}

// unicode_class_rank is the rank of the canonical combining class of a code point among those
// classes: 0 for a starter, and for the marks numbers in the order of their classes.
fn unicode_class_rank(cp u32) u32 {
	if cp < unicode_class_ranks[0] {
		return 0
	}
	i := unicode_case_entry(unicode_class_ranks, 2, cp)
	return if i >= 0 { unicode_class_ranks[i + 1] } else { 0 }
}

// unicode_mapping is the decomposition of a code point in a table of unicode_normalization_data.v.
fn unicode_mapping(keys []u32, starts []u32, data []u32, cp u32) ?[]u32 {
	mut low := 0
	mut high := keys.len - 1
	for low <= high {
		mid := (low + high) / 2
		if keys[mid] == cp {
			return data[int(starts[mid])..int(starts[mid + 1])]
		}
		if keys[mid] < cp {
			low = mid + 1
		} else {
			high = mid - 1
		}
	}
	return none
}

// unicode_decompose replaces each code point with its full decomposition, the compatibility one
// if `compatible`, and puts each run of marks in the order of their classes (a stable sort).
fn unicode_decompose(points []u32, compatible bool) []u32 {
	mut out := []u32{cap: points.len}
	for cp in points {
		if cp < unicode_first_decomposable {
			out << cp
			continue
		}
		if unicode_is_syllable(cp) {
			index := cp - hangul_s_base
			out << hangul_l_base + index / hangul_n_count
			out << hangul_v_base + (index % hangul_n_count) / hangul_t_count
			if index % hangul_t_count != 0 {
				out << hangul_t_base + index % hangul_t_count
			}
			continue
		}
		if compatible {
			if mapping := unicode_mapping(unicode_nfkd_keys, unicode_nfkd_starts, unicode_nfkd_data,
				cp)
			{
				out << mapping
				continue
			}
		}
		if mapping := unicode_mapping(unicode_nfd_keys, unicode_nfd_starts, unicode_nfd_data, cp) {
			out << mapping
			continue
		}
		out << cp
	}
	for i in 1 .. out.len {
		class := unicode_class_rank(out[i])
		if class == 0 {
			continue
		}
		mut j := i
		for j > 0 && unicode_class_rank(out[j - 1]) > class {
			out[j - 1], out[j] = out[j], out[j - 1]
			j--
		}
	}
	return out
}

// unicode_compose_pair is the primary composite of two code points, or 0 when there is none.
fn unicode_compose_pair(a u32, b u32) u32 {
	if a >= hangul_l_base && a < hangul_l_base + hangul_l_count && b >= hangul_v_base
		&& b < hangul_v_base + hangul_v_count {
		return hangul_s_base + ((a - hangul_l_base) * hangul_v_count + (b - hangul_v_base)) * hangul_t_count
	}
	if unicode_is_syllable(a) && (a - hangul_s_base) % hangul_t_count == 0 && b > hangul_t_base
		&& b < hangul_t_base + hangul_t_count {
		return a + (b - hangul_t_base)
	}
	mut low := 0
	mut high := unicode_compositions.len / 3 - 1
	for low <= high {
		mid := (low + high) / 2
		first := unicode_compositions[3 * mid]
		second := unicode_compositions[3 * mid + 1]
		if first == a && second == b {
			return unicode_compositions[3 * mid + 2]
		}
		if first < a || (first == a && second < b) {
			low = mid + 1
		} else {
			high = mid - 1
		}
	}
	return 0
}

// unicode_compose ports the canonical composition of UAX #15: each code point composes with the
// last starter when nothing between them blocks it (a mark of the same class or higher, or a
// starter, unless the two are next to each other).
fn unicode_compose(points []u32) []u32 {
	if points.len == 0 {
		return points
	}
	mut out := [points[0]]
	mut starter := 0
	// A mark at the start blocks nothing, and nothing composes with it.
	mut last_class := if unicode_class_rank(points[0]) == 0 { u32(0) } else { u32(256) }
	for cp in points[1..] {
		class := unicode_class_rank(cp)
		composite := unicode_compose_pair(out[starter], cp)
		if composite != 0 && (last_class < class || last_class == 0) {
			out[starter] = composite
			continue
		}
		if class == 0 {
			starter = out.len
		}
		last_class = class
		out << cp
	}
	return out
}
