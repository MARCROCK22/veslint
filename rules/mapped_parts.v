module rules

import tsgo { TypeResponse }

// The modifiersType of a mapped type, which the tsgo API does not give (7.1.0-beta included), read
// from its declaration and the type arguments of the type (type_sources.v), or from the parts of
// the instance that 7.1 gives (mapped_parts_of_instance).

// MappedParts is what the declaration of a mapped type and its type arguments tell of it.
struct MappedParts {
	// The modifiersType (getModifiersTypeFromMappedType: the `T` of `keyof T`) could be told. A
	// null `modifiers` then stands for the unknown type, which is what a mapped type whose keys
	// are not a `keyof` has.
	known     bool
	modifiers TypeResponse
	// The template is `T[K]`, with that same T and the type parameter of the mapped type: each
	// property has the type of the property of the modifiers type.
	identity bool
}

// mapped_parts reads the modifiersType of a mapped type, which the tsgo API of 7.0.2 does not
// give, from its declaration: the type of the `T` of its `keyof T` constraint (or of the one of
// the type parameter its keys are, `K extends keyof T`) with the type arguments of the type.
// Those are known for the type its declaration declares (there are none) and for a type with an
// alias, whose type arguments are those of the alias: the declaration is the body of that alias,
// or is reached from it through the aliases it names (`Omit` names `Pick`). An instance without
// an alias (the type a generic function returns, a member of a generic class) does not tell its
// type arguments: not known.
fn (mut c Checker) mapped_parts(t TypeResponse) !MappedParts {
	if t.id in c.mapped_parts_cache {
		return c.mapped_parts_cache[t.id]
	}
	mut state := new_source_state()
	parts := c.read_mapped_parts(t, 0, mut state)!
	c.mapped_parts_cache[t.id] = parts
	return parts
}

// mapped_parts_from is mapped_parts for a type of a walk, whose origin may tell the type
// arguments of an instance without an alias: a member of a generic class or interface, declared
// as a mapped type.
fn (mut c Checker) mapped_parts_from(t TypeResponse, origin int, mut state SourceState) !MappedParts {
	if t.id in c.mapped_parts_cache && (origin == 0 || c.mapped_parts_cache[t.id].known) {
		return c.mapped_parts_cache[t.id]
	}
	parts := c.read_mapped_parts(t, origin, mut state)!
	c.mapped_parts_cache[t.id] = parts
	return parts
}

fn (mut c Checker) read_mapped_parts(t TypeResponse, origin int, mut state SourceState) !MappedParts {
	symbol := c.symbol_of(t)!
	if symbol.declarations.len == 0
		|| tsgo.handle_kind(symbol.declarations[0]) != source_kind_mapped_type {
		return MappedParts{}
	}
	declaration := symbol.declarations[0]
	tree := c.declaration_ast(tsgo.handle_path(declaration))!
	node := tsgo.handle_index(declaration)
	parameter := tree.node_child(node, 'typeParameter')
	constraint := tree.node_child(parameter, 'constraint')
	if constraint == 0 {
		return MappedParts{}
	}
	// The modifiers type as declared, before the type arguments (getModifiersTypeFromMappedType):
	// the type of the `T` node of a `keyof T` constraint (isMappedTypeWithKeyofConstraintDeclaration)
	// or, otherwise, the declared constraint and, when it is a type parameter, the constraint of
	// that one: if it is a `keyof T`, T; if not, the unknown type, whatever the type arguments.
	keyof_operand := if tree.node_kind(constraint) == source_kind_type_operator
		&& tree.node_source_text(constraint).starts_with('keyof') {
		tree.node_handle(tree.node_child(constraint, 'type'))
	} else {
		''
	}
	mut declared := TypeResponse{}
	if keyof_operand != '' {
		declared = c.declared_type_node(keyof_operand)!
	} else {
		mut keys := c.declared_type_node(tree.node_handle(constraint))!
		if keys.flags & type_flag_type_parameter != 0 {
			keys = c.constraint_of(keys)!
		}
		if keys.is_null() || keys.flags & source_type_flag_index == 0 {
			return MappedParts{
				known: true
			}
		}
		declared = c.target_of(keys)!
	}
	if declared.is_null() {
		return MappedParts{}
	}
	env, from_alias := c.mapped_env(t, declaration, origin, mut state)!
	if env < 0 {
		return c.mapped_parts_of_instance(t, tree, node, declared)!
	}
	modifiers := if keyof_operand != '' {
		c.source_type(TypeSource{keyof_operand, env}, mut state, 0)!
	} else {
		c.instantiated_type(declared, env, mut state)!
	}
	if modifiers.is_null() {
		return MappedParts{}
	}
	// `{ [K in keyof T]: … }` with a union for T is one mapped type for each member: the type
	// arguments of an alias are those of the member, and the ones found from the origin are not.
	if !from_alias && modifiers.flags & type_flag_union != 0 {
		return MappedParts{}
	}
	return MappedParts{
		known:     true
		modifiers: modifiers
		identity:  c.mapped_template_is_identity(tree, node, declared)!
	}
}

// mapped_parts_of_instance tells the modifiersType of an instance whose type arguments are not
// known when the template of its declaration indexes the declared modifiers type T with the type
// parameter of the mapped type (`T[K]`, `Promise<T[K]>`, `T[K] | null`…): the T of the instance is
// then the object type of the `X[K']` its own template has, K' being its type parameter. tsgo gives
// both since TypeScript 7.1 (getTemplateTypeOfMappedType and getTypeParameterOfMappedType).
fn (mut c Checker) mapped_parts_of_instance(t TypeResponse, tree tsgo.AstTree, node int, declared TypeResponse) !MappedParts {
	template_node := tree.node_child(node, 'type')
	if t.object_flags & source_object_flag_instantiated == 0 || template_node == 0
		|| !c.mapped_template_indexes(tree, node, template_node, declared, 0)! {
		return MappedParts{}
	}
	template := c.client.part_of_type('getTemplateTypeOfMappedType', c.snapshot, c.project,
		t.id)!
	parameter := c.client.part_of_type('getTypeParameterOfMappedType', c.snapshot, c.project,
		t.id)!
	if template.is_null() || parameter.is_null() {
		return MappedParts{}
	}
	mut objects := []TypeResponse{}
	c.indexed_objects(template, parameter.id, mut objects, 0)!
	// A union for T makes one mapped type for each member, as in read_mapped_parts.
	if objects.len != 1 || objects[0].flags & type_flag_union != 0 {
		return MappedParts{}
	}
	return MappedParts{
		known:     true
		modifiers: objects[0]
		identity:  c.mapped_template_is_identity(tree, node, declared)!
	}
}

// mapped_template_indexes tells whether a node of the template of a mapped type declaration has
// a `T[K]`, T being the modifiers type as declared and K the type parameter of the mapped type.
fn (mut c Checker) mapped_template_indexes(tree tsgo.AstTree, mapped int, index int, declared TypeResponse, depth int) !bool {
	if index == 0 || depth > 32 {
		return false
	}
	if tree.node_kind(index) == source_kind_indexed_access_type
		&& c.indexes_with_parameter(tree, mapped, index, declared)! {
		return true
	}
	for child in tree.node_children(index) {
		if c.mapped_template_indexes(tree, mapped, child, declared, depth + 1)! {
			return true
		}
	}
	return false
}

// indexed_objects gathers the object types of the `X[K]` of a type whose index is the type with
// id `index`, through unions, intersections and type arguments.
fn (mut c Checker) indexed_objects(t TypeResponse, index int, mut objects []TypeResponse, depth int) ! {
	if t.is_null() || depth > 8 {
		return
	}
	if t.flags & type_flag_indexed_access != 0 {
		if c.client.part_of_type('getIndexTypeOfType', c.snapshot, c.project, t.id)!.id == index {
			object := c.client.part_of_type('getObjectTypeOfType', c.snapshot, c.project,
				t.id)!
			if !object.is_null() && !objects.any(it.id == object.id) {
				objects << object
			}
		}
		return
	}
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		for part in c.members_of(t)! {
			c.indexed_objects(part, index, mut objects, depth + 1)!
		}
		return
	}
	if is_type_reference(t) {
		for argument in c.type_args(t)! {
			c.indexed_objects(argument, index, mut objects, depth + 1)!
		}
	}
}

// mapped_template_is_identity: the mapped type node has no `as` clause and its template is
// `T[K]`, T being the modifiers type as declared and K the type parameter of the mapped type.
fn (mut c Checker) mapped_template_is_identity(tree tsgo.AstTree, node int, declared TypeResponse) !bool {
	template := skip_type_parentheses(tree, tree.node_child(node, 'type'))
	if tree.node_child(node, 'nameType') != 0 || template == 0
		|| tree.node_kind(template) != source_kind_indexed_access_type {
		return false
	}
	return c.indexes_with_parameter(tree, node, template, declared)!
}

// indexes_with_parameter: an indexed access node `T[K]` of the declaration of a mapped type, with T
// the modifiers type as declared and K the type parameter of the mapped type.
fn (mut c Checker) indexes_with_parameter(tree tsgo.AstTree, mapped int, access int, declared TypeResponse) !bool {
	object := c.declared_type_node(tree.node_handle(tree.node_child(access, 'objectType')))!
	index := c.declared_type_node(tree.node_handle(tree.node_child(access, 'indexType')))!
	if object.is_null() || object.id != declared.id || index.flags & type_flag_type_parameter == 0
		|| index.symbol == 0 {
		return false
	}
	name := tree.node_child(tree.node_child(mapped, 'typeParameter'), 'name')
	return name != 0 && c.name_symbols([tree.node_handle(name)])![0].id == index.symbol
}

// mapped_template_sources are the sources of the type of any property of a mapped type: its
// template, with the type arguments of the type and its type parameter standing for the key.
fn (mut c Checker) mapped_template_sources(t TypeResponse, origin int, mut state SourceState) ![]TypeSource {
	symbol := c.symbol_of(t)!
	if symbol.declarations.len == 0
		|| tsgo.handle_kind(symbol.declarations[0]) != source_kind_mapped_type {
		return []TypeSource{}
	}
	declaration := symbol.declarations[0]
	tree := c.declaration_ast(tsgo.handle_path(declaration))!
	node := tsgo.handle_index(declaration)
	template := tree.node_child(node, 'type')
	name := tree.node_child(tree.node_child(node, 'typeParameter'), 'name')
	env, _ := c.mapped_env(t, declaration, origin, mut state)!
	if template == 0 || name == 0 || env < 0 {
		return []TypeSource{}
	}
	key := c.name_symbols([tree.node_handle(name)])![0]
	if key.is_null() {
		return []TypeSource{}
	}
	mut bindings := state.envs[env].bindings.clone()
	bindings[key.id] = TypeBinding{
		unknown: true
	}
	state.envs << TypeEnv{
		open:     state.envs[env].open
		bindings: bindings
	}
	return [TypeSource{tree.node_handle(template), state.envs.len - 1}]
}

// mapped_env is the environment the declaration of a mapped type is read with in the type (-1
// when not known), and whether it comes from the alias of the type or it is the type its
// declaration declares.
fn (mut c Checker) mapped_env(t TypeResponse, declaration string, origin int, mut state SourceState) !(int, bool) {
	if t.object_flags & source_object_flag_instantiated == 0 {
		// The type its declaration declares.
		if c.declared_type_node(declaration)!.id == t.id {
			return source_env_declared, true
		}
		return -1, false
	}
	alias_env := c.alias_container_env(t, declaration, mut state)!
	if alias_env >= 0 {
		return alias_env, true
	}
	// Otherwise, where the sources of the type have that mapped type.
	sources := c.origin_sources(mut state, origin)!
	mut search := SourceSearch{
		goal:      .container
		subject:   t
		container: declaration
	}
	for source in sources {
		if !c.search_source(source, mut search, mut state, 0)! {
			return -1, false
		}
	}
	mut env := -1
	for found in search.found {
		if env >= 0 && found.env != env {
			return -1, false
		}
		env = found.env
	}
	return env, false
}
