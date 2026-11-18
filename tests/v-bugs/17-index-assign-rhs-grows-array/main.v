// V bug: in `a[i].field = f()` where f appends to the same array `a`, the address of `a[i]` is
// taken before f runs; when the append reallocates the array, the value is written into the old
// buffer and is lost (JavaScript, and V's own `x := f(); a[i].field = x`, keep it). Found in
// svelte/convert.v (the attributes of a <script> start tag vanished).
// expected: 3
struct Node {
mut:
	attrs []int
}

struct Arena {
mut:
	nodes []Node
}

fn (mut a Arena) add_many() []int {
	mut out := []int{}
	for _ in 0 .. 3 {
		a.nodes << Node{}
		out << a.nodes.len - 1
	}
	return out
}

fn main() {
	mut a := Arena{}
	a.nodes << Node{}
	a.nodes[0].attrs = a.add_many()
	println(a.nodes[0].attrs.len)
}
