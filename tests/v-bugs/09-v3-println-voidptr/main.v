// V bug: V3: `println(p)` of a voidptr prints `2a`, while `p.str()` and the stable compiler print `0x2a`
// Reported in vlang/v#29761. (Both compilers print `2a` for '${p}'; that part may be intended.)
// expected: 0x2a
// expected: 0x2a

fn main() {
	p := voidptr(u64(42))
	println(p)
	println(p.str())
}
