module rules

import estree
import time
import tsgo { TypeResponse, handle_index, handle_path }

// Port of the `@typescript-eslint/no-unsafe-enum-assignment` rule of typescript-eslint 8.72.2 (it
// has no options), with its FunctionSignature (util/FunctionSignature.ts) and the getEnumTypes of
// rules/enum-utils/shared.ts (nuec_enum_types of rules/no_unsafe_enum_comparison.v). The listeners
// run in ESLint's traversal order, as markChecked depends on it. Types are asked to tsgo for the
// nodes typescript-estree maps to TypeScript's; a node without a counterpart has no type and is
// not checked.

const nuea_messages = {
	'unsafeEnumAccess':     'The computed key used here does not have a shared enum type with the expected enum {{enumNames}}.'
	'unsafeEnumArgument':   'The argument passed here does not have a shared enum type with the expected enum {{enumNames}}.'
	'unsafeEnumAssertion':  'The value asserted here does not have a shared enum type with the expected enum {{enumNames}}.'
	'unsafeEnumAssignment': 'The value assigned here does not have a shared enum type with the expected enum {{enumNames}}.'
	'unsafeEnumMutation':   'This mutation can produce a value outside of the expected enum {{enumNames}}.'
	'unsafeEnumReturn':     'The value returned here does not have a shared enum type with the expected enum {{enumNames}}.'
}

const nuea_assigning_operators = ['=', '&&=', '&=', '??=', '^=', '|=', '||=']

const nuea_bitwise_operators = ['&', '^', '|']

const nuea_maximum_depth = 5

const nuea_syntax_kind_get_accessor = u32(179)
const nuea_syntax_kind_property_signature = u32(173)
const nuea_syntax_kind_variable_declaration = u32(262)
const nuea_syntax_kind_mapped_type = u32(202)
const nuea_syntax_kind_type_literal = u32(189)

// NueaState is what the rule keeps while it lints a file.
struct NueaState {
	t        &estree.EsTree
	abs_path string
mut:
	stats      Stats
	checked    map[int]bool
	mismatches map[u64]bool
	generic    map[int]bool
	base_enum  map[int]TypeResponse
	findings   []Finding
}

fn (mut c Checker) lint_no_unsafe_enum_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut s := NueaState{
		t:        t
		abs_path: abs_path
	}
	// The nodes whose types (or handles) the listeners ask, requested at once.
	mut spans := []Span{}
	for node in 0 .. t.nodes.len {
		for wanted in nuea_wanted_nodes(t, node) {
			if span := c.nuea_span(t, wanted) {
				spans << span
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut s.stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	for step in t.steps() {
		if step.leave {
			continue
		}
		c.nuea_enter(mut s, step.node)!
	}
	stats.nodes += s.stats.nodes
	stats.unmatched += s.stats.unmatched
	stats.checked += s.stats.checked
	stats.eval_ms += ms(sw.elapsed())
	return s.findings
}

// nuea_wanted_nodes are the nodes a listener of `node` asks about.
fn nuea_wanted_nodes(t &estree.EsTree, node int) []int {
	mut out := []int{}
	match t.typ(node) {
		.property_definition, .accessor_property {
			out << node
			out << t.node(node, .value) or { -1 }
		}
		.array_expression {
			out << t.list(node, .elements) or { []int{} }
		}
		.arrow_function_expression {
			out << node
			out << t.node(node, .body) or { -1 }
		}
		.function_declaration, .function_expression {
			out << node
		}
		.assignment_expression, .assignment_pattern {
			out << t.node(node, .left) or { -1 }
			out << t.node(node, .right) or { -1 }
		}
		.call_expression, .new_expression {
			out << node
			for argument in t.list(node, .arguments) or { []int{} } {
				out << argument
				if t.typ(argument) == .spread_element {
					out << t.node(argument, .argument) or { -1 }
				}
			}
		}
		.tagged_template_expression {
			out << node
			if quasi := t.node(node, .quasi) {
				out << t.list(quasi, .expressions) or { []int{} }
			}
		}
		.jsx_expression_container {
			out << t.node(node, .expression) or { -1 }
		}
		.member_expression {
			if t.flag(node, .computed) or { false } {
				out << t.node(node, .object) or { -1 }
				out << t.node(node, .property) or { -1 }
			}
		}
		.object_expression {
			out << node
			for property in t.list(node, .properties) or { []int{} } {
				if t.typ(property) == .spread_element {
					out << t.node(property, .argument) or { -1 }
				} else {
					out << t.node(property, .value) or { -1 }
				}
			}
		}
		.return_statement {
			out << t.node(node, .argument) or { -1 }
		}
		.ts_as_expression, .ts_type_assertion {
			out << t.node(node, .type_annotation) or { -1 }
			out << t.node(node, .expression) or { -1 }
		}
		.update_expression {
			out << t.node(node, .argument) or { -1 }
		}
		.variable_declarator {
			if t.node(node, .init) != none {
				out << t.node(node, .id) or { -1 }
				out << t.node(node, .init) or { -1 }
			}
		}
		.binary_expression {
			if (t.string_of(node, .operator) or { '' }) in nuea_bitwise_operators {
				out << t.node(node, .left) or { -1 }
				out << t.node(node, .right) or { -1 }
			}
		}
		.unary_expression {
			if (t.string_of(node, .operator) or { '' }) == '~' {
				out << t.node(node, .argument) or { -1 }
			}
		}
		else {}
	}
	return out.filter(it >= 0)
}

// nuea_is_type_node tells whether an ESTree node is the type of a type assertion, whose type is
// getTypeFromTypeNode.
fn nuea_is_type_node(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) in [.ts_as_expression, .ts_type_assertion]
		&& (t.node(parent, .type_annotation) or { -1 }) == node
}

// nuea_span is the span of the TypeScript node typescript-estree maps an ESTree node to.
fn (c &Checker) nuea_span(t &estree.EsTree, node int) ?Span {
	ts := t.ts_node(node)?
	if t.typ(node) in [.property_definition, .accessor_property] {
		// With its decorators (siblings in tree-sitter) and its `;`.
		return member_span(ts)
	}
	parent := t.nodes[node].parent
	if t.typ(node) == .function_expression && parent >= 0
		&& t.typ(parent) in [.method_definition, .ts_abstract_method_definition] {
		return member_span(ts)
	}
	if nuea_is_type_node(t, node) {
		return c.type_node_span(ts)
	}
	return node_span(ts)
}

// nuea_type ports services.getTypeAtLocation (the null type when the node has no counterpart).
fn (mut c Checker) nuea_type(mut s NueaState, node int) !TypeResponse {
	span := c.nuea_span(s.t, node) or { return TypeResponse{} }
	c.resolve_spans([span], s.abs_path, mut s.stats)!
	return c.span_type(span) or { TypeResponse{} }
}

// nuea_handle is the tsgo handle of the node's counterpart, '' if none.
fn (mut c Checker) nuea_handle(mut s NueaState, node int) !string {
	span := c.nuea_span(s.t, node) or { return '' }
	c.resolve_spans([span], s.abs_path, mut s.stats)!
	return c.node_handles[span.key] or { '' }
}

// nuea_contextual_type ports checker.getContextualType (the null type for undefined).
fn (mut c Checker) nuea_contextual_type(mut s NueaState, node int) !TypeResponse {
	if c.nuea_handle(mut s, node)! == '' {
		return TypeResponse{}
	}
	return c.contextual_type(s.t.ts_node(node) or { return TypeResponse{} })!
}

// nuea_enter runs the listeners of a node.
fn (mut c Checker) nuea_enter(mut s NueaState, node int) ! {
	t := s.t
	match t.typ(node) {
		.property_definition, .accessor_property {
			if value := t.node(node, .value) {
				s.stats.checked++
				c.nuea_check_class_member(mut s, node, value)!
			}
		}
		.array_expression {
			if s.checked[node] {
				return
			}
			s.stats.checked++
			for element in t.list(node, .elements) or { []int{} } {
				if element < 0 {
					continue
				}
				receiver := c.nuea_contextual_type(mut s, element)!
				if !receiver.is_null() {
					c.nuea_check_assignment(mut s, receiver, element, element, 'unsafeEnumAssignment',
						none)!
				}
			}
		}
		.arrow_function_expression {
			body := t.node(node, .body) or { return }
			if t.typ(body) != .block_statement {
				s.stats.checked++
				c.nuea_check_return(mut s, body, body)!
			}
		}
		.assignment_expression {
			s.stats.checked++
			left := t.node(node, .left) or { return }
			if (t.string_of(node, .operator) or { '' }) in nuea_assigning_operators {
				c.nuea_check_assignment(mut s, c.nuea_type(mut s, left)!, t.node(node, .right) or {
					return
				}, node, 'unsafeEnumAssignment', none)!
			} else {
				c.nuea_check_mutation(mut s, left, node)!
			}
		}
		.assignment_pattern {
			s.stats.checked++
			left := t.node(node, .left) or { return }
			c.nuea_check_assignment(mut s, c.nuea_type(mut s, left)!, t.node(node, .right) or {
				return
			}, node, 'unsafeEnumAssignment', none)!
		}
		.call_expression, .new_expression {
			s.stats.checked++
			c.nuea_check_arguments(mut s, node, t.list(node, .arguments) or { []int{} })!
		}
		.jsx_expression_container {
			parent := t.nodes[node].parent
			expression := t.node(node, .expression) or { return }
			if parent >= 0 && t.typ(parent) == .jsx_attribute
				&& t.typ(expression) != .jsx_empty_expression {
				s.stats.checked++
				receiver := c.nuea_contextual_type(mut s, expression)!
				if !receiver.is_null() {
					c.nuea_check_assignment(mut s, receiver, expression, expression, 'unsafeEnumAssignment',
						none)!
				}
			}
		}
		.member_expression {
			if t.flag(node, .computed) or { false } {
				s.stats.checked++
				c.nuea_check_computed_member(mut s, node)!
			}
		}
		.object_expression {
			if s.checked[node] {
				return
			}
			s.stats.checked++
			for property in t.list(node, .properties) or { []int{} } {
				receiver_node, sender_node := if t.typ(property) == .spread_element {
					node, t.node(property, .argument) or { continue }
				} else {
					v := t.node(property, .value) or { continue }
					v, v
				}
				receiver := c.nuea_contextual_type(mut s, receiver_node)!
				if !receiver.is_null() {
					c.nuea_check_assignment(mut s, receiver, sender_node, property, 'unsafeEnumAssignment',
						none)!
				}
			}
		}
		.return_statement {
			if argument := t.node(node, .argument) {
				s.stats.checked++
				c.nuea_check_return(mut s, argument, node)!
			}
		}
		.tagged_template_expression {
			s.stats.checked++
			quasi := t.node(node, .quasi) or { return }
			c.nuea_check_arguments(mut s, node, t.list(quasi, .expressions) or { []int{} })!
		}
		.ts_as_expression, .ts_type_assertion {
			s.stats.checked++
			annotation := t.node(node, .type_annotation) or { return }
			c.nuea_check_assignment(mut s, c.nuea_type(mut s, annotation)!, t.node(node, .expression) or {
				return
			}, node, 'unsafeEnumAssertion', none)!
		}
		.update_expression {
			s.stats.checked++
			c.nuea_check_mutation(mut s, t.node(node, .argument) or { return }, node)!
		}
		.variable_declarator {
			init := t.node(node, .init) or { return }
			s.stats.checked++
			c.nuea_check_assignment(mut s, c.nuea_type(mut s, t.node(node, .id) or { return })!,
				init, node, 'unsafeEnumAssignment', none)!
		}
		else {}
	}
}

// nuea_report reports a node with the names of the enums of the receivers.
fn (mut c Checker) nuea_report(mut s NueaState, node int, message_id string, receivers []TypeResponse) ! {
	s.findings << Finding{
		stmt:       c.es_tree_position(s.t, node)
		message_id: message_id
		data:       {
			'enumNames': c.nuea_describe_enum_types(mut s, receivers)!
		}
	}
}

// nuea_mark_checked ports markChecked.
fn nuea_mark_checked(mut s NueaState, node int) {
	t := s.t
	if node < 0 {
		return
	}
	s.checked[node] = true
	match t.typ(node) {
		.array_expression {
			for element in t.list(node, .elements) or { []int{} } {
				if element >= 0 {
					nuea_mark_checked(mut s, element)
				}
			}
		}
		.conditional_expression {
			nuea_mark_checked(mut s, t.node(node, .consequent) or { -1 })
			nuea_mark_checked(mut s, t.node(node, .alternate) or { -1 })
		}
		.logical_expression {
			nuea_mark_checked(mut s, t.node(node, .left) or { -1 })
			nuea_mark_checked(mut s, t.node(node, .right) or { -1 })
		}
		.object_expression {
			for property in t.list(node, .properties) or { []int{} } {
				nuea_mark_checked(mut s, property)
			}
		}
		.property {
			nuea_mark_checked(mut s, t.node(node, .value) or { -1 })
		}
		.spread_element {
			nuea_mark_checked(mut s, t.node(node, .argument) or { -1 })
		}
		.ts_as_expression, .ts_non_null_expression, .ts_satisfies_expression, .ts_type_assertion {
			nuea_mark_checked(mut s, t.node(node, .expression) or { -1 })
		}
		else {}
	}
}

// nuea_is_safe_enum_bitwise_expression ports isSafeEnumBitwiseExpression.
fn (mut c Checker) nuea_is_safe_enum_bitwise_expression(mut s NueaState, node int, receiver TypeResponse) !bool {
	t := s.t
	match t.typ(node) {
		.binary_expression {
			if (t.string_of(node, .operator) or { '' }) !in nuea_bitwise_operators {
				return false
			}
			return c.nuea_is_safe_operand(mut s, t.node(node, .left) or { return false }, receiver)!
				&& c.nuea_is_safe_operand(mut s, t.node(node, .right) or { return false }, receiver)!
		}
		.unary_expression {
			return (t.string_of(node, .operator) or { '' }) == '~'
				&& c.nuea_is_safe_operand(mut s, t.node(node, .argument) or { return false }, receiver)!
		}
		else {
			return false
		}
	}
}

// nuea_is_safe_operand ports isSafeOperand.
fn (mut c Checker) nuea_is_safe_operand(mut s NueaState, operand int, receiver TypeResponse) !bool {
	if c.nuea_is_safe_enum_bitwise_expression(mut s, operand, receiver)! {
		return true
	}
	return !c.nuea_is_mismatched_enum_assignment_types(mut s, c.nuea_type(mut s, operand)!,
		receiver)!
}

// nuea_is_unsafe_assignment ports isUnsafeAssignment.
fn (mut c Checker) nuea_is_unsafe_assignment(mut s NueaState, sender_node int, receiver TypeResponse, sender ?TypeResponse) !bool {
	sender_type := sender or { c.nuea_type(mut s, sender_node)! }
	return c.nuea_has_enum_assignment_mismatch(mut s, sender_type, receiver)!
		&& !c.nuea_is_safe_enum_bitwise_expression(mut s, sender_node, receiver)!
}

// nuea_check_assignment ports checkAssignment.
fn (mut c Checker) nuea_check_assignment(mut s NueaState, receiver TypeResponse, sender_node int, reporting_node int, message_id string, sender ?TypeResponse) ! {
	if s.t.typ(sender_node) in [.array_expression, .object_expression]
		|| !c.nuea_is_unsafe_assignment(mut s, sender_node, receiver, sender)! {
		return
	}
	c.nuea_report(mut s, reporting_node, message_id, [receiver])!
	nuea_mark_checked(mut s, sender_node)
}

// NueaSignature ports FunctionSignature (rest_kind: 0 none, 1 array, 2 other, 3 tuple).
struct NueaSignature {
mut:
	param_types []TypeResponse
	rest_kind   int
	rest_index  int
	rest_type   TypeResponse
	rest_args   []TypeResponse
	consumed    bool
	index       int
}

// next_parameter_type ports getNextParameterType (none for null or undefined).
fn (mut sig NueaSignature) next_parameter_type() ?TypeResponse {
	index := sig.index
	sig.index++
	if index >= sig.param_types.len || sig.consumed {
		match sig.rest_kind {
			0 {
				return none
			}
			3 {
				if sig.rest_args.len == 0 {
					return none
				}
				if sig.consumed {
					return sig.rest_args.last()
				}
				type_index := index - sig.rest_index
				if type_index >= sig.rest_args.len {
					return sig.rest_args.last()
				}
				return sig.rest_args[type_index]
			}
			else {
				return sig.rest_type
			}
		}
	}
	return sig.param_types[index]
}

// nuea_function_signature ports FunctionSignature.create.
fn (mut c Checker) nuea_function_signature(mut s NueaState, node int) !NueaSignature {
	mut sig := NueaSignature{}
	handle := c.nuea_handle(mut s, node)!
	if handle == '' {
		return sig
	}
	signature := c.resolved_signature(s.t.ts_node(node) or { return sig })!
	if signature.id == 0 {
		return sig
	}
	params := c.signature_parameters(signature)!
	for index, param in params {
		typ := c.client.type_of_symbol_at_location(c.snapshot, c.project, param.id, handle)!
		constrained := c.constrained(typ)!
		if param.declarations.len > 0 && c.nuea_is_rest_parameter_declaration(param.declarations[0])! {
			sig.rest_index = index
			if constrained.is_tuple_type {
				sig.rest_kind = 3
				sig.rest_args = c.type_args(constrained)!
			} else {
				element := c.number_index_type(constrained)!
				if !element.is_null() {
					sig.rest_kind = 1
					sig.rest_type = element
				} else {
					sig.rest_kind = 2
					sig.rest_type = constrained
				}
			}
			break
		}
		sig.param_types << typ
	}
	return sig
}

// nuea_is_rest_parameter_declaration ports isRestParameterDeclaration: a parameter with `...`.
fn (mut c Checker) nuea_is_rest_parameter_declaration(handle string) !bool {
	tree := c.declaration_ast(handle_path(handle))!
	index := handle_index(handle)
	return tree.node_kind(index) == syntax_kind_parameter
		&& tree.node_child(index, 'dotDotDotToken') != 0
}

// nuea_check_arguments ports checkArguments.
fn (mut c Checker) nuea_check_arguments(mut s NueaState, node int, args []int) ! {
	t := s.t
	mut sig := c.nuea_function_signature(mut s, node)!
	if t.typ(node) == .tagged_template_expression {
		// The first parameter receives the template's strings, not a value.
		sig.next_parameter_type()
	}
	for argument in args {
		if t.typ(argument) == .spread_element {
			spread_type := c.nuea_type(mut s, t.node(argument, .argument) or { continue })!
			if !spread_type.is_null() && spread_type.is_tuple_type {
				mut mismatched := []TypeResponse{}
				for element_type in c.type_args(spread_type)! {
					parameter_type := sig.next_parameter_type() or { continue }
					if c.nuea_has_enum_assignment_mismatch(mut s, element_type, parameter_type)! {
						mismatched << parameter_type
					}
				}
				if mismatched.len > 0 {
					c.nuea_report(mut s, argument, 'unsafeEnumArgument', mismatched)!
				}
				if c.is_variable_tuple(spread_type)! {
					sig.consumed = true
				}
				continue
			}
		}
		parameter_type := sig.next_parameter_type() or { continue }
		c.nuea_check_assignment(mut s, parameter_type, argument, argument, 'unsafeEnumArgument',
			none)!
	}
}

// nuea_check_class_member ports checkClassMember.
fn (mut c Checker) nuea_check_class_member(mut s NueaState, node int, value int) ! {
	heritage_member_types := c.nuea_heritage_member_types(mut s, node)!
	if heritage_member_types.len > 0 {
		mut every := true
		for heritage_member_type in heritage_member_types {
			if !c.nuea_is_unsafe_assignment(mut s, value, heritage_member_type, none)! {
				every = false
				break
			}
		}
		if every {
			c.nuea_report(mut s, node, 'unsafeEnumAssignment', heritage_member_types)!
			nuea_mark_checked(mut s, value)
			return
		}
	}
	c.nuea_check_assignment(mut s, c.nuea_type(mut s, node)!, value, node, 'unsafeEnumAssignment',
		none)!
}

// nuea_heritage_member_types ports getHeritageMemberTypes: the types of the member of the same
// name in the types the class extends and implements.
fn (mut c Checker) nuea_heritage_member_types(mut s NueaState, node int) ![]TypeResponse {
	t := s.t
	ts := t.ts_node(node) or { return []TypeResponse{} }
	member_name := c.static_member_name(ts) or { return []TypeResponse{} }
	body := t.nodes[node].parent
	class := if body >= 0 { t.nodes[body].parent } else { -1 }
	if class < 0 {
		return []TypeResponse{}
	}
	// The heritage clauses: an ExpressionWithTypeArguments for `extends`, a type reference for
	// each `implements` (as tsgo 7.1 gives their types).
	mut spans := []Span{}
	if super_class := t.node(class, .super_class) {
		end := if args := t.node(class, .super_type_arguments) {
			t.nodes[args].end
		} else {
			t.nodes[super_class].end
		}
		if first := t.ts_node(super_class) {
			spans << heritage_span(first, end, syntax_kind_expression_with_type_arguments)
		}
	}
	for implement in t.list(class, .implements_) or { []int{} } {
		if first := t.ts_node(implement) {
			spans << heritage_span(first, t.nodes[implement].end, syntax_kind_type_reference)
		}
	}
	mut out := []TypeResponse{}
	for span in spans {
		c.resolve_spans([span], s.abs_path, mut s.stats)!
		heritage_type := c.span_type(span) or { continue }
		member_symbol := c.property(heritage_type, member_name)!
		if !member_symbol.is_null() {
			out << c.symbol_type(member_symbol.id)!
		}
	}
	return out
}

// nuea_check_mutation ports checkMutation.
fn (mut c Checker) nuea_check_mutation(mut s NueaState, target int, reporting_node int) ! {
	target_type := c.nuea_type(mut s, target)!
	if target_type.is_null() {
		return
	}
	if c.nuea_enum_types(mut s, c.constrained(target_type)!)!.len > 0 {
		c.nuea_report(mut s, reporting_node, 'unsafeEnumMutation', [target_type])!
	}
}

// nuea_check_return ports checkReturn.
fn (mut c Checker) nuea_check_return(mut s NueaState, return_node int, reporting_node int) ! {
	t := s.t
	mut function_node := t.nodes[return_node].parent
	for function_node >= 0 && t.typ(function_node) !in [.arrow_function_expression,
		.function_declaration, .function_expression] {
		function_node = t.nodes[function_node].parent
	}
	if function_node < 0 {
		return
	}
	handle := c.nuea_handle(mut s, function_node)!
	if handle == '' {
		return
	}
	signature := c.client.signature_from_declaration(c.snapshot, c.project, handle)!
	if signature.id == 0 {
		return
	}
	mut receiver := c.return_type(signature.id)!
	mut sender := c.nuea_type(mut s, return_node)!
	if t.flag(function_node, .async) or { false } {
		receiver = c.awaited_type(receiver)!.typ
		sender = c.awaited_type(sender)!.typ
	}
	if !receiver.is_null() && !sender.is_null() {
		c.nuea_check_assignment(mut s, receiver, return_node, reporting_node, 'unsafeEnumReturn',
			sender)!
	}
}

// nuea_check_computed_member is the listener of a computed MemberExpression.
fn (mut c Checker) nuea_check_computed_member(mut s NueaState, node int) ! {
	t := s.t
	object := t.node(node, .object) or { return }
	property := t.node(node, .property) or { return }
	handle := c.nuea_handle(mut s, object)!
	if handle == '' {
		return
	}
	symbol := c.sy_symbol_at_handle(handle)!
	if symbol.is_null() {
		return
	}
	mut receivers := []TypeResponse{}
	for declaration in symbol.declarations {
		receivers << c.nuea_mapped_key_constraint_types(declaration)!
	}
	if receivers.len == 0 {
		return
	}
	sender := c.nuea_type(mut s, property)!
	if sender.is_null() {
		return
	}
	for receiver in receivers {
		if !c.nuea_has_enum_assignment_mismatch(mut s, sender, receiver)!
			&& c.assignable(sender.id, receiver.id)! {
			return
		}
	}
	c.nuea_report(mut s, property, 'unsafeEnumAccess', receivers)!
}

// nuea_mapped_key_constraint_types ports getMappedKeyConstraintTypes for a declaration handle.
fn (mut c Checker) nuea_mapped_key_constraint_types(handle string) ![]TypeResponse {
	tree := c.declaration_ast(handle_path(handle))!
	index := handle_index(handle)
	if tree.node_kind(index) !in [nuea_syntax_kind_get_accessor, syntax_kind_parameter,
		syntax_kind_property_declaration, nuea_syntax_kind_property_signature,
		nuea_syntax_kind_variable_declaration] {
		return []TypeResponse{}
	}
	type_node := tree.node_child(index, 'type')
	if type_node == 0 {
		return []TypeResponse{}
	}
	if tree.node_kind(type_node) == nuea_syntax_kind_mapped_type {
		type_parameter := tree.node_child(type_node, 'typeParameter')
		constraint := if type_parameter != 0 {
			tree.node_child(type_parameter, 'constraint')
		} else {
			0
		}
		if constraint == 0 {
			return []TypeResponse{}
		}
		return [
			c.client.type_from_type_node(c.snapshot, c.project, tree.node_handle(constraint))!,
		]
	}
	if tree.node_kind(type_node) == nuea_syntax_kind_type_literal {
		mut out := []TypeResponse{}
		members := tree.node_child(type_node, 'members')
		if members == 0 {
			return out
		}
		for member in tree.node_children(members) {
			name := tree.node_child(member, 'name')
			if name == 0 || tree.node_kind(name) != syntax_kind_computed_property_name {
				continue
			}
			expression := tree.node_child(name, 'expression')
			if expression == 0 {
				continue
			}
			types := c.client.types_at_locations(c.snapshot, c.project, [
				tree.node_handle(expression),
			])!
			if types.len == 1 {
				out << types[0]
			}
		}
		return out
	}
	return []TypeResponse{}
}

// nuea_type_arguments ports getTypeArguments: those of a type reference.
fn (mut c Checker) nuea_type_arguments(typ TypeResponse) ![]TypeResponse {
	if typ.flags & type_flag_object == 0 || typ.object_flags & object_flag_reference == 0 {
		return []TypeResponse{}
	}
	return c.type_args(typ)!
}

// nuea_is_generic_type ports isGenericType (its cache: false while a type is being decided).
fn (mut c Checker) nuea_is_generic_type(mut s NueaState, typ TypeResponse) !bool {
	if cached := s.generic[typ.id] {
		return cached
	}
	s.generic[typ.id] = false
	mut generic := typ.flags & type_flag_instantiable != 0
	if !generic && typ.flags & (type_flag_union | type_flag_intersection) != 0 {
		for part in c.members_of(typ)! {
			if c.nuea_is_generic_type(mut s, part)! {
				generic = true
				break
			}
		}
	}
	if !generic && typ.alias_type_arguments.len > 0 {
		for part in c.client.alias_type_arguments_of_type(c.snapshot, c.project, typ.id)! {
			if c.nuea_is_generic_type(mut s, part)! {
				generic = true
				break
			}
		}
	}
	if !generic {
		for part in c.nuea_type_arguments(typ)! {
			if c.nuea_is_generic_type(mut s, part)! {
				generic = true
				break
			}
		}
	}
	s.generic[typ.id] = generic
	return generic
}

// nuea_has_enum_assignment_mismatch ports hasEnumAssignmentMismatch, kept for each pair.
fn (mut c Checker) nuea_has_enum_assignment_mismatch(mut s NueaState, sender TypeResponse, receiver TypeResponse) !bool {
	if sender.is_null() || receiver.is_null() {
		return false
	}
	key := (u64(u32(sender.id)) << 32) | u64(u32(receiver.id))
	if cached := s.mismatches[key] {
		return cached
	}
	mut visited := map[u64]bool{}
	mismatch := c.nuea_has_deep_mismatch(mut s, sender, receiver, mut visited, 0, false)!
	s.mismatches[key] = mismatch
	return mismatch
}

// nuea_has_deep_mismatch ports hasDeepEnumAssignmentMismatch.
fn (mut c Checker) nuea_has_deep_mismatch(mut s NueaState, sender TypeResponse, receiver TypeResponse, mut visited map[u64]bool, depth int, within_generic_members bool) !bool {
	if depth > nuea_maximum_depth || sender.is_null() || receiver.is_null() {
		return false
	}
	cs := c.constrained(sender)!
	cr := c.constrained(receiver)!
	if cs.id == cr.id {
		return false
	}
	// Recursive types would otherwise be visited endlessly.
	key := (u64(u32(cs.id)) << 32) | u64(u32(cr.id))
	if visited[key] {
		return false
	}
	visited[key] = true
	if c.nuea_is_mismatched_enum_assignment_types(mut s, cs, cr)! {
		return true
	}
	// Set<number> -> Set<Fruit>
	sender_arguments := c.nuea_type_arguments(cs)!
	receiver_arguments := c.nuea_type_arguments(cr)!
	if sender_arguments.len == receiver_arguments.len {
		for i, argument in sender_arguments {
			if c.nuea_has_deep_mismatch(mut s, argument, receiver_arguments[i], mut visited,
				depth + 1, within_generic_members)! {
				return true
			}
		}
	}
	// Members of generic types can instantiate ever-larger generic types.
	generic := c.nuea_is_generic_type(mut s, cs)! || c.nuea_is_generic_type(mut s, cr)!
	if generic && within_generic_members {
		return false
	}
	// [number, Fruit] -> Fruit[]
	sender_element := c.number_index_type(cs)!
	receiver_element := c.number_index_type(cr)!
	if !sender_element.is_null() && !receiver_element.is_null()
		&& c.nuea_has_deep_mismatch(mut s, sender_element, receiver_element, mut visited, depth + 1, generic
		|| within_generic_members)! {
		return true
	}
	// { fruit: number } -> { fruit: Fruit }
	for receiver_property in c.properties(cr)! {
		sender_property := c.property(cs, receiver_property.name)!
		if !sender_property.is_null()
			&& c.nuea_has_deep_mismatch(mut s, c.symbol_type(sender_property.id)!, c.symbol_type(receiver_property.id)!, mut
			visited, depth + 1, generic || within_generic_members)! {
			return true
		}
	}
	return false
}

// nuea_enum_types ports getEnumTypes.
fn (mut c Checker) nuea_enum_types(mut s NueaState, typ TypeResponse) ![]TypeResponse {
	if typ.is_null() {
		return []TypeResponse{}
	}
	return c.nuec_enum_types(typ, mut s.base_enum)!
}

// nuea_describe_enum_types ports describeEnumTypes: the sorted names of the enums of the types,
// their type arguments, element types and properties.
fn (mut c Checker) nuea_describe_enum_types(mut s NueaState, types []TypeResponse) !string {
	mut names := []string{}
	mut visited := map[int]bool{}
	for typ in types {
		c.nuea_describe_visit(mut s, typ, mut visited, mut names)!
	}
	names.sort_with_compare(fn (a &string, b &string) int {
		return if utf16_less(*a, *b) {
			-1
		} else if utf16_less(*b, *a) {
			1
		} else {
			0
		}
	})
	return names.map("'${it}'").join(', ')
}

fn (mut c Checker) nuea_describe_visit(mut s NueaState, typ TypeResponse, mut visited map[int]bool, mut names []string) ! {
	if typ.is_null() {
		return
	}
	constrained := c.constrained(typ)!
	if visited[constrained.id] {
		return
	}
	visited[constrained.id] = true
	for enum_type in c.nuea_enum_types(mut s, constrained)! {
		name := c.type_string(enum_type)!
		if name !in names {
			names << name
		}
	}
	for argument in c.nuea_type_arguments(constrained)! {
		c.nuea_describe_visit(mut s, argument, mut visited, mut names)!
	}
	element := c.number_index_type(constrained)!
	if !element.is_null() {
		c.nuea_describe_visit(mut s, element, mut visited, mut names)!
	}
	for property in c.properties(constrained)! {
		c.nuea_describe_visit(mut s, c.symbol_type(property.id)!, mut visited, mut names)!
	}
}

// nuea_enum_value_type ports getEnumValueType: 1 for Number, 2 for String, 0 for undefined.
fn nuea_enum_value_type(typ TypeResponse) int {
	if typ.flags & nuec_enum_like == 0 {
		return 0
	}
	return if typ.flags & type_flag_number_literal != 0 { 1 } else { 2 }
}

// nuea_is_mismatched_enum_assignment_types ports isMismatchedEnumAssignmentTypes.
fn (mut c Checker) nuea_is_mismatched_enum_assignment_types(mut s NueaState, sender TypeResponse, receiver TypeResponse) !bool {
	if sender.is_null() || receiver.is_null() {
		return false
	}
	receiver_enum_types := c.nuea_enum_types(mut s, receiver)!
	receiver_parts := c.constituents(receiver)!
	value_types := receiver_parts.map(nuea_enum_value_type(it))
	mut non_enum_parts := []TypeResponse{}
	for part in receiver_parts {
		if c.nuea_enum_types(mut s, part)!.len == 0 {
			non_enum_parts << part
		}
	}
	for sender_part in c.constituents(sender)! {
		like := (1 in value_types
			&& c.nuec_every_part_like(sender_part, type_flag_number_like)!)
			|| (2 in value_types && c.nuec_every_part_like(sender_part, type_flag_string_like)!)
		if !like {
			continue
		}
		// hasSharedEnumType
		sender_enum_ids := c.nuea_enum_types(mut s, sender_part)!.map(it.id)
		if receiver_enum_types.any(it.id in sender_enum_ids) {
			continue
		}
		mut assignable := false
		for part in non_enum_parts {
			if c.assignable(sender_part.id, part.id)! {
				assignable = true
				break
			}
		}
		if !assignable {
			return true
		}
	}
	return false
}
