// V bug: checker: `fn dump/sizeof/typeof/isreftype` can be declared, but calls parse as the builtin; reject the declaration
// Reported in vlang/v#29648.
// expected-error: cannot redefine builtin function `dump`

fn dump(a int, b int) {
	println(a + b)
}

fn main() {
	dump(1, 2)
}
