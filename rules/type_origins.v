module rules

import tsgo { SymbolResponse, TypeResponse }

// The sources of the types a walk reaches (type_sources.v): those of a property, of an index
// signature and of an element of an array or tuple type, from the type they are a part of.

// origin_sources are the sources of an origin; none when they are not known.
fn (mut c Checker) origin_sources(mut state SourceState, index int) ![]TypeSource {
	if index <= 0 || index >= state.origins.len {
		return []TypeSource{}
	}
	origin := state.origins[index]
	if origin.resolved {
		return origin.sources
	}
	sources := match origin.kind {
		.property {
			c.property_sources(origin.owner, origin.property, origin.parent, mut state,
				0)!
		}
		.element {
			c.element_sources(origin, mut state)!
		}
		.index_value {
			c.member_sources(origin.owner, origin.declaration, origin.parent, mut state)!
		}
		else {
			origin.sources
		}
	}
	state.origins[index].resolved = true
	state.origins[index].sources = sources
	return sources
}

// property_sources are the sources of the type of a property of a type: the annotation of its
// declaration, with the type arguments of the type.
fn (mut c Checker) property_sources(owner TypeResponse, property SymbolResponse, parent int, mut state SourceState, depth int) ![]TypeSource {
	if depth > max_type_depth {
		return []TypeSource{}
	}
	if owner.flags & type_flag_intersection != 0 {
		// The property only one member has is the property of that member.
		mut holders := []TypeResponse{}
		for member in c.members_of(owner)! {
			if !c.nuta_property_of(member, property.name)!.is_null() {
				holders << member
			}
		}
		if holders.len != 1 {
			return []TypeSource{}
		}
		return c.property_sources(holders[0], c.nuta_property_of(holders[0], property.name)!,
			parent, mut state, depth + 1)!
	}
	if owner.flags & type_flag_object != 0 && owner.object_flags & object_flag_mapped != 0 {
		// The property of `{ [K in keyof T]: T[K] }` has the type of the property of T (and
		// `undefined`, or not, as the modifiers say).
		parts := c.mapped_parts_from(owner, parent, mut state)!
		if !parts.identity {
			return c.mapped_template_sources(owner, parent, mut state)!
		}
		if parts.modifiers.is_null() {
			return []TypeSource{}
		}
		inner := c.nuta_property_of(parts.modifiers, property.name)!
		if inner.is_null() {
			return []TypeSource{}
		}
		return c.property_sources(parts.modifiers, inner, 0, mut state, depth + 1)!
	}
	if property.declarations.len != 1 {
		return []TypeSource{}
	}
	return c.member_sources(owner, property.declarations[0], parent, mut state)!
}

// member_sources are the sources of the type of a member (a property or an index signature, by
// its declaration) of a type.
fn (mut c Checker) member_sources(owner TypeResponse, declaration string, parent int, mut state SourceState) ![]TypeSource {
	kind := tsgo.handle_kind(declaration)
	if kind !in [source_kind_property_signature, syntax_kind_property_declaration,
		syntax_kind_parameter, source_kind_index_signature] {
		return []TypeSource{}
	}
	tree := c.declaration_ast(tsgo.handle_path(declaration))!
	index := tsgo.handle_index(declaration)
	annotation := tree.node_child(index, 'type')
	mut container := tree.node_parent(index)
	if kind == syntax_kind_parameter {
		// A parameter property is a member of the class of its constructor.
		if tree.node_kind(container) != source_kind_constructor {
			return []TypeSource{}
		}
		container = tree.node_parent(container)
	}
	if annotation == 0 || container == 0 {
		return []TypeSource{}
	}
	mut sources := []TypeSource{}
	for env in c.owner_envs(owner, tree.node_handle(container), parent, mut state)! {
		sources << TypeSource{tree.node_handle(annotation), env}
	}
	return sources
}

// owner_envs are the environments the members `container` declares (a class, an interface or an
// object type literal, by its handle) are read with in the type `owner`; none when not known.
fn (mut c Checker) owner_envs(owner TypeResponse, container string, parent int, mut state SourceState) ![]int {
	if owner.flags & type_flag_object == 0 {
		return []int{}
	}
	if owner.object_flags & source_object_flag_anonymous == 0 {
		env := c.heritage_env(owner, container, mut state)!
		return if env < 0 { []int{} } else { [env] }
	}
	symbol := c.symbol_of(owner)!
	if symbol.declarations.len != 1 || symbol.declarations[0] != container {
		return []int{}
	}
	if owner.object_flags & source_object_flag_instantiated == 0 {
		return [source_env_declared]
	}
	// An instance with an alias: the body of the alias with its type arguments has that literal,
	// in the body itself or in the aliases it names.
	alias_env := c.alias_container_env(owner, container, mut state)!
	if alias_env >= 0 {
		return [alias_env]
	}
	// Otherwise, where the sources of the type have that literal.
	mut search := SourceSearch{
		goal:      .container
		subject:   owner
		container: container
	}
	for source in c.origin_sources(mut state, parent)! {
		if !c.search_source(source, mut search, mut state, 0)! {
			return []int{}
		}
	}
	mut envs := []int{}
	for found in search.found {
		if found.env !in envs {
			envs << found.env
		}
	}
	return envs
}

// heritage_env is the environment the members the class or interface declaration `container`
// declares are read with in `owner`, an instance of that class or interface or of one that extends
// it; -1 when not known.
fn (mut c Checker) heritage_env(owner TypeResponse, container string, mut state SourceState) !int {
	declared := if is_type_reference(owner) { c.target_of(owner)! } else { owner }
	if declared.is_null() || declared.object_flags & object_flags_class_or_interface == 0 {
		return -1
	}
	mut env := source_env_closed
	if is_type_reference(owner) {
		parameters := c.type_args(declared)!
		type_arguments := c.type_args(owner)!
		mut bindings := map[int]TypeBinding{}
		for i, parameter in parameters {
			if i < type_arguments.len && parameter.symbol != 0 {
				bindings[parameter.symbol] = TypeBinding{
					typ: type_arguments[i]
				}
			}
		}
		env = state.new_env(bindings)
	}
	return c.declaring_env(declared, env, container, mut state, 0)!
}

// declaring_env looks for the declaration `container` in a class or interface (the type it
// declares, whose type parameters `env` binds) and in the ones it extends.
fn (mut c Checker) declaring_env(declared TypeResponse, env int, container string, mut state SourceState, depth int) !int {
	if depth > max_type_depth {
		return -1
	}
	if container in c.symbol_of(declared)!.declarations {
		return env
	}
	for base in c.base_types_for_type(declared)! {
		base_declared := if is_type_reference(base) { c.target_of(base)! } else { base }
		if base_declared.is_null()
			|| base_declared.object_flags & object_flags_class_or_interface == 0 {
			continue
		}
		mut base_env := source_env_closed
		if is_type_reference(base) {
			parameters := c.type_args(base_declared)!
			type_arguments := c.type_args(base)!
			mut bindings := map[int]TypeBinding{}
			for i, parameter in parameters {
				if i >= type_arguments.len || parameter.symbol == 0 {
					continue
				}
				// The type argument is written with the type parameters of the extending
				// declaration: it is known when it is one of them or a type they do not change.
				argument := type_arguments[i]
				if argument.flags & type_flag_type_parameter != 0 && argument.symbol != 0 {
					if binding := state.envs[env].bindings[argument.symbol] {
						bindings[parameter.symbol] = binding
					}
				} else if type_is_fixed(argument) {
					bindings[parameter.symbol] = TypeBinding{
						typ: argument
					}
				}
			}
			base_env = state.new_env(bindings)
		}
		found := c.declaring_env(base_declared, base_env, container, mut state, depth + 1)!
		if found >= 0 {
			return found
		}
	}
	return -1
}

// element_sources are the sources of a type argument of an array or tuple type: the element
// nodes of the array and tuple type nodes its sources have.
fn (mut c Checker) element_sources(origin TypeOrigin, mut state SourceState) ![]TypeSource {
	mut search := SourceSearch{
		goal:     .elements
		subject:  origin.owner
		position: origin.position
		symbol:   origin.owner.symbol
	}
	for source in c.origin_sources(mut state, origin.parent)! {
		if !c.search_source(source, mut search, mut state, 0)! {
			return []TypeSource{}
		}
	}
	return search.found
}
