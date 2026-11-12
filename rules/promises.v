module rules

import tsgo { TypeResponse, handle_path }

// Promise helpers shared by the rules (port of isPromiseLike/isBuiltinSymbolLike).

// promise_like_type ports isPromiseLike with checkThenables: false: some part of the union (on the
// apparent type) is the native Promise or a class or interface that extends it.
fn (mut c Checker) promise_like_type(t TypeResponse) !bool {
	if t.is_null() {
		return false
	}
	if t.id in c.promise_cache {
		return c.promise_cache[t.id]
	}
	mut result := false
	for part in c.constituents(c.apparent_of(t)!)! {
		if c.builtin_promise(part, 0)! {
			result = true
			break
		}
	}
	c.promise_cache[t.id] = result
	return result
}

// builtin_promise ports isBuiltinSymbolLike(…, 'Promise').
fn (mut c Checker) builtin_promise(t TypeResponse, depth int) !bool {
	return c.builtin_symbol_like(t, 'Promise', depth)!
}

// builtin_symbol_like ports isBuiltinSymbolLike(program, type, name) of type-utils.
fn (mut c Checker) builtin_symbol_like(t TypeResponse, name string, depth int) !bool {
	return c.builtin_symbol_like_any(t, [name], depth)!
}

// builtin_symbol_like_any ports isBuiltinSymbolLike with a list of names: the symbol of the type
// has one of the names and a declaration in a default library (isSymbolFromDefaultLibrary), or it
// is a class or interface one of whose base types is such a type; for intersections one part is
// enough, for unions all are needed (so `Map<K, V> | WeakMap<K, V>` matches both names), and for a
// type parameter its constraint counts.
fn (mut c Checker) builtin_symbol_like_any(t TypeResponse, names []string, depth int) !bool {
	if depth > max_type_depth || t.is_null() {
		return false
	}
	if t.flags & type_flag_intersection != 0 {
		for member in c.members_of(t)! {
			if c.builtin_symbol_like_any(member, names, depth + 1)! {
				return true
			}
		}
		return false
	}
	if t.flags & type_flag_union != 0 {
		members := c.members_of(t)!
		for member in members {
			if !c.builtin_symbol_like_any(member, names, depth + 1)! {
				return false
			}
		}
		return members.len > 0
	}
	if t.flags & type_flag_type_parameter != 0 {
		return c.builtin_symbol_like_any(c.constraint_of(t)!, names, depth + 1)!
	}
	key := '${t.id}:${names.join(',')}'
	if cached := c.builtin_cache[key] {
		return cached
	}
	symbol := c.symbol_of(t)!
	mut result := false
	if !symbol.is_null() {
		if symbol.name in names && c.from_default_library(symbol.declarations)! {
			result = true
		} else if symbol.flags & (symbol_flag_class | symbol_flag_interface) != 0 {
			for base in c.bases_of(symbol.id)! {
				if c.builtin_symbol_like_any(base, names, depth + 1)! {
					result = true
					break
				}
			}
		}
	}
	c.builtin_cache[key] = result
	return result
}

// from_default_library ports isSymbolFromDefaultLibrary: one of the declarations is in a default
// library file (program.isSourceFileDefaultLibrary).
fn (mut c Checker) from_default_library(declarations []string) !bool {
	for declaration in declarations {
		if c.is_default_library(handle_path(declaration))! {
			return true
		}
	}
	return false
}
