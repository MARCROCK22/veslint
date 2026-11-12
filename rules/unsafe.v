module rules

import tsgo { TypeResponse }
import treesitter { first_named_child, named_children, node_field, node_kind, node_parent }

// Utilities of the no-unsafe-* family: the `any` and `unknown` predicates of type-utils, and the
// ports of isUnsafeAssignment, discriminateAnyType, getThisExpression and getContextualType from
// typescript-eslint 8.62.0. getAwaitedType is asked to tsgo (rules/awaited_type.v).

// AnyType ports util.AnyType.
enum AnyType {
	any
	promise_any
	any_array
	safe
}

// UnsafePair is the result of isUnsafeAssignment: the types named in the message.
struct UnsafePair {
	found    bool
	sender   TypeResponse
	receiver TypeResponse
}

// type_flags ports getTypeFlags from type-utils: the flags of all the parts of a union.
fn (mut c Checker) type_flags(t TypeResponse) !u32 {
	if t.flags & type_flag_union == 0 {
		return t.flags
	}
	mut flags := u32(0)
	for part in c.members_of(t)! {
		flags |= part.flags
	}
	return flags
}

fn (mut c Checker) is_any(t TypeResponse) !bool {
	return c.type_flags(t)! & type_flag_any != 0
}

fn (mut c Checker) is_unknown(t TypeResponse) !bool {
	return c.type_flags(t)! & type_flag_unknown != 0
}

// is_error_type ports isIntrinsicErrorType: the `any` TypeScript uses when it cannot resolve a
// type.
fn is_error_type(t TypeResponse) bool {
	return t.flags & type_flag_any != 0 && t.intrinsic_name == 'error'
}

// is_type_reference ports isTypeReference from ts-api-utils.
fn is_type_reference(t TypeResponse) bool {
	return t.flags & type_flag_object != 0 && t.object_flags & object_flag_reference != 0
}

// is_array ports checker.isArrayType: a reference to the global Array or ReadonlyArray.
fn (mut c Checker) is_array(t TypeResponse) !bool {
	if t.object_flags & object_flag_reference == 0 {
		return false
	}
	if t.id !in c.array_type_cache {
		c.array_type_cache[t.id] = c.client.is_array_type(c.snapshot, c.project, t.id)!
	}
	return c.array_type_cache[t.id]
}

// is_tuple ports checker.isTupleType, which tsgo sends with every type. It keeps the result type
// of is_array, its twin in the rules.
fn (mut c Checker) is_tuple(t TypeResponse) !bool {
	return t.is_tuple_type
}

fn (mut c Checker) type_args(t TypeResponse) ![]TypeResponse {
	if t.id !in c.type_args_cache {
		c.type_args_cache[t.id] = c.client.type_arguments(c.snapshot, c.project, t.id)!
	}
	return c.type_args_cache[t.id]
}

fn (mut c Checker) is_any_array(t TypeResponse) !bool {
	if !c.is_array(t)! {
		return false
	}
	args := c.type_args(t)!
	return args.len > 0 && c.is_any(args[0])!
}

fn (mut c Checker) is_unknown_array(t TypeResponse) !bool {
	if !c.is_array(t)! {
		return false
	}
	args := c.type_args(t)!
	return args.len > 0 && c.is_unknown(args[0])!
}

// is_variable_tuple: the tuple has a rest or variadic element (target.combinedFlags &
// ElementFlags.Variable).
fn (mut c Checker) is_variable_tuple(t TypeResponse) !bool {
	target := c.client.target_of_type(c.snapshot, c.project, t.id)!
	for flags in target.element_flags {
		if flags & element_flags_variable != 0 {
			return true
		}
	}
	return false
}

// type_constituents ports typeConstituents from ts-api-utils: the parts of a union or an
// intersection.
fn (mut c Checker) type_constituents(t TypeResponse) ![]TypeResponse {
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		return c.members_of(t)!
	}
	return [t]
}

// unsafe_assignment ports isUnsafeAssignment: assigning `any` to something that is neither `any`
// nor `unknown`, or a generic reference to another of the same type with such an argument
// (Set<any> to Set<string>). `sender_node` is the assigned value, if any.
fn (mut c Checker) unsafe_assignment(sender TypeResponse, receiver TypeResponse, sender_node ?C.TSNode) !UnsafePair {
	mut visited := map[string]bool{}
	return c.unsafe_assignment_worker(sender, receiver, sender_node, mut visited, 0)!
}

fn (mut c Checker) unsafe_assignment_worker(t TypeResponse, receiver TypeResponse, sender_node ?C.TSNode, mut visited map[string]bool, depth int) !UnsafePair {
	if c.is_any(t)! {
		if c.is_unknown(receiver)! {
			return UnsafePair{}
		}
		if !c.is_any(receiver)! {
			return UnsafePair{
				found:    true
				sender:   t
				receiver: receiver
			}
		}
	}
	key := '${t.id}:${receiver.id}'
	if key in visited || depth > max_type_depth {
		return UnsafePair{}
	}
	visited[key] = true
	if !is_type_reference(t) || !is_type_reference(receiver) || t.target != receiver.target {
		return UnsafePair{}
	}
	// `new Map()` is typed as Map<any, any>.
	if node := sender_node {
		if c.is_new_map_without_arguments(node) {
			return UnsafePair{}
		}
	}
	args := c.type_args(t)!
	receiver_args := c.type_args(receiver)!
	for i, arg in args {
		if i >= receiver_args.len {
			break
		}
		if c.unsafe_assignment_worker(arg, receiver_args[i], sender_node, mut visited, depth + 1)!.found {
			return UnsafePair{
				found:    true
				sender:   t
				receiver: receiver
			}
		}
	}
	return UnsafePair{}
}

fn (c &Checker) is_new_map_without_arguments(n C.TSNode) bool {
	node := unwrap_parens(n)
	if node_kind(node) != 'new_expression' {
		return false
	}
	callee := node_field(node, 'constructor') or { return false }
	if node_kind(callee) != 'identifier' || c.text(callee) != 'Map' {
		return false
	}
	if _ := node_field(node, 'type_arguments') {
		return false
	}
	args := node_field(node, 'arguments') or { return true }
	return named_children(args).len == 0
}

// discriminate_any ports discriminateAnyType(type, checker, program, tsNode): `any`, `any[]`, a
// Promise of `any`, or none of them. `at` is the node.
fn (mut c Checker) discriminate_any(t TypeResponse, at SymbolLocation) !AnyType {
	if c.is_any(t)! {
		return .any
	}
	if c.is_any_array(t)! {
		return .any_array
	}
	for part in c.type_constituents(t)! {
		if c.is_thenable(part, at)! {
			awaited := c.awaited_type(part)!
			if awaited.found && c.awaited_flags(awaited)! & type_flag_any != 0 {
				return .promise_any
			}
		}
	}
	return .safe
}

fn unique_types(types []TypeResponse) []TypeResponse {
	mut seen := map[int]bool{}
	mut out := []TypeResponse{}
	for t in types {
		if t.id !in seen {
			seen[t.id] = true
			out << t
		}
	}
	return out
}

// this_expression ports getThisExpression: the `this` a chain of calls and member accesses starts
// from (`this.a.b()`). A tagged template breaks the chain.
fn this_expression(n C.TSNode) ?C.TSNode {
	mut node := unwrap_parens(n)
	for {
		match node_kind(node) {
			'call_expression' {
				args := node_field(node, 'arguments')?
				if node_kind(args) != 'arguments' {
					return none
				}
				node = unwrap_parens(node_field(node, 'function')?)
			}
			'member_expression', 'subscript_expression' {
				node = unwrap_parens(node_field(node, 'object')?)
			}
			'this' {
				return node
			}
			else {
				return none
			}
		}
	}
	return none
}

// this_is_any: `n` comes from a `this` whose type (with its constraint) is `any`, and the project
// does not have `noImplicitThis`. It is the "this" variant of the messages.
fn (mut c Checker) this_is_any(n C.TSNode) !bool {
	if c.no_implicit_this {
		return false
	}
	this := this_expression(n) or { return false }
	t := c.node_type(this) or { return false }
	return c.is_any(c.constrained(t)!)!
}

// this_spans are the `this` the nodes come from, for the "this" variant of the messages.
fn (c &Checker) this_spans(nodes []C.TSNode) []Span {
	if c.no_implicit_this {
		return []Span{}
	}
	mut spans := []Span{}
	for n in nodes {
		if this := this_expression(n) {
			spans << node_span(this)
		}
	}
	return spans
}

// util_contextual_type ports getContextualType from type-utils, which is not the checker's: it
// decides by the parent in the TypeScript AST, where parentheses are nodes. Returns the null type
// when typescript-eslint would return undefined.
fn (mut c Checker) util_contextual_type(n C.TSNode) !TypeResponse {
	parent := node_parent(n) or { return TypeResponse{} }
	match node_kind(parent) {
		'arguments', 'template_substitution' {
			// An argument of a call or a `${…}` of a template.
			return c.contextual_type(n)!
		}
		'call_expression', 'new_expression' {
			// The callee has no contextual type.
			return TypeResponse{}
		}
		'jsx_expression' {
			// The value of a JSX attribute or child: the contextual type of the `{…}`.
			return c.contextual_type(parent)!
		}
		'variable_declarator', 'public_field_definition', 'required_parameter',
		'optional_parameter' {
			annotation := node_field(parent, 'type') or { return TypeResponse{} }
			type_node := first_named_child(annotation) or { return TypeResponse{} }
			return c.node_type(type_node) or { TypeResponse{} }
		}
		'pair' {
			// Only the key, if it is an identifier.
			key := node_field(parent, 'key') or { return TypeResponse{} }
			if node_key(key) == node_key(n) && node_kind(n) == 'property_identifier' {
				return c.contextual_type(n)!
			}
			return TypeResponse{}
		}
		'assignment_expression' {
			right := node_field(parent, 'right') or { return TypeResponse{} }
			if node_key(right) != node_key(n) {
				return TypeResponse{}
			}
			left := node_field(parent, 'left') or { return TypeResponse{} }
			return c.node_type(left) or { TypeResponse{} }
		}
		else {
			return TypeResponse{}
		}
	}
}

// util_contextual_spans are the nodes util_contextual_type may need for `n`.
fn (c &Checker) util_contextual_spans(n C.TSNode) []Span {
	parent := node_parent(n) or { return []Span{} }
	mut spans := [node_span(n)]
	match node_kind(parent) {
		'variable_declarator', 'public_field_definition', 'required_parameter',
		'optional_parameter' {
			if annotation := node_field(parent, 'type') {
				if type_node := first_named_child(annotation) {
					spans << c.type_node_span(type_node)
				}
			}
		}
		'assignment_expression' {
			if left := node_field(parent, 'left') {
				spans << node_span(left)
			}
		}
		'jsx_expression' {
			spans << node_span(parent)
		}
		else {}
	}
	return spans
}
