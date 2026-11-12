module rules

import tsgo { TypeResponse }

// Port of isTypeReadonly and isTypeBrandedLiteralLike from typescript-eslint's type-utils 8.62.0.
//
// For a conditional type the original looks at the types of the two branches as they are written
// in its declaration (getTypeFromTypeNode of root.node.trueType and falseType). The tsgo API has
// no `root` (microsoft/TypeScript#64740): it gives the branches of the type itself, which are
// those with its type arguments applied, and they differ when a branch is a type parameter of the
// declaration that the use replaces with an object type while the condition stays unresolved.
// The declaration is looked for instead (conditional_declared_readonlyness, with type_sources.v):
// from the alias of the type or from where the walk got the type (the annotation of the
// parameter, the declaration of a property or of an index signature, an element of an array or
// tuple type). It is not found for a type that comes from an expression (a parameter without an
// annotation) or through a type veslint does not follow (an indexed access, a `typeof`, what an
// `infer` gives): the branches of the type itself are looked at then.

enum Readonlyness {
	unknown_type // the type cannot be handled by the function
	mutable
	readonly
}

struct ReadonlynessOptions {
	allow                     []TypeSpecifier
	treat_methods_as_readonly bool
}

struct ReadonlynessState {
mut:
	seen    map[int]bool
	cache   NutaCache
	sources SourceState
}

const type_flag_string = u32(32)
const type_flag_bigint = u32(128)
const type_flag_template_literal = u32(4194304)
const type_flag_conditional = u32(67108864)

// The original recurses without a limit and overflows the stack on a type that contains itself
// through its type arguments; here such a type is not looked into past this depth.
const readonlyness_max_depth = 200

// is_type_readonly ports isTypeReadonly. `annotation` is the handle of the type node the type is
// that of ('' if it is not that of a type node).
fn (mut c Checker) is_type_readonly(t TypeResponse, options ReadonlynessOptions, annotation string) !bool {
	mut state := ReadonlynessState{
		sources: new_source_state()
	}
	origin := state.sources.source_origin(annotation)
	return c.type_readonlyness(t, options, mut state, 0, origin)! == .readonly
}

// readonlyness_seen_or_readonly: `seenTypes.has(t) || isTypeReadonlyRecurser(…) === Readonly`.
fn (mut c Checker) readonlyness_seen_or_readonly(t TypeResponse, options ReadonlynessOptions, mut state ReadonlynessState, depth int, origin int) !bool {
	return state.seen[t.id]
		|| c.type_readonlyness(t, options, mut state, depth, origin)! == .readonly
}

// type_readonlyness ports isTypeReadonlyRecurser. `origin` is where the type comes from
// (ReadonlynessState.sources.origins), for the declaration of a conditional type.
fn (mut c Checker) type_readonlyness(t TypeResponse, options ReadonlynessOptions, mut state ReadonlynessState, depth int, origin int) !Readonlyness {
	state.seen[t.id] = true
	if depth > readonlyness_max_depth {
		return .readonly
	}
	if t.alias_symbol != 0 {
		alias := c.alias_symbol_of(t)!
		for specifier in options.allow {
			if alias.name in specifier.names {
				return .readonly
			}
		}
	}
	if c.type_matches_some_specifier(t, options.allow)! {
		return .readonly
	}
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if !c.readonlyness_seen_or_readonly(part, options, mut state, depth + 1, origin)! {
				return .mutable
			}
		}
		return .readonly
	}
	if t.flags & type_flag_intersection != 0 {
		parts := c.members_of(t)!
		mut has_array := false
		for part in parts {
			if c.is_array(part)! || c.is_tuple(part)! {
				has_array = true
				break
			}
		}
		if has_array {
			for part in parts {
				if !c.readonlyness_seen_or_readonly(part, options, mut state, depth + 1,
					origin)! {
					return .mutable
				}
			}
			return .readonly
		}
		return c.object_readonlyness(t, options, mut state, depth, origin)!
	}
	if t.flags & type_flag_conditional != 0 {
		declared := c.conditional_declared_readonlyness(t, options, mut state, depth,
			origin)!
		if declared != .unknown_type {
			return declared
		}
		branches := [
			c.client.true_type_of_conditional(c.snapshot, c.project, t.id)!,
			c.client.false_type_of_conditional(c.snapshot, c.project, t.id)!,
		]
		for branch in branches {
			if branch.is_null() {
				continue
			}
			if !c.readonlyness_seen_or_readonly(branch, options, mut state, depth + 1,
				0)! {
				return .mutable
			}
		}
		return .readonly
	}
	if t.flags & type_flag_object == 0 {
		return .readonly
	}
	if c.signatures_of(t, signature_kind_call)!.len > 0 && c.properties(t)!.len == 0 {
		return .readonly
	}
	array := c.array_or_tuple_readonlyness(t, options, mut state, depth, origin)!
	if array != .unknown_type {
		return array
	}
	return c.object_readonlyness(t, options, mut state, depth, origin)!
}

const syntax_kind_conditional_type = u32(196)
const syntax_kind_parenthesized_type = u32(198)

// TypeFlags of the types that are the same whatever the type arguments: the primitives, their
// literals and the other types without parts.
const type_flags_without_parts = u32(1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024 | 2048 | 4096 | 8192 | 16384 | 32768 | 65536 | 131072 | 262144)

// conditional_declared_readonlyness is what the original answers for a conditional type, from the
// branches as declared, when its declaration is known for certain; unknown_type otherwise.
//
// TypeScript does not always give a conditional type the node it was asked from as its root: when
// the condition is decided it goes on with the conditional type in the branch taken. So the root
// is one of the conditional type nodes the type may come from (conditional_root_nodes). The
// answer is certain when all of them give the same one.
fn (mut c Checker) conditional_declared_readonlyness(t TypeResponse, options ReadonlynessOptions, mut state ReadonlynessState, depth int, origin int) !Readonlyness {
	nodes := c.conditional_root_nodes(t, origin, mut state.sources)!
	if nodes.len == 0 {
		return .unknown_type
	}
	seen := state.seen.clone()
	mut results := []Readonlyness{}
	mut seen_after := []map[int]bool{}
	for node in nodes {
		tree := c.declaration_ast(tsgo.handle_path(node))!
		state.seen = seen.clone()
		mut result := Readonlyness.readonly
		for property in ['trueType', 'falseType'] {
			handle := tree.node_handle(tree.node_child(tsgo.handle_index(node), property))
			branch := c.type_from_type_node(handle)!
			if branch.is_null() {
				state.seen = seen.clone()
				return .unknown_type
			}
			if !state.seen[branch.id]
				&& c.type_readonlyness(branch, options, mut state, depth + 1, state.sources.source_origin(handle))! == .mutable {
				result = .mutable
				break
			}
		}
		results << result
		seen_after << state.seen.clone()
	}
	if !results.all(it == results[0]) {
		state.seen = seen.clone()
		return .unknown_type
	}
	state.seen = seen_after[0].clone()
	if results[0] == .readonly {
		// Everything the candidates looked at is readonly.
		for other in seen_after {
			for id, _ in other {
				state.seen[id] = true
			}
		}
	}
	return results[0]
}

const symbol_flag_alias = u32(2097152)
const syntax_kind_qualified_name = u32(168)

// type_from_type_node ports checker.getTypeFromTypeNode for a node of a declaration.
fn (mut c Checker) type_from_type_node(handle string) !TypeResponse {
	if handle !in c.type_node_cache {
		c.type_node_cache[handle] = c.client.type_from_type_node(c.snapshot, c.project,
			handle)!
	}
	return c.type_node_cache[handle]
}

// array_or_tuple_readonlyness ports isTypeReadonlyArrayOrTuple.
fn (mut c Checker) array_or_tuple_readonlyness(t TypeResponse, options ReadonlynessOptions, mut state ReadonlynessState, depth int, origin int) !Readonlyness {
	if c.is_array(t)! {
		symbol := c.symbol_of(t)!
		if symbol.name == 'Array' {
			return .mutable
		}
	} else if c.is_tuple(t)! {
		if !c.target_of(t)!.readonly {
			return .mutable
		}
	} else {
		return .unknown_type
	}
	// checkTypeArguments
	for position, argument in c.type_args(t)! {
		element := if origin == 0 {
			0
		} else {
			state.sources.new_origin(TypeOrigin{
				kind:     .element
				parent:   origin
				owner:    t
				position: position
			})
		}
		if c.type_readonlyness(argument, options, mut state, depth + 1, element)! == .mutable {
			return .mutable
		}
	}
	return .readonly
}

// readonlyness_is_method: the declaration (a tsgo node handle) declares a method, so its symbol
// has SymbolFlags.Method.
fn readonlyness_is_method(declaration string) bool {
	return declaration != ''
		&& tsgo.handle_kind(declaration) in [syntax_kind_method_declaration,
			syntax_kind_method_signature]
}

// object_readonlyness ports isTypeReadonlyObject.
fn (mut c Checker) object_readonlyness(t TypeResponse, options ReadonlynessOptions, mut state ReadonlynessState, depth int, origin int) !Readonlyness {
	if origin != 0 && t.alias_symbol == 0 && t.flags & type_flag_object != 0
		&& t.object_flags & object_flag_mapped != 0
		&& t.object_flags & source_object_flag_instantiated != 0 {
		// An instance of a mapped type without an alias: where the type comes from may tell what
		// it maps over, for the readonly properties below.
		c.mapped_parts_from(t, origin, mut state.sources)!
	}
	properties := c.properties(t)!
	for property in properties {
		if options.treat_methods_as_readonly {
			if readonlyness_is_method(property.value_declaration) {
				continue
			}
			if property.declarations.len > 0 && readonlyness_is_method(property.declarations.last()) {
				continue
			}
		}
		if c.nuta_readonly_in_type(t, property.name, mut state.cache, 0)! {
			continue
		}
		// A private identifier (`#name`), whose symbol has a name of its own.
		if property.name.starts_with('__#') {
			continue
		}
		return .mutable
	}
	for property in properties {
		// getTypeOfPropertyOfType: for a symbol-named property the original asks for the declared
		// type of the property symbol, which is the error type and so never mutable.
		if property.name.starts_with('__@') {
			continue
		}
		property_type := c.symbol_type(property.id)!
		if state.seen[property_type.id] {
			continue
		}
		member := state.sources.new_origin(TypeOrigin{
			kind:     .property
			parent:   origin
			owner:    t
			property: property
		})
		if c.type_readonlyness(property_type, options, mut state, depth + 1, member)! == .mutable {
			return .mutable
		}
	}
	infos := c.index_infos(t.id)!
	// checkIndexSignature(ts.IndexKind.String), then Number.
	for key_flag in [type_flag_string, type_flag_number] {
		for info in infos {
			if info.key_type.flags != key_flag {
				continue
			}
			if !info.is_readonly {
				return .mutable
			}
			if info.value_type.id == t.id || state.seen[info.value_type.id] {
				break
			}
			value := state.sources.new_origin(TypeOrigin{
				kind:        .index_value
				parent:      origin
				owner:       t
				declaration: info.declaration
			})
			if c.type_readonlyness(info.value_type, options, mut state, depth + 1, value)! == .mutable {
				return .mutable
			}
			break
		}
	}
	return .readonly
}

// is_type_branded_literal_like ports isTypeBrandedLiteralLike: an intersection of primitives and
// object types without signatures (`string & { __brand: 'id' }`), or a union of such.
fn (mut c Checker) is_type_branded_literal_like(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if !c.is_type_branded_literal(part)! {
				return false
			}
		}
		return true
	}
	return c.is_type_branded_literal(t)!
}

fn (mut c Checker) is_type_branded_literal(t TypeResponse) !bool {
	if t.flags & type_flag_intersection == 0 {
		return false
	}
	mut had_object := false
	mut had_primitive := false
	for part in c.members_of(t)! {
		if part.flags & type_flag_object != 0 && c.signatures_of(part, signature_kind_call)!.len == 0
			&& c.signatures_of(part, signature_kind_construct)!.len == 0 {
			had_object = true
		} else if part.flags & (type_flag_literal_value | type_flag_bigint | type_flag_number | type_flag_string | type_flag_template_literal) != 0 {
			had_primitive = true
		} else {
			return false
		}
	}
	return had_object && had_primitive
}
