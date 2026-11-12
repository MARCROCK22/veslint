module rules

import treesitter { has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds }

// Port of typescript-eslint 8.62.0's util/collectUnusedVariables.js (the analysis of the
// `no-unused-vars` rule), which the `unused` modifier of `naming-convention` uses: the variables
// of a file that nothing uses, on the scope tree (scope.v).

const unused_function_kinds = ['function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'arrow_function', 'method_definition']

const unused_loop_kinds = ['do_statement', 'for_statement', 'for_in_statement', 'while_statement']

// unused_variables ports collectUnusedVariables: the variables (by index in the scope tree) that
// are not marked as used, not exported and without a reference that uses them.
fn (mut c Checker) unused_variables(root C.TSNode, tree &ScopeTree) map[int]bool {
	marked := c.unused_marked(root, tree)
	mut unused := map[int]bool{}
	for scope in tree.scopes {
		// The name of a function expression is not looked at.
		if scope.kind == .function_expression_name {
			continue
		}
		for v in scope.variables {
			variable := tree.variables[v]
			// The implicit variables of the libs are never looked at; the globals ESLint declares
			// are, and a `/* exported */` comment marks them as used.
			if variable.lib {
				continue
			}
			if marked[v] || variable.eslint_used || unused_is_exported(variable)
				|| c.unused_is_used(tree, v) {
				continue
			}
			unused[v] = true
		}
	}
	return unused
}

// unused_mark ports markVariableAsUsed for a name: the first variable with it from the scope of
// the node outwards.
fn unused_mark(name string, node C.TSNode, tree &ScopeTree, mut marked map[int]bool) {
	mut scope := tree.get_scope(node)
	for scope >= 0 {
		variable := tree.own_variable(scope, name)
		if variable >= 0 {
			marked[variable] = true
			return
		}
		scope = tree.scopes[scope].upper
	}
}

// unused_marked ports the visitor: the variables that count as used whatever their references.
fn (mut c Checker) unused_marked(root C.TSNode, tree &ScopeTree) map[int]bool {
	mut marked := map[int]bool{}
	for node in c.nodes_of_kinds(root, ['required_parameter', 'optional_parameter', 'enum_declaration',
		'mapped_type_clause', 'ambient_declaration', 'class_declaration', 'abstract_class_declaration',
		'class', 'for_in_statement', 'function_declaration', 'generator_function_declaration',
		'function_expression', 'generator_function', 'method_definition', 'call_signature',
		'constructor_type', 'construct_signature', 'function_signature', 'method_signature',
		'abstract_method_signature', 'function_type'], []string{}) {
		kind := node_kind(node)
		match kind {
			'required_parameter', 'optional_parameter' {
				pattern := node_field(node, 'pattern') or { continue }
				// The `this` parameter, and a parameter property.
				is_property := has_child_kind(node, 'accessibility_modifier')
					|| has_child_kind(node, 'readonly') || has_child_kind(node, 'override_modifier')
				if node_kind(pattern) == 'this' || (is_property && node_kind(pattern) == 'identifier') {
					unused_mark(c.nc_name(pattern), pattern, tree, mut marked)
				}
			}
			'enum_declaration' {
				// The members of an enum.
				for v in tree.scopes[tree.get_scope(node)].variables {
					marked[v] = true
				}
			}
			'mapped_type_clause' {
				if key := node_field(node, 'name') {
					unused_mark(c.identifier_name(key), key, tree, mut marked)
				}
			}
			'ambient_declaration' {
				// `declare global { … }`
				if has_child_kind(node, 'global') {
					if parent := node_parent(node) {
						unused_mark('global', parent, tree, mut marked)
					}
				}
			}
			'class_declaration', 'abstract_class_declaration', 'class' {
				// The name of the class inside the class.
				id := node_field(node, 'name') or { continue }
				for v in tree.scopes[tree.get_scope(node)].variables {
					identifiers := tree.variables[v].identifiers
					if identifiers.len > 0 && node_key(identifiers[0]) == node_key(id) {
						marked[v] = true
						break
					}
				}
			}
			'for_in_statement' {
				// `for (const key in object) return true;`
				left := node_field(node, 'left') or { continue }
				mut body := node_field(node, 'body') or { continue }
				if node_kind(body) == 'statement_block' {
					statements := named_children(body)
					if statements.len != 1 {
						continue
					}
					body = statements[0]
				}
				if node_kind(body) != 'return_statement' {
					continue
				}
				if _ := node_field(node, 'kind') {
					mut identifiers := []C.TSNode{}
					nc_pattern_identifiers(left, mut identifiers)
					if identifiers.len > 0 {
						variable := tree.declared_variable(identifiers[0])
						if variable >= 0 {
							marked[variable] = true
						}
					}
				} else if node_kind(left) == 'identifier' {
					unused_mark(c.identifier_name(left), left, tree, mut marked)
				}
			}
			else {
				is_function := kind in ['function_declaration', 'generator_function_declaration',
					'function_expression', 'generator_function', 'method_definition']
				if is_function {
					// The implicit `arguments`.
					scope := tree.get_scope(node)
					arguments_variable := tree.own_variable(scope, 'arguments')
					if arguments_variable >= 0 && tree.variables[arguments_variable].defs.len == 0 {
						marked[arguments_variable] = true
					}
				}
				// The parameters of a signature without a body, and those of a setter. The visitor
				// walks them with a PatternVisitor that takes its options
				// (visitChildrenEvenIfSelectorExists), so every Identifier inside a parameter is
				// marked: its names, and those of its type annotation, default value and decorators.
				is_signature := kind in ['call_signature', 'constructor_type', 'construct_signature',
					'function_signature', 'method_signature', 'abstract_method_signature',
					'function_type']
				is_setter := kind == 'method_definition' && has_child_kind(node, 'set')
				if !is_signature && !is_setter {
					continue
				}
				parameters := node_field(node, 'parameters') or { continue }
				for parameter in named_children(parameters) {
					mut identifiers := []C.TSNode{}
					c.unused_parameter_identifiers(parameter, mut identifiers)
					for identifier in identifiers {
						unused_mark(c.nc_name(identifier), identifier, tree, mut marked)
					}
				}
			}
		}
	}
	return marked
}

// unused_parameter_identifiers are the nodes of a parameter that are ESTree Identifiers: what the
// PatternVisitor of the visitor calls back for, as it visits every child (a `this` parameter is an
// Identifier; the `bigint` keyword, which tree-sitter reads as a type name, is not).
fn (c &Checker) unused_parameter_identifiers(n C.TSNode, mut out []C.TSNode) {
	match node_kind(n) {
		'identifier', 'property_identifier', 'shorthand_property_identifier',
		'shorthand_property_identifier_pattern', 'statement_identifier', 'undefined' {
			out << n
			return
		}
		'type_identifier' {
			if c.text(n) != 'bigint' {
				out << n
			}
			return
		}
		'this' {
			if parent := node_parent(n) {
				if node_kind(parent) in ['required_parameter', 'optional_parameter'] {
					out << n
				}
			}
			return
		}
		else {}
	}
	for child in named_children(n) {
		c.unused_parameter_identifiers(child, mut out)
	}
}

// unused_is_exported ports isExported and isMergeableExported.
fn unused_is_exported(variable ScopeVariable) bool {
	// isExported and isMergeableExported: a definition that is not a parameter, in an `export`.
	for definition in variable.defs {
		if definition.kind == .parameter {
			continue
		}
		mut node := definition.node
		if node_kind(node) == 'variable_declarator' {
			node = node_parent(node) or { continue }
		}
		if parent := nc_estree_parent(node) {
			if node_kind(parent) == 'export_statement' {
				return true
			}
		}
	}
	return false
}

fn unused_is_inside(inner C.TSNode, outer C.TSNode) bool {
	return node_start(inner) >= node_start(outer) && node_end(inner) <= node_end(outer)
}

// unused_parent is the ESTree parent of an expression: without parentheses, and the call for an
// argument.
fn unused_parent(node C.TSNode) ?C.TSNode {
	mut parent := node_parent(node)?
	for node_kind(parent) in ['parenthesized_expression', 'arguments'] {
		parent = node_parent(parent)?
	}
	return parent
}

// unused_is_unused_expression ports isUnusedExpression: the value of the expression is thrown
// away.
fn unused_is_unused_expression(node C.TSNode) bool {
	parent := unused_parent(node) or { return false }
	match node_kind(parent) {
		'expression_statement' {
			return true
		}
		'sequence_expression' {
			elements := named_children(parent)
			if elements.len == 0 || node_key(unwrap_parens(elements.last())) != node_key(node) {
				return true
			}
			return unused_is_unused_expression(parent)
		}
		else {
			return false
		}
	}
}

// unused_is_left: the node is the left side of an AssignmentExpression.
fn unused_is_left(parent C.TSNode, node C.TSNode) bool {
	if node_kind(parent) !in ['assignment_expression', 'augmented_assignment_expression'] {
		return false
	}
	left := node_field(parent, 'left') or { return false }
	return node_key(unwrap_parens(left)) == node_key(node)
}

fn unused_is_in_loop(node C.TSNode) bool {
	mut current := node
	for {
		kind := node_kind(current)
		if kind in unused_function_kinds {
			return false
		}
		if kind in unused_loop_kinds {
			return true
		}
		current = node_parent(current) or { return false }
	}
	return false
}

// unused_is_storable_function ports isStorableFunction: the function the reference is in may be
// called later (it is assigned, passed or returned inside the right side of the assignment).
fn (c &Checker) unused_is_storable_function(function C.TSNode, rhs C.TSNode) bool {
	mut node := function
	for {
		parent := unused_parent(node) or { return false }
		if !unused_is_inside(parent, rhs) {
			return false
		}
		kind := node_kind(parent)
		match kind {
			'sequence_expression' {
				elements := named_children(parent)
				if elements.len == 0
					|| node_key(unwrap_parens(elements.last())) != node_key(node) {
					return false
				}
			}
			'call_expression', 'new_expression' {
				// A tagged template takes anything.
				if arguments := node_field(parent, 'arguments') {
					if node_kind(arguments) == 'template_string' {
						return true
					}
				}
				callee := call_callee(parent) or { return true }
				return node_key(unwrap_parens(callee)) != node_key(node)
			}
			'assignment_expression', 'augmented_assignment_expression', 'yield_expression' {
				return true
			}
			else {
				// A statement or a declaration: too complex to follow.
				if kind.ends_with('_statement') || kind.ends_with('_declaration')
					|| kind == 'statement_block' {
					return true
				}
			}
		}
		node = parent
	}
	return false
}

// unused_self_reference ports isSelfReference: the reference is made from inside one of the
// nodes (from a scope whose block is one of them).
fn unused_self_reference(tree &ScopeTree, from int, nodes []C.TSNode) bool {
	mut scope := from
	for scope >= 0 {
		block := tree.scopes[scope].block
		for node in nodes {
			if node_key(node) == node_key(block) && node_kind(node) == node_kind(block) {
				return true
			}
		}
		scope = tree.scopes[scope].upper
	}
	return false
}

// unused_is_type_import ports isTypeImport: the definition is an import of `import type`, or an
// import specifier with `type`.
fn unused_is_type_import(definition ScopeDefinition) bool {
	if definition.kind != .import_binding {
		return false
	}
	node := definition.node
	if node_kind(node) == 'import_specifier' {
		if name := node_field(node, 'name') {
			if node_start(name) != node_start(node) {
				return true
			}
		}
	}
	mut current := node
	for {
		current = node_parent(current) or { return false }
		if node_kind(current) == 'import_statement' {
			return has_child_kind(current, 'type')
		}
	}
	return false
}

// unused_in_type_predicate ports referenceContainsTypePredicate: the identifier is the parameter
// name of a type predicate (`value is T`, `asserts value`).
fn unused_in_type_predicate(identifier C.TSNode) bool {
	parent := node_parent(identifier) or { return false }
	match node_kind(parent) {
		'asserts' {
			return true
		}
		'type_predicate' {
			name := node_field(parent, 'name') or { return false }
			return node_key(name) == node_key(identifier)
		}
		else {
			return false
		}
	}
}

// unused_is_used ports isUsedVariable: some reference reads the variable for something else
// than itself.
fn (c &Checker) unused_is_used(tree &ScopeTree, v int) bool {
	variable := tree.variables[v]
	mut function_nodes := []C.TSNode{}
	mut type_nodes := []C.TSNode{}
	mut module_nodes := []C.TSNode{}
	mut enum_nodes := []C.TSNode{}
	for definition in variable.defs {
		if definition.kind == .function_name {
			function_nodes << definition.node
		}
		if definition.kind == .variable {
			if init := definition.init {
				value := unwrap_parens(init)
				if node_kind(value) in ['function_expression', 'generator_function', 'arrow_function'] {
					function_nodes << value
				}
			}
		}
		match node_kind(definition.node) {
			'interface_declaration', 'type_alias_declaration' { type_nodes << definition.node }
			'module', 'internal_module' { module_nodes << definition.node }
			'enum_declaration' { enum_nodes << definition.node }
			else {}
		}
	}
	mut imported_as_type := true
	for definition in variable.defs {
		if !unused_is_type_import(definition) {
			imported_as_type = false
			break
		}
	}
	variable_scope := tree.scopes[variable.scope].variable_scope
	mut rhs := ?C.TSNode(none)
	for index in variable.references {
		reference := tree.references[index]
		id := reference.identifier
		parent := unused_parent(id)
		// isReadForItself: `a = a + 1`, `a++`, or a read inside the right side of an assignment
		// to the variable whose value is thrown away.
		mut for_itself := false
		if reference.read {
			if p := parent {
				if unused_is_left(p, id) && unused_is_unused_expression(p)
					&& operator_of(p) !in ['??=', '&&=', '||='] {
					for_itself = true
				}
				if node_kind(p) == 'update_expression' && unused_is_unused_expression(p) {
					for_itself = true
				}
			}
			if rhs_node := rhs {
				if unused_is_inside(id, rhs_node) {
					mut in_storable_function := false
					mut function := ?C.TSNode(none)
					mut current := id
					for {
						current = node_parent(current) or { break }
						if node_kind(current) in unused_function_kinds {
							function = current
							break
						}
					}
					if function_node := function {
						in_storable_function = unused_is_inside(function_node, rhs_node)
							&& c.unused_is_storable_function(function_node, rhs_node)
					}
					if !in_storable_function {
						for_itself = true
					}
				}
			}
		}
		// getRhsNode: the right side of an assignment to the variable whose value is thrown
		// away, when the variable cannot be read later.
		mut next_rhs := ?C.TSNode(none)
		if previous := rhs {
			if unused_is_inside(id, previous) {
				next_rhs = previous
			}
		}
		if next_rhs == none {
			if p := parent {
				can_be_used_later := tree.scopes[reference.from].variable_scope != variable_scope
					|| unused_is_in_loop(id)
				if unused_is_left(p, id) && unused_is_unused_expression(p) && !can_be_used_later {
					if right := node_field(p, 'right') {
						next_rhs = unwrap_parens(right)
					}
				}
			}
		}
		rhs = next_rhs
		if !reference.read || for_itself {
			continue
		}
		if !imported_as_type && (inside_type_query(id) || unused_in_type_predicate(id)) {
			continue
		}
		if function_nodes.len > 0 && unused_self_reference(tree, reference.from, function_nodes) {
			continue
		}
		if type_nodes.len > 0 && type_nodes.any(unused_is_inside(id, it)) {
			continue
		}
		if module_nodes.len > 0 && unused_self_reference(tree, reference.from, module_nodes) {
			continue
		}
		if enum_nodes.len > 0 && unused_self_reference(tree, reference.from, enum_nodes) {
			continue
		}
		return true
	}
	return false
}
