module rules

import time
import tsgo { TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { has_child_kind, named_children, node_field, node_kind, node_parent, node_start, nodes_of_kind, position_of }

// Port of the `no-mixed-enums` rule of typescript-eslint 8.72.2 (it has no options).

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
	node    C.vt_node
	name    C.vt_node
	members []C.vt_node
}

fn nme_enum(node C.vt_node) ?NmeEnum {
	name := node_field(node, 'name')?
	body := node_field(node, 'body')?
	return NmeEnum{
		node:    node
		name:    name
		members: named_children(body)
	}
}

// nme_initializer is the ESTree initializer of a member (without parentheses), if any.
fn nme_initializer(member C.vt_node) ?C.vt_node {
	if node_kind(member) != 'enum_assignment' {
		return none
	}
	return unwrap_parens(node_field(member, 'value')?)
}

fn (mut c Checker) lint_no_mixed_enums(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
	// Multiple enum declarations in the same file, also merged across declarations of a
	// namespace (getEnclosingScopes): the first earlier one with members.
	name := c.identifier_name(e.name)
	for s in c.nme_enclosing_scopes(scopes, e.node, 0) {
		v := scopes.own_variable(s, name)
		if v < 0 {
			continue
		}
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
	// The type of the first member.
	return c.nme_member_type(e.members[0])!
}

// nme_enclosing_scopes ports getEnclosingScopes of an enum or a module declaration: the scope
// around it and, when it is exported from a namespace, the scopes of every declaration of that
// namespace in the scopes around it (getMergedScopes).
fn (c &Checker) nme_enclosing_scopes(scopes &ScopeTree, node C.vt_node, depth int) []int {
	enclosing := scopes.scopes[scopes.get_scope(node)].upper
	if enclosing < 0 {
		return []int{}
	}
	if !nme_is_exported(node) || depth > max_expression_depth {
		return [enclosing]
	}
	// getMergedScopes
	scope := scopes.scopes[enclosing]
	if scope.kind != .ts_module {
		return [enclosing]
	}
	name := c.nme_module_name(scope.block)
	mut out := []int{}
	for around in c.nme_enclosing_scopes(scopes, scope.block, depth + 1) {
		for child in scopes.scopes[around].children {
			if scopes.scopes[child].kind == .ts_module
				&& c.nme_module_name(scopes.scopes[child].block) == name {
				out << child
			}
		}
	}
	return out
}

// nme_is_exported: the ESTree parent of the declaration (a `declare` is part of it) is an
// ExportNamedDeclaration.
fn nme_is_exported(node C.vt_node) bool {
	mut parent := node_parent(node) or { return false }
	if node_kind(parent) == 'ambient_declaration' {
		parent = node_parent(parent) or { return false }
	}
	return node_kind(parent) == 'export_statement' && !has_child_kind(parent, 'default')
}

// nme_module_name ports getModuleName for the block of a module scope: the JSON of a string name,
// `global`, or the name with its qualifiers (`A.B.C`), which are only compared with each other.
fn (c &Checker) nme_module_name(block C.vt_node) string {
	if node_kind(block) == 'ambient_declaration' {
		return 'global'
	}
	id := node_field(block, 'name') or { return '' }
	if node_kind(id) == 'string' {
		return '"' + c.text(id)#[1..-1] + '"'
	}
	return c.text(id).split('.').map(it.trim_space()).join('.')
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
fn (mut c Checker) nme_member_type(member C.vt_node) !NmeAllowed {
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
