module rules

import treesitter { has_child_kind, node_end, node_field, node_kind, node_parent, node_start }

// Where a declared name ends and whether a place is in its initializer, on ESTree's ranges (for
// no-use-before-define and no-shadow).

// identifier_end is the end of the ESTree range of an identifier a declaration names: the name of a
// parameter takes its `?` and its type annotation (not its default value), and the name of a
// variable declarator or of a catch clause its type annotation (typescript-estree's
// fixParentLocation).
fn (c &Checker) identifier_end(ident C.TSNode) int {
	end := node_end(ident)
	parent := node_parent(ident) or { return end }
	match node_kind(parent) {
		'required_parameter', 'optional_parameter' {
			pattern := node_field(parent, 'pattern') or {
				node_field(parent, 'name') or { return end }
			}
			if node_key(pattern) != node_key(ident) {
				return end
			}
			if annotation := node_field(parent, 'type') {
				return c.tokens.last_end(node_end(annotation))
			}
			if node_kind(parent) == 'optional_parameter' {
				for child in children_of_kind(parent, '?') {
					return node_end(child)
				}
			}
		}
		'variable_declarator' {
			if name := node_field(parent, 'name') {
				if node_key(name) == node_key(ident) {
					if annotation := node_field(parent, 'type') {
						return c.tokens.last_end(node_end(annotation))
					}
				}
			}
		}
		'catch_clause' {
			if parameter := node_field(parent, 'parameter') {
				if node_key(parameter) == node_key(ident) {
					if annotation := node_field(parent, 'type') {
						return c.tokens.last_end(node_end(annotation))
					}
				}
			}
		}
		else {}
	}
	return end
}

// in_range ports isInRange: the node exists and `location` is in [start, end] of its ESTree range
// (parentheses around an expression are not part of it, and no identifier ends inside them).
fn in_range(n ?C.TSNode, location int) bool {
	node := unwrap_parens(n or { return false })
	return node_start(node) <= location && location <= node_end(node)
}

// in_initializer ports the walk of isInInitializer (no-use-before-define) and isInitPatternNode
// (no-shadow): from the declared name `name` up through its ESTree parents, `location` is in the
// initializer of its VariableDeclarator (or in the right side of the for-in/of loop the
// declarator heads), or in the right side of an AssignmentPattern around it; a function, a class,
// a catch clause, an import or a named export stops the walk.
fn in_initializer(name C.TSNode, location int) bool {
	mut node := name
	for {
		node = node_parent(node) or { return false }
		match node_kind(node) {
			'variable_declarator' {
				// VariableDeclarator: its init, and the loop of a for-in/of declaration.
				return in_range(node_field(node, 'value'), location)
			}
			'for_in_statement' {
				// A for-in/of declaration has no declarator node in tree-sitter: the name is in
				// its `left`, and `value` is the initializer of `for (var a = b in c)`.
				if _ := node_field(node, 'kind') {
					return in_range(node_field(node, 'value'), location)
						|| in_range(node_field(node, 'right'), location)
				}
				return false
			}
			'assignment_pattern', 'object_assignment_pattern' {
				// AssignmentPattern
				if in_range(node_field(node, 'right'), location) {
					return true
				}
			}
			'required_parameter', 'optional_parameter' {
				// A parameter with a default value is an AssignmentPattern.
				if in_range(node_field(node, 'value'), location) {
					return true
				}
			}
			'function_declaration', 'generator_function_declaration', 'function_expression',
			'generator_function', 'arrow_function', 'method_definition', 'class_declaration',
			'abstract_class_declaration', 'class', 'catch_clause', 'import_statement' {
				// FunctionDeclaration, FunctionExpression (also a method's), ArrowFunctionExpression,
				// ClassDeclaration, ClassExpression, CatchClause and ImportDeclaration.
				return false
			}
			'export_statement' {
				// ExportNamedDeclaration (an ExportDefaultDeclaration does not stop the walk).
				if !has_child_kind(node, 'default') {
					return false
				}
			}
			else {}
		}
	}
	return false
}
