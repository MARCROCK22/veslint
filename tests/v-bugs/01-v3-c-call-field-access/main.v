// V bug: v3: `C.fn(args).field` on a struct returned by value compiles to a pointer cast `((fn*)args)->field`
// Reported in vlang/v#29629.
// expected: 6

#flag -I @DIR
#include "pt.h"

@[typedef]
struct C.Pt {
	row    u32
	column u32
}

fn C.get_pt(x int) C.Pt

fn main() {
	row := int(C.get_pt(5).row) + 1
	println(row)
}
