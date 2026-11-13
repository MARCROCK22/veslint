module rules

import time
import tsgo { TypeResponse }
import treesitter { first_named_child, named_children, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `no-unsafe-argument` rule of typescript-eslint 8.62.0 (it has no options). Limits of
// the port: internals.md, "Rules" section.

const nuarg_messages = {
	'unsafeArgument':    'Unsafe argument of type {{sender}} assigned to a parameter of type {{receiver}}.'
	'unsafeArraySpread': 'Unsafe spread of an {{sender}} array type.'
	'unsafeSpread':      'Unsafe spread of an {{sender}} type.'
	'unsafeTupleSpread': 'Unsafe spread of a tuple type. The argument is {{sender}} and is assigned to a parameter of type {{receiver}}.'
}

// ArgumentCall is a call (CallExpression, NewExpression or TaggedTemplateExpression) with its
// arguments as in ESTree: without parentheses and, in a template, the `${…}` expressions.
struct ArgumentCall {
	node   C.TSNode
	callee C.TSNode
	args   []C.TSNode
	tagged bool
	// an `await (…)` or `` await `…` `` that TypeScript may read as a call (see await_reading)
	await_misread bool
}

enum RestKind {
	array
	tuple
	other
}

// FunctionSignature ports the class of the same name: the types of the parameters of the signature
// TypeScript chose for the call, consumed in order by the arguments.
struct FunctionSignature {
mut:
	resolved    bool
	param_types []TypeResponse
	has_rest    bool
	rest_kind   RestKind
	rest_index  int
	rest_type   TypeResponse   // .array (type of the elements) and .other
	rest_args   []TypeResponse // .tuple
	consumed    bool
	index       int
}

// next_parameter_type ports getNextParameterType; none means there is no parameter.
fn (mut s FunctionSignature) next_parameter_type() ?TypeResponse {
	index := s.index
	s.index++
	if index < s.param_types.len && !s.consumed {
		return s.param_types[index]
	}
	if !s.has_rest {
		return none
	}
	if s.rest_kind != .tuple {
		return if s.rest_type.is_null() { none } else { s.rest_type }
	}
	if s.rest_args.len == 0 {
		return none
	}
	// With the arguments consumed by a spread, the last type of the tuple is assumed.
	type_index := index - s.rest_index
	if s.consumed || type_index >= s.rest_args.len {
		return s.rest_args.last()
	}
	return s.rest_args[type_index]
}

fn (mut c Checker) lint_no_unsafe_argument(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	calls := c.collect_argument_calls(root)
	mut spans := []Span{}
	for call in calls {
		spans << node_span(call.node)
		if call.await_misread {
			spans << await_keyword_span(call.node) or { continue }
		} else {
			spans << node_span(call.callee)
		}
		for arg in call.args {
			spans << node_span(spread_argument(arg) or { arg })
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for call in calls {
		c.check_unsafe_arguments(call, mut findings)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}

// collect_argument_calls collects the calls with some argument. `import(…)` is an
// ImportExpression in ESTree, not a call.
fn (c &Checker) collect_argument_calls(root C.TSNode) []ArgumentCall {
	mut calls := []ArgumentCall{}
	for node in c.nodes_of_kinds(root, ['call_expression', 'new_expression', 'await_expression'], []) {
		if node_kind(node) == 'await_expression' {
			if call := await_call(node) {
				calls << call
			}
			continue
		}
		field := if node_kind(node) == 'call_expression' { 'function' } else { 'constructor' }
		callee := unwrap_parens(node_field(node, field) or { continue })
		if node_kind(callee) == 'import' {
			continue
		}
		list := node_field(node, 'arguments') or { continue }
		tagged := node_kind(list) == 'template_string'
		mut args := []C.TSNode{}
		for child in named_children(list) {
			if !tagged {
				args << unwrap_parens(child)
			} else if node_kind(child) == 'template_substitution' {
				args << unwrap_parens(first_named_child(child) or { continue })
			}
		}
		if args.len > 0 {
			calls << ArgumentCall{
				node:   node
				callee: callee
				args:   args
				tagged: tagged
			}
		}
	}
	return calls
}

// await_call is an `await (a, b)` or `` await `…${x}…` `` seen as the call TypeScript reads
// outside an async function: the callee is the `await` identifier.
fn await_call(node C.TSNode) ?ArgumentCall {
	operand := first_named_child(node)?
	callee := await_keyword(node)?
	mut args := []C.TSNode{}
	match node_kind(operand) {
		'parenthesized_expression' {
			inner := first_named_child(operand)?
			if node_kind(inner) == 'sequence_expression' {
				for arg in named_children(inner) {
					args << unwrap_parens(arg)
				}
			} else {
				args << unwrap_parens(inner)
			}
		}
		'template_string' {
			for child in named_children(operand) {
				if node_kind(child) == 'template_substitution' {
					args << unwrap_parens(first_named_child(child) or { continue })
				}
			}
		}
		else {
			return none
		}
	}
	if args.len == 0 {
		return none
	}
	return ArgumentCall{
		node:          node
		callee:        callee
		args:          args
		tagged:        node_kind(operand) == 'template_string'
		await_misread: true
	}
}

// spread_argument is the value of a `...x` (without parentheses), or none if `arg` is not a spread.
fn spread_argument(arg C.TSNode) ?C.TSNode {
	if node_kind(arg) != 'spread_element' {
		return none
	}
	return unwrap_parens(first_named_child(arg)?)
}

// check_unsafe_arguments ports checkUnsafeArguments.
fn (mut c Checker) check_unsafe_arguments(call ArgumentCall, mut findings []Finding) ! {
	if call.await_misread {
		reading := c.await_reading(call.node)
		if reading != .call && reading != .tagged_template {
			return
		}
	}
	// Calls to something `any` are reported by no-unsafe-call.
	callee_type := c.node_type(call.callee) or { return }
	if c.is_any(callee_type)! {
		return
	}
	// Without any argument that may be unsafe no findings are possible, and the signature is not
	// needed.
	mut candidate := false
	for arg in call.args {
		t := c.node_type(spread_argument(arg) or { arg }) or { continue }
		if c.may_be_unsafe(t, 0)! {
			candidate = true
			break
		}
	}
	if !candidate {
		return
	}
	mut sig := c.function_signature(call.node)!
	if !sig.resolved {
		return
	}
	if call.tagged {
		// The first parameter is the TemplateStringsArray.
		sig.next_parameter_type()
	}
	for arg in call.args {
		if node_kind(arg) == 'spread_element' {
			spread := spread_argument(arg) or { continue }
			t := c.node_type(spread) or { continue }
			if c.is_any(t)! {
				findings << Finding{
					stmt:       position_of(arg)
					message_id: 'unsafeSpread'
					data:       {
						'sender': c.describe_type(t)!
					}
				}
			} else if c.is_any_array(t)! {
				findings << Finding{
					stmt:       position_of(arg)
					message_id: 'unsafeArraySpread'
					data:       {
						'sender': c.describe_type_for_spread(t)!
					}
				}
			} else if c.is_tuple(t)! {
				for element in c.type_args(t)! {
					param := sig.next_parameter_type() or { continue }
					if c.unsafe_assignment(element, param, none)!.found {
						findings << Finding{
							stmt:       position_of(arg)
							message_id: 'unsafeTupleSpread'
							data:       {
								'receiver': c.describe_type(param)!
								'sender':   c.describe_type_for_tuple(element)!
							}
						}
					}
				}
				// After a rest element, the remaining arguments go against the rest type of the signature.
				if c.is_variable_tuple(t)! {
					sig.consumed = true
				}
			}
			// Other iterables are neither checked nor consume parameters.
			continue
		}
		param := sig.next_parameter_type() or { continue }
		t := c.node_type(arg) or { continue }
		if c.unsafe_assignment(t, param, arg)!.found {
			findings << Finding{
				stmt:       position_of(arg)
				message_id: 'unsafeArgument'
				data:       {
					'receiver': c.describe_type(param)!
					'sender':   c.describe_type(t)!
				}
			}
		}
	}
}

// function_signature ports FunctionSignature.create with the signature TypeScript chose for the
// call and the type of each parameter as seen from it. Like typescript-eslint, only a parameter
// declared with `...` counts as rest; those of synthesized signatures have no declaration.
fn (mut c Checker) function_signature(call C.TSNode) !FunctionSignature {
	handle := c.node_handles[node_key(call)] or { return FunctionSignature{} }
	signature := c.resolved_signature(call)!
	if signature.id == 0 {
		return FunctionSignature{}
	}
	params := c.signature_parameters(signature)!
	mut sig := FunctionSignature{
		resolved: true
	}
	for i, param in params {
		t := c.client.type_of_symbol_at_location(c.snapshot, c.project, param.id, handle)!
		if i == params.len - 1 && signature.flags & signature_flag_has_rest_parameter != 0
			&& param.declarations.len > 0 {
			sig.has_rest = true
			sig.rest_index = i
			if c.is_array(t)! {
				sig.rest_kind = .array
				args := c.type_args(t)!
				if args.len > 0 {
					sig.rest_type = args[0]
				}
			} else if c.is_tuple(t)! {
				sig.rest_kind = .tuple
				sig.rest_args = c.type_args(t)!
			} else {
				sig.rest_kind = .other
				sig.rest_type = t
			}
			break
		}
		sig.param_types << t
	}
	return sig
}

// may_be_unsafe: isUnsafeAssignment only reports an `any` or a generic reference with `any` in
// some type argument, also nested (Set<Map<string, any>>). When in doubt (too deep) it answers
// yes.
fn (mut c Checker) may_be_unsafe(t TypeResponse, depth int) !bool {
	if c.is_any(t)! {
		return true
	}
	if !is_type_reference(t) {
		return false
	}
	if depth > max_expression_depth {
		return true
	}
	if t.id in c.unsafe_cache {
		return c.unsafe_cache[t.id]
	}
	// A type that contains itself is not unsafe that way.
	c.unsafe_cache[t.id] = false
	mut result := false
	for arg in c.type_args(t)! {
		if c.may_be_unsafe(arg, depth + 1)! {
			result = true
			break
		}
	}
	c.unsafe_cache[t.id] = result
	return result
}

// describe_type ports describeType: the type in backticks, or "error typed".
fn (mut c Checker) describe_type(t TypeResponse) !string {
	if is_error_type(t) {
		return 'error typed'
	}
	return '`${c.client.type_to_string(c.snapshot, c.project, t.id)!}`'
}

// describe_type_for_spread ports describeTypeForSpread.
fn (mut c Checker) describe_type_for_spread(t TypeResponse) !string {
	if c.is_array(t)! {
		args := c.type_args(t)!
		if args.len > 0 && is_error_type(args[0]) {
			return 'error'
		}
	}
	return c.describe_type(t)!
}

// describe_type_for_tuple ports describeTypeForTuple.
fn (mut c Checker) describe_type_for_tuple(t TypeResponse) !string {
	if is_error_type(t) {
		return 'error typed'
	}
	return 'of type `${c.client.type_to_string(c.snapshot, c.project, t.id)!}`'
}
