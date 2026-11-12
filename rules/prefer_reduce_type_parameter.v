module rules

import time
import tsgo { TypeResponse }
import treesitter { named_children, node_end, node_field, node_kind, node_start, nodes_of_kind, position_of }

// Port of the `prefer-reduce-type-parameter` rule of typescript-eslint 8.62.0, with its fix.

const prtp_messages = {
	'preferTypeParameter': 'Unnecessary assertion: Array#reduce accepts a type parameter for the default value.'
}

// PrtpCall is a `x.reduce(callback, init as T)` call whose types decide the report.
struct PrtpCall {
	call       C.TSNode
	callee     C.TSNode // the MemberExpression, without parentheses
	object     C.TSNode // the object of the callee
	assertion  C.TSNode // the second argument, a type assertion
	expression C.TSNode // its expression
	type_node  C.TSNode // its type
}

fn (mut c Checker) lint_prefer_reduce_type_parameter(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut calls := []PrtpCall{}
	mut spans := []Span{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		// 'CallExpression > MemberExpression.callee'
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		if !is_member(callee) {
			continue
		}
		args := call_arguments(call) or { continue }
		if !c.is_static_member_access_of_value(callee, ['reduce']) || args.len < 2 {
			continue
		}
		second := unwrap_parens(args[1])
		expression, type_node := prtp_type_assertion(second) or { continue }
		object := unwrap_parens(node_field(callee, 'object') or { continue })
		calls << PrtpCall{
			call:       call
			callee:     callee
			object:     object
			assertion:  second
			expression: expression
			type_node:  type_node
		}
		spans << node_span(expression)
		spans << c.type_node_span(type_node)
		spans << node_span(object)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for call in calls {
		initializer := c.node_type(call.expression) or { continue }
		asserted := c.node_type(call.type_node) or { continue }
		// Don't report when the fix would be a type error.
		if !c.assignable(initializer.id, asserted.id)! {
			continue
		}
		object := c.node_type(call.object) or { continue }
		if c.prtp_is_array_type(c.constrained(object)!)! {
			findings << c.with_fixes(Finding{
				stmt:       position_of(call.assertion)
				message_id: 'preferTypeParameter'
			}, c.prtp_fixes(call))!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}

// prtp_fixes ports the fixer: the assertion is reduced to its expression (the parentheses around
// the expression go too) and, if the call has no type arguments, the asserted type becomes the
// type argument, inserted after the callee.
fn (c &Checker) prtp_fixes(call PrtpCall) []Fix {
	mut fixes := [
		fix_remove_range(node_start(call.assertion), node_start(call.expression)),
		fix_remove_range(node_end(call.expression), node_end(call.assertion)),
	]
	if _ := node_field(call.call, 'type_arguments') {
		return fixes
	}
	fixes << fix_insert_after(call.callee, '<${c.text(call.type_node)}>')
	return fixes
}

// prtp_type_assertion ports isTypeAssertion (TSAsExpression or TSTypeAssertion): its expression
// and its type.
fn prtp_type_assertion(n C.TSNode) ?(C.TSNode, C.TSNode) {
	named := named_children(n)
	match node_kind(n) {
		'as_expression' {
			if named.len == 2 {
				return unwrap_parens(named[0]), unwrap_type_parens(named[1])
			}
		}
		'type_assertion' {
			if named.len == 2 && node_kind(named[0]) == 'type_arguments' {
				type_node := first_named(named[0])?
				return unwrap_parens(named[1]), unwrap_type_parens(type_node)
			}
		}
		else {}
	}
	return none
}

// prtp_is_array_type: every part of the union is an intersection of arrays and tuples.
fn (mut c Checker) prtp_is_array_type(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		for inner in c.intersection_parts(part)! {
			if !c.is_array(inner)! && !c.is_tuple(inner)! {
				return false
			}
		}
	}
	return true
}
