module rules

import time
import tsgo { TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { named_children, node_field, node_kind, node_parent, node_start, nodes_of_kind, position_of }

// Port of the `no-mixed-enums` rule of typescript-eslint 8.62.0 (it has no options).

const nme_messages = {
	'mixed': 'Mixing number and string enums can be confusing.'
}

// NmeAllowed ports AllowedType.
enum NmeAllowed {
	number
	string
	unknown
}

// NmeEnum is an enum declaration with its members (ESTree TSEnumMember: an enum_assignment or a
// bare name).
struct NmeEnum {
	node    C.TSNode
	name    C.TSNode
	members []C.TSNode
}

fn nme_enum(node C.TSNode) ?NmeEnum {
	name := node_field(node, 'name')?
	body := node_field(node, 'body')?
	return NmeEnum{
		node:    node
		name:    name
		members: named_children(body)
	}
}

// nme_initializer is the ESTree initializer of a member (without parentheses), if any.
fn nme_initializer(member C.TSNode) ?C.TSNode {
	if node_kind(member) != 'enum_assignment' {
		return none
	}
	return unwrap_parens(node_field(member, 'value')?)
}

fn (mut c Checker) lint_no_mixed_enums(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut enums := []NmeEnum{}
	mut spans := []Span{}
	for node in c.nodes_of_kind(root, c'enum_declaration') {
		e := nme_enum(node) or { continue }
		if e.members.len == 0 {
			continue
		}
		enums << e
		spans << node_span(e.name)
		for member in e.members {
			if init := nme_initializer(member) {
				spans << node_span(init)
			}
		}
	}
	scopes := c.scope_tree(root)
	// The specifiers of the imports a desired type may come from.
	for e in enums {
		for definition in c.nme_imports(scopes, e) {
			if span := nme_import_span(definition) {
				spans << span
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for e in enums {
		mut desired := c.nme_desired_type(scopes, e)!
		if desired == .unknown {
			continue
		}
		for member in e.members {
			current := c.nme_member_type(member)!
			if current == .unknown {
				break
			}
			if current != desired {
				report := nme_initializer(member) or { member }
				findings << Finding{
					stmt:       position_of(report)
					message_id: 'mixed'
				}
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += enums.len
	return findings
}

// nme_imports ports the import part of collectNodeDefinitions: the import bindings named like the
// enum in its scope and every scope above, in that order.
fn (c &Checker) nme_imports(scopes &ScopeTree, e NmeEnum) []ScopeDefinition {
	name := c.identifier_name(e.name)
	mut out := []ScopeDefinition{}
	mut s := scopes.get_scope(e.node)
	for s >= 0 {
		v := scopes.own_variable(s, name)
		if v >= 0 {
			for definition in scopes.variables[v].defs {
				if definition.kind == .import_binding {
					out << definition
				}
			}
		}
		s = scopes.scopes[s].upper
	}
	return out
}

// nme_import_span is the node typescript-eslint gives getTypeAtLocation for an import binding: the
// ImportSpecifier, the ImportClause of a default import, the NamespaceImport, or the
// ImportEqualsDeclaration.
fn nme_import_span(definition ScopeDefinition) ?Span {
	node := definition.node
	if node_kind(node) == 'identifier' {
		// A default import: its specifier is the ImportClause.
		return node_span(node_parent(node)?)
	}
	return node_span(node)
}

// nme_desired_type ports getDesiredTypeForDefinition.
fn (mut c Checker) nme_desired_type(scopes &ScopeTree, e NmeEnum) !NmeAllowed {
	// Merged ambiently via module augmentation.
	for definition in c.nme_imports(scopes, e) {
		found, allowed := c.nme_type_from_imported(definition)!
		if found {
			return allowed
		}
	}
	// Multiple enum declarations in the same scope (scope.upper.set of the enum's own scope).
	name := c.identifier_name(e.name)
	enum_scope := scopes.get_scope(e.node)
	upper := scopes.scopes[enum_scope].upper
	if upper >= 0 {
		v := scopes.own_variable(upper, name)
		if v >= 0 {
			for definition in scopes.variables[v].defs {
				if definition.kind != .ts_enum_name
					|| node_start(definition.node) >= node_start(e.node) {
					continue
				}
				previous := nme_enum(definition.node) or { continue }
				if previous.members.len > 0 {
					return c.nme_member_type(previous.members[0])!
				}
			}
		}
	}
	// Namespace declaration merging: an exported enum of a namespace or module body.
	if c.nme_in_module_block(e.node) {
		return c.nme_namespace_type(e)!
	}
	// The type of the first member.
	return c.nme_member_type(e.members[0])!
}

// nme_in_module_block: the enum's ESTree parent is an ExportNamedDeclaration of a TSModuleBlock.
fn (c &Checker) nme_in_module_block(node C.TSNode) bool {
	mut parent := node_parent(node) or { return false }
	if node_kind(parent) == 'ambient_declaration' {
		parent = node_parent(parent) or { return false }
	}
	if node_kind(parent) != 'export_statement' {
		return false
	}
	block := node_parent(parent) or { return false }
	container := node_parent(block) or { return false }
	return node_kind(block) == 'statement_block'
		&& node_kind(container) in ['internal_module', 'module']
}

// nme_namespace_type: the first member of the first declaration of the enum's symbol is a string
// if its initializer has a string-like type. When that declaration has no members typescript-eslint
// crashes; veslint takes it as a member without initializer (a number).
fn (mut c Checker) nme_namespace_type(e NmeEnum) !NmeAllowed {
	handle := c.node_handles[node_key(e.name)] or { return NmeAllowed.number }
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
	if symbols.len == 0 || symbols[0].is_null() || symbols[0].declarations.len == 0 {
		return NmeAllowed.number
	}
	declaration := symbols[0].declarations[0]
	tree := c.declaration_ast(handle_path(declaration))!
	members := tree.node_children(tree.node_child(handle_index(declaration), 'members'))
	if members.len == 0 {
		return NmeAllowed.number
	}
	initializer := tree.node_child(members[0], 'initializer')
	if initializer == 0 {
		return NmeAllowed.number
	}
	return if c.nme_handle_string_like(tree.node_handle(initializer))! {
		NmeAllowed.string
	} else {
		NmeAllowed.number
	}
}

// nme_type_from_imported ports getTypeFromImported: the type of the first member of the enum an
// import binding resolves to; `found` is false if it is not an enum with members (undefined).
fn (mut c Checker) nme_type_from_imported(definition ScopeDefinition) !(bool, NmeAllowed) {
	span := nme_import_span(definition) or { return false, NmeAllowed.unknown }
	t := c.span_type(span) or { return false, NmeAllowed.unknown }
	if t.symbol == 0 {
		return false, NmeAllowed.unknown
	}
	symbol := c.symbol_of(t)!
	declaration := symbol.value_declaration
	if symbol.is_null() || declaration == ''
		|| handle_kind(declaration) != syntax_kind_enum_declaration {
		return false, NmeAllowed.unknown
	}
	tree := c.declaration_ast(handle_path(declaration))!
	members := tree.node_children(tree.node_child(handle_index(declaration), 'members'))
	if members.len == 0 {
		return false, NmeAllowed.unknown
	}
	allowed := if c.nme_handle_string_like(tree.node_handle(members[0]))! {
		NmeAllowed.string
	} else {
		NmeAllowed.number
	}
	return true, allowed
}

// nme_handle_string_like: the type at a node (any file) has the StringLike flags (its own).
fn (mut c Checker) nme_handle_string_like(handle string) !bool {
	types := c.client.types_at_locations(c.snapshot, c.project, [handle])!
	return types.len == 1 && types[0].flags & type_flag_string_like != 0
}

// nme_member_type ports getMemberType.
fn (mut c Checker) nme_member_type(member C.TSNode) !NmeAllowed {
	initializer := nme_initializer(member) or { return NmeAllowed.number }
	match node_kind(initializer) {
		'number' {
			// A BigInt literal has typeof 'bigint'.
			return if c.text(initializer).ends_with('n') {
				NmeAllowed.unknown
			} else {
				NmeAllowed.number
			}
		}
		'string' {
			return .string
		}
		'true', 'false', 'null', 'regex' {
			return .unknown
		}
		'template_string' {
			return .string
		}
		else {
			t := c.node_type(initializer) or { TypeResponse{} }
			return if t.flags & type_flag_string_like != 0 {
				NmeAllowed.string
			} else {
				NmeAllowed.number
			}
		}
	}
}
