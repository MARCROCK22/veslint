module rules

import json2
import time
import tsgo { SymbolResponse, TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { named_children, node_field, node_kind, node_parent, nodes_of_kinds, position_of }

// Port of the `unbound-method` rule of typescript-eslint 8.62.0, with its option. The natively bound
// members of the globals come from rules/unbound_method_natives.v.

const ubm_messages = {
	'unbound':                      'A method that is not declared with `this: void` may cause unintentional scoping of `this` when separated from its object.\nConsider using an arrow function or explicitly `.bind()`ing the method to avoid calling the method with an unintended `this` value. '
	'unboundWithoutThisAnnotation': 'A method that is not declared with `this: void` may cause unintentional scoping of `this` when separated from its object.\nConsider using an arrow function or explicitly `.bind()`ing the method to avoid calling the method with an unintended `this` value. \nIf a function does not access `this`, it can be annotated with `this: void`.'
}

// SUPPORTED_GLOBAL_TYPES of the rule.
const ubm_supported_global_types = ['NumberConstructor', 'ObjectConstructor', 'StringConstructor',
	'SymbolConstructor', 'ArrayConstructor', 'Array', 'ProxyConstructor', 'Console', 'DateConstructor',
	'Atomics', 'Math', 'JSON']

// SyntaxKind MethodDeclaration (175) is in type_queries.v; these are the other ones of checkIfMethod.
const ubm_kinds_with_initializer = [syntax_kind_property_declaration, syntax_kind_property_assignment]

struct UbmOptions {
	ignore_static bool
}

fn ubm_options(options []json2.Any) !UbmOptions {
	o := option_object(unbound_method, options, ['ignoreStatic'])!
	return UbmOptions{
		ignore_static: o.bool_value('ignoreStatic')!
	}
}

// UbmMember is a MemberExpression that is not a safe use, with its ESTree object and property.
struct UbmMember {
	node     C.TSNode
	object   C.TSNode
	property C.TSNode
}

// UbmPattern is an ObjectPattern with the node it is initialized from and its identifier keys.
struct UbmPattern {
	pattern               C.TSNode
	init                  ?C.TSNode
	in_assignment_pattern bool
	keys                  []C.TSNode
}

fn (mut c Checker) lint_unbound_method(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := ubm_options(c.rule_options(unbound_method))!
	mut members := []UbmMember{}
	mut patterns := []UbmPattern{}
	for node in c.nodes_of_kinds(root, ['member_expression', 'subscript_expression', 'object_pattern'],
		type_name_kinds) {
		if node_kind(node) == 'object_pattern' {
			if pattern := c.ubm_pattern(node) {
				patterns << pattern
			}
			continue
		}
		if ubm_in_type_query(node) || c.ubm_is_safe_use(node, 0) {
			continue
		}
		object := node_field(node, 'object') or { continue }
		property := member_property(node) or { continue }
		members << UbmMember{
			node:     node
			object:   unwrap_parens(object)
			property: property
		}
	}
	mut spans := []Span{}
	for m in members {
		spans << node_span(m.node)
		spans << node_span(m.object)
		spans << node_span(m.property)
	}
	for p in patterns {
		spans << node_span(p.pattern)
		if init := p.init {
			spans << node_span(init)
		}
		spans << p.keys.map(node_span(it))
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	// The symbols of the member expressions and of the identifiers isNativelyBound names, in one
	// request.
	mut handles := []string{}
	mut symbol_keys := []u64{}
	for m in members {
		for n in [m.node, m.object] {
			if handle := c.node_handles[node_key(n)] {
				handles << handle
				symbol_keys << node_key(n)
			}
		}
	}
	for p in patterns {
		if init := p.init {
			if handle := c.node_handles[node_key(init)] {
				handles << handle
				symbol_keys << node_key(init)
			}
		}
	}
	mut symbols := map[u64]SymbolResponse{}
	if handles.len > 0 {
		found := c.client.symbols_at_locations(c.snapshot, c.project, handles)!
		for i, symbol in found {
			if i < symbol_keys.len {
				symbols[symbol_keys[i]] = symbol
			}
		}
	}
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for m in members {
		if c.ubm_is_natively_bound(m.object, m.property, symbols)! {
			continue
		}
		symbol := symbols[node_key(m.node)] or { continue }
		message_id := c.ubm_check_if_method(symbol, o)!
		if message_id != '' {
			findings << Finding{
				stmt:       position_of(m.node)
				message_id: message_id
			}
		}
	}
	for p in patterns {
		for key in p.keys {
			name := c.identifier_name(key)
			if init := p.init {
				if !c.ubm_is_natively_bound(init, key, symbols)! {
					init_type := c.node_type(init) or { TypeResponse{} }
					if !init_type.is_null() {
						message_id := c.ubm_check_if_method(c.property(init_type, name)!, o)!
						if message_id != '' {
							findings << Finding{
								stmt:       position_of(key)
								message_id: message_id
							}
							continue
						}
					}
				} else if !p.in_assignment_pattern {
					continue
				}
			}
			pattern_type := c.node_type(p.pattern) or { continue }
			for union_part in c.constituents(pattern_type)! {
				parts := if union_part.flags & type_flag_intersection != 0 {
					c.members_of(union_part)!
				} else {
					[union_part]
				}
				mut reported := false
				for part in parts {
					message_id := c.ubm_check_if_method(c.property(part, name)!, o)!
					if message_id != '' {
						findings << Finding{
							stmt:       position_of(key)
							message_id: message_id
						}
						reported = true
						break
					}
				}
				if reported {
					break
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += members.len + patterns.len
	return findings
}

// ubm_in_type_query: the member expression is part of a `typeof` type query (a TSQualifiedName in
// ESTree) or of an import type that tree-sitter reads as a member access.
fn ubm_in_type_query(n C.TSNode) bool {
	mut node := n
	for _ in 0 .. max_expression_depth {
		parent := node_parent(node) or { return false }
		match node_kind(parent) {
			'member_expression', 'subscript_expression' {
				node = parent
			}
			'type_query' {
				return true
			}
			'type_annotation', 'union_type', 'intersection_type', 'type_arguments', 'array_type',
			'tuple_type', 'parenthesized_type', 'lookup_type', 'type_alias_declaration',
			'function_type', 'readonly_type', 'index_type_query' {
				// `import('m').T` in a type position.
				return true
			}
			else {
				return false
			}
		}
	}
	return false
}

// ubm_is_safe_use ports isSafeUse on the ESTree parent (parentheses are not nodes and the
// ChainExpression of an optional chain is transparent).
fn (c &Checker) ubm_is_safe_use(node C.TSNode, depth int) bool {
	if depth >= max_expression_depth {
		return false
	}
	parent := estree_parent(node) or { return false }
	match node_kind(parent) {
		'if_statement', 'for_statement', 'member_expression', 'subscript_expression',
		'switch_statement', 'update_expression', 'while_statement' {
			return true
		}
		'call_expression' {
			// The callee of a call or the tag of a tagged template.
			callee := node_field(parent, 'function') or { return false }
			return node_key(unwrap_parens(callee)) == node_key(node)
		}
		'ternary_expression' {
			condition := node_field(parent, 'condition') or { return false }
			return node_key(unwrap_parens(condition)) == node_key(node)
		}
		'unary_expression' {
			return operator_of(parent) in ['!', 'delete', 'typeof', 'void']
		}
		'binary_expression' {
			operator := operator_of(parent)
			if operator in ['!=', '!==', '==', '===', 'instanceof'] {
				return true
			}
			if operator in ['&&', '||', '??'] {
				left := node_field(parent, 'left') or { return false }
				if operator == '&&' && node_key(unwrap_parens(left)) == node_key(node) {
					return true
				}
				return c.ubm_is_safe_use(parent, depth + 1)
			}
			return false
		}
		'assignment_expression' {
			left := unwrap_parens(node_field(parent, 'left') or { return false })
			if node_key(left) == node_key(node) {
				return true
			}
			// `this.x = super.x`
			if !is_member(node) || !is_member(left) {
				return false
			}
			object := unwrap_parens(node_field(node, 'object') or { return false })
			left_object := unwrap_parens(node_field(left, 'object') or { return false })
			return node_kind(object) == 'super' && node_kind(left_object) == 'this'
		}
		'non_null_expression', 'as_expression', 'type_assertion' {
			return c.ubm_is_safe_use(parent, depth + 1)
		}
		else {
			return false
		}
	}
}

// ubm_pattern prepares an ObjectPattern (the ObjectPattern visitor): none inside a type
// declaration.
fn (c &Checker) ubm_pattern(pattern C.TSNode) ?UbmPattern {
	if ubm_inside_type_declaration(pattern) {
		return none
	}
	mut init := ?C.TSNode(none)
	mut in_assignment_pattern := false
	parent := node_parent(pattern)?
	match node_kind(parent) {
		'variable_declarator' {
			if name := node_field(parent, 'name') {
				if node_key(name) == node_key(pattern) {
					if value := node_field(parent, 'value') {
						init = unwrap_parens(value)
					}
				}
			}
		}
		'assignment_expression' {
			if right := node_field(parent, 'right') {
				init = unwrap_parens(right)
			}
		}
		'assignment_pattern', 'required_parameter', 'optional_parameter' {
			// A default value: an ESTree AssignmentPattern.
			field := if node_kind(parent) == 'assignment_pattern' { 'right' } else { 'value' }
			if value := node_field(parent, field) {
				init = unwrap_parens(value)
				in_assignment_pattern = true
			}
		}
		else {}
	}
	mut keys := []C.TSNode{}
	for property in named_children(pattern) {
		match node_kind(property) {
			'shorthand_property_identifier_pattern' {
				keys << property
			}
			'object_assignment_pattern' {
				if left := node_field(property, 'left') {
					if node_kind(left) == 'shorthand_property_identifier_pattern' {
						keys << left
					}
				}
			}
			'pair_pattern' {
				key := node_field(property, 'key') or { continue }
				if node_kind(key) == 'property_identifier' {
					keys << key
				} else if node_kind(key) == 'computed_property_name' {
					// A computed identifier key (`[a]`) is also an Identifier.
					inner := unwrap_parens(first_named(key) or { continue })
					if node_kind(inner) == 'identifier' {
						keys << inner
					}
				}
			}
			else {}
		}
	}
	return UbmPattern{
		pattern:               pattern
		init:                  init
		in_assignment_pattern: in_assignment_pattern
		keys:                  keys
	}
}

// ubm_inside_type_declaration ports isNodeInsideTypeDeclaration.
fn ubm_inside_type_declaration(n C.TSNode) bool {
	mut node := n
	for _ in 0 .. 100000 {
		parent := node_parent(node) or { return false }
		match node_kind(parent) {
			'abstract_method_signature', 'function_signature', 'function_type',
			'interface_declaration', 'type_alias_declaration' {
				return true
			}
			'class_declaration', 'lexical_declaration', 'variable_declaration' {
				if grand := node_parent(parent) {
					if node_kind(grand) == 'ambient_declaration' {
						return true
					}
				}
			}
			else {}
		}
		node = parent
	}
	return false
}

// ubm_is_natively_bound ports isNativelyBound: a member of a global (not imported) in the list of
// natively bound members, or a standard library member of one of the supported global types.
fn (mut c Checker) ubm_is_natively_bound(object C.TSNode, property C.TSNode, symbols map[u64]SymbolResponse) !bool {
	if estree_type(object) == 'Identifier'
		&& node_kind(property) in ['property_identifier', 'identifier',
			'shorthand_property_identifier_pattern'] {
		if symbol := symbols[node_key(object)] {
			// isNotImported: the value declaration is in another file.
			not_imported := !symbol.is_null() && symbol.value_declaration != ''
				&& handle_path(symbol.value_declaration) != c.ast.path
			if not_imported && '${c.identifier_name(object)}.${c.identifier_name(property)}' in ubm_natively_bound_members {
				return true
			}
		}
	}
	object_type := c.node_type(object) or { return false }
	if !c.builtin_symbol_like_any(object_type, ubm_supported_global_types, 0)! {
		return false
	}
	property_type := c.node_type(property) or { return false }
	if property_type.symbol == 0 {
		return false
	}
	symbol := c.symbol_of(property_type)!
	for declaration in symbol.declarations {
		if c.is_default_library(handle_path(declaration))! {
			return true
		}
	}
	return false
}

// ubm_check_if_method ports checkIfMethod and the choice of message: '' if it is not dangerous.
fn (mut c Checker) ubm_check_if_method(symbol SymbolResponse, o UbmOptions) !string {
	declaration := symbol.value_declaration
	if symbol.is_null() || declaration == '' {
		return ''
	}
	kind := handle_kind(declaration)
	if kind !in ubm_kinds_with_initializer && kind !in [
		syntax_kind_method_declaration,
		syntax_kind_method_signature,
	] {
		return ''
	}
	tree := c.declaration_ast(handle_path(declaration))!
	index := handle_index(declaration)
	if kind == syntax_kind_property_declaration {
		initializer := tree.node_child(index, 'initializer')
		return if tree.node_kind(initializer) == syntax_kind_function_expression {
			'unbound'
		} else {
			''
		}
	}
	if kind == syntax_kind_property_assignment {
		initializer := tree.node_child(index, 'initializer')
		if tree.node_kind(initializer) != syntax_kind_function_expression {
			return ''
		}
		return ubm_check_method(tree, initializer, o)
	}
	return ubm_check_method(tree, index, o)
}

// ubm_check_method ports checkMethod: dangerous unless the first parameter is `this: void` (or the
// method is static with ignoreStatic).
fn ubm_check_method(tree tsgo.AstTree, index int, o UbmOptions) string {
	parameters := tree.node_children(tree.node_child(index, 'parameters'))
	mut first_param_is_this := false
	mut this_is_void := false
	if parameters.len > 0 {
		name := tree.node_child(parameters[0], 'name')
		first_param_is_this = tree.node_kind(name) == syntax_kind_identifier
			&& tree.node_text(name) == 'this'
		this_is_void = first_param_is_this
			&& tree.node_kind(tree.node_child(parameters[0], 'type')) == syntax_kind_void_keyword
	}
	if this_is_void {
		return ''
	}
	if o.ignore_static {
		modifiers := tree.node_children(tree.node_child(index, 'modifiers'))
		if modifiers.any(tree.node_kind(it) == syntax_kind_static_keyword) {
			return ''
		}
	}
	return if first_param_is_this { 'unbound' } else { 'unboundWithoutThisAnnotation' }
}
