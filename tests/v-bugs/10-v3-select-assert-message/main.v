// V bug: V3: an `assert` message that prints an array or a struct declared in a `select` branch does not compile in C (`y` undeclared)
// Reported in vlang/v#30194. The statements that build the string of the message are emitted before the `select`.
// Found in VLS's tests, 2026-10-11, with the variable that a branch receives; still there with master 81be246.
// expected: ok

fn main() {
	select {
		else {
			y := [1]
			assert true, y.str()
			println('ok')
		}
	}
}
