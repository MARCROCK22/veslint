// V bug: a call of a local closure (`blank := fn (…) {…}; blank(1, 2, mut out)`) is compiled as a
// call of the private function of the same name of another module of the program (`a.blank`), so
// the C does not compile ("invalid initializer", "incompatible type for argument 2 of 'blank'").
// Found when module svelte (a closure `blank` in svelte/blocks.v) and module vue (`fn blank` in
// vue/script.v) were first imported by the same program.
// expected: x
// expected: 1
module main

import a

fn main() {
	println(a.use_a())
	mut out := []u8{}
	blank := fn (from int, to int, mut out []u8) {
		out << u8(from + to)
	}
	blank(1, 2, mut out)
	println(out.len)
}
