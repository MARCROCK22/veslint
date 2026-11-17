module vue

// Calc is one of vue-eslint-parser's location calculators (src/common/location-calculator.ts):
// it maps an index of a code string handed to the script parser to an offset of the file, both
// in UTF-16 units. An HTML calculator walks over the gaps the decoded text skipped (entities,
// CRLF); an offset calculator (createOffsetLocationCalculator) adds a fixed offset.
struct Calc {
	html              bool
	base              int
	base_index_of_gap int
	shift             int
	fixed             int
}

fn (d &Document) html_calc(base int, shift int) Calc {
	return Calc{
		html:              true
		base:              base
		base_index_of_gap: if base == 0 { 0 } else { sorted_last_index(d.gaps, base) }
		shift:             shift
	}
}

fn offset_calc(offset int) Calc {
	return Calc{
		fixed: offset
	}
}

// sub_after is getSubCalculatorAfter (its base plus a decoded index, as the original does).
fn (d &Document) sub_after(c Calc, offset int) Calc {
	return d.html_calc(c.base + offset, c.shift)
}

// sub_shift is getSubCalculatorShift.
fn (d &Document) sub_shift(c Calc, offset int) Calc {
	return d.html_calc(c.base, c.shift + offset)
}

fn (d &Document) get_gap(c Calc, index int) int {
	gaps := d.gaps
	mut g0 := sorted_last_index(gaps, index + c.base)
	mut pos := index + c.base + g0 - c.base_index_of_gap
	for g0 < gaps.len && gaps[g0] <= pos {
		g0++
		pos++
	}
	return g0 - c.base_index_of_gap
}

// fix_offset is getFixOffset.
fn (d &Document) fix_offset(c Calc, offset int) int {
	if !c.html {
		return c.fixed
	}
	return c.base + d.get_gap(c, offset + c.shift) + c.shift
}

// offset_with_gap is getOffsetWithGap: the UTF-16 offset of the file of an index.
fn (d &Document) offset_with_gap(c Calc, index int) int {
	return index + d.fix_offset(c, index)
}

// offsets_with_gap is offset_with_gap of every index from 0 to `count`, in one pass over the
// gaps (the indexes grow, so does the first gap past them).
fn (d &Document) offsets_with_gap(c Calc, count int) []int {
	mut out := []int{len: count + 1}
	if !c.html {
		for i in 0 .. count + 1 {
			out[i] = i + c.fixed
		}
		return out
	}
	gaps := d.gaps
	mut first := sorted_last_index(gaps, c.shift + c.base)
	for i in 0 .. count + 1 {
		index := i + c.shift
		for first < gaps.len && gaps[first] <= index + c.base {
			first++
		}
		mut g0 := first
		mut pos := index + c.base + g0 - c.base_index_of_gap
		for g0 < gaps.len && gaps[g0] <= pos {
			g0++
			pos++
		}
		out[i] = i + c.base + (g0 - c.base_index_of_gap) + c.shift
	}
	return out
}
