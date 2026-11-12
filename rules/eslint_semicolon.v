module rules

import treesitter { children, node_end, node_field, node_kind, node_parent, node_start }

// needsPrecedingSemicolon and canContinueExpressionInClassBody of ESLint 10.6.0's ast-utils
// (lib/rules/utils/ast-utils.js), which no-useless-constructor uses. They differ from
// typescript-eslint's older needsPrecedingSemicolon (needs_preceding_semicolon in fix_tokens.v):
// no semicolon is needed after the key or the computed key of an uninitialized class field, after
// a TSDeclareFunction, inside a TSImportEqualsDeclaration, after a TypeScript type, nor after an
// identifier that ends a declarator without an initializer.

// The punctuators before which no `;` is needed: postfix `++` and `--` always trigger ASI, and
// after `:`, `;`, `{` and `=>` a `;` would be an empty statement (PUNCTUATORS).
const esl_punctuators = [':', ';', '{', '=>', '++', '--']

// The kinds of the TSTypeAnnotation of typescript-estree in tree-sitter.
const esl_type_annotation_kinds = ['type_annotation', 'opting_type_annotation',
	'omitting_type_annotation', 'adding_type_annotation', 'asserts_annotation',
	'type_predicate_annotation']

// can_continue_expression_in_class_body ports canContinueExpressionInClassBody: a token that can
// start a class member and continue the expression of a field before it (`[`, `*`, and the keys
// `in` and `instanceof`).
fn (c &Checker) can_continue_expression_in_class_body(token SourceToken) bool {
	text := c.token_text(token)
	return (token.kind == .punctuator && text in ['[', '*'])
		|| (token.kind in [.identifier, .keyword] && text in ['in', 'instanceof'])
}

// eslint_needs_preceding_semicolon ports needsPrecedingSemicolon(sourceCode, node) of ESLint 10.6.0
// for the ESTree node that starts at `start` (`n` is a node of the file): whether code that starts
// with `(`, `[`, `*` or a template and takes the place of the node would continue the token before
// it. prevNode, the innermost ESTree node that contains that token (getNodeByRangeIndex), is the
// leaf of a name or a literal, or else the node the token belongs to.
fn (mut c Checker) eslint_needs_preceding_semicolon(n C.TSNode, start int) bool {
	tokens := c.source_tokens(n)
	previous := tokens.before(start, false) or { return false }
	text := c.token_text(previous)
	if previous.kind == .punctuator && text in esl_punctuators {
		return false
	}
	leaf := previous.node
	owner := node_parent(leaf) or { return false }
	is_punctuator := previous.kind == .punctuator
	// An uninitialized class field: the token is its key, or the `]` of its computed key.
	if !is_punctuator && node_kind(owner) == 'public_field_definition'
		&& cm_type(owner) == 'PropertyDefinition' {
		if key := node_field(owner, 'name') {
			if node_key(key) == node_key(leaf) {
				return false
			}
		}
	}
	if is_punctuator && text == ']' && node_kind(owner) == 'computed_property_name' {
		if field := node_parent(owner) {
			if node_kind(field) == 'public_field_definition'
				&& cm_type(field) == 'PropertyDefinition' {
				return false
			}
		}
	}
	// A TSDeclareFunction, a TSImportEqualsDeclaration and the TypeScript types.
	if esl_estree_owner(owner).kind == 'function_signature' && !C.ts_node_is_named(leaf) {
		return false
	}
	if esl_in_import_equals(leaf) || esl_in_type(leaf) {
		return false
	}
	if is_punctuator && text == ')' {
		// Not the `)` of the head of a statement (STATEMENTS).
		container := esl_estree_owner(owner)
		return container.kind !in ['do_statement', 'for_in_statement', 'for_statement', 'if_statement',
			'while_statement', 'with_statement']
	}
	if is_punctuator && text == '}' {
		// The block of a function expression that is not a class method, the body of a class
		// expression, or an object.
		outer := node_parent(owner) or { return false }
		return match node_kind(owner) {
			'statement_block' {
				match node_kind(outer) {
					'function_expression', 'generator_function' {
						true
					}
					'method_definition' {
						holder := node_parent(outer) or { return false }
						node_kind(holder) == 'object'
					}
					else {
						false
					}
				}
			}
			'class_body' {
				// `export default class {}` is a ClassDeclaration.
				node_kind(outer) == 'class'
					&& node_kind(node_parent(outer) or { outer }) != 'export_statement'
			}
			'object' {
				true
			}
			else {
				false
			}
		}
	}
	if previous.kind in [.identifier, .keyword] {
		// The id of a declarator without an initializer, or the label of a break or continue.
		if node_kind(owner) == 'variable_declarator' && C.ts_node_is_named(leaf) {
			if name := node_field(owner, 'name') {
				if node_key(name) == node_key(leaf) {
					if _ := node_field(owner, 'value') {
					} else {
						return false
					}
				}
			}
		}
		if node_kind(owner) in ['break_statement', 'continue_statement'] && C.ts_node_is_named(leaf) {
			return false
		}
		// A keyword of the statement it belongs to (NODE_TYPES_BY_KEYWORD).
		expected := semicolon_keyword_nodes[text] or { return true }
		if C.ts_node_is_named(leaf) {
			return true
		}
		return node_kind(owner) != expected
	}
	if previous.kind == .string_ {
		// The source of an import or of an export (DECLARATIONS).
		if node_kind(owner) in ['import_statement', 'export_statement'] {
			source := node_field(owner, 'source') or { return true }
			return node_key(source) != node_key(leaf)
		}
		return true
	}
	return true
}

// esl_estree_owner is the ESTree node a token of `owner` belongs to: parentheses and the lists of
// arguments and of parameters are not ESTree nodes, the `else` of an IfStatement is its own.
fn esl_estree_owner(owner C.TSNode) EslOwner {
	mut node := owner
	for node_kind(node) in ['parenthesized_expression', 'arguments', 'formal_parameters', 'else_clause'] {
		node = node_parent(node) or { break }
	}
	return EslOwner{
		node: node
		kind: node_kind(node)
	}
}

struct EslOwner {
	node C.TSNode
	kind string
}

// esl_in_import_equals: the token is part of a TSImportEqualsDeclaration (`import x = require('y')`,
// `import x = A.B`), where prevNode or its parent is a child of it.
fn esl_in_import_equals(leaf C.TSNode) bool {
	mut node := leaf
	for {
		node = node_parent(node) or { return false }
		if node_kind(node) in ['import_require_clause', 'import_alias'] {
			return true
		}
		if node_kind(node) in ['program', 'statement_block'] {
			return false
		}
	}
	return false
}

// esl_in_type ports isInType and the check of prevNode itself against TS_TYPE_NODE_TYPES: the
// token is in a TSTypeAnnotation, or is the operator or the type of a TSAsExpression or a
// TSSatisfiesExpression, or part of a TSTypeAliasDeclaration but its name (a function type has a
// TSTypeAnnotation for its return type too).
fn esl_in_type(leaf C.TSNode) bool {
	start := node_start(leaf)
	mut previous := leaf
	mut node := leaf
	for {
		node = node_parent(node) or { return false }
		kind := node_kind(node)
		if kind in esl_type_annotation_kinds {
			return true
		}
		match kind {
			'as_expression', 'satisfies_expression' {
				for child in children(node) {
					if node_kind(child) in ['as', 'satisfies'] {
						if start >= node_start(child) {
							return true
						}
						break
					}
				}
			}
			'type_alias_declaration' {
				name := node_field(node, 'name') or { return true }
				return node_key(name) != node_key(previous)
			}
			'function_type' {
				if return_type := node_field(node, 'return_type') {
					if start >= node_start(return_type) && start < node_end(return_type) {
						return true
					}
				}
			}
			else {}
		}
		previous = node
	}
	return false
}
