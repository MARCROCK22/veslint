module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { first_named_child, has_child_kind, named_children, node_end, node_field, node_kind, node_start, nodes_of_kind, position_of }

// Port of the `no-floating-promises` rule of typescript-eslint 8.62.0, with all its options and its
// `floatingFixVoid` and `floatingFixAwait` suggestions.
// Limits of the port: internals.md, "Rules" section.

// typescript-eslint's messages: the `*Void` ones are for `ignoreVoid: true`, and the `floatingFix*`
// ones label the suggestions.
const nfp_messages = {
	'floating':                            'Promises must be awaited, end with a call to .catch, or end with a call to .then with a rejection handler.'
	'floatingFixAwait':                    'Add await operator.'
	'floatingFixVoid':                     'Add void operator to ignore.'
	'floatingPromiseArray':                "An array of Promises may be unintentional. Consider handling the promises' fulfillment or rejection with Promise.all or similar."
	'floatingPromiseArrayVoid':            "An array of Promises may be unintentional. Consider handling the promises' fulfillment or rejection with Promise.all or similar, or explicitly marking the expression as ignored with the `void` operator."
	'floatingUselessRejectionHandler':     'Promises must be awaited, end with a call to .catch, or end with a call to .then with a rejection handler. A rejection handler that is not a function will be ignored.'
	'floatingUselessRejectionHandlerVoid': 'Promises must be awaited, end with a call to .catch, end with a call to .then with a rejection handler or be explicitly marked as ignored with the `void` operator. A rejection handler that is not a function will be ignored.'
	'floatingVoid':                        'Promises must be awaited, end with a call to .catch, end with a call to .then with a rejection handler or be explicitly marked as ignored with the `void` operator.'
}

struct Unhandled {
	unhandled            bool
	non_function_handler bool
	promise_array        bool
}

// HandlingCall is a `.catch(…)` or `.then(…)` recognized like parseCatchCall/parseThenCall.
struct HandlingCall {
	on_rejected ?C.TSNode
}

// NfpOptions are the options the rule applies.
struct NfpOptions {
	safe_calls      []TypeSpecifier // allowForKnownSafeCalls
	safe_promises   []TypeSpecifier // allowForKnownSafePromises
	check_thenables bool
	ignore_iife     bool
	ignore_void     bool
}

fn nfp_options(options []json2.Any) !NfpOptions {
	o := option_object(no_floating_promises, options, [
		'allowForKnownSafeCalls',
		'allowForKnownSafePromises',
		'checkThenables',
		'ignoreIIFE',
		'ignoreVoid',
	])!
	return NfpOptions{
		safe_calls:      o.specifiers('allowForKnownSafeCalls')!
		safe_promises:   o.specifiers('allowForKnownSafePromises')!
		check_thenables: o.bool_value('checkThenables')!
		ignore_iife:     o.bool_value('ignoreIIFE')!
		ignore_void:     o.bool_value('ignoreVoid')!
	}
}

// nfp_is_async_iife ports isAsyncIife: the statement is a call (not an optional chain, which is a
// ChainExpression) of an arrow function or a function expression, async or not.
fn nfp_is_async_iife(expr C.TSNode) bool {
	node := unwrap_parens(expr)
	if is_optional_chain(node) {
		return false
	}
	callee := nfp_statement_callee(node) or { return false }
	return node_kind(callee) in ['arrow_function', 'function_expression', 'generator_function']
}

// nfp_void_argument is the argument of a `void` expression.
fn nfp_void_argument(node C.TSNode) ?C.TSNode {
	if node_kind(node) != 'unary_expression' || operator_of(node) != 'void' {
		return none
	}
	return node_field(node, 'argument')
}

// nfp_statement_callee is the callee of the expression of a statement when it is a call
// (CallExpression in ESTree: not a tagged template).
fn nfp_statement_callee(expr C.TSNode) ?C.TSNode {
	node := unwrap_parens(expr)
	if node_kind(node) != 'call_expression' {
		return none
	}
	arguments := node_field(node, 'arguments')?
	if node_kind(arguments) != 'arguments' {
		return none
	}
	return unwrap_parens(node_field(node, 'function')?)
}

// nfp_known_safe_call ports isKnownSafePromiseCall: the statement is a call whose callee is in
// allowForKnownSafeCalls, by its name (an identifier) or by its type.
fn (mut c Checker) nfp_known_safe_call(expr C.TSNode, o NfpOptions) !bool {
	callee := nfp_statement_callee(expr) or { return false }
	t := c.node_type(callee) or { TypeResponse{} }
	name := if node_kind(callee) in ['identifier', 'undefined'] { c.text(callee) } else { '' }
	if c.value_matches_some_specifier(name, o.safe_calls, t)! {
		return true
	}
	return !t.is_null() && c.type_matches_some_specifier(t, o.safe_calls)!
}

// nfp_promise_like ports the isPromiseLike(node, type) of the rule: a type in
// allowForKnownSafePromises is not one; a builtin Promise is; and with checkThenables, so is a
// thenable that can be rejected. `at` is the node.
fn (mut c Checker) nfp_promise_like(t TypeResponse, at SymbolLocation, o NfpOptions) !bool {
	if o.safe_promises.len > 0 && c.type_matches_some_specifier(t, o.safe_promises)! {
		return false
	}
	if c.promise_like_type(t)! {
		return true
	}
	if !o.check_thenables {
		return false
	}
	// Some part of the apparent type has a `then` with a call signature of two or more parameters
	// whose first two are functions.
	for part in c.constituents(c.apparent_of(t)!)! {
		then := c.property(part, 'then')!
		if then.is_null() {
			continue
		}
		for sub in c.constituents(c.symbol_type_at(then, at)!)! {
			for sig in c.signatures_of(sub, signature_kind_call)! {
				params := c.signature_parameters(sig)!
				if params.len >= 2 && c.is_function_param(params[0], at)!
					&& c.is_function_param(params[1], at)! {
					return true
				}
			}
		}
	}
	return false
}

// lint_no_floating_promises evaluates each expression statement. Phase 1: the type of every node
// isUnhandledPromise may look at, in a single request. Phase 2: the rule.
fn (mut c Checker) lint_no_floating_promises(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nfp_options(c.rule_options(no_floating_promises))!
	statements := c.nodes_of_kind(root, c'expression_statement')
	mut wanted := []C.TSNode{}
	for stmt in statements {
		if expr := first_named_child(stmt) {
			c.unhandled_nodes(expr, 0, o.ignore_void, mut wanted)
			if o.safe_calls.len > 0 {
				if callee := nfp_statement_callee(expr) {
					wanted << callee
				}
			}
		}
	}
	c.resolve_node_types(wanted, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for stmt in statements {
		expr := first_named_child(stmt) or { continue }
		if o.ignore_iife && nfp_is_async_iife(expr) {
			continue
		}
		if o.safe_calls.len > 0 && c.nfp_known_safe_call(expr, o)! {
			continue
		}
		result := c.is_unhandled(expr, false, 0, o)!
		if !result.unhandled {
			continue
		}
		message_id := if result.promise_array {
			'floatingPromiseArray'
		} else if result.non_function_handler {
			'floatingUselessRejectionHandler'
		} else {
			'floating'
		} + if o.ignore_void { 'Void' } else { '' }
		mut suggestions := []Suggestion{}
		if !result.promise_array {
			if o.ignore_void {
				void_fixes := c.nfp_prefix_operator(stmt, expr, 'void')
				_, fix_void := c.suggestion('floatingFixVoid', map[string]string{}, void_fixes)!
				suggestions << fix_void
			}
			await_fixes := c.nfp_add_await(stmt, expr)
			_, fix_await := c.suggestion('floatingFixAwait', map[string]string{}, await_fixes)!
			suggestions << fix_await
		}
		findings << Finding{
			stmt:        position_of(stmt)
			message_id:  message_id
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += statements.len
	return findings
}

// nfp_prefix_operator ports the fixer of `floatingFixVoid` (and the general case of addAwait): the
// operator goes before the statement, whose expression `expr` is put in parentheses unless it is
// parenthesized already or its precedence is higher than a unary operator's.
fn (mut c Checker) nfp_prefix_operator(stmt C.TSNode, expr C.TSNode, operator string) []Fix {
	expression := unwrap_parens(expr)
	// Outside an async function TypeScript reads `await (p)`, `await [p]` and `` await `p` `` as a
	// call, an element access and a tagged template of an `await` identifier (see await_reading),
	// all above a unary operator.
	high := if node_kind(expression) == 'await_expression' && c.await_reading(expression) != .await_expr {
		true
	} else {
		estree_operator_precedence(expression) > precedence_unary
	}
	if c.is_parenthesized(es_inner(expr)) || high {
		return [fix_insert_before(stmt, '${operator} ')]
	}
	return [fix_insert_before(stmt, '${operator} ('), fix_insert_at(node_end(expression), ')')]
}

// nfp_add_await ports addAwait: the `void` of a `void` expression becomes `await`; any other
// expression gets `await` before it.
fn (mut c Checker) nfp_add_await(stmt C.TSNode, expr C.TSNode) []Fix {
	expression := unwrap_parens(expr)
	if node_kind(expression) == 'unary_expression' && operator_of(expression) == 'void' {
		start := node_start(expression)
		return [fix_replace_range(start, start + 'void'.len, 'await')]
	}
	return c.nfp_prefix_operator(stmt, expr, 'await')
}

// unhandled_nodes records the nodes whose type is_unhandled may look at: the same ones it walks.
fn (mut c Checker) unhandled_nodes(n C.TSNode, depth int, ignore_void bool, mut out []C.TSNode) {
	if depth > max_expression_depth {
		return
	}
	node := unwrap_parens(n)
	match node_kind(node) {
		'assignment_expression', 'augmented_assignment_expression' {
			return
		}
		'sequence_expression' {
			for child in named_children(node) {
				c.unhandled_nodes(child, depth + 1, ignore_void, mut out)
			}
			return
		}
		else {}
	}
	if !ignore_void {
		if argument := nfp_void_argument(node) {
			c.unhandled_nodes(argument, depth + 1, ignore_void, mut out)
			return
		}
	}
	out << node
	match node_kind(node) {
		'call_expression' {
			if handling := c.promise_handling_call(node) {
				if on_rejected := handling.on_rejected {
					out << unwrap_parens(on_rejected)
				}
			} else if object := c.finally_object(node) {
				c.unhandled_nodes(object, depth + 1, ignore_void, mut out)
			}
		}
		'ternary_expression' {
			for name in ['alternative', 'consequence'] {
				if branch := node_field(node, name) {
					c.unhandled_nodes(branch, depth + 1, ignore_void, mut out)
				}
			}
		}
		'binary_expression' {
			if operator_of(node) in ['&&', '||', '??'] {
				for name in ['left', 'right'] {
					if side := node_field(node, name) {
						c.unhandled_nodes(side, depth + 1, ignore_void, mut out)
					}
				}
			}
		}
		else {}
	}
}

// is_unhandled ports isUnhandledPromise, with the checks in the same order. A node without a type
// (no tsgo counterpart) is not reported. `chain_root` says the node starts an expression: if it is
// an optional chain, in ESTree it is a ChainExpression. Only at the whole statement does
// skipChainExpression remove it.
fn (mut c Checker) is_unhandled(n C.TSNode, chain_root bool, depth int, o NfpOptions) !Unhandled {
	if depth > max_expression_depth {
		c.too_deep++
		return Unhandled{}
	}
	node := unwrap_parens(n)
	kind := node_kind(node)
	if kind in ['assignment_expression', 'augmented_assignment_expression'] {
		return Unhandled{}
	}
	if kind == 'sequence_expression' {
		// Any element of a comma expression may leave a floating promise.
		for child in named_children(node) {
			result := c.is_unhandled(child, true, depth + 1, o)!
			if result.unhandled {
				return result
			}
		}
		return Unhandled{}
	}
	if !o.ignore_void {
		// A `void` expression is always undefined: what counts is what is inside it.
		if argument := nfp_void_argument(node) {
			return c.is_unhandled(argument, true, depth + 1, o)!
		}
	}
	t := c.node_type(node) or { return Unhandled{} }
	at := c.symbol_location(node)
	if c.is_promise_array(t, at, o)! {
		return Unhandled{
			unhandled:     true
			promise_array: true
		}
	}
	// `await` handles promises, but not those of an array. Outside an async function, TypeScript may
	// read `await (p)` as a call to an `await` identifier (see await_reading).
	if kind == 'await_expression' && c.await_reading(node) == .await_expr {
		return Unhandled{}
	}
	if !c.nfp_promise_like(t, at, o)! {
		return Unhandled{}
	}
	// A ChainExpression is not a call: it is not checked for being a `.catch` or a `.then`.
	if chain_root && is_optional_chain(node) {
		return Unhandled{
			unhandled: true
		}
	}
	if kind == 'call_expression' {
		// `.catch()` or `.then()` with a rejection handler handle the promise.
		if handling := c.promise_handling_call(node) {
			if on_rejected := handling.on_rejected {
				if c.is_valid_rejection_handler(on_rejected)! {
					return Unhandled{}
				}
				return Unhandled{
					unhandled:            true
					non_function_handler: true
				}
			}
			return Unhandled{
				unhandled: true
			}
		}
		if object := c.finally_object(node) {
			// In `x.finally(…)`, x stays in the same chain unless it is parenthesized.
			return c.is_unhandled(object, node_kind(object) == 'parenthesized_expression',
				depth + 1, o)!
		}
		return Unhandled{
			unhandled: true
		}
	}
	if kind == 'ternary_expression' {
		if alternative := node_field(node, 'alternative') {
			result := c.is_unhandled(alternative, true, depth + 1, o)!
			if result.unhandled {
				return result
			}
		}
		if consequence := node_field(node, 'consequence') {
			return c.is_unhandled(consequence, true, depth + 1, o)!
		}
		return Unhandled{}
	}
	if kind == 'binary_expression' && operator_of(node) in ['&&', '||', '??'] {
		if left := node_field(node, 'left') {
			result := c.is_unhandled(left, true, depth + 1, o)!
			if result.unhandled {
				return result
			}
		}
		if right := node_field(node, 'right') {
			return c.is_unhandled(right, true, depth + 1, o)!
		}
		return Unhandled{}
	}
	return Unhandled{
		unhandled: true
	}
}

// is_optional_chain: the node is a call or a member access of a chain with `?.`. Parentheses and
// operators like `!` break the chain.
fn is_optional_chain(n C.TSNode) bool {
	mut node := n
	for {
		field := match node_kind(node) {
			'call_expression' { 'function' }
			'member_expression', 'subscript_expression' { 'object' }
			else { return false }
		}
		// `a?.b` has an optional_chain node; an optional call `f?.()` has the `?.` token itself.
		if has_child_kind(node, 'optional_chain') || has_child_kind(node, '?.') {
			return true
		}
		node = node_field(node, field) or { return false }
	}
	return false
}

// member_call_name is the static name of the method in `x.m(…)`, like getStaticMemberAccessValue
// (in ESTree the parentheses of the callee do not count, but `!`, `as` or `satisfies` do, and an
// optional chain in parentheses is a ChainExpression, not a member access: `(x?.m)(…)`).
fn (mut c Checker) member_call_name(call C.TSNode) ?string {
	callee := unwrap_parens(node_field(call, 'function')?)
	if node_kind(callee) !in ['member_expression', 'subscript_expression']
		|| estree_type(callee) != 'MemberExpression' {
		return none
	}
	return c.static_member_string(callee)
}

// promise_handling_call ports parseCatchCall and parseThenCall: the rejection handler is the first
// argument of `.catch` and the second of `.then`; with a spread it is unknown which one it is.
fn (mut c Checker) promise_handling_call(call C.TSNode) ?HandlingCall {
	method := c.member_call_name(call)?
	args := call_args(call) or { []C.TSNode{} }
	if method == 'catch' {
		if args.len >= 1 && node_kind(args[0]) != 'spread_element' {
			return HandlingCall{
				on_rejected: args[0]
			}
		}
		return HandlingCall{}
	}
	if method == 'then' {
		if args.len >= 2 && node_kind(args[0]) != 'spread_element'
			&& node_kind(args[1]) != 'spread_element' {
			return HandlingCall{
				on_rejected: args[1]
			}
		}
		return HandlingCall{}
	}
	return none
}

// finally_object ports parseFinallyCall: in `x.finally(…)` what happens to x counts.
fn (mut c Checker) finally_object(call C.TSNode) ?C.TSNode {
	if c.member_call_name(call)? != 'finally' {
		return none
	}
	callee := unwrap_parens(node_field(call, 'function')?)
	return node_field(callee, 'object')
}

// is_valid_rejection_handler ports isValidRejectionHandler: the type of the handler has call
// signatures. Without a type it cannot be said not to be a function, so it is taken as valid.
fn (mut c Checker) is_valid_rejection_handler(n C.TSNode) !bool {
	t := c.node_type(unwrap_parens(n)) or { return true }
	return c.signatures_of(t, signature_kind_call)!.len > 0
}

// is_promise_array ports isPromiseArray(node): some part of the type is (in its apparent type) an
// array of promises or a tuple with some promise. `at` is the node; the answer is kept by type
// when it does not depend on the node (only with checkThenables may it: see is_thenable).
fn (mut c Checker) is_promise_array(t TypeResponse, at SymbolLocation, o NfpOptions) !bool {
	located := o.check_thenables && (at.always || at.identifier != '')
	if !located && t.id in c.array_cache {
		return c.array_cache[t.id]
	}
	mut found := false
	for part in c.constituents(t)! {
		apparent := c.apparent_of(part)!
		if c.is_array(apparent)! {
			args := c.client.type_arguments(c.snapshot, c.project, apparent.id)!
			if args.len > 0 && c.nfp_promise_like(args[0], at, o)! {
				found = true
				break
			}
		}
		if c.is_tuple(apparent)! {
			for arg in c.client.type_arguments(c.snapshot, c.project, apparent.id)! {
				if c.nfp_promise_like(arg, at, o)! {
					found = true
					break
				}
			}
			if found {
				break
			}
		}
	}
	if !located {
		c.array_cache[t.id] = found
	}
	return found
}
