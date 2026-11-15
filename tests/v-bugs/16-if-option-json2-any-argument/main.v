// V bug: an `if` expression whose branches are `?json2.Any(...)` and `?json2.Any(none)`, given
// as an argument of type ?json2.Any, makes C that does not compile ("incompatible types when
// assigning to type json2__Any from type __v_option_json2__Any": the temporary of the `if` is
// declared as json2.Any). The same with a sum type of the program works. Found in
// perfectionist/sort-imports (P2): isSideEffectOnlyGroup(options.groups[groupIndex]).
// expected: true
import x.json2

fn truthy(group ?json2.Any) bool {
	value := group or { return false }
	return value is string
}

fn main() {
	groups := [json2.Any('a'), json2.Any(1)]
	index := 0
	println(truthy(if index < groups.len { ?json2.Any(groups[index]) } else { ?json2.Any(none) }))
}
