module rules

import json2
import time
import treesitter { first_named_child, named_children, node_field, node_kind, node_parent, node_start, nodes_of_kind, position_of }

// Port of the `only-throw-error` rule of typescript-eslint 8.62.0, with its options (`allow` with
// bare names and `from: "lib"` specifiers, like the other rules).
//
// Deviation: for a thrown identifier without a variable in the scopes of the file (a global that
// another file declares, or an undeclared name), typescript-eslint's isRethrownError throws
// ("Variable … should exist in scope manager") and lints nothing; veslint takes it as not rethrown
// and checks its type.

const ote_messages = {
	'object': 'Expected an error object to be thrown.'
	'undef':  'Do not throw undefined.'
}

struct OteOptions {
	allow                  []TypeSpecifier
	allow_rethrowing       bool
	allow_throwing_any     bool
	allow_throwing_unknown bool
}

fn ote_options(options []json2.Any) !OteOptions {
	o := option_object(only_throw_error, options, ['allow', 'allowRethrowing', 'allowThrowingAny',
		'allowThrowingUnknown'])!
	return OteOptions{
		allow:                  o.specifiers('allow')!
		allow_rethrowing:       o.bool_value('allowRethrowing')!
		allow_throwing_any:     o.bool_value('allowThrowingAny')!
		allow_throwing_unknown: o.bool_value('allowThrowingUnknown')!
	}
}

// OteRethrow tells how isRethrownError sees a thrown expression.
enum OteRethrow {
	no          // not a rethrown value
	yes         // the variable of a catch clause
	if_thenable // the first parameter of the arrow function that handles the rejection of `object`
}

// OteThrow is the argument of a `throw`, without parentheses.
struct OteThrow {
	argument C.TSNode
	rethrow  OteRethrow
	object   C.TSNode // rethrow == .if_thenable: the object of the `catch` or `then` call
}

fn (mut c Checker) lint_only_throw_error(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := ote_options(c.rule_options(only_throw_error))!
	mut throws := []OteThrow{}
	for node in c.nodes_of_kind(root, c'throw_statement') {
		argument := unwrap_parens(first_named_child(node) or { continue })
		mut rethrow := OteRethrow.no
		mut object := argument
		if o.allow_rethrowing {
			rethrow, object = c.ote_rethrown(root, argument)
		}
		throws << OteThrow{
			argument: argument
			rethrow:  rethrow
			object:   object
		}
	}
	mut spans := []Span{}
	for t in throws {
		if t.rethrow == .yes {
			continue
		}
		spans << node_span(t.argument)
		if t.rethrow == .if_thenable {
			spans << node_span(t.object)
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for t in throws {
		if t.rethrow == .yes {
			continue
		}
		if t.rethrow == .if_thenable {
			// Make sure the handler belongs to a promise.
			if object_type := c.node_type(t.object) {
				if c.is_thenable(object_type, c.symbol_location(t.object))! {
					continue
				}
			}
		}
		thrown := c.node_type(t.argument) or { continue }
		if c.type_matches_some_specifier(thrown, o.allow)! {
			continue
		}
		if thrown.flags & type_flag_undefined != 0 {
			findings << Finding{
				stmt:       position_of(t.argument)
				message_id: 'undef'
			}
			continue
		}
		flags := c.type_flags(thrown)!
		if (o.allow_throwing_any && flags & type_flag_any != 0)
			|| (o.allow_throwing_unknown && flags & type_flag_unknown != 0) {
			continue
		}
		if c.builtin_symbol_like(thrown, 'Error', 0)! {
			continue
		}
		findings << Finding{
			stmt:       position_of(t.argument)
			message_id: 'object'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += throws.len
	return findings
}

// ote_rethrown ports isRethrownError, but for the type check of its promise case (the object it
// returns): an identifier whose variable has a single variable definition, the first of its
// definitions being a catch clause, or the first parameter of the arrow function passed as the
// rejection handler of a `catch` or `then` call.
fn (mut c Checker) ote_rethrown(root C.TSNode, argument C.TSNode) (OteRethrow, C.TSNode) {
	if node_kind(argument) !in ['identifier', 'undefined'] {
		return OteRethrow.no, argument
	}
	scopes := c.scope_tree(root)
	variable := scopes.find_variable(scopes.get_scope(argument), c.identifier_name(argument),
		node_start(argument))
	// typescript-eslint throws without a variable (see the header).
	if variable < 0 {
		return OteRethrow.no, argument
	}
	defs := scopes.variables[variable].defs
	if defs.filter(it.kind.is_variable_definition()).len != 1 {
		return OteRethrow.no, argument
	}
	def := defs[0]
	// try { … } catch (x) { throw x; }
	if def.kind == .catch_clause {
		return OteRethrow.yes, argument
	}
	// promise.catch(x => { throw x; }), promise.then(onFulfilled, x => { throw x; })
	if def.kind != .parameter || node_kind(def.node) != 'arrow_function'
		|| !ote_is_first_parameter(def.node, def.name) {
		return OteRethrow.no, argument
	}
	// The ESTree parent of the function must be a CallExpression (tree-sitter puts the arguments
	// of a call in an `arguments` node).
	mut call := estree_parent(def.node) or { return OteRethrow.no, argument }
	if node_kind(call) == 'arguments' {
		call = node_parent(call) or { return OteRethrow.no, argument }
	}
	if node_kind(call) != 'call_expression' {
		return OteRethrow.no, argument
	}
	object := c.ote_rejection_handler_object(call, def.node) or { return OteRethrow.no, argument }
	return OteRethrow.if_thenable, object
}

// ote_is_first_parameter: `params[0] === def.name`: the first parameter of the arrow function is
// that identifier itself (not a default value, a pattern or a rest).
fn ote_is_first_parameter(function C.TSNode, name C.TSNode) bool {
	if single := node_field(function, 'parameter') {
		return node_key(single) == node_key(name)
	}
	parameters := node_field(function, 'parameters') or { return false }
	params := named_children(parameters)
	if params.len == 0 || node_kind(params[0]) !in ['required_parameter', 'optional_parameter'] {
		return false
	}
	if _ := node_field(params[0], 'value') {
		return false
	}
	pattern := node_field(params[0], 'pattern') or { return false }
	return node_key(pattern) == node_key(name)
}

// ote_rejection_handler_object ports parseCatchCall and parseThenCall for a call whose onRejected
// argument is `handler`: the object of its callee, `x` in `x.catch(handler)` or
// `x.then(…, handler)`.
fn (mut c Checker) ote_rejection_handler_object(call C.TSNode, handler C.TSNode) ?C.TSNode {
	args := call_arguments(call)?
	callee := unwrap_parens(node_field(call, 'function')?)
	// The callee must be a MemberExpression: a parenthesized optional chain is a ChainExpression.
	if !is_member(callee) || is_estree_chain_root(callee) {
		return none
	}
	method := c.static_member_name(callee)?
	if method != 'catch' && method != 'then' {
		return none
	}
	index := if method == 'then' { 1 } else { 0 }
	// No spread up to the handler, which must be that argument.
	if args.len < index + 1 || args[..index + 1].any(node_kind(it) == 'spread_element')
		|| node_key(unwrap_parens(args[index])) != node_key(handler) {
		return none
	}
	return unwrap_parens(node_field(callee, 'object')?)
}
