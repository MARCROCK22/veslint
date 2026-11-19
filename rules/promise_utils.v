module rules

import estree

// Ports of the helpers of eslint-plugin-promise 7.3.0 (rules/lib/*.js and rules/fix/*.js) on the
// ESTree, for the `promise/*` rules (prefix prm_).

// prm_promise_statics is lib/promise-statics.js.
const prm_promise_statics = ['all', 'allSettled', 'any', 'race', 'reject', 'resolve', 'withResolvers']

// prm_default_callbacks is the initial `callbacks` of lib/is-named-callback.js.
const prm_default_callbacks = ['done', 'cb', 'callback', 'next']

// prm_name is `node.name` when it is a string (an Identifier, a PrivateIdentifier, a
// JSXIdentifier); '' for undefined (no node, or a node without a string name), which no
// comparison of the rules matches.
fn prm_name(t &estree.EsTree, node int) string {
	if node < 0 {
		return ''
	}
	return t.string_of(node, .name) or { '' }
}

// prm_child is a property of a node that is a node, -1 when the node has none (or is -1).
fn prm_child(t &estree.EsTree, node int, key estree.Key) int {
	if node < 0 {
		return -1
	}
	return t.node(node, key) or { -1 }
}

// prm_callee_property_name is `node.callee.property.name` ('' when one of them is missing).
fn prm_callee_property_name(t &estree.EsTree, node int) string {
	return prm_name(t, prm_child(t, prm_child(t, node, .callee), .property))
}

// prm_is_member_call: `node` is a CallExpression whose callee is a MemberExpression.
fn prm_is_member_call(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .call_expression {
		return false
	}
	callee := prm_child(t, node, .callee)
	return callee >= 0 && t.typ(callee) == .member_expression
}

// prm_is_promise ports lib/is-promise.js.
fn prm_is_promise(t &estree.EsTree, expression int) bool {
	if !prm_is_member_call(t, expression) {
		return false
	}
	callee := prm_child(t, expression, .callee)
	name := prm_name(t, prm_child(t, callee, .property))
	if name in ['then', 'catch', 'finally'] {
		return true
	}
	object := prm_child(t, callee, .object)
	if prm_is_promise(t, object) {
		return true
	}
	return object >= 0 && t.typ(object) == .identifier && prm_name(t, object) == 'Promise'
		&& name in prm_promise_statics && name != 'withResolvers'
}

// prm_has_promise_callback ports lib/has-promise-callback.js.
fn prm_has_promise_callback(t &estree.EsTree, node int) bool {
	return prm_is_member_call(t, node) && prm_callee_property_name(t, node) in ['then', 'catch']
}

// prm_is_function_expression: a FunctionExpression or an ArrowFunctionExpression.
fn prm_is_function_expression(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.function_expression, .arrow_function_expression]
}

// prm_is_inside_promise ports lib/is-inside-promise.js: a function expression whose parent's
// `callee.property.name` is `then` or `catch`.
fn prm_is_inside_promise(t &estree.EsTree, node int) bool {
	if !prm_is_function_expression(t, node) {
		return false
	}
	return prm_callee_property_name(t, t.nodes[node].parent) in ['then', 'catch']
}

// prm_first_param_name is `node.params && node.params[0] && node.params[0].name`.
fn prm_first_param_name(t &estree.EsTree, node int) string {
	params := t.list(node, .params) or { return '' }
	if params.len == 0 {
		return ''
	}
	return prm_name(t, params[0])
}

// prm_is_inside_callback ports lib/is-inside-callback.js.
fn prm_is_inside_callback(t &estree.EsTree, node int, exempt_declarations bool) bool {
	is_function := t.typ(node) in [.function_expression, .arrow_function_expression]
		|| (!exempt_declarations && t.typ(node) == .function_declaration)
	if prm_is_inside_promise(t, node) {
		return false
	}
	return is_function && prm_first_param_name(t, node) in ['err', 'error']
}

// prm_is_member_call_with_object_name ports lib/is-member-call-with-object-name.js.
fn prm_is_member_call_with_object_name(t &estree.EsTree, object_name string, node int) bool {
	if !prm_is_member_call(t, node) {
		return false
	}
	object := prm_child(t, prm_child(t, node, .callee), .object)
	return (t.typ(object) == .identifier && prm_name(t, object) == object_name)
		|| prm_is_member_call_with_object_name(t, object_name, object)
}

// prm_is_promise_constructor ports isPromiseConstructor of lib/is-promise-constructor.js.
fn prm_is_promise_constructor(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .new_expression {
		return false
	}
	callee := prm_child(t, node, .callee)
	return callee >= 0 && t.typ(callee) == .identifier && prm_name(t, callee) == 'Promise'
}

// prm_is_promise_constructor_with_inline_executor ports isPromiseConstructorWithInlineExecutor.
fn prm_is_promise_constructor_with_inline_executor(t &estree.EsTree, node int) bool {
	if !prm_is_promise_constructor(t, node) {
		return false
	}
	args := t.list(node, .arguments) or { return false }
	return args.len == 1 && prm_is_function_expression(t, args[0])
}

// prm_is_named_callback ports lib/is-named-callback.js. Its list of names is the module's own
// state: the exceptions of a call take their names out of it for good, so that a name an
// exception took out is no callback in the files linted after it either. ESLint keeps that list
// once per process; veslint once per Checker (a project of a run, or of the server).
fn (mut c Checker) prm_is_named_callback(name string, exceptions []string) bool {
	if !c.prm_callbacks_set {
		c.prm_callbacks = prm_default_callbacks.clone()
		c.prm_callbacks_set = true
	}
	for exception in exceptions {
		c.prm_callbacks = c.prm_callbacks.filter(it != exception)
	}
	return name != '' && name in c.prm_callbacks
}

// prm_is_callback ports lib/is-callback.js.
fn (mut c Checker) prm_is_callback(t &estree.EsTree, node int, exceptions []string) bool {
	is_call_expression := t.typ(node) == .call_expression
	name_is_callback := c.prm_is_named_callback(prm_name(t, prm_child(t, node, .callee)),
		exceptions)
	return is_call_expression && name_is_callback
}

// prm_ancestors are the ancestors of a node, from the Program to its parent (getAncestors).
fn prm_ancestors(t &estree.EsTree, node int) []int {
	mut out := []int{}
	mut at := t.nodes[node].parent
	for at >= 0 {
		out << at
		at = t.nodes[at].parent
	}
	return out.reverse()
}

// prm_remove_argument ports fix/remove-argument.js: the argument of its call, with its
// parentheses and the comma that separates it from the argument after it (or, for the last one,
// from the argument before it).
fn (c &Checker) prm_remove_argument(t &estree.EsTree, tokens &SourceTokens, node int) Fix {
	call := t.nodes[node].parent
	args := t.list(call, .arguments) or { []int{} }
	index := args.index(node)
	parentheses := c.un_parentheses(t, tokens, node)
	first_start := if parentheses.len > 0 { parentheses[0].start } else { t.nodes[node].start }
	last_end := if parentheses.len > 0 { parentheses.last().end } else { t.nodes[node].end }
	mut start := first_start
	mut end := last_end
	if index != 0 {
		if before := tokens.before(first_start, false) {
			start = before.start
		}
	}
	if index < args.len - 1 {
		if after := tokens.after(last_end, false) {
			if c.token_is(after, ',') {
				if next := tokens.after(after.end, false) {
					end = next.start
				}
			}
		}
	}
	// With a single argument the token before it is the `(` of the call, never a comma: the
	// branch of the source for it changes nothing.
	return fix_replace_range(start, end, '')
}
