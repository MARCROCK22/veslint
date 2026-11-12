module rules

import time
import tsgo { SymbolResponse, handle_index, handle_kind, handle_path }
import treesitter { children, has_child_kind, next_sibling, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-unnecessary-qualifier` rule of typescript-eslint 8.62.0 (it has no options),
// with its fix.
//
// checker.getSymbolsInScope is not in the tsgo API, so getSymbolInScope
// (`getSymbolsInScope(qualifier, accessed.flags).find(name)`) is ported over
// resolveName(name, accessed.flags, location): both look the name up from the innermost scope
// outwards, but getSymbolsInScope takes every local of every scope whose flags share a bit with
// those of the accessed symbol, and resolveName differs in these ways (nuq_symbol_in_scope):
//   - it does not see the locals of a function from its parameters, its return type or its
//     decorators (a variable or a type declared in the body);
//   - inside a function it gives the `arguments` object for a variable with that name, which
//     for getSymbolsInScope is a property and never a variable;
//   - it takes an import alias for what it names, while the flags of an alias are only Alias;
//   - it takes the name an export specifier gives in a namespace, which getSymbolsInScope
//     leaves out.

const nuq_messages = {
	'unnecessaryQualifier': "Qualifier is unnecessary since '{{ name }}' is in scope."
}

// SyntaxKind and SymbolFlags of TypeScript 7.1.0-beta.
const nuq_syntax_kind_module_declaration = u32(269)
const nuq_symbol_flag_alias = u32(2097152)

// NuqAccess is a MemberExpression (not computed) whose object is an entity name, or a
// TSQualifiedName: the namespace access visitNamespaceAccess looks at.
struct NuqAccess {
	node      C.TSNode
	qualifier C.TSNode
	name      C.TSNode
	scope     []u64 // keys of the namespacesInScope spans when the access is visited
}

// NuqStep is a step of the walk: entering or leaving a node.
struct NuqStep {
	node    C.TSNode
	leaving bool
}

fn (mut c Checker) lint_no_unnecessary_qualifier(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut accesses := []NuqAccess{}
	mut spans := []Span{}
	c.nuq_walk(root, mut accesses, mut spans)
	for a in accesses {
		spans << node_span(a.qualifier)
		spans << node_span(a.name)
		mut functions := nuq_outer_functions(a.qualifier)
		if c.text(a.name) == 'arguments' {
			functions << nuq_arguments_functions(a.qualifier)
		}
		for function in functions {
			spans << Span{
				...function_span(function)
				optional: true
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	unnecessary := c.nuq_unnecessary(accesses)!
	// currentFailedNamespaceExpression: inside a reported access, nested ones are not checked.
	mut findings := []Finding{}
	mut reported := []C.TSNode{}
	for i, a in accesses {
		if !unnecessary[i] {
			continue
		}
		if reported.any(node_start(it) <= node_start(a.node) && node_end(a.node) <= node_end(it)) {
			continue
		}
		reported << a.node
		// The fixer removes from the start of the qualifier to the start of the name.
		findings << Finding{
			stmt:       position_of(a.qualifier)
			message_id: 'unnecessaryQualifier'
			data:       {
				'name': c.text(a.name)
			}
			has_fix:    true
			fix:        fix_remove_range(node_start(a.qualifier), node_start(a.name))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += accesses.len
	return findings
}

// nuq_walk visits the tree in order, keeping namespacesInScope like the rule's enter and exit
// handlers, and collects the namespace accesses with the namespaces in scope at each one.
fn (c &Checker) nuq_walk(root C.TSNode, mut accesses []NuqAccess, mut spans []Span) {
	mut scope := []u64{}
	mut steps := [NuqStep{
		node: root
	}]
	for steps.len > 0 {
		step := steps.pop()
		n := step.node
		kind := node_kind(n)
		if step.leaving {
			// TSModuleDeclaration:exit, TSEnumDeclaration:exit and ExportNamedDeclaration:exit pop.
			if nuq_is_module(n) || kind == 'enum_declaration' || nuq_exported(n) != none {
				if scope.len > 0 {
					scope.pop()
				}
			}
			continue
		}
		// ExportNamedDeclaration of an enum or a module: its TypeScript node is the declaration
		// (for `A.B`, the innermost module).
		if declaration := nuq_exported(n) {
			s := if node_kind(declaration) == 'enum_declaration' {
				c.nuq_declaration_span(declaration, syntax_kind_enum_declaration)
			} else {
				c.nuq_innermost_module_span(declaration)
			}
			spans << s
			scope << s.key
		}
		if kind == 'enum_declaration' {
			s := c.nuq_declaration_span(n, syntax_kind_enum_declaration)
			spans << s
			scope << s.key
		}
		// TSModuleDeclaration > TSModuleBlock: the (outermost) module.
		if kind == 'statement_block' {
			if parent := node_parent(n) {
				if nuq_is_module(parent) {
					s := c.nuq_declaration_span(parent, nuq_syntax_kind_module_declaration)
					spans << s
					scope << s.key
				}
			}
		}
		if access := nuq_access(n) {
			accesses << NuqAccess{
				...access
				scope: scope.clone()
			}
		}
		steps << NuqStep{
			node:    n
			leaving: true
		}
		kids := children(n)
		for i := kids.len - 1; i >= 0; i-- {
			steps << NuqStep{
				node: kids[i]
			}
		}
	}
}

// nuq_is_module: a TSModuleDeclaration (`namespace`, `module`, `declare global`).
fn nuq_is_module(n C.TSNode) bool {
	kind := node_kind(n)
	return kind in ['internal_module', 'module']
		|| (kind == 'ambient_declaration' && has_child_kind(n, 'global'))
}

// nuq_exported is the enum or module of an ExportNamedDeclaration (`export enum`, `export
// namespace`, `export declare namespace`).
fn nuq_exported(n C.TSNode) ?C.TSNode {
	if node_kind(n) != 'export_statement' {
		return none
	}
	mut declaration := node_field(n, 'declaration')?
	if node_kind(declaration) == 'ambient_declaration' && !has_child_kind(declaration, 'global') {
		declaration = first_named(declaration)?
	}
	if node_kind(declaration) == 'enum_declaration' || nuq_is_module(declaration) {
		return declaration
	}
	return none
}

// nuq_declaration_span is the TypeScript declaration of an enum or module: its modifiers
// (`export`, `declare`) are part of it.
fn (c &Checker) nuq_declaration_span(declaration C.TSNode, kind u32) Span {
	mut first := declaration
	for {
		parent := node_parent(first) or { break }
		if node_kind(parent) !in ['export_statement', 'ambient_declaration'] {
			break
		}
		first = parent
	}
	return Span{
		key:   (u64(node_start(first)) << 32) | u64(node_end(declaration))
		first: first
		end:   node_end(declaration)
		kind:  kind
	}
}

// nuq_innermost_module_span is the innermost ModuleDeclaration of `namespace A.B {}` (the one of
// `B`), or the module itself.
fn (c &Checker) nuq_innermost_module_span(module C.TSNode) Span {
	name := node_field(module, 'name') or {
		return c.nuq_declaration_span(module, nuq_syntax_kind_module_declaration)
	}
	if node_kind(name) != 'nested_identifier' {
		return c.nuq_declaration_span(module, nuq_syntax_kind_module_declaration)
	}
	last := node_field(name, 'property') or {
		return c.nuq_declaration_span(module, nuq_syntax_kind_module_declaration)
	}
	return Span{
		key:   (u64(node_start(last)) << 32) | u64(node_end(module))
		first: last
		end:   node_end(module)
		kind:  nuq_syntax_kind_module_declaration
	}
}

// nuq_access reads a namespace access: a member_expression whose object is an entity name, or
// a qualified name (nested_type_identifier, nested_identifier).
fn nuq_access(n C.TSNode) ?NuqAccess {
	match node_kind(n) {
		'member_expression' {
			object := unwrap_parens(node_field(n, 'object')?)
			if !nuq_is_entity_name(object) {
				return none
			}
			return NuqAccess{
				node:      n
				qualifier: object
				name:      node_field(n, 'property')?
			}
		}
		'nested_type_identifier' {
			return NuqAccess{
				node:      n
				qualifier: node_field(n, 'module')?
				name:      node_field(n, 'name')?
			}
		}
		'nested_identifier' {
			return NuqAccess{
				node:      n
				qualifier: node_field(n, 'object')?
				name:      node_field(n, 'property')?
			}
		}
		else {
			return none
		}
	}
}

// nuq_is_entity_name ports isEntityNameExpression: an identifier, or a non-computed member access
// of one.
fn nuq_is_entity_name(n C.TSNode) bool {
	mut node := n
	for depth := 0; depth < max_expression_depth; depth++ {
		match node_kind(node) {
			'identifier', 'undefined' {
				return true
			}
			'member_expression' {
				node = unwrap_parens(node_field(node, 'object') or { return false })
			}
			else {
				return false
			}
		}
	}
	return false
}

// nuq_unnecessary ports qualifierIsUnnecessary for each access.
fn (mut c Checker) nuq_unnecessary(accesses []NuqAccess) ![]bool {
	mut result := []bool{len: accesses.len}
	mut qualifier_handles := []string{}
	mut with_handles := []int{}
	for i, a in accesses {
		if handle := c.node_handles[node_key(a.qualifier)] {
			if node_key(a.name) in c.node_handles {
				qualifier_handles << handle
				with_handles << i
			}
		}
	}
	if qualifier_handles.len == 0 {
		return result
	}
	namespaces := c.client.symbols_at_locations(c.snapshot, c.project, qualifier_handles)!
	mut name_handles := []string{}
	mut in_scope := []int{}
	for j, i in with_handles {
		namespace := namespaces[j] or { continue }
		if namespace.is_null() {
			continue
		}
		scope := accesses[i].scope.map(c.node_handles[it] or { '' }).filter(it != '')
		if c.nuq_namespace_in_scope(namespace, scope, 0)! {
			name_handles << c.node_handles[node_key(accesses[i].name)]
			in_scope << i
		}
	}
	if name_handles.len == 0 {
		return result
	}
	accessed_symbols := c.client.symbols_at_locations(c.snapshot, c.project, name_handles)!
	for j, i in in_scope {
		accessed := accessed_symbols[j] or { continue }
		if accessed.is_null() {
			continue
		}
		a := accesses[i]
		from_scope := c.nuq_symbol_in_scope(a, int(accessed.flags))!
		if from_scope.is_null() {
			continue
		}
		result[i] = c.client.export_symbol_of_symbol(c.snapshot, c.project, from_scope)!.id == accessed.id
	}
	return result
}

// nuq_namespace_in_scope ports symbolIsNamespaceInScope: a declaration of the symbol (or of the
// one it aliases) is one of the namespaces in scope.
fn (mut c Checker) nuq_namespace_in_scope(symbol SymbolResponse, scope []string, depth int) !bool {
	if symbol.declarations.any(it in scope) {
		return true
	}
	if depth > max_type_depth || symbol.flags & nuq_symbol_flag_alias == 0 {
		return false
	}
	alias := c.aliased_symbol(symbol.id)!
	return !alias.is_null() && c.nuq_namespace_in_scope(alias, scope, depth + 1)!
}

// SyntaxKind and SymbolFlags of TypeScript 7.1.0-beta.
const nuq_syntax_kind_source_file = u32(308)
const nuq_syntax_kind_export_specifier = u32(283)
const nuq_syntax_kind_namespace_export = u32(282)

// SymbolFlags.ModuleMember: Variable | Function | Class | Interface | Enum | Module | TypeAlias |
// Alias.
const nuq_symbol_flags_module_member = 2623475

// The functions with locals: a body where variables and types are declared.
const nuq_function_kinds = ['function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'arrow_function', 'method_definition']

// nuq_outer_functions are the functions the node is in but not in their body (in a parameter, a
// return type or a type parameter), and the method a decorator with the node is on, from the
// innermost: resolveName does not look at their locals from there, and getSymbolsInScope does.
fn nuq_outer_functions(n C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	mut child := n
	for _ in 0 .. max_expression_depth {
		parent := node_parent(child) or { break }
		kind := node_kind(parent)
		if kind in nuq_function_kinds {
			if body := node_field(parent, 'body') {
				if node_key(body) != node_key(child) {
					out << parent
				}
			}
		} else if kind == 'decorator' {
			// The decorators of a member come before it, as siblings.
			mut member := parent
			for {
				member = next_sibling(member) or { break }
				if node_kind(member) != 'decorator' {
					break
				}
			}
			if node_kind(member) == 'method_definition' {
				out << member
			}
		}
		child = parent
	}
	return out
}

// nuq_symbol_in_scope ports getSymbolInScope(qualifier, flags, name): the first symbol with that
// name, from the innermost scope, whose flags share a bit with `meaning`.
fn (mut c Checker) nuq_symbol_in_scope(a NuqAccess, meaning int) !SymbolResponse {
	name := c.text(a.name)
	mut found := c.client.resolve_name_at(c.snapshot, c.project, name, meaning, c.node_handles[node_key(a.qualifier)],
		false)!
	// A local of a function resolveName does not see from where the qualifier is: asked from the
	// function itself, it is the first one found.
	for function in nuq_outer_functions(a.qualifier) {
		handle := c.node_handles[node_key(function)] or { continue }
		local := c.client.resolve_name_at(c.snapshot, c.project, name, meaning, handle,
			false)!
		if !local.is_null() && local.id != found.id && c.nuq_declared_in(local, handle)!
			&& !c.nuq_declared_in(found, handle)! {
			found = local
			break
		}
	}
	// The `arguments` of a function has no declaration and is not a variable: the lookup goes
	// on outside that function.
	if name == 'arguments' {
		for function in nuq_arguments_functions(a.qualifier) {
			if found.is_null() || found.declarations.len != 0 || int(found.flags) & meaning != 0 {
				break
			}
			handle := c.node_handles[node_key(function)] or { break }
			tree := c.declaration_ast(handle_path(handle))!
			parent := tree.node_parent(handle_index(handle))
			if parent == 0 {
				break
			}
			found = c.client.resolve_name_at(c.snapshot, c.project, name, meaning, tree.node_handle(parent),
				false)!
		}
	}
	// An import alias whose flags share nothing with the meaning is not taken, nor is a name an
	// export specifier gives: the lookup goes on from the module that declares it.
	for _ in 0 .. max_type_depth {
		if found.is_null() || found.declarations.len == 0 {
			break
		}
		from_specifier := found.declarations.any(handle_kind(it) in [
			nuq_syntax_kind_export_specifier,
			nuq_syntax_kind_namespace_export,
		])
		if !from_specifier
			&& (found.flags & nuq_symbol_flag_alias == 0 || int(found.flags) & meaning != 0) {
			break
		}
		found = c.nuq_beyond_alias(found.declarations[0], name, meaning)!
	}
	return found
}

// nuq_arguments_functions are the functions around the node that have an `arguments` object
// (not the arrow functions), from the innermost.
fn nuq_arguments_functions(n C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	mut node := n
	for _ in 0 .. max_expression_depth {
		node = node_parent(node) or { break }
		if node_kind(node) in nuq_function_kinds && node_kind(node) != 'arrow_function' {
			out << node
		}
	}
	return out
}

// nuq_declared_in: some declaration of the symbol is inside the node of that handle.
fn (mut c Checker) nuq_declared_in(symbol SymbolResponse, container string) !bool {
	if symbol.is_null() {
		return false
	}
	path := handle_path(container)
	target := handle_index(container)
	for declaration in symbol.declarations {
		if handle_path(declaration) != path {
			continue
		}
		tree := c.declaration_ast(path)!
		mut node := handle_index(declaration)
		for _ in 0 .. max_expression_depth {
			if node == target {
				return true
			}
			node = tree.node_parent(node)
			if node == 0 {
				break
			}
		}
	}
	return false
}

// nuq_beyond_alias goes on with the lookup of getSymbolsInScope past the locals of the module or
// namespace that declares an import alias: its exports that are not export specifiers and then,
// from outside it, what resolveName finds (the globals, past a file).
fn (mut c Checker) nuq_beyond_alias(declaration string, name string, meaning int) !SymbolResponse {
	tree := c.declaration_ast(handle_path(declaration))!
	// The module declaration around the alias, or the SourceFile (the node without a parent).
	mut container := tree.node_parent(handle_index(declaration))
	mut in_file := false
	for _ in 0 .. max_expression_depth {
		if tree.node_kind(container) == nuq_syntax_kind_module_declaration {
			break
		}
		parent := tree.node_parent(container)
		if parent == 0 {
			in_file = true
			break
		}
		container = parent
	}
	// The symbol of a file is that of its module (a script has none).
	location := if in_file {
		tree.node_handle(container)
	} else {
		tree.node_handle(tree.node_child(container, 'name'))
	}
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [location])!
	if symbols.len == 1 && !symbols[0].is_null() {
		escaped := escape_leading_underscores(name)
		for exported in c.client.exports_of_symbol(c.snapshot, c.project, symbols[0].id)! {
			if exported.name == escaped && name != 'default'
				&& int(exported.flags) & meaning & nuq_symbol_flags_module_member != 0
				&& !exported.declarations.any(handle_kind(it) in [
					nuq_syntax_kind_export_specifier,
					nuq_syntax_kind_namespace_export,
				]) {
				return exported
			}
		}
	}
	if in_file {
		return c.client.resolve_name(c.snapshot, c.project, name, meaning)!
	}
	return c.client.resolve_name_at(c.snapshot, c.project, name, meaning, tree.node_handle(tree.node_parent(container)),
		false)!
}
