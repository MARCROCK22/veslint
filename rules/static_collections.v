module rules

// Map, Set, their iterators and the functions of Object for static_value.v: the functions of
// eslint-utils' callAllowed that build or read them (`new Map(…)`, `new Set(…)`, their `get`,
// `has`, `keys`, `values` and `entries`, the `keys`, `values` and `entries` of an array,
// `Object.keys`, `values` and `entries`, `Object(…)`). No function of callAllowed changes a Map
// or a Set, so their values are never mutated here (a `map.set(…)` in the code is not a mutation
// for eslint-utils' hasMutationInProperty either).

// The own properties of Map.prototype and Set.prototype with a string key (Node 26), without
// `size`, which is a getter.
const stv_map_methods = ['constructor', 'get', 'set', 'has', 'delete', 'clear', 'entries', 'forEach',
	'keys', 'values', 'getOrInsert', 'getOrInsertComputed']
const stv_set_methods = ['constructor', 'has', 'add', 'delete', 'difference', 'clear', 'entries',
	'forEach', 'intersection', 'isSubsetOf', 'isSupersetOf', 'isDisjointFrom', 'symmetricDifference',
	'union', 'values', 'keys']

fn (mut ctx StvContext) new_array(elements []JsAny) JsAny {
	return JsAny{
		kind:     .array_
		id:       ctx.new_id()
		elements: elements
	}
}

// new_iterator is an iterator that has `elements` left: `tag` is its @@toStringTag.
fn (mut ctx StvContext) new_iterator(tag string, elements []JsAny) JsAny {
	return JsAny{
		kind:     .iterator_
		id:       ctx.new_id()
		name:     tag
		elements: elements
	}
}

// stv_collection_key is a key as a Map or a Set stores it: -0 is +0.
fn stv_collection_key(v JsAny) JsAny {
	if v.kind == .hole_ {
		return js_any_undefined()
	}
	return if v.kind == .number_ && v.number == 0 { js_any_number(0) } else { v }
}

// stv_collection_index finds a key in a Map or a Set (SameValueZero); -1 without it.
fn stv_collection_index(keys []JsAny, key JsAny) int {
	for i, k in keys {
		if stv_same_value_zero(k, key) {
			return i
		}
	}
	return -1
}

// stv_collection_construct ports `new Map(iterable)` and `new Set(iterable)`: empty for undefined
// and null; otherwise the iterable gives the values of a Set, or the entries of a Map, each an
// object whose `0` and `1` are the key and the value. none: the argument is not iterable or an
// entry is not an object (a TypeError), or veslint does not iterate it.
fn stv_collection_construct(is_map bool, args []JsAny, mut ctx StvContext) ?JsAny {
	mut keys := []JsAny{}
	mut values := []JsAny{}
	if args.len > 0 && !stv_is_nullish(args[0]) {
		for item in stv_iterate(args[0], mut ctx)? {
			if !is_map {
				key := stv_collection_key(item)
				if stv_collection_index(keys, key) < 0 {
					keys << key
				}
				continue
			}
			if !stv_is_object(item) {
				return none
			}
			key := stv_collection_key(stv_get(item, js_any_text('0'))?)
			value := stv_get(item, js_any_text('1'))?
			i := stv_collection_index(keys, key)
			if i >= 0 {
				values[i] = value
			} else {
				keys << key
				values << value
			}
		}
	}
	return JsAny{
		kind:     if is_map { .map_ } else { .set_ }
		id:       ctx.new_id()
		elements: keys
		values:   values
	}
}

// stv_collection_method calls a method of Map.prototype or Set.prototype of callAllowed on
// `this`, which must be a Map or a Set (a TypeError otherwise).
fn stv_collection_method(name string, this JsAny, args []JsAny, mut ctx StvContext) ?JsAny {
	key := if args.len > 0 { args[0] } else { js_any_undefined() }
	if name.starts_with('Map.') {
		if this.kind != .map_ {
			return none
		}
		match name {
			'Map.prototype.get' {
				i := stv_collection_index(this.elements, key)
				return if i >= 0 { this.values[i] } else { js_any_undefined() }
			}
			'Map.prototype.has' {
				return js_any_bool(stv_collection_index(this.elements, key) >= 0)
			}
			'Map.prototype.keys' {
				return ctx.new_iterator('Map Iterator', this.elements)
			}
			'Map.prototype.values' {
				return ctx.new_iterator('Map Iterator', this.values)
			}
			'Map.prototype.entries' {
				return ctx.new_iterator('Map Iterator', stv_iterate(this, mut ctx)?)
			}
			else {
				return none
			}
		}
	}
	if this.kind != .set_ {
		return none
	}
	match name {
		'Set.prototype.has' {
			return js_any_bool(stv_collection_index(this.elements, key) >= 0)
		}
		'Set.prototype.values' {
			return ctx.new_iterator('Set Iterator', this.elements)
		}
		'Set.prototype.entries' {
			mut entries := []JsAny{cap: this.elements.len}
			for value in this.elements {
				entries << ctx.new_array([value, value])
			}
			return ctx.new_iterator('Set Iterator', entries)
		}
		else {
			return none
		}
	}
}

// stv_own_enumerable gives the own enumerable properties with a string key of ToObject(value),
// in order: the elements of an array (not its holes), the units of a string and the properties
// of a plain object. No other value of static_value.v has one: a RegExp, a Map, a Set, an
// iterator, the builtin functions and namespaces (no property of theirs is enumerable in Node)
// and the objects of the other primitives. none (a TypeError) for undefined and null.
fn stv_own_enumerable(target JsAny) ?([]string, []JsAny) {
	mut keys := []string{}
	mut values := []JsAny{}
	match target.kind {
		.undefined_, .null_, .hole_ {
			return none
		}
		.array_ {
			for i, e in target.elements {
				if e.kind != .hole_ {
					keys << i.str()
					values << e
				}
			}
		}
		.string_ {
			for i, u in target.units {
				keys << i.str()
				values << js_any_string([u])
			}
		}
		.object_ {
			keys << target.keys
			values << target.values
		}
		.wrapper_ {
			return stv_own_enumerable(target.elements[0])
		}
		else {}
	}
	return keys, values
}

// stv_object_call ports Object(value) and `new Object(value)`: a new object for undefined and
// null, the value itself if it is an object, and the object of a primitive.
fn stv_object_call(args []JsAny, mut ctx StvContext) ?JsAny {
	if args.len == 0 || stv_is_nullish(args[0]) {
		return JsAny{
			kind: .object_
			id:   ctx.new_id()
		}
	}
	if stv_is_object(args[0]) {
		return args[0]
	}
	return JsAny{
		kind:     .wrapper_
		id:       ctx.new_id()
		elements: [args[0]]
	}
}
