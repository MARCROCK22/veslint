module collation

// The order of strings of ICU's root collation, which Node's `a.localeCompare(b)` gives with its
// default locale (en-US, the same as the root: ICU 78.3, CLDR 48), at its default strength
// (tertiary), with variable characters not ignored: what eslint-plugin-perfectionist's alphabetical
// order (and natural-orderby, for what is not a number) compares with.
//
// The ASCII strings are compared here exactly (checked against Node on random strings): their
// primary weights (ascii_primary, from Node's base-strength order; 0 is a completely ignorable
// control character), then, at the tertiary level, the case (a lowercase letter or another
// character before an uppercase letter); ASCII has no secondary differences.
//
// TODO(collation): the Unicode Collation Algorithm with CLDR 48's root data (allkeys_CLDR.txt) for
// the other strings, which are compared by code points meanwhile.

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
	if is_ascii(a) && is_ascii(b) {
		return compare_ascii(a, b)
	}
	return compare_code_points(a, b)
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

// compare_code_points is the order of code points (provisional, see the TODO above).
fn compare_code_points(a string, b string) int {
	ra := a.runes()
	rb := b.runes()
	for k in 0 .. (if ra.len < rb.len { ra.len } else { rb.len }) {
		if ra[k] != rb[k] {
			return if ra[k] < rb[k] { -1 } else { 1 }
		}
	}
	return if ra.len == rb.len {
		0
	} else if ra.len < rb.len {
		-1
	} else {
		1
	}
}
