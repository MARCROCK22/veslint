module svelte

// Offset maps between the file, the pre-virtual code and the virtual code (spec §8.2.2–§8.2.4):
// what veslint needs to give tsgo the virtual code as the .svelte file's content and to map
// positions both ways. File offsets are bytes; virtual and pre_u16 offsets are UTF-16 (what
// TypeScript reports).

// virtual_to_pre is RestoreContext's offset table applied to a virtual position (`end`: the
// position ends a range): a position inside an inserted fragment moves to its edge (the end
// of the fragment for a start, its start for an end).
pub fn (d &Document) virtual_to_pre(pos int, end bool) int {
	mut p := pos
	for f in d.virtual_fragments {
		if !end && f.start <= p && p < f.end {
			p = f.end
			break
		}
		if end && f.start < p && p <= f.end {
			p = f.start
			break
		}
	}
	mut best := -1
	for k, o in d.virtual_offsets {
		if (!end && o.dist <= p) || (end && o.dist < p) {
			best = k
		} else {
			break
		}
	}
	if best < 0 {
		return p
	}
	o := d.virtual_offsets[best]
	return o.original + (p - o.dist)
}

// pre_u16_to_file maps a UTF-16 offset of pre_u16 to a byte offset of the file: the script part
// is at file positions, the template expressions through their segments; -1 elsewhere (code
// svelte-eslint-parser made up: wrappers, typings, declarations).
pub fn (d &Document) pre_u16_to_file(u int) int {
	sep16 := if d.separator >= 0 { d.utf16(d.separator) } else { d.index.u16_len + 1 }
	if u < sep16 {
		return d.byte_offset(u)
	}
	for s in d.segments {
		a := pre_u16_offset(d, s.pre_start)
		b := pre_u16_offset(d, s.pre_start + s.len)
		if a <= u && u <= b {
			// Inside a copied piece: the same characters as the file's.
			piece := d.src[s.file_start..s.file_start + s.len]
			return s.file_start + u16_byte_offset(piece, u - a)
		}
	}
	return -1
}

// virtual_to_file maps a UTF-16 offset of the virtual code (a TypeScript position) to a byte
// offset of the file, or -1 for code that is not in the file.
pub fn (d &Document) virtual_to_file(pos int, end bool) int {
	return d.pre_u16_to_file(d.virtual_to_pre(pos, end))
}

// file_to_virtual maps a byte offset of the file to a UTF-16 offset of the virtual code (where
// TypeScript sees that character), or -1 when the file's character is not in it (markup).
pub fn (d &Document) file_to_virtual(offset int) int {
	mut pre16 := -1
	if d.separator < 0 || offset < d.separator {
		// The script part: script contents are at the same place (markup is blank in pre).
		if offset >= 0 && offset < d.pre.len && offset < d.src.len && d.pre[offset] == d.src[offset] {
			pre16 = d.utf16(offset)
		}
	}
	if pre16 < 0 {
		for s in d.segments {
			if s.file_start <= offset && offset <= s.file_start + s.len {
				pre16 = pre_u16_offset(d, s.pre_start + (offset - s.file_start))
				break
			}
		}
	}
	if pre16 < 0 {
		return -1
	}
	// The inverse of the offset table: the last entry whose original part holds pre16.
	for k := d.virtual_offsets.len - 1; k >= 0; k-- {
		o := d.virtual_offsets[k]
		if o.original <= pre16 {
			next_dist := if k + 1 < d.virtual_offsets.len {
				d.virtual_offsets[k + 1].dist
			} else {
				u16_len_of(d.virtual_code)
			}
			// The copied length of that entry: up to the next fragment or entry.
			mut copied_end := next_dist
			for f in d.virtual_fragments {
				if f.start >= o.dist && f.start < copied_end {
					copied_end = f.start
					break
				}
			}
			if o.dist + (pre16 - o.original) <= copied_end {
				return o.dist + (pre16 - o.original)
			}
			return -1
		}
	}
	return pre16
}
