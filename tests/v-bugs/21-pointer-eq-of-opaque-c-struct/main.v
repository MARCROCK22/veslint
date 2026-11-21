// V bug: `==` between two pointers to a C struct whose layout V does not know (an opaque typedef,
// as tree-sitter's `TSLanguage`) compiles to a comparison of the structs they point to, which C
// rejects ("storage size of '__eq_rhs_…' isn't known"), instead of a comparison of the
// addresses. Comparing them as `voidptr` works. Found while trying a table of node kinds in
// treesitter/treesitter.v, which compared `&C.TSLanguage` pointers.
// expected: true
#include "@DIR/opaque.h"

@[typedef]
struct C.Opaque {}

fn C.opaque_get() &C.Opaque

fn main() {
	a := C.opaque_get()
	b := C.opaque_get()
	println(a == b)
}
