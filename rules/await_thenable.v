module rules

import time
import tsgo { SignatureResponse, TypeResponse }
import treesitter { children, first_named_child, named_children, node_field, node_kind, nodes_of_kind, position_of }

// Port of the `await-thenable` rule of typescript-eslint 8.62.0 (it has no options), with its
// suggestions. It uses the exact type of each expression (getTypeAtLocations). Limits of the port:
// README, "Rules" section.

// typescript-eslint messages.
const at_messages = {
	'await':                          'Unexpected `await` of a non-Promise (non-"Thenable") value.'
	'awaitUsingOfNonAsyncDisposable': 'Unexpected `await using` of a value that is not async disposable.'
	'convertToOrdinaryFor':           'Convert to an ordinary `for...of` loop.'
	'forAwaitOfNonAsyncIterable':     'Unexpected `for await...of` of a value that is not async iterable.'
	'invalidPromiseAggregatorInput':  'Unexpected iterable of non-Promise (non-"Thenable") values passed to promise aggregator.'
	'removeAwait':                    'Remove unnecessary `await`.'
}

// PromiseConstructor methods that take an iterable (PROMISE_CONSTRUCTOR_ARRAY_METHODS).
const aggregator_methods = ['all', 'allSettled', 'race', 'any']

// Awaitable ports util.Awaitable: whether a value of that type needs to be awaited.
enum Awaitable {
	never
	may
	always
}

struct AwaitThenableTargets {
mut:
	awaits      []C.TSNode // await_expression
	aggregators []C.TSNode // calls to Promise.all and the like
	loops       []C.TSNode // for await (… of …)
	resources   []C.TSNode // the initializers of `await using` declarations
	// the declaration of each of `resources`, and how many declarators it has
	declarations []C.TSNode
	declarators  []int
}

fn (mut c Checker) lint_await_thenable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut targets := AwaitThenableTargets{}
	mut wanted := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'await_expression') {
		// In ESTree parentheses are not nodes: the argument is what is inside them.
		arg := unwrap_parens(first_named_child(node) or { continue })
		targets.awaits << node
		wanted << node
		wanted << arg
	}
	for call in c.nodes_of_kind(root, c'call_expression') {
		callee := c.aggregator_callee(call) or { continue }
		object := node_field(callee, 'object') or { continue }
		arg := first_argument(call) or { continue }
		targets.aggregators << call
		wanted << object
		wanted << aggregator_inputs(arg)
	}
	for loop in c.nodes_of_kind(root, c'for_in_statement') {
		if !is_for_await_of(loop) {
			continue
		}
		right := node_field(loop, 'right') or { continue }
		targets.loops << loop
		wanted << right
	}
	// VariableDeclaration[kind="await using"]: each declarator with an initializer.
	for declaration in c.nodes_of_kind(root, c'lexical_declaration') {
		if using_kind(declaration) != 'await using' {
			continue
		}
		declarators := named_children(declaration).filter(node_kind(it) == 'variable_declarator')
		for declarator in declarators {
			init := unwrap_parens(node_field(declarator, 'value') or { continue })
			targets.resources << init
			targets.declarations << declaration
			targets.declarators << declarators.len
			wanted << init
		}
	}
	c.resolve_node_types(wanted, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	findings := c.check_await_thenable(targets)!
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += targets.awaits.len + targets.aggregators.len + targets.loops.len +
		targets.resources.len
	return findings
}

fn (mut c Checker) check_await_thenable(targets AwaitThenableTargets) ![]Finding {
	mut findings := []Finding{}
	// AwaitExpression. Outside an async function, TypeScript reads `await` followed by a template with
	// substitutions as a tagged template; it only counts if tsgo sees an await too.
	for node in targets.awaits {
		if c.ts_kind(node) != syntax_kind_await_expression {
			continue
		}
		arg := unwrap_parens(first_named_child(node) or { continue })
		t := c.node_type(arg) or { continue }
		if c.needs_to_be_awaited(t, c.symbol_location(arg))! == .never {
			findings << Finding{
				stmt:        position_of(node)
				message_id:  'await'
				suggestions: c.at_remove_await(node, 'removeAwait')!
			}
		}
	}
	// CallExpression: isPromiseAggregatorMethod on the first argument.
	for call in targets.aggregators {
		callee := c.aggregator_callee(call) or { continue }
		object := node_field(callee, 'object') or { continue }
		receiver := c.node_type(object) or { continue }
		if !c.builtin_symbol_like(c.constrained(receiver)!, 'PromiseConstructor', 0)! {
			continue
		}
		arg := first_argument(call) or { continue }
		if node_kind(arg) == 'array' {
			for element in aggregator_inputs(arg) {
				t := c.node_type(element) or { continue }
				if c.always_non_awaitable(c.constrained(t)!, c.symbol_location(element))! {
					findings << Finding{
						stmt:       position_of(element)
						message_id: 'invalidPromiseAggregatorInput'
					}
				}
			}
			continue
		}
		t := c.node_type(arg) or { continue }
		if c.invalid_aggregator_input(c.constrained(t)!, c.symbol_location(arg))! {
			findings << Finding{
				stmt:       position_of(arg)
				message_id: 'invalidPromiseAggregatorInput'
			}
		}
	}
	// ForOfStatement[await=true]
	for loop in targets.loops {
		right := node_field(loop, 'right') or { continue }
		t := c.node_type(right) or { continue }
		if t.flags & type_flag_any != 0 {
			continue
		}
		mut async_iterable := false
		for part in c.constituents(t)! {
			if c.has_well_known_property(part, 'asyncIterator')! {
				async_iterable = true
				break
			}
		}
		if !async_iterable {
			// Note that this suggestion breaks the code for sync iterables of promises, since the
			// loop variable is not awaited.
			findings << Finding{
				stmt:        c.es_for_head_position(loop)
				message_id:  'forAwaitOfNonAsyncIterable'
				suggestions: c.at_remove_await(loop, 'convertToOrdinaryFor')!
			}
		}
	}
	// `await using x = init`: init must have a `[Symbol.asyncDispose]` in some part of its type.
	for i, init in targets.resources {
		t := c.node_type(init) or { continue }
		if t.flags & type_flag_any != 0 {
			continue
		}
		mut async_disposable := false
		for part in c.constituents(t)! {
			if c.has_well_known_property(part, 'asyncDispose')! {
				async_disposable = true
				break
			}
		}
		if !async_disposable {
			// With several declarators the user figures out what to do: no suggestion.
			findings << Finding{
				stmt:        position_of(init)
				message_id:  'awaitUsingOfNonAsyncDisposable'
				suggestions: if targets.declarators[i] == 1 {
					c.at_remove_await(targets.declarations[i], 'removeAwait')!
				} else {
					[]Suggestion{}
				}
			}
		}
	}
	findings.sort(a.stmt.start_byte < b.stmt.start_byte)
	return findings
}

// at_remove_await is the suggestion that removes the first `await` token of a node (an await
// expression, a `for await` loop or an `await using` declaration): fixer.remove(awaitToken).
fn (c &Checker) at_remove_await(node C.TSNode, message_id string) ![]Suggestion {
	for child in children(node) {
		if node_kind(child) == 'await' {
			_, suggestion := c.suggestion(message_id, map[string]string{}, [fix_remove(child)])!
			return [suggestion]
		}
	}
	return []Suggestion{}
}

// aggregator_callee returns the `X.all` of `X.all(…)` (or `X['all']`, or parenthesized), like
// isPromiseAggregatorMethod before looking at the type of X.
fn (mut c Checker) aggregator_callee(call C.TSNode) ?C.TSNode {
	mut callee := node_field(call, 'function') or { return none }
	for node_kind(callee) == 'parenthesized_expression' {
		callee = first_named_child(callee) or { return none }
	}
	name := c.static_member_string(callee) or { return none }
	if name !in aggregator_methods {
		return none
	}
	return callee
}

// first_argument is the first argument of a call; tagged templates do not count.
fn first_argument(call C.TSNode) ?C.TSNode {
	args := node_field(call, 'arguments') or { return none }
	if node_kind(args) != 'arguments' {
		return none
	}
	// In ESTree parentheses are not nodes.
	return unwrap_parens(first_named_child(args)?)
}

// aggregator_inputs are the nodes whose type is checked: the elements of an array literal or the
// whole argument.
fn aggregator_inputs(arg C.TSNode) []C.TSNode {
	if node_kind(arg) == 'array' {
		return named_children(arg).map(unwrap_parens(it))
	}
	return [arg]
}

// is_for_await_of: `for await (… of …)`. The `await` is the one before the parenthesis, not that
// of a header that declares with `await using`.
fn is_for_await_of(loop C.TSNode) bool {
	op := node_field(loop, 'operator') or { return false }
	if node_kind(op) != 'of' {
		return false
	}
	for child in children(loop) {
		match node_kind(child) {
			'await' { return true }
			'(' { return false }
			else {}
		}
	}
	return false
}

// needs_to_be_awaited ports util.needsToBeAwaited(checker, node, type): `at` is the node.
fn (mut c Checker) needs_to_be_awaited(t TypeResponse, at SymbolLocation) !Awaitable {
	mut constraint := t
	if t.flags & type_flag_type_parameter != 0 {
		// An unconstrained generic is treated as unknown.
		constraint = c.base_constraint(t)!
		if constraint.is_null() {
			return .may
		}
	}
	if constraint.flags & (type_flag_any | type_flag_unknown) != 0 {
		return .may
	}
	if c.is_thenable(constraint, at)! {
		return .always
	}
	return .never
}

// is_thenable ports isThenableType(checker, node, type) from ts-api-utils: some part of the
// apparent type has a callable `then` whose first parameter is a function. `at` is the node: the
// types of `then` and of the parameter are asked at it (getTypeOfSymbolAtLocation), so the answer
// is kept by type only when it does not depend on the node (see symbol_type_at).
fn (mut c Checker) is_thenable(t TypeResponse, at SymbolLocation) !bool {
	located := at.always || at.identifier != ''
	if !located && t.id in c.thenable_cache {
		return c.thenable_cache[t.id]
	}
	mut result := false
	for part in c.constituents(c.apparent_of(t)!)! {
		then := c.property(part, 'then')!
		if then.is_null() {
			continue
		}
		for sub in c.constituents(c.symbol_type_at(then, at)!)! {
			for sig in c.signatures_of(sub, signature_kind_call)! {
				if sig.parameters.len != 0 && c.is_callback(sig, at)! {
					result = true
					break
				}
			}
			if result {
				break
			}
		}
		if result {
			break
		}
	}
	if !located {
		c.thenable_cache[t.id] = result
	}
	return result
}

// is_callback ports isCallback for the first parameter of the signature. If it is a rest
// (`...args`), the type of its elements counts.
fn (mut c Checker) is_callback(sig SignatureResponse, at SymbolLocation) !bool {
	params := c.signature_parameters(sig)!
	if params.len == 0 {
		return false
	}
	mut t := c.apparent_of(c.parameter_type_at(params[0], at)!)!
	if sig.flags & signature_flag_has_rest_parameter != 0 && params.len == 1 {
		t = c.number_index_type(t)!
		if t.is_null() {
			return false
		}
	}
	for sub in c.constituents(t)! {
		if c.signatures_of(sub, signature_kind_call)!.len != 0 {
			return true
		}
	}
	return false
}

fn (mut c Checker) always_non_awaitable(t TypeResponse, at SymbolLocation) !bool {
	for part in c.constituents(t)! {
		if c.needs_to_be_awaited(part, at)! != .never {
			return false
		}
	}
	return true
}

fn (mut c Checker) contains_non_awaitable(t TypeResponse, at SymbolLocation) !bool {
	for part in c.constituents(t)! {
		if c.needs_to_be_awaited(part, at)! == .never {
			return true
		}
	}
	return false
}

// invalid_aggregator_input ports isInvalidPromiseAggregatorInput(checker, node, type).
fn (mut c Checker) invalid_aggregator_input(t TypeResponse, at SymbolLocation) !bool {
	parts := c.constituents(t)!
	// What is not iterable is already a type error.
	for part in parts {
		if !c.has_well_known_property(part, 'iterator')! {
			return false
		}
	}
	for part in parts {
		for value in c.array_like_values(part)! {
			if c.contains_non_awaitable(value, at)! {
				return true
			}
		}
	}
	return false
}

// array_like_values ports getValueTypesOfArrayLike: the element types of a tuple, an array (or
// similar) or an `Iterable<T>`; empty if it is none of them.
fn (mut c Checker) array_like_values(t TypeResponse) ![]TypeResponse {
	if c.is_tuple(t)! {
		return c.client.type_arguments(c.snapshot, c.project, t.id)!
	}
	if c.client.is_array_like_type(c.snapshot, c.project, t.id)! {
		index := c.number_index_type(t)!
		if index.is_null() {
			return error('tsgo: an array-like type without a number index (type ${t.id})')
		}
		return [index]
	}
	if t.flags & type_flag_object != 0 && t.object_flags & object_flag_reference != 0 {
		args := c.client.type_arguments(c.snapshot, c.project, t.id)!
		return if args.len > 0 { args[..1] } else { args }
	}
	return []TypeResponse{}
}
