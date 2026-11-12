// V bug: v3: a user struct named `T` collides with json2's type parameter: `json2.decode[[]T]` fails inside vlib/json2/decode.v
// Reported in vlang/v#29633.
// expected: 1

import json2

struct T {
	id    int
	flags u32
	value json2.Any
}

fn main() {
	ts := json2.decode[[]T]('[{"id":1,"flags":2,"value":"ab"}]') or { panic(err) }
	println(ts.len)
}
