// V bug: the value of an `or {}` block may be an option of a C struct (`?C.tm` where `C.tm` is
// expected): the checker lets it through and the C compilation fails ("incompatible types when
// assigning to type 'struct tm' from type '__v_option_struct_tm'"). With a V struct the checker
// reports it. Found writing `node_field(clause, 'value') or { first_named(clause) }` in veslint
// (rules/class_members.v), where both give a ?C.TSNode.
// expected-error: `or` block must provide a value of type
#include <time.h>

struct C.tm {
	tm_sec int
}

fn first(items []C.tm) ?C.tm {
	if items.len == 0 {
		return none
	}
	return items[0]
}

fn pick(a []C.tm, b []C.tm) ?C.tm {
	return first(a) or { first(b) }
}

fn main() {
	t := pick([], [C.tm{
		tm_sec: 2
	}]) or { C.tm{} }
	println(t.tm_sec)
}
