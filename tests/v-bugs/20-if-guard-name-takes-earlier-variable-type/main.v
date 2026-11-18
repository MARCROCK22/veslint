// V bug: an if-guard variable of an `if` expression (`n := if h := m['a'] { h } else { … }`)
// takes the type of a variable of the same name declared earlier in a block that has ended (`h`, a
// string, in the `for`), so the C of the `if`'s value is a string assigned an int (C does not
// compile). Found in svelte_compiler/a11y.v (`href := if h := attribute_map['href'] { h } …`).
// expected: x!
// expected: 2
fn main() {
	m := {
		'b': 2
	}
	for k in ['x'] {
		h := k + '!'
		println(h)
	}
	n := if h := m['a'] {
		h
	} else {
		m['b'] or { -1 }
	}
	println(n)
}
