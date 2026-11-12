module rules

import tsgo { TypeResponse }

// checker.getAwaitedType, asked to tsgo (TypeScript 7.1 has it in its API; up to 7.0.2 veslint
// ported it from the checker, with three cases the API did not let decide).

// AwaitedType is the answer of checker.getAwaitedType.
struct AwaitedType {
	found bool // false: TypeScript gives no awaited type (undefined)
	typ   TypeResponse
}

fn (mut c Checker) awaited_type(t TypeResponse) !AwaitedType {
	if cached := c.awaited[t.id] {
		return cached
	}
	awaited := c.client.awaited_type(c.snapshot, c.project, t.id)!
	result := AwaitedType{
		found: !awaited.is_null()
		typ:   awaited
	}
	c.awaited[t.id] = result
	return result
}

// awaited_flags are the TypeFlags of an awaited type, those of all the members of a union
// (getTypeFlags of typescript-eslint's type-utils); 0 when there is none.
fn (mut c Checker) awaited_flags(a AwaitedType) !u32 {
	return if a.found { c.type_flags(a.typ)! } else { u32(0) }
}

// awaited_same tells whether two awaited types are the same type (`===`); two that TypeScript
// does not give are both undefined.
fn (mut c Checker) awaited_same(a AwaitedType, b AwaitedType) !bool {
	return a.found == b.found && (!a.found || a.typ.id == b.typ.id)
}
