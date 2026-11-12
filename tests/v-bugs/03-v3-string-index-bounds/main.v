// V bug: v3: string indexing `s[i]` has no bounds check (reads out of bounds instead of panicking)
// Reported in vlang/v#29622.
// expected-error: string index out of range(idx,s.len):100000, 3

fn get(s string, i int) u8 {
	return s[i]
}

fn main() {
	println(get('abc', 100000))
	println('no panic')
}
