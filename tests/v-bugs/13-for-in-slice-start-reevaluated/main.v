// V bug: in `for x in a[b.len..]`, the start of the slice is evaluated again on every iteration,
// so a loop that appends to `b` skips elements of `a`: with a = [1, 2, 3] and b empty, b gets
// [1, 3]. The slice should be taken once, before the loop (as with a variable start). Found in
// veslint's effective_options (rules/options.v), which appended the options past the defaults
// this way and lost every other one (consistent-this with three aliases, no-restricted-imports
// with several paths).
// expected: [1, 2, 3]
// expected: [1, 2, 3]
fn main() {
	a := [1, 2, 3]
	mut b := []int{}
	for x in a[b.len..] {
		b << x
	}
	println(b)
	mut c := []int{}
	start := c.len
	for x in a[start..] {
		c << x
	}
	println(c)
}
