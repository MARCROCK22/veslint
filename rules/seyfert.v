module rules

import tsgo { SymbolResponse, TypeResponse, handle_path }
import treesitter { node_field, node_kind }

// What the rules of @slipher/eslint-plugin 1.1.0 (tiramisulabs/extra 221401c7c2,
// packages/eslint-plugin), the `seyfert/*` rules, share: its src/utils.ts, and the TypeScript nodes
// they resolve values on. Where the plugin works with TypeScript's nodes (a `const` it follows
// through an import, the declaration of a class in another file), these rules work with the nodes
// of tsgo's AST of the file (SyNode); the handle of a requested tree-sitter node leads to its
// counterpart in the file being linted.

// TypeScript 7.1.0-beta's SyntaxKind of the nodes the rules look at (dist/enums/syntaxKind.enum.js).
const sy_kind_numeric_literal = u32(8)
const sy_kind_string_literal = u32(10)
const sy_kind_no_substitution_template_literal = u32(14)
const sy_kind_identifier = u32(79)
const sy_kind_default_keyword = u32(89)
const sy_kind_export_keyword = u32(94)
const sy_kind_false_keyword = u32(96)
const sy_kind_true_keyword = u32(111)
const sy_kind_declare_keyword = u32(137)
const sy_kind_computed_property_name = u32(169)
const sy_kind_decorator = u32(172)
const sy_kind_array_literal_expression = u32(211)
const sy_kind_object_literal_expression = u32(212)
const sy_kind_property_access_expression = u32(213)
const sy_kind_call_expression = u32(215)
const sy_kind_parenthesized_expression = u32(219)
const sy_kind_spread_element = u32(232)
const sy_kind_class_expression = u32(233)
const sy_kind_as_expression = u32(236)
const sy_kind_non_null_expression = u32(237)
const sy_kind_satisfies_expression = u32(240)
const sy_kind_variable_declaration = u32(262)
const sy_kind_class_declaration = u32(265)
const sy_kind_export_assignment = u32(279)
const sy_kind_property_assignment = u32(304)
const sy_kind_shorthand_property_assignment = u32(305)
const sy_kind_spread_assignment = u32(306)

// NodeFlags.Const (dist/enums/nodeFlags.enum.js).
const sy_node_flag_const = u32(2)

// The seyfert base classes that carry the command lifecycle (COMMAND_BASES).
const sy_command_bases = ['BaseCommand', 'Command', 'SubCommand', 'ContextMenuCommand',
	'EntryPointCommand']

// sy_in_path: the file is under a directory of the installed `seyfert` package (the SEYFERT_DECL
// expressions of the plugin: `/[\\/]seyfert[\\/]lib[\\/]/` and the like, with either separator).
fn sy_in_path(path string, directory string) bool {
	return path.replace('\\', '/').contains(directory)
}

// SyNode is a node of tsgo's AST of a program file; index 0 is no node.
struct SyNode {
	tree  tsgo.AstTree
	index int
}

fn (n SyNode) exists() bool {
	return n.index != 0
}

fn (n SyNode) kind() u32 {
	return n.tree.node_kind(n.index)
}

fn (n SyNode) child(property string) SyNode {
	return SyNode{
		tree:  n.tree
		index: n.tree.node_child(n.index, property)
	}
}

// list is the elements of a list property (`properties`, `arguments`, `modifiers`…).
fn (n SyNode) list(property string) []SyNode {
	row := n.tree.node_child(n.index, property)
	if row == 0 {
		return []SyNode{}
	}
	return n.tree.node_children(row).map(SyNode{
		tree:  n.tree
		index: it
	})
}

fn (n SyNode) parent() SyNode {
	return SyNode{
		tree:  n.tree
		index: n.tree.node_parent(n.index)
	}
}

fn (n SyNode) handle() string {
	return n.tree.node_handle(n.index)
}

// text is the text of an identifier; literal_text the `text` of a literal.
fn (n SyNode) text() string {
	return n.tree.node_text(n.index)
}

fn (n SyNode) literal_text() string {
	return n.tree.node_literal_text(n.index)
}

// decorators ports ts.getDecorators: the decorators among the modifiers of the node.
fn (n SyNode) decorators() []SyNode {
	return n.list('modifiers').filter(it.kind() == sy_kind_decorator)
}

fn (n SyNode) has_modifier(kind u32) bool {
	return n.list('modifiers').any(it.kind() == kind)
}

// sy_node_of_handle is the node of a tsgo handle (`index.kind.path`).
fn (mut c Checker) sy_node_of_handle(handle string) !SyNode {
	if handle == '' {
		return SyNode{}
	}
	return SyNode{
		tree:  c.declaration_ast(handle_path(handle))!
		index: handle.all_before('.').int()
	}
}

// sy_node_at is the counterpart in tsgo's AST of a tree-sitter node of the file, requested with
// resolve_node_types (esTreeNodeToTSNodeMap); no node without one.
fn (mut c Checker) sy_node_at(n C.TSNode) !SyNode {
	return c.sy_node_of_handle(c.node_handles[node_key(n)] or { return SyNode{} })!
}

// sy_position_of is where ESLint reports the counterpart of a node of the file being linted
// (tsNodeToESTreeNodeMap): where the node starts, but for a parenthesized expression, whose
// counterpart is the expression inside it; none for a node of another file.
fn (c &Checker) sy_position_of(n SyNode) ?int {
	if !n.exists() || c.ast_path == '' || n.tree.path != c.ast.path {
		return none
	}
	mut node := n
	for node.kind() == sy_kind_parenthesized_expression {
		node = node.child('expression')
	}
	offset := node.tree.node_token_start(node.index)
	if offset < 0 || offset > c.src.len {
		return none
	}
	return offset
}

// sy_place_of is the place of a report on the counterpart of a node of the file being linted:
// from sy_position_of to where the node ends; none for a node of another file.
fn (c &Checker) sy_place_of(n SyNode) ?treesitter.Ident {
	start := c.sy_position_of(n)?
	mut node := n
	for node.kind() == sy_kind_parenthesized_expression {
		node = node.child('expression')
	}
	end := node.tree.node_end_byte(node.index)
	if end < start || end > c.src.len {
		return c.position_at(start)
	}
	return c.position_range(start, end)
}

// sy_prefetch_symbols asks in one request the symbols of the requested tree-sitter nodes that
// have a counterpart and were not asked yet.
fn (mut c Checker) sy_prefetch_symbols(nodes []C.TSNode) ! {
	mut handles := []string{}
	for n in nodes {
		handle := c.node_handles[node_key(n)] or { continue }
		if handle !in c.sy_symbols && handle !in handles {
			handles << handle
		}
	}
	if handles.len == 0 {
		return
	}
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, handles)!
	if symbols.len != handles.len {
		return error('protocol: tsgo returned ${symbols.len} symbols for ${handles.len} nodes')
	}
	for i, handle in handles {
		c.sy_symbols[handle] = symbols[i]
	}
}

// sy_symbol_at_handle ports checker.getSymbolAtLocation, asked once for each node.
fn (mut c Checker) sy_symbol_at_handle(handle string) !SymbolResponse {
	if handle == '' {
		return SymbolResponse{}
	}
	if handle !in c.sy_symbols {
		symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
		c.sy_symbols[handle] = if symbols.len == 1 { symbols[0] } else { SymbolResponse{} }
	}
	return c.sy_symbols[handle]
}

// sy_symbol_at is services.getSymbolAtLocation of a tree-sitter node requested with
// resolve_node_types; sy_symbol_of the same for a node of tsgo's AST.
fn (mut c Checker) sy_symbol_at(n C.TSNode) !SymbolResponse {
	return c.sy_symbol_at_handle(c.node_handles[node_key(n)] or { return SymbolResponse{} })!
}

fn (mut c Checker) sy_symbol_of(n SyNode) !SymbolResponse {
	if !n.exists() {
		return SymbolResponse{}
	}
	return c.sy_symbol_at_handle(n.handle())!
}

// sy_type_of ports checker.getTypeAtLocation for a node of tsgo's AST, asked once for each node.
fn (mut c Checker) sy_type_of(n SyNode) !TypeResponse {
	if !n.exists() {
		return TypeResponse{}
	}
	handle := n.handle()
	if handle !in c.sy_types {
		types := c.client.types_at_locations(c.snapshot, c.project, [handle])!
		c.sy_types[handle] = if types.len == 1 { types[0] } else { TypeResponse{} }
	}
	return c.sy_types[handle]
}

// sy_declared_type ports checker.getDeclaredTypeOfSymbol, asked once for each symbol.
fn (mut c Checker) sy_declared_type(symbol SymbolResponse) !TypeResponse {
	if symbol.is_null() {
		return TypeResponse{}
	}
	if symbol.id !in c.sy_declared {
		c.sy_declared[symbol.id] = c.client.declared_type_of_symbol(c.snapshot, c.project,
			symbol.id)!
	}
	return c.sy_declared[symbol.id]
}

// sy_unalias ports unalias: an alias is followed to the symbol it stands for.
fn (mut c Checker) sy_unalias(symbol SymbolResponse) !SymbolResponse {
	if symbol.is_null() || symbol.flags & symbol_flag_alias == 0 {
		return symbol
	}
	return c.aliased_symbol(symbol.id)!
}

// sy_export_name ports seyfertExportName: the name of the symbol, after following an alias, when
// one of its declarations is in the seyfert package; '' otherwise (no seyfert export has an
// empty name).
fn (mut c Checker) sy_export_name(symbol SymbolResponse) !string {
	if symbol.is_null() {
		return ''
	}
	original := c.sy_unalias(symbol)!
	for declaration in original.declarations {
		if sy_in_path(handle_path(declaration), '/seyfert/lib/') {
			return unescape_name(original.name)
		}
	}
	return ''
}

// sy_is_seyfert ports isSeyfertSymbol: a seyfert export, named `name` unless it is ''.
fn (mut c Checker) sy_is_seyfert(symbol SymbolResponse, name string) !bool {
	export_name := c.sy_export_name(symbol)!
	return export_name != '' && (name == '' || export_name == name)
}

// sy_construct_return ports `type.getConstructSignatures()[0]?.getReturnType() ?? type`.
fn (mut c Checker) sy_construct_return(t TypeResponse) !TypeResponse {
	if t.is_null() {
		return t
	}
	signatures := c.signatures_of(t, signature_kind_construct)!
	if signatures.len > 0 {
		return c.return_type(signatures[0].id)!
	}
	return t
}

// sy_instance_type ports instanceTypeOfExpression for an expression of the file (the superClass
// of a class): the declared type of its symbol when it is an object type, or else what its type
// constructs.
fn (mut c Checker) sy_instance_type(expression C.TSNode) !TypeResponse {
	symbol := c.sy_symbol_at(expression)!
	if !symbol.is_null() {
		declared := c.sy_declared_type(c.sy_unalias(symbol)!)!
		if !declared.is_null() && declared.flags & type_flag_object != 0 {
			return declared
		}
	}
	t := c.node_type(expression) or { return TypeResponse{} }
	return c.sy_construct_return(t)!
}

// sy_extends_class ports extendsSeyfertClass: the type or one of its ancestors (base types, and
// the generic declaration of an instantiated generic) is a seyfert class with one of those names.
fn (mut c Checker) sy_extends_class(t TypeResponse, names []string) !bool {
	mut seen := map[int]bool{}
	mut stack := [t]
	for stack.len > 0 {
		current := stack.pop()
		if current.is_null() || current.id in seen {
			continue
		}
		seen[current.id] = true
		symbol := if current.alias_symbol != 0 {
			c.alias_symbol_of(current)!
		} else {
			c.symbol_of(current)!
		}
		if !symbol.is_null() && unescape_name(symbol.name) in names
			&& c.sy_export_name(symbol)! != '' {
			return true
		}
		// Type.getBaseTypes is only defined for a class or an interface.
		if current.object_flags & object_flags_class_or_interface != 0 {
			if current.id !in c.base_types_cache {
				c.base_types_cache[current.id] = c.client.base_types(c.snapshot, c.project,
					current.id)!
			}
			stack << c.base_types_cache[current.id]
		}
		if current.flags & type_flag_object != 0 && current.object_flags & object_flag_reference != 0 {
			stack << c.target_of(current)!
		}
	}
	return false
}

// sy_decorator_expression is the ESTree `expression` of a decorator (without parentheses), and
// sy_decorator_callee the callee of the call it is, or the expression itself.
fn sy_decorator_expression(decorator C.TSNode) ?C.TSNode {
	return unwrap_parens(first_named(decorator)?)
}

fn sy_decorator_callee(decorator C.TSNode) ?C.TSNode {
	expression := sy_decorator_expression(decorator)?
	if estree_type(expression) == 'CallExpression' {
		return node_field(expression, 'function')
	}
	return expression
}

// sy_decorator_call is the call of a decorator whose expression is a CallExpression.
fn sy_decorator_call(decorator C.TSNode) ?C.TSNode {
	expression := sy_decorator_expression(decorator)?
	return if estree_type(expression) == 'CallExpression' { expression } else { none }
}

// sy_has_decorator ports hasSeyfertDecorator for the decorators of a class of the file: one of
// them is a call of, or names, the seyfert export `name`.
fn (mut c Checker) sy_has_decorator(decorators []C.TSNode, name string) !bool {
	for decorator in decorators {
		callee := sy_decorator_callee(decorator) or { continue }
		if c.sy_is_seyfert(c.sy_symbol_at(callee)!, name)! {
			return true
		}
	}
	return false
}

// sy_decorator_ts_callee is the same for a decorator of tsgo's AST.
fn sy_decorator_ts_callee(decorator SyNode) SyNode {
	expression := decorator.child('expression')
	return if expression.kind() == sy_kind_call_expression {
		expression.child('expression')
	} else {
		expression
	}
}

// sy_unwrap ports unwrap: without `as`, `satisfies`, parentheses and `!`.
fn sy_unwrap(n SyNode) SyNode {
	mut current := n
	for current.exists() && current.kind() in [sy_kind_as_expression, sy_kind_satisfies_expression,
		sy_kind_parenthesized_expression, sy_kind_non_null_expression] {
		current = current.child('expression')
	}
	return current
}

// sy_symbol_const_initializer ports symbolConstInitializer: the initializer of the `const` the
// symbol is declared by.
fn (mut c Checker) sy_symbol_const_initializer(symbol SymbolResponse) !SyNode {
	if symbol.is_null() || symbol.value_declaration == '' {
		return SyNode{}
	}
	declaration := c.sy_node_of_handle(symbol.value_declaration)!
	if declaration.kind() != sy_kind_variable_declaration {
		return SyNode{}
	}
	initializer := declaration.child('initializer')
	list := declaration.parent()
	if !initializer.exists() || list.tree.node_flags(list.index) & sy_node_flag_const == 0 {
		return SyNode{}
	}
	return initializer
}

// sy_const_initializer ports constInitializer: the initializer of the `const` an identifier or a
// property access refers to, through an import.
fn (mut c Checker) sy_const_initializer(n SyNode) !SyNode {
	mut symbol := c.sy_symbol_of(n)!
	if !symbol.is_null() && symbol.flags & symbol_flag_alias != 0 {
		symbol = c.aliased_symbol(symbol.id)!
	}
	return c.sy_symbol_const_initializer(symbol)!
}

// sy_resolve_object_literal ports resolveObjectLiteral: the object literal an expression ends up
// being, through `const` bindings and imports.
fn (mut c Checker) sy_resolve_object_literal(n SyNode, mut seen map[string]bool) !SyNode {
	expression := sy_unwrap(n)
	if !expression.exists() {
		return SyNode{}
	}
	key := expression.handle()
	if key in seen {
		return SyNode{}
	}
	seen[key] = true
	kind := expression.kind()
	if kind == sy_kind_object_literal_expression {
		return expression
	}
	if kind != sy_kind_identifier && kind != sy_kind_property_access_expression {
		return SyNode{}
	}
	initializer := c.sy_const_initializer(expression)!
	if !initializer.exists() {
		return SyNode{}
	}
	return c.sy_resolve_object_literal(initializer, mut seen)!
}

// sy_property_name ports propertyName: the text of an identifier, string or number key, or of a
// computed string; 'option' for anything else.
fn sy_property_name(name SyNode) string {
	match name.kind() {
		sy_kind_identifier {
			return name.text()
		}
		sy_kind_string_literal, sy_kind_numeric_literal {
			return name.literal_text()
		}
		sy_kind_computed_property_name {
			expression := name.child('expression')
			if expression.kind() in [sy_kind_string_literal, sy_kind_no_substitution_template_literal] {
				return expression.literal_text()
			}
		}
		else {}
	}
	return 'option'
}

// sy_object_property ports objectProperty: the value of a `name: value` property, or the name of
// a shorthand `name`.
fn sy_object_property(object SyNode, name string) SyNode {
	for property in object.list('properties') {
		match property.kind() {
			sy_kind_property_assignment {
				if sy_property_name(property.child('name')) == name {
					return property.child('initializer')
				}
			}
			sy_kind_shorthand_property_assignment {
				if property.child('name').text() == name {
					return property.child('name')
				}
			}
			else {}
		}
	}
	return SyNode{}
}

// sy_string_literal_value ports stringLiteralValue: the value of a string literal or of a template
// without substitutions, after unwrap.
fn sy_string_literal_value(n SyNode) ?string {
	node := sy_unwrap(n)
	if node.kind() in [sy_kind_string_literal, sy_kind_no_substitution_template_literal] {
		return node.literal_text()
	}
	return none
}

// sy_boolean_literal_value ports booleanLiteralValue.
fn sy_boolean_literal_value(n SyNode) ?bool {
	node := sy_unwrap(n)
	return match node.kind() {
		sy_kind_true_keyword { true }
		sy_kind_false_keyword { false }
		else { none }
	}
}

// sy_option_builder_name ports seyfertOptionBuilderName: the name of the seyfert `createXOption`
// builder the expression calls; '' otherwise.
fn (mut c Checker) sy_option_builder_name(n SyNode) !string {
	node := sy_unwrap(n)
	if node.kind() != sy_kind_call_expression {
		return ''
	}
	name := c.sy_export_name(c.sy_symbol_of(node.child('expression'))!)!
	return if sy_is_option_builder(name) { name } else { '' }
}

// sy_is_option_builder: the name of a builder (OPTION_BUILDER, /^create[A-Za-z]*Option$/).
fn sy_is_option_builder(name string) bool {
	if name.len < 'createOption'.len || !name.starts_with('create') || !name.ends_with('Option') {
		return false
	}
	return name['create'.len..name.len - 'Option'.len].bytes().all(it.is_letter())
}

// sy_is_class_node: a ClassDeclaration or a ClassExpression of the file in tree-sitter, and
// sy_class_of_decorator the one a decorator belongs to (ESTree's parent: the class also when the
// decorator comes before its `export`).
fn sy_is_class_node(n C.TSNode) bool {
	return node_kind(n) in ['class_declaration', 'abstract_class_declaration', 'class']
}

fn sy_class_of_decorator(decorator C.TSNode) ?C.TSNode {
	parent := treesitter.node_parent(decorator)?
	if sy_is_class_node(parent) {
		return parent
	}
	if node_kind(parent) == 'export_statement' {
		declaration := node_field(parent, 'declaration')?
		if sy_is_class_node(declaration) {
			return declaration
		}
	}
	return none
}
