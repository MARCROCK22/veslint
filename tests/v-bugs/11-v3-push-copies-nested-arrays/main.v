// V bug: V3: `a << x` copies in depth the arrays inside the struct `x`, while `[x]`, `a << [x]` and the established compiler share them
// Reported in vlang/v#30463. The copy costs the size of the whole value at every push; found profiling
// veslint's constant evaluation (rules/static_value.v), where a nested value was copied at each level.
// expected: array literal shares the nested array: true
// expected: push of one element shares it: true
// expected: push of an array shares it: true

struct Node {
mut:
	kids []Node
	n    int
}

fn main() {
	mut inner := Node{
		kids: [Node{
			n: 1
		}]
	}
	literal := [inner]
	mut pushed := []Node{}
	pushed << inner
	mut pushed_many := []Node{}
	pushed_many << [inner]
	inner.kids[0].n = 2
	println('array literal shares the nested array: ${literal[0].kids[0].n == 2}')
	println('push of one element shares it: ${pushed[0].kids[0].n == 2}')
	println('push of an array shares it: ${pushed_many[0].kids[0].n == 2}')
}
