module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { named_children, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `prefer-promise-reject-errors` rule of typescript-eslint 8.62.0, with its options
// (`allow` with bare names and `from: "lib"` specifiers, like the other rules).

const ppre_messages = {
	'rejectAnError': 'Expected the Promise rejection reason to be an Error.'
}

struct PpreOptions {
	allow                  []TypeSpecifier
	allow_empty_reject     bool
	allow_throwing_any     bool
	allow_throwing_unknown bool
}

fn ppre_options(options []json2.Any) !PpreOptions {
	o := option_object(prefer_promise_reject_errors, options, ['allow', 'allowEmptyReject',
		'allowThrowingAny', 'allowThrowingUnknown'])!
	return PpreOptions{
		allow:                  o.specifiers('allow')!
		allow_empty_reject:     o.bool_value('allowEmptyReject')!
		allow_throwing_any:     o.bool_value('allowThrowingAny')!
		allow_throwing_unknown: o.bool_value('allowThrowingUnknown')!
	}
}

// PpreCall is a call checkRejectCall looks at: `X.reject(…)` (with the ESTree object of its callee)
// or a call of the `reject` parameter of a Promise executor.
struct PpreCall {
	node     C.TSNode
	argument ?C.TSNode // the first argument (a spread included), without parentheses
	object   ?C.TSNode // `X` of `X.reject(…)`, whose type must be like a Promise
}

fn (mut c Checker) lint_prefer_promise_reject_errors(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := ppre_options(c.rule_options(prefer_promise_reject_errors))!
	mut calls := []PpreCall{}
	// NewExpression of a Promise constructor: its callee, with the calls of its reject parameter.
	mut constructions := []C.TSNode{}
	mut reject_calls := [][]PpreCall{}
	for node in c.nodes_of_kinds(root, ['call_expression', 'new_expression'], []string{}) {
		if node_kind(node) == 'call_expression' {
			call := ppre_member_reject_call(node) or { continue }
			callee := unwrap_parens(node_field(node, 'function') or { continue })
			if c.is_static_member_access_of_value(callee, ['reject']) {
				calls << call
			}
			continue
		}
		callee := node_field(node, 'constructor') or { continue }
		constructions << unwrap_parens(callee)
		reject_calls << c.ppre_executor_reject_calls(root, node)
	}
	mut spans := []Span{}
	for call in calls {
		if object := call.object {
			spans << node_span(object)
		}
		if argument := call.argument {
			spans << node_span(argument)
		}
	}
	for i, callee in constructions {
		if reject_calls[i].len == 0 {
			continue
		}
		spans << node_span(callee)
		for call in reject_calls[i] {
			if argument := call.argument {
				spans << node_span(argument)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	if calls.len > 0 || reject_calls.any(it.len > 0) {
		error_symbols := ['Error']
		for call in calls {
			object := call.object or { continue }
			t := c.node_type(object) or { continue }
			// typeAtLocationIsLikePromise
			if !c.builtin_symbol_like(t, 'PromiseConstructor', 0)!
				&& !c.builtin_promise(t, 0)! {
				continue
			}
			if c.ppre_rejects_non_error(call, o, error_symbols)! {
				findings << Finding{
					stmt:       position_of(call.node)
					message_id: 'rejectAnError'
				}
			}
		}
		for i, callee in constructions {
			if reject_calls[i].len == 0 {
				continue
			}
			t := c.node_type(callee) or { continue }
			if !c.builtin_symbol_like(t, 'PromiseConstructor', 0)! {
				continue
			}
			for call in reject_calls[i] {
				if c.ppre_rejects_non_error(call, o, error_symbols)! {
					findings << Finding{
						stmt:       position_of(call.node)
						message_id: 'rejectAnError'
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len + constructions.len
	return findings
}

// ppre_member_reject_call: a call (not a tagged template) whose callee, without its
// ChainExpression, is a MemberExpression.
fn ppre_member_reject_call(node C.TSNode) ?PpreCall {
	args := node_field(node, 'arguments')?
	if node_kind(args) != 'arguments' {
		return none
	}
	callee := unwrap_parens(node_field(node, 'function')?)
	if node_kind(callee) !in ['member_expression', 'subscript_expression'] {
		return none
	}
	return PpreCall{
		node:     node
		argument: ppre_first_argument(args)
		object:   unwrap_parens(node_field(callee, 'object')?)
	}
}

// ppre_first_argument is `arguments.at(0)`: the first argument, without parentheses.
fn ppre_first_argument(args C.TSNode) ?C.TSNode {
	for child in named_children(args) {
		if node_kind(child) != 'comment' {
			return unwrap_parens(child)
		}
	}
	return none
}

// ppre_executor_reject_calls are the calls of the reject parameter of the executor of a `new`
// expression (its first argument, a function whose second parameter is an identifier): the
// references to the parameter that are the callee of a call.
fn (mut c Checker) ppre_executor_reject_calls(root C.TSNode, node C.TSNode) []PpreCall {
	mut out := []PpreCall{}
	args := node_field(node, 'arguments') or { return out }
	executor := ppre_first_argument(args) or { return out }
	if node_kind(executor) !in ['arrow_function', 'function_expression', 'generator_function'] {
		return out
	}
	parameters := node_field(executor, 'parameters') or { return out }
	params := named_children(parameters).filter(node_kind(it) != 'comment')
	if params.len < 2 || node_kind(params[1]) !in ['required_parameter', 'optional_parameter'] {
		return out
	}
	if _ := node_field(params[1], 'value') {
		return out
	}
	name := node_field(params[1], 'pattern') or { return out }
	if node_kind(name) != 'identifier' {
		return out
	}
	scopes := c.scope_tree(root)
	variable := scopes.declared_variable(name)
	if variable < 0 {
		return out
	}
	for r in scopes.variables[variable].references {
		identifier := scopes.references[r].identifier
		call := estree_parent(identifier) or { continue }
		if node_kind(call) != 'call_expression' {
			continue
		}
		reject_args := node_field(call, 'arguments') or { continue }
		callee := node_field(call, 'function') or { continue }
		if node_kind(reject_args) != 'arguments'
			|| node_key(unwrap_parens(callee)) != node_key(identifier) {
			continue
		}
		out << PpreCall{
			node:     call
			argument: ppre_first_argument(reject_args)
		}
	}
	return out
}

// ppre_rejects_non_error ports checkRejectCall: the first argument is not of an allowed type nor
// like an Error (or Readonly<Error>); without argument, unless allowEmptyReject.
fn (mut c Checker) ppre_rejects_non_error(call PpreCall, o PpreOptions, error_symbols []string) !bool {
	argument := call.argument or { return !o.allow_empty_reject }
	t := c.node_type(argument) or { return false }
	if c.type_matches_some_specifier(t, o.allow)! {
		return false
	}
	flags := c.type_flags(t)!
	if (o.allow_throwing_any && flags & type_flag_any != 0)
		|| (o.allow_throwing_unknown && flags & type_flag_unknown != 0) {
		return false
	}
	return !c.builtin_symbol_like_any(t, error_symbols, 0)!
		&& !c.ppre_readonly_error_like(t, error_symbols, 0)!
}

// ppre_readonly_error_like ports isReadonlyErrorLike: like isBuiltinSymbolLike, a type that is (or
// whose class or interface extends) `Readonly<T>` of the standard library, with T like an Error or
// itself a Readonly<Error>.
fn (mut c Checker) ppre_readonly_error_like(t TypeResponse, error_symbols []string, depth int) !bool {
	if depth > max_type_depth || t.is_null() {
		return false
	}
	if t.flags & type_flag_intersection != 0 {
		for member in c.members_of(t)! {
			if c.ppre_readonly_error_like(member, error_symbols, depth + 1)! {
				return true
			}
		}
		return false
	}
	if t.flags & type_flag_union != 0 {
		members := c.members_of(t)!
		for member in members {
			if !c.ppre_readonly_error_like(member, error_symbols, depth + 1)! {
				return false
			}
		}
		return true
	}
	if t.flags & type_flag_type_parameter != 0 {
		constraint := c.constraint_of(t)!
		return !constraint.is_null()
			&& c.ppre_readonly_error_like(constraint, error_symbols, depth + 1)!
	}
	// isBuiltinTypeAliasLike: false without an alias with type arguments.
	if t.alias_symbol == 0 || t.alias_type_arguments.len == 0 {
		return false
	}
	alias := c.alias_symbol_of(t)!
	if !alias.is_null() && alias.name == 'Readonly' && c.from_default_library(alias.declarations)! {
		type_arguments := c.client.alias_type_arguments_of_type(c.snapshot, c.project, t.id)!
		if type_arguments.len > 0 && (c.builtin_symbol_like_any(type_arguments[0], error_symbols, 0)!
			|| c.ppre_readonly_error_like(type_arguments[0], error_symbols, depth + 1)!) {
			return true
		}
	}
	// null: the base types of its class or interface.
	symbol := c.symbol_of(t)!
	if !symbol.is_null() && symbol.flags & (symbol_flag_class | symbol_flag_interface) != 0 {
		for base in c.bases_of(symbol.id)! {
			if c.ppre_readonly_error_like(base, error_symbols, depth + 1)! {
				return true
			}
		}
	}
	return false
}
