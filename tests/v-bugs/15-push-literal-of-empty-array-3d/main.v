// V bug: pushing an array literal that holds an empty array of structs (`[[]Node{}]`) onto an
// array of arrays of arrays makes C that does not compile ("invalid initializer": the empty
// array is copied as if it were a Node). Found in perfectionist/sort-imports (P2), which starts a
// new run of partitions; `runs << [][]Node{len: 1}` works.
// expected: 2
struct Node {
	n int
}

fn main() {
	mut runs := [][][]Node{len: 1, init: [][]Node{len: 1}}
	runs << [[]Node{}]
	println(runs.len)
}
