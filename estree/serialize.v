module estree

import strings

// serialize writes the tree in the canonical text of the differential test (tools/oracle.mjs):
// per node a line `Type start-end`, then its properties sorted by name, one per line, with nested
// nodes indented. Strings are quoted with every character outside printable ASCII as `\uXXXX` of
// its UTF-16 units; numbers are the hexadecimal bits of the double.
pub fn (t &EsTree) serialize() string {
	mut b := strings.new_builder(t.nodes.len * 64)
	if t.root >= 0 {
		t.ser_node(mut b, t.root, '')
	}
	return b.str()
}

// sorted_keys gives the order of the properties by name (JavaScript's sort of the keys).
const sorted_keys = sort_keys()

fn sort_keys() []int {
	mut order := []int{len: key_names.len}
	mut names := []string{}
	for name in key_names {
		names << name
	}
	names.sort()
	for rank, name in names {
		order[key_names.index(name)] = rank
	}
	return order
}

fn (t &EsTree) ser_node(mut b strings.Builder, i int, ind string) {
	n := t.nodes[i]
	b.write_string('${ind}${n.typ.type_name()} ${n.start}-${n.end}\n')
	mut props := n.props.clone()
	props.sort_with_compare(fn (a &Prop, b &Prop) int {
		return sorted_keys[int(a.key)] - sorted_keys[int(b.key)]
	})
	for p in props {
		t.ser_prop(mut b, p, ind)
	}
}

fn (t &EsTree) ser_prop(mut b strings.Builder, p Prop, ind string) {
	name := p.key.key_name()
	match p.kind {
		.node {
			b.write_string('${ind} .${name}:\n')
			t.ser_node(mut b, p.idx, ind + '  ')
		}
		.list {
			items := t.lists[p.idx]
			b.write_string('${ind} .${name}[${items.len}]\n')
			for item in items {
				if item < 0 {
					b.write_string('${ind}  null\n')
				} else {
					t.ser_node(mut b, item, ind + '  ')
				}
			}
		}
		.regex {
			b.write_string('${ind} .${name}{}\n')
			b.write_string('${ind}   .flags=${quote(p.str2)}\n')
			b.write_string('${ind}   .pattern=${quote(p.str)}\n')
		}
		.template {
			b.write_string('${ind} .${name}{}\n')
			cooked := if p.b { 'null' } else { quote(p.str) }
			b.write_string('${ind}   .cooked=${cooked}\n')
			b.write_string('${ind}   .raw=${quote(p.str2)}\n')
		}
		else {
			b.write_string('${ind} .${name}=${scalar(p)}\n')
		}
	}
}

fn scalar(p Prop) string {
	return match p.kind {
		.null { 'null' }
		.bool {
			if p.b { 'true' } else { 'false' }
		}
		.number { 'num(${u64_hex(math_f64_bits(p.num))})' }
		.string { quote(p.str) }
		.bigint { 'bigint(${p.str})' }
		.regexp { 'RegExp' }
		else { '?' }
	}
}

fn math_f64_bits(f f64) u64 {
	return unsafe { *(&u64(&f)) }
}

fn u64_hex(v u64) string {
	s := v.hex()
	return '0'.repeat(16 - s.len) + s
}

// quote writes a JavaScript string as the oracle does.
pub fn quote(s string) string {
	mut b := strings.new_builder(s.len + 2)
	b.write_u8(`"`)
	for unit in utf16_units(s) {
		if unit == `"` {
			b.write_string('\\"')
		} else if unit == `\\` {
			b.write_string('\\\\')
		} else if unit >= 0x20 && unit < 0x7f {
			b.write_u8(u8(unit))
		} else {
			h := unit.hex()
			b.write_string('\\u' + '0'.repeat(4 - h.len) + h)
		}
	}
	b.write_u8(`"`)
	return b.str()
}
