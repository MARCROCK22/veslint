module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { children, has_child_kind, named_children, node_field, node_kind, node_parent, nodes_of_kinds, position_of }

// Port of the `strict-void-return` rule of typescript-eslint 8.62.0, with its `allowReturnAny`
// option.

const svr_messages = {
	'asyncFunc':     'Async function used in a context where a void function is expected.'
	'nonVoidFunc':   'Value-returning function used in a context where a void function is expected.'
	'nonVoidReturn': 'Value returned in a context where a void return is expected.'
}

const svr_class_kinds = ['class_declaration', 'class', 'abstract_class_declaration']

const svr_function_kinds = ['arrow_function', 'function_expression', 'generator_function',
	'method_definition']

struct SvrOptions {
	allow_return_any bool
}

fn svr_options(options []json2.Any) !SvrOptions {
	o := option_object(strict_void_return, options, ['allowReturnAny'])!
	return SvrOptions{
		allow_return_any: o.bool_value('allowReturnAny')!
	}
}

// SvrCall is a CallExpression or a NewExpression with arguments.
struct SvrCall {
	node   C.TSNode
	callee C.TSNode
	// The callee as written, with its parentheses: the node the parameter types are asked at.
	callee_node C.TSNode
	args        []C.TSNode
}

// SvrObjectMethod is a method of an object literal whose name is not computed.
struct SvrObjectMethod {
	object C.TSNode
	method C.TSNode
	name   string
}

// SvrMember is a class method, or a class property with a value: its name, the function or the
// value to report, and the base types of its class.
struct SvrMember {
	name      C.TSNode
	value     C.TSNode
	is_method bool
	heritage  []Span
	// The member: the node the types of the base members are asked at.
	member C.TSNode
}

struct SvrState {
	options SvrOptions
mut:
	findings []Finding
	// Function literals with a block body whose `return` statements are looked at once the
	// types of their arguments are known.
	pending []C.TSNode
}

fn (mut c Checker) lint_strict_void_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut state := SvrState{
		options: svr_options(c.rule_options(strict_void_return))!
	}
	mut sw := time.new_stopwatch()
	mut expressions := []C.TSNode{} // checkExpressionNode
	mut calls := []SvrCall{}
	mut object_methods := []SvrObjectMethod{}
	mut members := []SvrMember{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['array', 'arrow_function', 'assignment_expression',
		'augmented_assignment_expression', 'call_expression', 'new_expression', 'jsx_attribute',
		'object', 'return_statement', 'variable_declarator', 'class_body'], type_name_kinds) {
		match node_kind(node) {
			'array' {
				for element in named_children(node) {
					if node_kind(element) != 'spread_element' {
						expressions << unwrap_parens(element)
					}
				}
			}
			'arrow_function' {
				body := node_field(node, 'body') or { continue }
				if node_kind(body) != 'statement_block' {
					expressions << unwrap_parens(body)
				}
			}
			'assignment_expression', 'augmented_assignment_expression' {
				right := node_field(node, 'right') or { continue }
				expressions << unwrap_parens(right)
			}
			'call_expression', 'new_expression' {
				args := call_args(node) or { continue }
				callee := call_callee(node) or { continue }
				if args.len == 0 {
					continue
				}
				calls << SvrCall{
					node:        node
					callee:      unwrap_parens(callee)
					callee_node: callee
					args:        args.map(unwrap_parens(it))
				}
				spans << node_span(unwrap_parens(callee))
				if node_kind(callee) == 'parenthesized_expression' {
					spans << Span{
						...node_span(callee)
						optional: true
					}
				}
				for arg in args {
					if node_kind(arg) != 'spread_element' {
						spans << svr_span(unwrap_parens(arg))
					}
				}
			}
			'jsx_attribute' {
				if value := jsx_attribute_expression(node) {
					expressions << value
				}
			}
			'object' {
				for property in named_children(node) {
					match node_kind(property) {
						'pair' {
							value := node_field(property, 'value') or { continue }
							expressions << unwrap_parens(value)
						}
						'shorthand_property_identifier' {
							expressions << property
						}
						'method_definition' {
							name := node_field(property, 'name') or { continue }
							if has_child_kind(property, 'get') || has_child_kind(property, 'set') {
								// An accessor is not a method: it is checked like any value.
								expressions << property
							} else if node_kind(name) != 'computed_property_name' {
								object_methods << SvrObjectMethod{
									object: node
									method: property
									name:   c.literal_name(name) or { c.identifier_name(name) }
								}
								spans << node_span(node)
								spans << function_span(property)
							}
						}
						else {}
					}
				}
			}
			'return_statement' {
				for argument in named_children(node) {
					expressions << unwrap_parens(argument)
					break
				}
			}
			'variable_declarator' {
				value := node_field(node, 'value') or { continue }
				expressions << unwrap_parens(value)
			}
			'class_body' {
				class_node := node_parent(node) or { continue }
				if node_kind(class_node) !in svr_class_kinds {
					continue
				}
				heritage := c.class_like(class_node).heritage
				for member in named_children(node) {
					name := node_field(member, 'name') or { continue }
					match node_kind(member) {
						'method_definition' {
							// A constructor has no name in TypeScript.
							if c.pfa_is_constructor(member) {
								continue
							}
							members << SvrMember{
								name:      name
								value:     member
								is_method: true
								heritage:  heritage
								member:    member
							}
							spans << node_span(name)
							spans << function_span(member)
						}
						'public_field_definition' {
							value := node_field(member, 'value') or { continue }
							// An AccessorProperty is not a PropertyDefinition.
							if has_child_kind(member, 'accessor') {
								continue
							}
							members << SvrMember{
								name:     name
								value:    unwrap_parens(value)
								heritage: heritage
								member:   member
							}
							spans << Span{
								...member_span(member)
								optional: true
							}
							spans << node_span(name)
							spans << svr_span(unwrap_parens(value))
						}
						else {}
					}
				}
				spans << heritage
			}
			else {}
		}
	}
	for expression in expressions {
		spans << svr_span(expression)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	for expression in expressions {
		c.svr_check_expression(expression, mut state)!
	}
	for call in calls {
		c.svr_check_call(call, mut state)!
	}
	for method in object_methods {
		c.svr_check_object_method(method, mut state)!
	}
	for member in members {
		c.svr_check_member(member, mut state)!
	}
	stats.eval_ms += ms(sw.elapsed())
	sw.restart()
	// The `return` statements of the function literals found so far.
	mut returns := map[u64][]C.TSNode{}
	mut return_spans := []Span{}
	for function in state.pending {
		// A function reported through two contexts is only walked once.
		if node_key(function) in returns {
			continue
		}
		returns[node_key(function)] = []C.TSNode{}
		body := node_field(function, 'body') or { continue }
		mut statements := []C.TSNode{}
		svr_walk_statements(named_children(body), mut statements)
		for statement in statements {
			if node_kind(statement) != 'return_statement' {
				continue
			}
			for argument in named_children(statement) {
				returns[node_key(function)] << statement
				return_spans << node_span(unwrap_parens(argument))
				break
			}
		}
	}
	c.resolve_spans(return_spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	allowed := svr_allowed_flags(state.options)
	for function in state.pending {
		for statement in returns[node_key(function)] {
			argument := unwrap_parens(named_children(statement)[0])
			return_type := c.node_type(argument) or { continue }
			if return_type.flags & allowed != 0 {
				continue
			}
			// The `return` keyword.
			state.findings << finding_at(statement, 'nonVoidReturn')
		}
	}
	state.findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += expressions.len + calls.len + object_methods.len + members.len
	return state.findings
}

// svr_span is the TypeScript node of an expression that may be a function: a method is its
// member, with its decorators.
fn svr_span(n C.TSNode) Span {
	return if node_kind(n) == 'method_definition' { function_span(n) } else { node_span(n) }
}

// jsx_attribute_expression is the expression of a JSX attribute whose value is an expression
// container that is not empty.
fn jsx_attribute_expression(attribute C.TSNode) ?C.TSNode {
	for child in named_children(attribute) {
		if node_kind(child) == 'jsx_expression' {
			return jsx_expression_value(child)
		}
	}
	return none
}

// svr_allowed_flags are the TypeFlags a void function may return: Void, Never and Undefined, and
// Any with `allowReturnAny`.
fn svr_allowed_flags(options SvrOptions) u32 {
	any := if options.allow_return_any { type_flag_any } else { u32(0) }
	return type_flag_void | type_flag_never | type_flag_undefined | any
}

// svr_is_void_returning_function_type ports isVoidReturningFunctionType: the type has call
// signatures (getCallSignaturesOfType) and every part of every return type is void.
fn (mut c Checker) svr_is_void_returning_function_type(t TypeResponse) !bool {
	signatures := c.call_signatures_of(t)!
	mut returns := 0
	for signature in signatures {
		for part in c.constituents(c.return_type(signature.id)!)! {
			if part.flags & type_flag_void == 0 {
				return false
			}
			returns++
		}
	}
	return returns > 0
}

// svr_may_be_function: whether the type of an expression has call signatures. Without them
// reportIfNonVoidFunction reports nothing in any context (every call signature of the value
// returns void when there is none), so nothing else is asked of tsgo about the expression: most
// of them are not functions, and what their types tell is mostly known without asking
// (apparent_of and signatures_of).
fn (mut c Checker) svr_may_be_function(node C.TSNode) !bool {
	if node_kind(node) in svr_function_kinds {
		return true
	}
	t := c.node_type(node) or { return false }
	return c.call_signatures_of(c.apparent_of(t)!)!.len > 0
}

// svr_check_expression ports checkExpressionNode: the contextual type of the expression is a
// void function. Returns whether it was.
fn (mut c Checker) svr_check_expression(node C.TSNode, mut state SvrState) !bool {
	if !c.svr_may_be_function(node)! {
		return false
	}
	expected := c.contextual_type(node)!
	if !expected.is_null() && c.svr_is_void_returning_function_type(expected)! {
		c.svr_report_if_non_void_function(node, mut state)!
		return true
	}
	return false
}

fn svr_is_nullish_or_any(t TypeResponse) bool {
	return t.flags & (type_flag_void | type_flag_undefined | type_flag_null | type_flag_any | type_flag_never) != 0
}

// svr_check_call ports checkFunctionCallNode: each argument against the contextual type and
// against the parameter of every signature of the callee.
fn (mut c Checker) svr_check_call(call SvrCall, mut state SvrState) ! {
	callee_type := c.node_type(call.callee) or { return }
	// Only an argument that may be a function is reported.
	mut may_report := []bool{cap: call.args.len}
	for arg in call.args {
		may_report << node_kind(arg) != 'spread_element' && c.svr_may_be_function(arg)!
	}
	if true !in may_report {
		return
	}
	kind := if node_kind(call.node) == 'new_expression' {
		signature_kind_construct
	} else {
		signature_kind_call
	}
	mut signatures := []tsgo.SignatureResponse{}
	for part in c.constituents(callee_type)! {
		signatures << c.signatures_of(part, kind)!
	}
	for index, arg in call.args {
		if !may_report[index] {
			continue
		}
		// The return types the signatures expect of this argument.
		mut expected_returns := []TypeResponse{}
		for signature in signatures {
			parameters := c.signature_parameters(signature)!
			if index >= parameters.len {
				continue
			}
			// getTypeOfSymbolAtLocation(param, callTsNode.expression)
			parameter_type := c.parameter_type_at(parameters[index], c.symbol_location(call.callee_node))!
			for part in c.constituents(parameter_type)! {
				for parameter_signature in c.signatures_of(part, signature_kind_call)! {
					expected_returns << c.return_type(parameter_signature.id)!
				}
			}
		}
		mut all_return_void := true
		mut some_void := false
		mut all_nullish_or_any := true
		for t in expected_returns {
			is_void := t.flags & type_flag_void != 0
			// A type parameter is treated like void: whether a generic overload matches the call
			// cannot be told.
			if !is_void && !svr_is_nullish_or_any(t) && t.flags & type_flag_type_parameter == 0 {
				all_return_void = false
			}
			some_void = some_void || is_void
			all_nullish_or_any = all_nullish_or_any && svr_is_nullish_or_any(t)
		}
		// The contextual type is that of the first overload, so it only counts with a single
		// signature or when every signature returns void.
		if (signatures.len == 1 || all_return_void) && c.svr_check_expression(arg, mut state)! {
			continue
		}
		if some_void && all_nullish_or_any {
			c.svr_report_if_non_void_function(arg, mut state)!
		}
	}
}

// svr_check_object_method ports the method branch of checkObjectPropertyNode: the property of
// the contextual type of the object with the name of the method.
fn (mut c Checker) svr_check_object_method(m SvrObjectMethod, mut state SvrState) ! {
	object_type := c.contextual_type(m.object)!
	if object_type.is_null() {
		return
	}
	property := c.property(object_type, m.name)!
	if property.is_null() {
		return
	}
	// getTypeOfSymbolAtLocation(propSymbol, propTsNode)
	if c.svr_is_void_returning_function_type(c.symbol_type_at(property, c.symbol_location(m.method))!)! {
		c.svr_report_if_non_void_function(m.method, mut state)!
	}
}

// svr_check_member ports checkClassMethodNode and checkClassPropertyNode: the member of each base
// type with the same name (getBaseTypesOfClassMember) and, for a property, the contextual type.
fn (mut c Checker) svr_check_member(member SvrMember, mut state SvrState) ! {
	if !member.is_method && !c.svr_may_be_function(member.value)! {
		return
	}
	handle := if member.heritage.len > 0 {
		c.node_handles[node_key(member.name)] or { '' }
	} else {
		''
	}
	if handle != '' {
		symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
		if symbols.len == 1 && !symbols[0].is_null() {
			for span in member.heritage {
				base_type := c.node_types[span.key] or { continue }
				if base_type.is_null() {
					continue
				}
				// The name as TypeScript 6's `symbol.name` gives it: a name of the API that starts with
				// `__` has one more underscore.
				base_member := c.property(base_type, unescape_name(symbols[0].name))!
				if base_member.is_null() {
					continue
				}
				// getTypeOfSymbolAtLocation(baseMemberSymbol, memberTsNode)
				base_member_type := c.symbol_type_at(base_member, c.symbol_location(member.member))!
				if c.svr_is_void_returning_function_type(base_member_type)! {
					// At most one report.
					c.svr_report_if_non_void_function(member.value, mut state)!
					return
				}
			}
		}
	}
	if !member.is_method {
		c.svr_check_expression(member.value, mut state)!
	}
}

// svr_report_if_non_void_function ports reportIfNonVoidFunction.
fn (mut c Checker) svr_report_if_non_void_function(node C.TSNode, mut state SvrState) ! {
	allowed := svr_allowed_flags(state.options)
	node_type := c.node_type(node) or { return }
	actual := c.apparent_of(node_type)!
	mut already_void := true
	for signature in c.call_signatures_of(actual)! {
		for part in c.constituents(c.return_type(signature.id)!)! {
			if part.flags & allowed == 0 {
				already_void = false
			}
		}
	}
	if already_void {
		return
	}
	kind := node_kind(node)
	if kind !in svr_function_kinds {
		// Not a function literal.
		state.findings << finding_at(node, 'nonVoidFunc')
		return
	}
	if is_generator(node) {
		state.findings << Finding{
			stmt:       function_head(node)
			message_id: 'nonVoidFunc'
		}
		return
	}
	if has_child_kind(node, 'async') {
		state.findings << Finding{
			stmt:       function_head(node)
			message_id: 'asyncFunc'
		}
		return
	}
	body := node_field(node, 'body') or { return }
	if node_kind(body) != 'statement_block' {
		// An arrow function without braces.
		state.findings << finding_at(unwrap_parens(body), 'nonVoidReturn')
		return
	}
	if annotation := node_field(node, 'return_type') {
		if return_type := first_named(annotation) {
			inner := unwrap_type_parens(return_type)
			if !(node_kind(inner) == 'predefined_type' && c.text(inner) == 'void') {
				state.findings << finding_at(inner, 'nonVoidFunc')
				return
			}
		}
	}
	state.pending << node
}

// svr_walk_statements ports walkStatements: the statements of a function body, through blocks and
// control flow but not into other functions.
fn svr_walk_statements(body []C.TSNode, mut out []C.TSNode) {
	for statement in body {
		match node_kind(statement) {
			'statement_block' {
				svr_walk_statements(named_children(statement), mut out)
			}
			'switch_statement' {
				switch_body := node_field(statement, 'body') or { continue }
				for switch_case in named_children(switch_body) {
					// The consequent: what follows the `:`.
					mut after_colon := false
					mut consequent := []C.TSNode{}
					for child in children(switch_case) {
						if !after_colon {
							after_colon = node_kind(child) == ':'
						} else if node_kind(child) != 'comment' {
							consequent << child
						}
					}
					svr_walk_statements(consequent, mut out)
				}
			}
			'if_statement' {
				if consequence := node_field(statement, 'consequence') {
					svr_walk_statements([consequence], mut out)
				}
				if alternative := node_field(statement, 'alternative') {
					svr_walk_statements(named_children(alternative), mut out)
				}
			}
			'while_statement', 'do_statement', 'for_statement', 'for_in_statement',
			'with_statement', 'labeled_statement' {
				if inner := node_field(statement, 'body') {
					svr_walk_statements([inner], mut out)
				}
			}
			'try_statement' {
				if block := node_field(statement, 'body') {
					svr_walk_statements([block], mut out)
				}
				if handler := node_field(statement, 'handler') {
					if handler_body := node_field(handler, 'body') {
						svr_walk_statements([handler_body], mut out)
					}
				}
				if finalizer := node_field(statement, 'finalizer') {
					if finalizer_body := node_field(finalizer, 'body') {
						svr_walk_statements([finalizer_body], mut out)
					}
				}
			}
			else {
				out << statement
			}
		}
	}
}
