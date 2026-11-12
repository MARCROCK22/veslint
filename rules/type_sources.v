module rules

import tsgo { SymbolResponse, TypeResponse }

// Where a type comes from, to find the declaration of a conditional type.
//
// isTypeReadonly looks at the branches of a conditional type as its declaration writes them
// (`type.root.node` in TypeScript 6), and the tsgo API of 7.0.2 has no `root`
// (microsoft/TypeScript#64740). TypeScript gives a conditional type its root in getConditionalType
// (checker.go): the conditional type node the type was asked from or, when a condition is decided,
// the root of the conditional type in the branch taken, and so on. So the root is one of the
// conditional type nodes reachable from the type node the type comes from, through the branches of
// conditional types, the members of unions and intersections, the bodies of the aliases named and
// the type arguments the type parameters stand for. veslint follows the type from a node it knows
// (the annotation of the parameter, the alias of the type, the declaration of the property or
// index signature a type is that of, the element of an array or tuple type) and collects those
// nodes; a node whose check, extends and branch types cannot become those of the type is not the
// root. When what is left answers the same, that is the answer; otherwise the declaration is not
// known and the caller looks at the branches of the type itself, as before.

// TypeSource: a type is that of the type node `node` (a tsgo handle) with its type parameters
// replaced as the environment `env` says, or a member of that type when it is a union or an
// intersection.
struct TypeSource {
	node string
	env  int
}

// TypeEnv is what the type parameters in scope stand for, by the id of their symbol. In an open
// one (the type of a node as it is declared) a type parameter without a binding is itself; in a
// closed one it is not known.
struct TypeEnv {
	open     bool
	bindings map[int]TypeBinding
}

// TypeBinding is a type argument: a type, a type node read with an environment, or one that is
// not known (the key the type parameter of a mapped type stands for in each property).
struct TypeBinding {
	typ     TypeResponse
	node    string
	env     int
	unknown bool
}

// The environment of a type as declared, and the closed one without bindings: the first two of
// SourceState.envs.
const source_env_declared = 0
const source_env_closed = 1

enum TypeOriginKind {
	unknown
	sources     // known sources
	property    // the type of `property` of `owner`
	element     // the type argument `position` of the array or tuple type `owner`
	index_value // the type of the index signature `declaration` of `owner`
}

// TypeOrigin is where a type of the walk comes from. Its sources are only computed when a
// conditional type asks for them (origin_sources): most types never do.
struct TypeOrigin {
	kind        TypeOriginKind
	parent      int // the origin of `owner`
	owner       TypeResponse
	property    SymbolResponse
	position    int
	declaration string
mut:
	resolved bool
	sources  []TypeSource
}

const source_kind_constructor = u32(178)
const source_kind_property_signature = u32(173)
const source_kind_index_signature = u32(183)
const source_kind_type_literal = u32(189)
const source_kind_array_type = u32(190)
const source_kind_tuple_type = u32(191)
const source_kind_optional_type = u32(192)
const source_kind_rest_type = u32(193)
const source_kind_union_type = u32(194)
const source_kind_intersection_type = u32(195)
const source_kind_infer_type = u32(197)
const source_kind_type_operator = u32(200)
const source_kind_mapped_type = u32(202)
const source_kind_named_tuple_member = u32(204)
const source_kind_intrinsic_keyword = u32(141)

// Type nodes whose type is never a conditional type, an array, a tuple or an object type literal,
// whatever the type arguments: the keywords (any, unknown, string, number, bigint, boolean, symbol,
// void, undefined, never, object), a literal type, a template literal type, a function type and a
// constructor type.
const source_kinds_without_parts = [u32(132), 159, 154, 150, 163, 135, 155, 115, 157, 146, 151,
	203, 205, 186, 187]

const source_symbol_flag_type_parameter = u32(262144)
const source_symbol_flag_type_alias = u32(524288)
// SymbolFlags.Class | Interface | ConstEnum | RegularEnum | EnumMember: what else a type reference
// names.
const source_symbol_flags_named_type = u32(32 | 64 | 128 | 256 | 8)
const source_object_flag_anonymous = u32(16)
const source_object_flag_instantiated = u32(64)

// A source is not followed deeper than this through aliases and type arguments.
const max_source_depth = 24

// SourceState holds the environments and the origins of a walk, by index. Origin 0 is the unknown
// one.
struct SourceState {
mut:
	envs    []TypeEnv
	origins []TypeOrigin
}

fn new_source_state() SourceState {
	return SourceState{
		envs:    [TypeEnv{
			open: true
		}, TypeEnv{}]
		origins: [TypeOrigin{}]
	}
}

// new_origin adds an origin to the state and gives its index.
fn (mut state SourceState) new_origin(origin TypeOrigin) int {
	state.origins << origin
	return state.origins.len - 1
}

// source_origin is the origin of the type of a type node as declared.
fn (mut state SourceState) source_origin(node string) int {
	if node == '' {
		return 0
	}
	return state.new_origin(TypeOrigin{
		kind:     .sources
		resolved: true
		sources:  [TypeSource{node, source_env_declared}]
	})
}

fn (mut state SourceState) new_env(bindings map[int]TypeBinding) int {
	state.envs << TypeEnv{
		bindings: bindings
	}
	return state.envs.len - 1
}

enum SourceGoal {
	roots     // the conditional type nodes
	elements  // the nodes of the element `position` of the array and tuple types
	container // the object type literal or mapped type node `container`
}

// SourceSearch looks in the sources of the type `subject` for the nodes it may come from.
struct SourceSearch {
	goal      SourceGoal
	subject   TypeResponse
	container string
	position  int
	symbol    int // elements: the symbol of the array type (Array or ReadonlyArray)
mut:
	found    []TypeSource
	expanded []string // the alias declarations being read
}

// search_source collects in `search.found` the nodes of a source the subject may come from. It
// answers false when the subject may come from somewhere it cannot follow: nothing is known then.
fn (mut c Checker) search_source(source TypeSource, mut search SourceSearch, mut state SourceState, depth int) !bool {
	if depth > max_source_depth {
		return false
	}
	tree := c.declaration_ast(tsgo.handle_path(source.node))!
	node := skip_type_parentheses(tree, tsgo.handle_index(source.node))
	if node == 0 {
		return false
	}
	if depth == 0 {
		// The names it will look at, in one request.
		mut name_handles := []string{}
		branch_names(tree, node, mut name_handles, 0)
		c.name_symbols(name_handles)!
	}
	kind := tree.node_kind(node)
	match kind {
		source_kind_union_type, source_kind_intersection_type {
			for member in tree.node_children(tree.node_child(node, 'types')) {
				if !c.search_source(TypeSource{tree.node_handle(member), source.env}, mut
					search, mut state, depth + 1)! {
					return false
				}
			}
			return true
		}
		syntax_kind_conditional_type {
			// The type is this conditional type or, when its condition is decided, what the branch
			// taken gives.
			if search.goal == .roots {
				search.found << TypeSource{tree.node_handle(node), source.env}
			}
			for property in ['trueType', 'falseType'] {
				branch := tree.node_child(node, property)
				if branch == 0 || !c.search_source(TypeSource{tree.node_handle(branch), source.env}, mut
					search, mut state, depth + 1)! {
					return false
				}
			}
			return true
		}
		syntax_kind_type_reference {
			return c.search_reference(tree, node, source.env, mut search, mut state, depth)!
		}
		source_kind_type_literal {
			if search.goal == .container && tree.node_handle(node) == search.container {
				search.found << TypeSource{search.container, source.env}
			}
			return true
		}
		source_kind_array_type {
			if search.goal == .elements {
				search.found << TypeSource{tree.node_handle(tree.node_child(node, 'elementType')), source.env}
			}
			return true
		}
		source_kind_tuple_type {
			return search.goal != .elements || search_tuple_element(tree, node, source.env, mut search)
		}
		source_kind_type_operator {
			// `readonly T[]` is the array or tuple type; `keyof T` and `unique symbol` are none of
			// what is looked for.
			if tree.node_source_text(node).starts_with('readonly') {
				return c.search_source(TypeSource{tree.node_handle(tree.node_child(node,
					'type')), source.env}, mut search, mut state, depth + 1)!
			}
			return true
		}
		source_kind_indexed_access_type {
			return c.search_indexed_access(tree, node, source.env, mut search, mut state,
				depth)!
		}
		source_kind_mapped_type {
			if search.goal == .container && tree.node_handle(node) == search.container {
				search.found << TypeSource{search.container, source.env}
			}
			// A mapped type gives an object type, or the array or tuple type it maps.
			return search.goal != .elements
		}
		else {
			return kind in source_kinds_without_parts
		}
	}
}

// search_tuple_element adds the node of the element of a tuple type node the search wants.
fn search_tuple_element(tree tsgo.AstTree, node int, env int, mut search SourceSearch) bool {
	elements := tree.node_children(tree.node_child(node, 'elements'))
	if search.position >= elements.len {
		return false
	}
	// With a rest element the type arguments are not the elements one by one.
	for element in elements {
		if tree.node_kind(element) == source_kind_rest_type
			|| (tree.node_kind(element) == source_kind_named_tuple_member
				&& tree.node_child(element, 'dotDotDotToken') != 0) {
			return false
		}
	}
	mut element := elements[search.position]
	if tree.node_kind(element) == source_kind_named_tuple_member {
		element = tree.node_child(element, 'type')
	}
	if tree.node_kind(element) == source_kind_optional_type {
		element = tree.node_child(element, 'type')
	}
	if element == 0 {
		return false
	}
	search.found << TypeSource{tree.node_handle(element), env}
	return true
}

// search_indexed_access is search_source for `T['name']`: the type of that property of T, when T
// is known.
fn (mut c Checker) search_indexed_access(tree tsgo.AstTree, node int, env int, mut search SourceSearch, mut state SourceState, depth int) !bool {
	object := tree.node_child(node, 'objectType')
	index := skip_type_parentheses(tree, tree.node_child(node, 'indexType'))
	if object == 0 || index == 0 || tree.node_kind(index) != syntax_kind_literal_type {
		return false
	}
	// A string literal without escapes; tsgo gives a name that starts with `__` one more `_`.
	text := tree.node_source_text(index)
	if text.len < 2 || text[0] !in [`'`, `"`] || text[text.len - 1] != text[0] || text.contains('\\') {
		return false
	}
	mut name := text[1..text.len - 1]
	if name.starts_with('__') {
		name = '_' + name
	}
	owner_source := TypeSource{tree.node_handle(object), env}
	owner := c.source_type(owner_source, mut state, 0)!
	if owner.is_null() {
		return false
	}
	property := c.nuta_property_of(owner, name)!
	if property.is_null() {
		return false
	}
	parent := state.new_origin(TypeOrigin{
		kind:     .sources
		resolved: true
		sources:  [owner_source]
	})
	sources := c.property_sources(owner, property, parent, mut state, 0)!
	if sources.len == 0 {
		return false
	}
	for property_source in sources {
		if !c.search_source(property_source, mut search, mut state, depth + 1)! {
			return false
		}
	}
	return true
}

// search_reference is search_source for a type reference: what it names tells where to go on.
fn (mut c Checker) search_reference(tree tsgo.AstTree, node int, env int, mut search SourceSearch, mut state SourceState, depth int) !bool {
	symbol := c.type_name_symbol(tree, node)!
	if symbol.is_null() {
		return false
	}
	if symbol.flags & source_symbol_flag_type_parameter != 0 {
		// What an `infer` gives is not in a declaration.
		if c.is_infer_type_parameter(symbol)! {
			return false
		}
		if binding := state.envs[env].bindings[symbol.id] {
			if binding.unknown {
				return false
			}
			if binding.node != '' {
				return c.search_source(TypeSource{binding.node, binding.env}, mut search, mut
					state, depth + 1)!
			}
			// A type argument that is, or has as a member, the type looked for: it comes from the
			// use, not from a declaration followed here.
			return !c.type_has_part(binding.typ, search.subject, 0)!
		}
		return state.envs[env].open
	}
	type_arguments := tree.node_children(tree.node_child(node, 'typeArguments'))
	if symbol.flags & source_symbol_flag_type_alias != 0 {
		declaration := alias_declaration(symbol)
		if declaration == '' {
			return false
		}
		// An alias that names itself: each time, its type parameters stand for the type arguments
		// it gives itself, read with what they stood for the time before. After as many times as
		// it has type parameters, they have stood for everything they ever will.
		if search.expanded.filter(it == declaration).len > c.alias_parameter_count(declaration)! {
			return true
		}
		mut bindings := []TypeBinding{}
		for argument in type_arguments {
			bindings << TypeBinding{
				node: tree.node_handle(argument)
				env:  env
			}
		}
		body := c.alias_body_source(declaration, bindings, mut state)!
		if body.node == '' {
			return false
		}
		search.expanded << declaration
		known := c.search_source(body, mut search, mut state, depth + 1)!
		search.expanded.pop()
		return known
	}
	if symbol.flags & source_symbol_flags_named_type == 0 {
		return false
	}
	// A class, an interface or an enum: an object type or the members of the enum. `Array<T>` and
	// `ReadonlyArray<T>` are the array type.
	if search.goal == .elements && symbol.id == search.symbol && type_arguments.len == 1 {
		search.found << TypeSource{tree.node_handle(type_arguments[0]), env}
	}
	return true
}

// type_has_part: the type is `part`, or a union or intersection that has it as a member.
fn (mut c Checker) type_has_part(t TypeResponse, part TypeResponse, depth int) !bool {
	if t.id == part.id {
		return true
	}
	if depth > max_type_depth || t.flags & (type_flag_union | type_flag_intersection) == 0 {
		return false
	}
	for member in c.members_of(t)! {
		if c.type_has_part(member, part, depth + 1)! {
			return true
		}
	}
	return false
}

// skip_type_parentheses is the type node inside its parentheses.
fn skip_type_parentheses(tree tsgo.AstTree, node int) int {
	mut inner := node
	for inner != 0 && tree.node_kind(inner) == syntax_kind_parenthesized_type {
		inner = tree.node_child(inner, 'type')
	}
	return inner
}

// name_symbols are the symbols of name nodes of declarations (getSymbolAtLocation), by handle.
fn (mut c Checker) name_symbols(handles []string) ![]SymbolResponse {
	missing := handles.filter(it !in c.name_symbol_cache)
	if missing.len > 0 {
		symbols := c.client.symbols_at_locations(c.snapshot, c.project, missing)!
		for i, handle in missing {
			c.name_symbol_cache[handle] = if i < symbols.len {
				symbols[i]
			} else {
				SymbolResponse{}
			}
		}
	}
	return handles.map(c.name_symbol_cache[it])
}

// type_name_symbol is the symbol a type reference names: the type alias, type parameter, class,
// interface or enum, through the import that brings it.
fn (mut c Checker) type_name_symbol(tree tsgo.AstTree, reference int) !SymbolResponse {
	mut name := tree.node_child(reference, 'typeName')
	if name != 0 && tree.node_kind(name) == syntax_kind_qualified_name {
		name = tree.node_child(name, 'right')
	}
	if name == 0 {
		return SymbolResponse{}
	}
	symbol := c.name_symbols([tree.node_handle(name)])![0]
	if !symbol.is_null() && symbol.flags & symbol_flag_alias != 0 {
		return c.aliased_symbol(symbol.id)!
	}
	return symbol
}

// is_infer_type_parameter: the type parameter is that of an `infer T`.
fn (mut c Checker) is_infer_type_parameter(symbol SymbolResponse) !bool {
	if symbol.declarations.len == 0 {
		return true
	}
	declaration := symbol.declarations[0]
	tree := c.declaration_ast(tsgo.handle_path(declaration))!
	return tree.node_kind(tree.node_parent(tsgo.handle_index(declaration))) == source_kind_infer_type
}

// alias_declaration is the handle of the declaration of a type alias, '' unless it has just one.
fn alias_declaration(alias SymbolResponse) string {
	declarations := alias.declarations.filter(tsgo.handle_kind(it) == syntax_kind_type_alias_declaration)
	return if declarations.len == 1 { declarations[0] } else { '' }
}

// alias_parameter_count is the number of type parameters of a type alias declaration.
fn (mut c Checker) alias_parameter_count(declaration string) !int {
	tree := c.declaration_ast(tsgo.handle_path(declaration))!
	return tree.node_children(tree.node_child(tsgo.handle_index(declaration), 'typeParameters')).len
}

// alias_bindings are the type arguments of the alias of a type.
fn (mut c Checker) alias_bindings(t TypeResponse) ![]TypeBinding {
	mut bindings := []TypeBinding{}
	if t.alias_type_arguments.len > 0 {
		for argument in c.client.alias_type_arguments_of_type(c.snapshot, c.project, t.id)! {
			bindings << TypeBinding{
				typ: argument
			}
		}
	}
	return bindings
}

// alias_body_source is the body of a type alias with its type parameters bound to the type
// arguments, and to their defaults where there is none. An empty source when it cannot be read: an
// intrinsic alias (`Uppercase`, `NoInfer`), or more type arguments than type parameters.
fn (mut c Checker) alias_body_source(declaration string, type_arguments []TypeBinding, mut state SourceState) !TypeSource {
	tree := c.declaration_ast(tsgo.handle_path(declaration))!
	index := tsgo.handle_index(declaration)
	body := tree.node_child(index, 'type')
	if body == 0 || tree.node_kind(body) == source_kind_intrinsic_keyword {
		return TypeSource{}
	}
	parameters := tree.node_children(tree.node_child(index, 'typeParameters'))
	if type_arguments.len > parameters.len {
		return TypeSource{}
	}
	// The names of the type parameters, and with them those the body may be followed through.
	mut name_handles := parameters.map(tree.node_handle(tree.node_child(it, 'name')))
	branch_names(tree, body, mut name_handles, 0)
	symbols := c.name_symbols(name_handles)!
	// A default may name the type parameters before it: it is read with this same environment.
	env := state.envs.len
	mut bindings := map[int]TypeBinding{}
	for i, parameter in parameters {
		if symbols[i].is_null() {
			return TypeSource{}
		}
		if i < type_arguments.len {
			bindings[symbols[i].id] = type_arguments[i]
			continue
		}
		default_type := tree.node_child(parameter, 'defaultType')
		if default_type != 0 {
			bindings[symbols[i].id] = TypeBinding{
				node: tree.node_handle(default_type)
				env:  env
			}
		}
	}
	state.new_env(bindings)
	return TypeSource{tree.node_handle(body), env}
}

// type_is_fixed: no type argument changes the type. A primitive, a literal or another type without
// parts (`boolean` is the only union among them), or an interface without type parameters (a
// class always has a `this` type).
fn type_is_fixed(t TypeResponse) bool {
	if t.flags & type_flag_object != 0 {
		return t.object_flags & object_flags_class_or_interface != 0
			&& t.object_flags & object_flag_reference == 0
	}
	if t.flags & type_flags_without_parts == 0 || t.flags & type_flag_intersection != 0 {
		return false
	}
	return t.flags & type_flag_union == 0 || t.flags & u32(256) != 0
}

// binding_type is the type of a type argument when it can be known; the null type otherwise.
fn (mut c Checker) binding_type(binding TypeBinding, mut state SourceState, depth int) !TypeResponse {
	if binding.unknown {
		return TypeResponse{}
	}
	if binding.node == '' {
		return binding.typ
	}
	return c.source_type(TypeSource{binding.node, binding.env}, mut state, depth + 1)!
}

// source_type is the type of a source when it can be known: that of its node as declared, one of
// the type arguments of its environment, or a type no type argument changes. The null type
// otherwise.
fn (mut c Checker) source_type(source TypeSource, mut state SourceState, depth int) !TypeResponse {
	if depth > max_source_depth {
		return TypeResponse{}
	}
	env := state.envs[source.env]
	if env.open && env.bindings.len == 0 {
		return c.declared_type_node(source.node)!
	}
	tree := c.declaration_ast(tsgo.handle_path(source.node))!
	node := skip_type_parentheses(tree, tsgo.handle_index(source.node))
	if node != 0 && tree.node_kind(node) == syntax_kind_type_reference
		&& tree.node_child(node, 'typeArguments') == 0 {
		symbol := c.type_name_symbol(tree, node)!
		if !symbol.is_null() && symbol.flags & source_symbol_flag_type_parameter != 0 {
			if binding := env.bindings[symbol.id] {
				return c.binding_type(binding, mut state, depth)!
			}
			return if env.open { c.declared_type_node(source.node)! } else { TypeResponse{} }
		}
	}
	declared := c.declared_type_node(source.node)!
	return if type_is_fixed(declared) { declared } else { TypeResponse{} }
}

// request_type_nodes asks for the types of the type nodes type_from_type_node does not have yet,
// in one request (the type at a type node is the one getTypeFromTypeNode gives).
fn (mut c Checker) request_type_nodes(handles []string) ! {
	missing := handles.filter(it !in c.type_node_cache && tsgo.handle_index(it) != 0)
	if missing.len < 2 {
		return
	}
	types := c.client.types_at_locations(c.snapshot, c.project, missing) or {
		// A node tsgo panics on (7.0.2 did on microsoft/TypeScript#63869): they are asked one by one.
		if !tsgo.is_panic(err) {
			return err
		}
		return
	}
	if types.len != missing.len {
		return
	}
	for i, handle in missing {
		c.type_node_cache[handle] = types[i]
	}
}

// declared_type_node is type_from_type_node for the nodes only this file looks at: the null type
// for a node tsgo panics on, which then tells nothing.
fn (mut c Checker) declared_type_node(handle string) !TypeResponse {
	return c.type_from_type_node(handle) or {
		if !tsgo.is_panic(err) {
			return err
		}
		TypeResponse{}
	}
}

// branch_names collects the names of the type references a search may look at from a type node:
// those of the node, of the members of a union or intersection and of the branches of a
// conditional type.
fn branch_names(tree tsgo.AstTree, start int, mut name_handles []string, depth int) {
	node := skip_type_parentheses(tree, start)
	if node == 0 || depth > max_source_depth {
		return
	}
	match tree.node_kind(node) {
		source_kind_union_type, source_kind_intersection_type {
			for member in tree.node_children(tree.node_child(node, 'types')) {
				branch_names(tree, member, mut name_handles, depth + 1)
			}
		}
		syntax_kind_conditional_type {
			branch_names(tree, tree.node_child(node, 'trueType'), mut name_handles, depth + 1)
			branch_names(tree, tree.node_child(node, 'falseType'), mut name_handles, depth + 1)
		}
		syntax_kind_type_reference {
			mut name := tree.node_child(node, 'typeName')
			if name != 0 && tree.node_kind(name) == syntax_kind_qualified_name {
				name = tree.node_child(name, 'right')
			}
			if name != 0 {
				name_handles << tree.node_handle(name)
			}
		}
		else {}
	}
}

const source_kind_indexed_access_type = u32(201)
const source_type_flag_index = u32(2097152)

// alias_container_env is the environment the type literal or mapped type node `container` is
// read with in a type that has an alias: the body of the alias with the type arguments of the
// alias is that node, or names the alias whose body is. -1 when not known.
fn (mut c Checker) alias_container_env(t TypeResponse, container string, mut state SourceState) !int {
	if t.alias_symbol == 0 {
		return -1
	}
	alias := alias_declaration(c.alias_symbol_of(t)!)
	if alias == '' {
		return -1
	}
	body := c.alias_body_source(alias, c.alias_bindings(t)!, mut state)!
	mut search := SourceSearch{
		goal:      .container
		subject:   t
		container: container
		expanded:  [alias]
	}
	if body.node == '' || !c.search_source(body, mut search, mut state, 0)! {
		return -1
	}
	mut env := -1
	for found in search.found {
		if env >= 0 && found.env != env {
			return -1
		}
		env = found.env
	}
	return env
}

// instantiated_type is what a type as declared becomes with the type arguments of an environment,
// when it can be known: the type itself where nothing is bound, the type argument of a type
// parameter, or a type no type argument changes. The null type otherwise.
fn (mut c Checker) instantiated_type(t TypeResponse, env_index int, mut state SourceState) !TypeResponse {
	env := state.envs[env_index]
	if env.open && env.bindings.len == 0 {
		return t
	}
	if t.flags & type_flag_type_parameter != 0 && t.symbol != 0 {
		if binding := env.bindings[t.symbol] {
			return c.binding_type(binding, mut state, 0)!
		}
		return if env.open { t } else { TypeResponse{} }
	}
	return if type_is_fixed(t) { t } else { TypeResponse{} }
}
