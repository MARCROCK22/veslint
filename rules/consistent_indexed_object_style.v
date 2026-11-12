module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `consistent-indexed-object-style` rule of typescript-eslint 8.62.0, with its option
// ('record' or 'index-signature'), its fixes and its suggestions.

const cios_messages = {
	'preferIndexSignature':           'An index signature is preferred over a record.'
	'preferIndexSignatureSuggestion': 'Change into an index signature instead of a record.'
	'preferRecord':                   'A record is preferred over an index signature.'
	'preferRecordSuggestion':         'Change into a record instead of an index signature.'
}

fn cios_options(options []json2.Any) !string {
	option := if options.len > 0 { options[0] } else { json2.Any('record') }
	if option is string {
		mode := option as string
		if mode in ['record', 'index-signature'] {
			return mode
		}
	}
	return error('the option of `${consistent_indexed_object_style}` must be one of: record, index-signature')
}

// CiosRole is the ESTree node a tree-sitter node stands for in isDeeplyReferencingType: one node
// may be several (a bare type name is a TSTypeReference and its Identifier).
enum CiosRole {
	type_node  // a TypeNode
	alias      // TSTypeAliasDeclaration
	interface  // TSInterfaceDeclaration
	member     // a member of an interface or of a TSTypeLiteral
	annotation // TSTypeAnnotation
	arguments  // TSTypeParameterInstantiation
	name       // the Identifier of a TSTypeReference
	other      // anything else, which never references the type
}

fn (mut c Checker) lint_consistent_indexed_object_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mode := cios_options(c.rule_options(consistent_indexed_object_style))!
	mut findings := []Finding{}
	mut checked := 0
	if mode == 'index-signature' {
		for node in c.nodes_of_kinds(root, ['generic_type'], []) {
			if c.cios_record_type(node, mut findings)! {
				checked++
			}
		}
	} else {
		for node in c.nodes_of_kinds(root, ['interface_declaration', 'object_type'], []) {
			checked++
			if node_kind(node) == 'interface_declaration' {
				c.cios_interface(root, node, mut findings)!
			} else if clause := scope_mapped_clause(node) {
				c.cios_mapped_type(root, node, clause, mut findings)!
			} else {
				// TSTypeLiteral.
				mut parent_id := ?C.TSNode(none)
				if declaration := cios_parent_declaration(node) {
					parent_id = node_field(declaration, 'name')
				}
				c.cios_check_members(root, named_children(node), node, node, parent_id, '',
					'', true, mut findings)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// cios_record_type ports the TSTypeReference listener of 'index-signature': `Record<K, V>`
// becomes `{ [key: K]: V }`, a fix when K is `string`, `number` or `symbol` and no comment would
// be lost, a suggestion otherwise. It tells whether the node is a reference to `Record`.
fn (mut c Checker) cios_record_type(node C.TSNode, mut findings []Finding) !bool {
	name := node_field(node, 'name') or { return false }
	if node_kind(name) != 'type_identifier' || type_name_role(name) != .reference
		|| c.identifier_name(name) != 'Record' {
		return false
	}
	args := node_field(node, 'type_arguments') or { return false }
	params := named_children(args).map(unwrap_type_parens(it))
	if params.len != 2 {
		return true
	}
	should_fix := node_kind(params[0]) == 'predefined_type'
		&& c.text(params[0]) in ['string', 'number', 'symbol']
	fix := fix_replace(node, '{ [key: ${c.text(params[0])}]: ${c.text(params[1])} }')
	if should_fix && !c.cios_has_unpreserved_comments(node, node_start(node), node_end(node), params) {
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'preferIndexSignature'
			has_fix:    true
			fix:        fix
		}
	} else {
		_, suggestion := c.suggestion('preferIndexSignatureSuggestion', map[string]string{},
			[fix])!
		findings << Finding{
			stmt:        position_of(node)
			message_id:  'preferIndexSignature'
			suggestions: [suggestion]
		}
	}
	return true
}

// cios_interface ports the TSInterfaceDeclaration listener: an interface with a single index
// signature becomes a type alias, unless it extends something or is a default export (there is no
// `export default type`), which are reported without a fix.
fn (mut c Checker) cios_interface(root C.TSNode, node C.TSNode, mut findings []Finding) ! {
	id := node_field(node, 'name') or { return }
	body := node_field(node, 'body') or { return }
	mut generic_types := ''
	if parameters := node_field(node, 'type_parameters') {
		list := named_children(parameters)
		if list.len > 0 {
			generic_types = '<${list.map(c.text(it)).join(', ')}>'
		}
	}
	// A declared interface starts at its `declare`.
	mut report := node
	mut export_default := false
	if parent := node_parent(node) {
		if node_kind(parent) == 'ambient_declaration' {
			report = parent
		} else if node_kind(parent) == 'export_statement' {
			export_default = children_of_kind(parent, 'default').len > 0
		}
	}
	extends := children_of_kind(node, 'extends_type_clause').len > 0
	c.cios_check_members(root, named_children(body), node, report, id, 'type ${c.identifier_name(id)}${generic_types} = ',
		';', !extends && !export_default, mut findings)!
}

// cios_check_members ports checkMembers: a single index signature `[key: K]: V` makes the type
// (from `report` to the end of `node`) a `Record<K, V>`, unless it references the type alias or
// interface it belongs to (`parent_id`).
fn (mut c Checker) cios_check_members(root C.TSNode, members []C.TSNode, node C.TSNode, report C.TSNode, parent_id ?C.TSNode, prefix string, postfix string, safe_fix bool, mut findings []Finding) ! {
	if members.len != 1 || node_kind(members[0]) != 'index_signature' {
		return
	}
	member := members[0]
	// An index signature without a parameter is a TSMappedType in a type literal, and a property
	// with a computed name in an interface.
	if !cios_signature_has_name(member) {
		return
	}
	key_type := unwrap_type_parens(node_field(member, 'index_type') or { return })
	annotation := node_field(member, 'type') or { return }
	value_type := unwrap_type_parens(first_named(annotation) or { return })
	if id := parent_id {
		tree := c.scope_tree(root)
		super_var := tree.find_variable(tree.get_scope(id), c.identifier_name(id), -1)
		if super_var >= 0 {
			role := if node_kind(node) == 'interface_declaration' {
				CiosRole.interface
			} else {
				CiosRole.type_node
			}
			mut visited := map[string]bool{}
			visited[cios_visit_key(id, .name)] = true
			if c.cios_deeply_references(tree, node, role, super_var, mut visited) {
				return
			}
		}
	}
	key := c.text(key_type)
	value := c.text(value_type)
	record := if children_of_kind(member, 'readonly').len > 0 {
		'Readonly<Record<${key}, ${value}>>'
	} else {
		'Record<${key}, ${value}>'
	}
	start := node_start(report)
	end := node_end(node)
	fix := fix_replace_range(start, end, '${prefix}${record}${postfix}')
	c.cios_report(report, safe_fix, c.cios_has_unpreserved_comments(node, start, end, [
		key_type,
		value_type,
	]), fix, mut findings)!
}

// cios_mapped_type ports the TSMappedType listener: `{ [K in T]: V }` becomes `Record<T, V>`,
// with `Partial`, `Required` and `Readonly` for its modifiers.
fn (mut c Checker) cios_mapped_type(root C.TSNode, node C.TSNode, clause C.TSNode, mut findings []Finding) ! {
	key := node_field(clause, 'name') or { return }
	tree := c.scope_tree(root)
	scope := tree.get_scope(key)
	key_name := c.identifier_name(key)
	mut key_variable := -1
	for v in tree.scopes[scope].variables {
		if tree.variables[v].name == key_name && tree.variables[v].is_type_variable() {
			key_variable = v
			break
		}
	}
	if key_variable < 0 {
		return
	}
	// The key is used to compute the value.
	if tree.variables[key_variable].references.any(tree.references[it].type_ref) {
		return
	}
	constraint_node := node_field(clause, 'type') or { return }
	constraint := unwrap_type_parens(constraint_node)
	// `[K in keyof T]` keeps the modifiers of T, which a Record does not.
	if node_kind(constraint) == 'index_type_query' && node_kind(constraint_node) != 'parenthesized_type' {
		return
	}
	// A circular mapped type cannot be a Record.
	if declaration := cios_parent_declaration(node) {
		if parent_id := node_field(declaration, 'name') {
			super_var := tree.find_variable(scope, c.identifier_name(parent_id), -1)
			if super_var >= 0 {
				parent, role := cios_es_parent(node)
				mut visited := map[string]bool{}
				visited[cios_visit_key(parent_id, .name)] = true
				if c.cios_deeply_references(tree, parent, role, super_var, mut visited) {
					return
				}
			}
		}
	}
	signature := first_named(node) or { return }
	annotation := node_field(signature, 'type') or { return }
	value_type := unwrap_type_parens(first_named(annotation) or { return })
	mut readonly := ''
	if children_of_kind(signature, 'readonly').len > 0 {
		readonly = if sign := node_field(signature, 'sign') { node_kind(sign) } else { 'true' }
	}
	mut record := 'Record<${c.text(constraint)}, ${c.text(value_type)}>'
	match node_kind(annotation) {
		'opting_type_annotation', 'adding_type_annotation' { record = 'Partial<${record}>' }
		'omitting_type_annotation' { record = 'Required<${record}>' }
		else {}
	}
	if readonly in ['+', 'true'] {
		record = 'Readonly<${record}>'
	}
	// There is no Mutable<T>: a `-readonly` mapped type is reported without a fix.
	c.cios_report(node, readonly != '-', c.cios_has_unpreserved_comments(node, node_start(node),
		node_end(node), [constraint, value_type]), fix_replace(node, record), mut findings)!
}

// cios_report reports preferRecord with getFixOrSuggest: the fix, the fix as a suggestion when a
// comment would be lost, or neither.
fn (mut c Checker) cios_report(report C.TSNode, can_fix bool, unpreserved bool, fix Fix, mut findings []Finding) ! {
	if !can_fix {
		findings << Finding{
			stmt:       position_of(report)
			message_id: 'preferRecord'
		}
	} else if unpreserved {
		_, suggestion := c.suggestion('preferRecordSuggestion', map[string]string{}, [fix])!
		findings << Finding{
			stmt:        position_of(report)
			message_id:  'preferRecord'
			suggestions: [suggestion]
		}
	} else {
		findings << Finding{
			stmt:       position_of(report)
			message_id: 'preferRecord'
			has_fix:    true
			fix:        fix
		}
	}
}

// cios_has_unpreserved_comments ports hasUnpreservedComments: a comment in [start, end) outside
// every preserved node, which the fix would drop.
fn (mut c Checker) cios_has_unpreserved_comments(node C.TSNode, start int, end int, preserved []C.TSNode) bool {
	tokens := c.source_tokens(node)
	for comment in tokens.comments_inside(start, end) {
		if preserved.all(comment.start < node_start(it) || comment.end > node_end(it)) {
			return true
		}
	}
	return false
}

// cios_parent_declaration ports findParentDeclaration: the type alias around a type, unless a
// TSTypeAnnotation comes first.
fn cios_parent_declaration(n C.TSNode) ?C.TSNode {
	mut node := n
	for {
		parent := node_parent(node) or { return none }
		if cios_is_type_annotation(parent, node) {
			return none
		}
		if node_kind(parent) == 'type_alias_declaration' {
			return parent
		}
		node = parent
	}
	return none
}

// cios_is_type_annotation: `parent` is, or holds `child` in, a TSTypeAnnotation. tree-sitter has
// no node for the TSTypeAnnotation of the return type of a function type, of the type of a type
// predicate and of the key of an index signature; the value of a mapped type and the type of a
// named tuple member have none in ESTree.
fn cios_is_type_annotation(parent C.TSNode, child C.TSNode) bool {
	match node_kind(parent) {
		'type_annotation' {
			holder := node_parent(parent) or { return true }
			if cios_is_tuple_member(holder) {
				return false
			}
			return node_kind(holder) != 'index_signature' || cios_signature_has_name(holder)
		}
		'type_predicate_annotation', 'asserts_annotation' {
			return true
		}
		'type_predicate' {
			return cios_field_is(parent, 'type', child)
		}
		'function_type' {
			return cios_field_is(parent, 'return_type', child)
		}
		'constructor_type' {
			return cios_field_is(parent, 'type', child)
		}
		'index_signature' {
			return cios_field_is(parent, 'index_type', child)
		}
		else {
			return false
		}
	}
}

// cios_signature_has_name: the index signature has a parameter (`[key: K]`), so it is not the
// one of a mapped type.
fn cios_signature_has_name(signature C.TSNode) bool {
	if _ := node_field(signature, 'name') {
		return true
	}
	return false
}

// cios_is_tuple_member: a named member of a tuple type (`[name: T]`, `[name?: T]`,
// `[...name: T]`), which tree-sitter reads as a parameter.
fn cios_is_tuple_member(holder C.TSNode) bool {
	if node_kind(holder) !in ['required_parameter', 'optional_parameter'] {
		return false
	}
	tuple := node_parent(holder) or { return false }
	return node_kind(tuple) == 'tuple_type'
}

fn cios_field_is(parent C.TSNode, field string, child C.TSNode) bool {
	value := node_field(parent, field) or { return false }
	return node_key(value) == node_key(child)
}

// cios_es_parent is the ESTree parent of a type node and what it is: parentheses are not nodes,
// a union or an intersection is the outermost one tree-sitter nests to the left, and the parts of
// a mapped type belong to the TSMappedType itself.
fn cios_es_parent(n C.TSNode) (C.TSNode, CiosRole) {
	mut parent := node_parent(n) or { return n, CiosRole.other }
	for node_kind(parent) == 'parenthesized_type' {
		parent = node_parent(parent) or { return n, CiosRole.other }
	}
	kind := node_kind(parent)
	if kind in ['union_type', 'intersection_type'] {
		for {
			outer := node_parent(parent) or { break }
			if node_kind(outer) != kind {
				break
			}
			parent = outer
		}
		return parent, CiosRole.type_node
	}
	if kind in ['type_annotation', 'opting_type_annotation', 'omitting_type_annotation',
		'adding_type_annotation', 'mapped_type_clause'] {
		holder := node_parent(parent) or { return parent, CiosRole.other }
		if node_kind(holder) == 'index_signature' && !cios_signature_has_name(holder) {
			// The value or the constraint of a mapped type.
			mapped := node_parent(holder) or { return parent, CiosRole.other }
			return mapped, CiosRole.type_node
		}
		if cios_is_tuple_member(holder) {
			// A TSNamedTupleMember has its type without a TSTypeAnnotation.
			return holder, CiosRole.other
		}
		return parent, CiosRole.annotation
	}
	role := match kind {
		'type_alias_declaration' { CiosRole.alias }
		'type_arguments' { CiosRole.arguments }
		'object_type', 'lookup_type', 'conditional_type' { CiosRole.type_node }
		else { CiosRole.other }
	}
	return parent, role
}

fn cios_visit_key(n C.TSNode, role CiosRole) string {
	return '${node_start(n)}-${node_end(n)}-${node_kind(n)}-${int(role)}'
}

// cios_deeply_references ports isDeeplyReferencingType: whether the type references the variable
// `super_var` of the type alias or interface it belongs to, directly or through the type aliases
// and interfaces it names. `visited` keeps it from going round a cycle.
fn (c &Checker) cios_deeply_references(tree &ScopeTree, n C.TSNode, role CiosRole, super_var int, mut visited map[string]bool) bool {
	key := cios_visit_key(n, role)
	if visited[key] {
		// Something on the chain is circular, but not the reference being checked.
		return false
	}
	visited[key] = true
	match role {
		.alias {
			value := node_field(n, 'value') or { return false }
			return c.cios_deeply_references(tree, unwrap_type_parens(value), .type_node, super_var, mut
				visited)
		}
		.interface {
			body := node_field(n, 'body') or { return false }
			for member in named_children(body) {
				if c.cios_deeply_references(tree, member, .member, super_var, mut visited) {
					return true
				}
			}
			return false
		}
		.member {
			// A TSIndexSignature, through its type annotation; other members are not followed.
			if node_kind(n) != 'index_signature' || !cios_signature_has_name(n) {
				return false
			}
			annotation := node_field(n, 'type') or { return false }
			return c.cios_deeply_references(tree, annotation, .annotation, super_var, mut visited)
		}
		.annotation {
			inner := first_named(n) or { return false }
			return c.cios_deeply_references(tree, unwrap_type_parens(inner), .type_node, super_var, mut
				visited)
		}
		.arguments {
			for param in named_children(n) {
				if c.cios_deeply_references(tree, unwrap_type_parens(param), .type_node, super_var, mut
					visited)
				{
					return true
				}
			}
			return false
		}
		.name {
			return c.cios_name_references(tree, n, super_var, mut visited)
		}
		.type_node {
			return c.cios_type_references(tree, n, super_var, mut visited)
		}
		.other {
			return false
		}
	}
}

// cios_type_references is the TypeNode part of isDeeplyReferencingType.
fn (c &Checker) cios_type_references(tree &ScopeTree, n C.TSNode, super_var int, mut visited map[string]bool) bool {
	mut parts := []C.TSNode{}
	match node_kind(n) {
		'object_type' {
			if _ := scope_mapped_clause(n) {
				// TSMappedType: its value type.
				signature := first_named(n) or { return false }
				annotation := node_field(signature, 'type') or { return false }
				inner := first_named(annotation) or { return false }
				parts << unwrap_type_parens(inner)
			} else {
				// TSTypeLiteral: its members.
				for member in named_children(n) {
					if c.cios_deeply_references(tree, member, .member, super_var, mut visited) {
						return true
					}
				}
				return false
			}
		}
		'lookup_type' {
			// TSIndexedAccessType: the index type, then the object type.
			list := named_children(n)
			if list.len == 2 {
				parts << unwrap_type_parens(list[1])
				parts << unwrap_type_parens(list[0])
			}
		}
		'conditional_type' {
			for field in ['left', 'right', 'alternative', 'consequence'] {
				if part := node_field(n, field) {
					parts << unwrap_type_parens(part)
				}
			}
		}
		'union_type', 'intersection_type' {
			parts << type_members(n)
		}
		'type_identifier' {
			// A TSTypeReference whose name is an Identifier.
			return c.cios_deeply_references(tree, n, .name, super_var, mut visited)
		}
		'generic_type' {
			name := node_field(n, 'name') or { return false }
			if node_kind(name) == 'type_identifier' {
				if c.cios_deeply_references(tree, name, .name, super_var, mut visited) {
					return true
				}
			} else if node_kind(name) != 'nested_type_identifier' {
				// An import type with type arguments is a TSImportType.
				return false
			}
			args := node_field(n, 'type_arguments') or { return false }
			return c.cios_deeply_references(tree, args, .arguments, super_var, mut visited)
		}
		else {
			return false
		}
	}
	for part in parts {
		if c.cios_deeply_references(tree, part, .type_node, super_var, mut visited) {
			return true
		}
	}
	return false
}

// cios_name_references is the Identifier part of isDeeplyReferencingType: a name the variable has
// a reference with (isNodeEqual compares the names of two Identifiers), or the definitions of the
// variable the name finds from the scope of `super_var`.
fn (c &Checker) cios_name_references(tree &ScopeTree, n C.TSNode, super_var int, mut visited map[string]bool) bool {
	name := c.identifier_name(n)
	variable := tree.variables[super_var]
	for r in variable.references {
		reference := tree.references[r]
		if reference.name == name && !node_kind(reference.identifier).starts_with('jsx') {
			return true
		}
	}
	referenced := tree.find_variable(variable.scope, name, -1)
	if referenced < 0 {
		return false
	}
	for definition in tree.variables[referenced].defs {
		role := match node_kind(definition.node) {
			'type_alias_declaration' { CiosRole.alias }
			'interface_declaration' { CiosRole.interface }
			'object_type' { CiosRole.type_node }
			else { CiosRole.other }
		}
		if c.cios_deeply_references(tree, definition.node, role, super_var, mut visited) {
			return true
		}
	}
	return false
}
