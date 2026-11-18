// V bug: an enum value written with the shorthand (`.a`) on the left of `in`/`!in` an array of
// that enum is not inferred from the array ("left operand to `in` does not match the array element
// type: expected `Kind`, not `int`"), though `.a == x` and `x in [.a, .b]` are. Found in
// svelte/require-event-prefix (`.other !in kinds`).
// expected: true
// expected: false
enum Kind {
	a
	b
}

fn main() {
	kinds := [Kind.a]
	println(.a in kinds)
	println(.b in kinds)
}
