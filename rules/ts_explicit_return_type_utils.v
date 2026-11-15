module rules

import estree
import treesitter { Ident }

// Ports of typescript-eslint 8.72.2's util/explicitReturnTypeUtils.ts and util/getFunctionHeadLoc.ts,
// shared by explicit-function-return-type and explicit-module-boundary-types.

// ErtOptions are the options explicitReturnTypeUtils reads.
struct ErtOptions {
	allow_direct_const_assertion_in_arrow_functions bool
	allow_expressions                               bool
	allow_higher_order_functions                    bool
	allow_typed_function_expressions                bool
}

// ert_is_function ports ASTUtils.isFunction.
fn ert_is_function(t &estree.EsTree, node int) bool {
	return node >= 0
		&& t.typ(node) in [.arrow_function_expression, .function_declaration, .function_expression]
}

// ert_is_type_assertion ports isTypeAssertion: `x as T` or `<T>x`.
fn ert_is_type_assertion(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.ts_as_expression, .ts_type_assertion]
}

// ert_function_returns are the ReturnStatements of each function (an arrow function, a function
// expression or declaration): the ones whose innermost function it is.
fn ert_function_returns(t &estree.EsTree) map[int][]int {
	mut out := map[int][]int{}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .return_statement {
			continue
		}
		mut f := t.nodes[node].parent
		for f >= 0 && !ert_is_function(t, f) {
			f = t.nodes[f].parent
		}
		if f >= 0 {
			out[f] << node
		}
	}
	return out
}

// ert_is_variable_declarator_with_type_annotation ports isVariableDeclaratorWithTypeAnnotation.
fn ert_is_variable_declarator_with_type_annotation(t &estree.EsTree, node int) bool {
	if t.typ(node) != .variable_declarator {
		return false
	}
	id := t.node(node, .id) or { return false }
	return t.node(id, .type_annotation) != none
}

// ert_is_property_definition_with_type_annotation ports isPropertyDefinitionWithTypeAnnotation.
fn ert_is_property_definition_with_type_annotation(t &estree.EsTree, node int) bool {
	return t.typ(node) == .property_definition && t.node(node, .type_annotation) != none
}

// ert_is_function_argument ports isFunctionArgument: an argument (or the callee, unless it is
// `callee`) of a call.
fn ert_is_function_argument(t &estree.EsTree, parent int, callee int) bool {
	return t.typ(parent) == .call_expression && (t.node(parent, .callee) or { -1 }) != callee
}

// ert_is_typed_jsx ports isTypedJSX.
fn ert_is_typed_jsx(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.jsx_expression_container, .jsx_spread_attribute]
}

// ert_is_default_function_parameter_with_type_annotation ports
// isDefaultFunctionParameterWithTypeAnnotation.
fn ert_is_default_function_parameter_with_type_annotation(t &estree.EsTree, node int) bool {
	if t.typ(node) != .assignment_pattern {
		return false
	}
	left := t.node(node, .left) or { return false }
	return t.node(left, .type_annotation) != none
}

// ert_is_typed_parent ports isTypedParent (`callee` -1 when there is none).
fn ert_is_typed_parent(t &estree.EsTree, parent int, callee int) bool {
	return ert_is_type_assertion(t, parent)
		|| ert_is_variable_declarator_with_type_annotation(t, parent)
		|| ert_is_default_function_parameter_with_type_annotation(t, parent)
		|| ert_is_property_definition_with_type_annotation(t, parent)
		|| ert_is_function_argument(t, parent, callee) || ert_is_typed_jsx(t, parent)
}

// ert_is_property_of_object_with_type ports isPropertyOfObjectWithType.
fn ert_is_property_of_object_with_type(t &estree.EsTree, property int) bool {
	if property < 0 || t.typ(property) != .property {
		return false
	}
	object_expr := t.nodes[property].parent
	if object_expr < 0 || t.typ(object_expr) != .object_expression {
		return false
	}
	parent := t.nodes[object_expr].parent
	if parent < 0 {
		return false
	}
	return ert_is_typed_parent(t, parent, -1) || ert_is_property_of_object_with_type(t, parent)
}

// ert_does_immediately_return_function_expression ports doesImmediatelyReturnFunctionExpression.
fn ert_does_immediately_return_function_expression(t &estree.EsTree, node int, returns []int) bool {
	if t.typ(node) == .arrow_function_expression
		&& ert_is_function(t, t.node(node, .body) or { -1 }) {
		return true
	}
	if returns.len == 0 {
		return false
	}
	return returns.all(ert_is_function(t, t.node(it, .argument) or { -1 }))
}

// ert_is_const_assertion ports isConstAssertion: `x as const` or `<const>x`.
fn ert_is_const_assertion(t &estree.EsTree, node int) bool {
	if ert_is_type_assertion(t, node) {
		annotation := t.node(node, .type_annotation) or { return false }
		if t.typ(annotation) == .ts_type_reference {
			name := t.node(annotation, .type_name) or { return false }
			return t.typ(name) == .identifier && (t.string_of(name, .name) or { '' }) == 'const'
		}
	}
	return false
}

// ert_is_typed_function_expression ports isTypedFunctionExpression.
fn ert_is_typed_function_expression(t &estree.EsTree, node int, o ErtOptions) bool {
	if !o.allow_typed_function_expressions {
		return false
	}
	parent := t.nodes[node].parent
	return ert_is_typed_parent(t, parent, node) || ert_is_property_of_object_with_type(t, parent)
		|| t.typ(parent) == .new_expression
}

// ert_is_valid_function_expression_return_type ports isValidFunctionExpressionReturnType.
fn ert_is_valid_function_expression_return_type(t &estree.EsTree, node int, o ErtOptions) bool {
	if ert_is_typed_function_expression(t, node, o) {
		return true
	}
	parent := t.nodes[node].parent
	if o.allow_expressions && t.typ(parent) !in [.variable_declarator, .method_definition,
		.export_default_declaration, .property_definition] {
		return true
	}
	if !o.allow_direct_const_assertion_in_arrow_functions
		|| t.typ(node) != .arrow_function_expression {
		return false
	}
	mut body := t.node(node, .body) or { return false }
	for t.typ(body) == .ts_satisfies_expression {
		body = t.node(body, .expression) or { return false }
	}
	return ert_is_const_assertion(t, body)
}

// ert_is_constructor ports isConstructor.
fn ert_is_constructor(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .method_definition
		&& (t.string_of(node, .kind) or { '' }) == 'constructor'
}

// ert_is_setter ports isSetter.
fn ert_is_setter(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.method_definition, .property]
		&& (t.string_of(node, .kind) or { '' }) == 'set'
}

// ert_is_valid_function_return_type ports isValidFunctionReturnType.
fn ert_is_valid_function_return_type(t &estree.EsTree, node int, returns []int, o ErtOptions) bool {
	if o.allow_higher_order_functions
		&& ert_does_immediately_return_function_expression(t, node, returns) {
		return true
	}
	parent := t.nodes[node].parent
	return t.node(node, .return_type) != none || ert_is_constructor(t, parent)
		|| ert_is_setter(t, parent)
}

// ert_check_function_return_type ports checkFunctionReturnType: the head of the function when it
// needs a return type.
fn (mut c Checker) ert_check_function_return_type(t &estree.EsTree, node int, returns []int, o ErtOptions) ?Ident {
	if ert_is_valid_function_return_type(t, node, returns, o) {
		return none
	}
	return c.ert_function_head(t, node)
}

// ert_check_function_expression_return_type ports checkFunctionExpressionReturnType.
fn (mut c Checker) ert_check_function_expression_return_type(t &estree.EsTree, node int, returns []int, o ErtOptions) ?Ident {
	if ert_is_valid_function_expression_return_type(t, node, o) {
		return none
	}
	return c.ert_check_function_return_type(t, node, returns, o)
}

// ert_ancestor_has_return_type ports ancestorHasReturnType.
fn ert_ancestor_has_return_type(t &estree.EsTree, node int) bool {
	mut ancestor := t.nodes[node].parent
	if t.typ(ancestor) == .property {
		ancestor = t.node(ancestor, .value) or { return false }
	}
	is_return_statement := t.typ(ancestor) == .return_statement
	is_bodyless_arrow := t.typ(ancestor) == .arrow_function_expression
		&& t.typ(t.node(ancestor, .body) or { return false }) != .block_statement
	if !is_return_statement && !is_bodyless_arrow {
		return false
	}
	for ancestor >= 0 {
		match t.typ(ancestor) {
			.arrow_function_expression, .function_expression, .function_declaration {
				if t.node(ancestor, .return_type) != none {
					return true
				}
			}
			.variable_declarator {
				id := t.node(ancestor, .id) or { return false }
				return t.node(id, .type_annotation) != none
			}
			.property_definition {
				return t.node(ancestor, .type_annotation) != none
			}
			.expression_statement {
				return false
			}
			else {}
		}
		ancestor = t.nodes[ancestor].parent
	}
	return false
}

// ert_function_head ports typescript-eslint's getFunctionHeadLoc: as ESLint's, but the head of a
// method or property of a class starts after its decorators.
fn (mut c Checker) ert_function_head(t &estree.EsTree, node int) Ident {
	parent := t.nodes[node].parent
	tokens := c.source_tokens(t.nodes[t.root].ts)
	if parent >= 0 && t.typ(parent) in [.method_definition, .property_definition] {
		decorators := t.list(parent, .decorators) or { []int{} }
		mut start := t.nodes[parent].start
		if decorators.len > 0 {
			if after := tokens.after(t.nodes[decorators.last()].end, false) {
				start = after.start
			}
		}
		return c.position_range(start, c.es_tree_params_paren(t, node))
	}
	if parent >= 0 && t.typ(parent) == .property {
		return c.position_range(t.nodes[parent].start, c.es_tree_params_paren(t, node))
	}
	if t.typ(node) == .arrow_function_expression {
		if body := t.node(node, .body) {
			mut at := t.nodes[body].start
			for {
				token := tokens.before(at, false) or { break }
				if c.src[token.start..token.end] == '=>' {
					return c.position_range(token.start, token.end)
				}
				at = token.start
			}
		}
	}
	return c.position_range(t.nodes[node].start, c.es_tree_params_paren(t, node))
}
