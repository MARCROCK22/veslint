module rules

import time
import tsgo { TypeResponse }
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-hanging-middleware` rule of @slipher/eslint-plugin 1.1.0 (it has no options): the
// callback of seyfert's `createMiddleware` can return without calling `next()` or `stop()`.
//
// The rule marks the code path segments that are current when ESLint enters a call of `next` or
// `stop`, and reports when a returned segment is reachable from the first one without going
// through a marked one. A segment is a stretch of code without forks, so that is the same as a
// path to a return (or the end) that does not reach the start of such a call. SyPaths follows the
// paths like ESLint 10.6.0's CodePathState does: forks at `&&`, `||`, `??`, `?:` and `?.`, loops
// (a test that is a literal that is true never exits), `switch`, labels, and `try`, whose `catch`
// is entered from the first node of the `try` block that may throw and from each `throw`, and
// whose `finally` is followed twice, for the normal path and for the one that leaves (the normal
// path and the returns and throws together).

const sy_nhm_messages = {
	'mayHang': 'This middleware can return without calling `next()` or `stop()`, leaving the command pipeline hanging.'
}

// SyPaths are the paths that get to a point of the code: `reach`, any; `live`, one that has not
// started a call of `next` or `stop`.
struct SyPaths {
	reach bool
	live  bool
}

fn (a SyPaths) join(b SyPaths) SyPaths {
	return SyPaths{
		reach: a.reach || b.reach
		live:  a.live || b.live
	}
}

const sy_nowhere = SyPaths{}

// SyTry is the context of a `try` statement (TryContext): where the analysis is (0 try, 1 catch,
// 2 finally) and the paths that throw or return from it.
struct SyTry {
	has_catch   bool
	has_finally bool
mut:
	position     int
	thrown       SyPaths
	thrown_any   bool
	returned     SyPaths
	returned_any bool
}

// SyTarget is what a `break` or a `continue` jumps to: a loop, a `switch` or a labeled statement.
struct SyTarget {
	label     string
	is_loop   bool
	breakable bool
mut:
	broken    SyPaths
	continued SyPaths
}

// SyFlow is the analysis of one middleware.
struct SyFlow {
	advancers []string
	param     string
mut:
	tries   []SyTry
	targets []SyTarget
	hang    bool
}

fn (mut c Checker) lint_seyfert_no_hanging_middleware(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// Function and arrow function expressions (generators too) that are the first argument of a
	// call of `createMiddleware` (an Identifier, or the name of a non-computed member).
	mut functions := []C.TSNode{}
	mut callees := []C.TSNode{}
	mut asked := []C.TSNode{}
	for function in c.nodes_of_kinds(root, ['arrow_function', 'function_expression', 'function',
		'generator_function'], []) {
		callee := c.sy_nhm_middleware_callee(function) or { continue }
		functions << function
		callees << callee
		asked << callee
		asked << sy_nhm_if_tests(function)
	}
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(callees)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, function in functions {
		if !c.sy_is_seyfert(c.sy_symbol_at(callees[i])!, 'createMiddleware')! {
			continue
		}
		advancers, param := c.sy_nhm_read_advancers(function)
		mut flow := SyFlow{
			advancers: advancers
			param:     param
		}
		if !c.sy_nhm_can_hang(mut flow, function) || c.sy_nhm_body_definitely_advances(flow, function)! {
			continue
		}
		findings << Finding{
			stmt:       position_of(function)
			message_id: 'mayHang'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += functions.len
	return findings
}

// sy_nhm_middleware_callee is the callee of the `createMiddleware` call the function is the first
// argument of (isSeyfertMiddlewareCallback, before the symbol is checked).
fn (c &Checker) sy_nhm_middleware_callee(function C.TSNode) ?C.TSNode {
	mut node := function
	mut parent := treesitter.node_parent(node)?
	for node_kind(parent) == 'parenthesized_expression' {
		node = parent
		parent = treesitter.node_parent(node)?
	}
	if node_kind(parent) != 'arguments' {
		return none
	}
	arguments := named_children(parent)
	if arguments.len == 0 || node_key(arguments[0]) != node_key(node) {
		return none
	}
	call := treesitter.node_parent(parent)?
	if node_kind(call) != 'call_expression' {
		return none
	}
	callee := unwrap_parens(node_field(call, 'function')?)
	name := match node_kind(callee) {
		'identifier' {
			callee
		}
		'member_expression' {
			property := node_field(callee, 'property')?
			if node_kind(property) != 'property_identifier' {
				return none
			}
			property
		}
		else {
			return none
		}
	}
	return if c.identifier_name(name) == 'createMiddleware' { callee } else { none }
}

// sy_nhm_if_tests are the tests of the `if` statements of a function, without parentheses: their
// types tell whether an `if` always takes a branch (definitelyAdvances).
fn sy_nhm_if_tests(function C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	for statement in treesitter.nodes_of_kind(function, c'if_statement') {
		condition := node_field(statement, 'condition') or { continue }
		out << unwrap_parens(condition)
	}
	return out
}

// sy_nhm_read_advancers ports readAdvancers: the names `next` and `stop` take in an object pattern
// that is the first parameter, or the name of the parameter.
fn (c &Checker) sy_nhm_read_advancers(function C.TSNode) ([]string, string) {
	mut advancers := []string{}
	param := sy_nhm_first_parameter(function) or { return advancers, '' }
	match node_kind(param) {
		'identifier' {
			return advancers, c.identifier_name(param)
		}
		'object_pattern' {
			for property in named_children(param) {
				match node_kind(property) {
					'shorthand_property_identifier_pattern' {
						name := c.identifier_name(property)
						if name in ['next', 'stop'] {
							advancers << name
						}
					}
					'object_assignment_pattern' {
						left := node_field(property, 'left') or { continue }
						if node_kind(left) == 'shorthand_property_identifier_pattern'
							&& c.identifier_name(left) in ['next', 'stop'] {
							advancers << c.identifier_name(left)
						}
					}
					'pair_pattern' {
						key := node_field(property, 'key') or { continue }
						if node_kind(key) != 'property_identifier'
							|| c.identifier_name(key) !in ['next', 'stop'] {
							continue
						}
						value := node_field(property, 'value') or { continue }
						if node_kind(value) == 'identifier' {
							advancers << c.identifier_name(value)
						} else if node_kind(value) == 'assignment_pattern' {
							left := node_field(value, 'left') or { continue }
							if node_kind(left) == 'identifier' {
								advancers << c.identifier_name(left)
							}
						}
					}
					else {}
				}
			}
		}
		else {}
	}
	return advancers, ''
}

// sy_nhm_first_parameter is the ESTree params[0] of a function, as an Identifier or an
// ObjectPattern (its type annotation aside); none for anything else.
fn sy_nhm_first_parameter(function C.TSNode) ?C.TSNode {
	if single := node_field(function, 'parameter') {
		return single
	}
	parameters := node_field(function, 'parameters')?
	list := named_children(parameters)
	if list.len == 0 {
		return none
	}
	first := list[0]
	if node_kind(first) !in ['required_parameter', 'optional_parameter'] {
		return none
	}
	if _ := node_field(first, 'value') {
		return none
	}
	pattern := node_field(first, 'pattern')?
	return if node_kind(pattern) in ['identifier', 'object_pattern'] { pattern } else { none }
}

// sy_nhm_is_advancer_call ports isAdvancerCall: a call of one of the advancer names, or of `next`
// or `stop` on the parameter.
fn (c &Checker) sy_nhm_is_advancer_call(flow SyFlow, call C.TSNode) bool {
	if node_kind(call) != 'call_expression' {
		return false
	}
	call_arguments(call) or { return false }
	callee := unwrap_parens(node_field(call, 'function') or { return false })
	if node_kind(callee) == 'identifier' {
		return c.identifier_name(callee) in flow.advancers
	}
	if node_kind(callee) != 'member_expression' || flow.param == '' {
		return false
	}
	object := unwrap_parens(node_field(callee, 'object') or { return false })
	property := node_field(callee, 'property') or { return false }
	return node_kind(object) == 'identifier' && c.identifier_name(object) == flow.param
		&& node_kind(property) == 'property_identifier'
		&& c.identifier_name(property) in ['next', 'stop']
}

// sy_nhm_can_hang ports canHang: a path that has not started a call of `next` or `stop` returns
// or reaches the end of the function.
fn (c &Checker) sy_nhm_can_hang(mut flow SyFlow, function C.TSNode) bool {
	body := node_field(function, 'body') or { return false }
	start := SyPaths{
		reach: true
		live:  true
	}
	end := if node_kind(body) == 'statement_block' {
		c.sy_flow_statements(mut flow, named_children(body), start)
	} else {
		c.sy_flow_expression(mut flow, body, start)
	}
	if end.live {
		flow.hang = true
	}
	return flow.hang
}

fn (c &Checker) sy_flow_statements(mut flow SyFlow, statements []C.TSNode, paths SyPaths) SyPaths {
	mut p := paths
	for statement in statements {
		p = c.sy_flow_statement(mut flow, statement, p, '')
	}
	return p
}

// sy_flow_return and sy_flow_throw send paths to the `finally` they leave through, to the `catch`
// of the `try` they are in, or out of the function: a returned path that is live hangs.
fn (mut flow SyFlow) sy_flow_return(p SyPaths) {
	if !p.reach {
		return
	}
	for i := flow.tries.len - 1; i >= 0; i-- {
		if flow.tries[i].has_finally && flow.tries[i].position != 2 {
			flow.tries[i].returned = flow.tries[i].returned.join(p)
			flow.tries[i].returned_any = true
			return
		}
	}
	if p.live {
		flow.hang = true
	}
}

fn (mut flow SyFlow) sy_flow_throw(p SyPaths) {
	if !p.reach {
		return
	}
	for i := flow.tries.len - 1; i >= 0; i-- {
		t := flow.tries[i]
		if t.position == 0 || (t.has_finally && t.position == 1) {
			flow.tries[i].thrown = t.thrown.join(p)
			flow.tries[i].thrown_any = true
			return
		}
	}
}

// sy_flow_throwable ports makeFirstThrowablePathInTryBlock: the first node of a `try` block that
// may throw, when the code gets there, also leads to its `catch`.
fn (mut flow SyFlow) sy_flow_throwable(p SyPaths) {
	if !p.reach {
		return
	}
	for i := flow.tries.len - 1; i >= 0; i-- {
		t := flow.tries[i]
		if t.position == 0 || (t.has_finally && t.position == 1) {
			if t.position == 0 && !t.thrown_any {
				flow.tries[i].thrown = p
				flow.tries[i].thrown_any = true
			}
			return
		}
	}
}

fn (c &Checker) sy_flow_statement(mut flow SyFlow, statement C.TSNode, paths SyPaths, label string) SyPaths {
	mut p := paths
	match node_kind(statement) {
		'statement_block' {
			if label != '' {
				return c.sy_flow_labeled(mut flow, statement, p, label)
			}
			return c.sy_flow_statements(mut flow, named_children(statement), p)
		}
		'expression_statement' {
			for child in named_children(statement) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			return p
		}
		'lexical_declaration', 'variable_declaration' {
			for declarator in named_children(statement) {
				if node_kind(declarator) != 'variable_declarator' {
					continue
				}
				if value := node_field(declarator, 'value') {
					p = c.sy_flow_expression(mut flow, value, p)
				}
			}
			return p
		}
		'if_statement' {
			condition := node_field(statement, 'condition') or { return p }
			test := c.sy_flow_expression(mut flow, condition, p)
			mut out := sy_nowhere
			if consequence := node_field(statement, 'consequence') {
				out = c.sy_flow_statement(mut flow, consequence, test, '')
			}
			if alternative := node_field(statement, 'alternative') {
				else_body := named_children(alternative)
				out = out.join(c.sy_flow_statements(mut flow, else_body, test))
			} else {
				out = out.join(test)
			}
			return out
		}
		'return_statement' {
			for child in named_children(statement) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			flow.sy_flow_return(p)
			return sy_nowhere
		}
		'throw_statement' {
			for child in named_children(statement) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			flow.sy_flow_throw(p)
			return sy_nowhere
		}
		'try_statement' {
			return c.sy_flow_try(mut flow, statement, p)
		}
		'while_statement' {
			condition := node_field(statement, 'condition') or { return p }
			test := c.sy_flow_expression(mut flow, condition, p)
			flow.targets << SyTarget{
				label:     label
				is_loop:   true
				breakable: true
			}
			if body := node_field(statement, 'body') {
				c.sy_flow_statement(mut flow, body, test, '')
			}
			target := flow.targets.pop()
			exits := if c.code_path_true_literal(unwrap_parens(condition)) {
				sy_nowhere
			} else {
				test
			}
			return exits.join(target.broken)
		}
		'do_statement' {
			flow.targets << SyTarget{
				label:     label
				is_loop:   true
				breakable: true
			}
			mut end := p
			if body := node_field(statement, 'body') {
				end = c.sy_flow_statement(mut flow, body, p, '')
			}
			mut target := flow.targets.pop()
			end = end.join(target.continued)
			condition := node_field(statement, 'condition') or { return end.join(target.broken) }
			test := c.sy_flow_expression(mut flow, condition, end)
			exits := if c.code_path_true_literal(unwrap_parens(condition)) {
				sy_nowhere
			} else {
				test
			}
			return exits.join(target.broken)
		}
		'for_statement' {
			if initializer := node_field(statement, 'initializer') {
				if node_kind(initializer) in ['lexical_declaration', 'variable_declaration'] {
					p = c.sy_flow_statement(mut flow, initializer, p, '')
				} else if node_kind(initializer) != 'empty_statement' {
					p = c.sy_flow_expression(mut flow, initializer, p)
				}
			}
			mut test := p
			mut endless := true
			if condition := node_field(statement, 'condition') {
				if node_kind(condition) != 'empty_statement' {
					condition_value := if node_kind(condition) == 'expression_statement' {
						named_children(condition)[0] or { condition }
					} else {
						condition
					}
					test = c.sy_flow_expression(mut flow, condition_value, p)
					endless = c.code_path_true_literal(unwrap_parens(condition_value))
				}
			}
			flow.targets << SyTarget{
				label:     label
				is_loop:   true
				breakable: true
			}
			mut end := test
			if body := node_field(statement, 'body') {
				end = c.sy_flow_statement(mut flow, body, test, '')
			}
			target := flow.targets.pop()
			if increment := node_field(statement, 'increment') {
				c.sy_flow_expression(mut flow, increment, end.join(target.continued))
			}
			exits := if endless { sy_nowhere } else { test }
			return exits.join(target.broken)
		}
		'for_in_statement' {
			right := node_field(statement, 'right') or { return p }
			entry := c.sy_flow_expression(mut flow, right, p)
			flow.targets << SyTarget{
				label:     label
				is_loop:   true
				breakable: true
			}
			if body := node_field(statement, 'body') {
				c.sy_flow_statement(mut flow, body, entry, '')
			}
			target := flow.targets.pop()
			return entry.join(target.broken)
		}
		'switch_statement' {
			return c.sy_flow_switch(mut flow, statement, p, label)
		}
		'labeled_statement' {
			name := node_field(statement, 'label') or { return p }
			body := node_field(statement, 'body') or { return p }
			return c.sy_flow_statement(mut flow, body, p, c.text(name))
		}
		'break_statement' {
			name := if target_label := node_field(statement, 'label') {
				c.text(target_label)
			} else {
				''
			}
			for i := flow.targets.len - 1; i >= 0; i-- {
				t := flow.targets[i]
				if (name == '' && t.breakable) || (name != '' && t.label == name) {
					flow.targets[i].broken = t.broken.join(p)
					break
				}
			}
			return sy_nowhere
		}
		'continue_statement' {
			name := if target_label := node_field(statement, 'label') {
				c.text(target_label)
			} else {
				''
			}
			for i := flow.targets.len - 1; i >= 0; i-- {
				t := flow.targets[i]
				if t.is_loop && (name == '' || t.label == name) {
					flow.targets[i].continued = t.continued.join(p)
					break
				}
			}
			return sy_nowhere
		}
		'function_declaration', 'generator_function_declaration', 'class_declaration',
		'abstract_class_declaration', 'empty_statement', 'type_alias_declaration',
		'interface_declaration', 'enum_declaration' {
			return p
		}
		else {
			if label != '' {
				return c.sy_flow_labeled(mut flow, statement, p, label)
			}
			for child in named_children(statement) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			return p
		}
	}
}

// sy_flow_labeled follows a labeled statement that is not a loop: a `break` with its label ends
// it.
fn (c &Checker) sy_flow_labeled(mut flow SyFlow, statement C.TSNode, p SyPaths, label string) SyPaths {
	flow.targets << SyTarget{
		label: label
	}
	end := c.sy_flow_statement(mut flow, statement, p, '')
	target := flow.targets.pop()
	return end.join(target.broken)
}

fn (c &Checker) sy_flow_switch(mut flow SyFlow, statement C.TSNode, p SyPaths, label string) SyPaths {
	value := node_field(statement, 'value') or { return p }
	mut chain := c.sy_flow_expression(mut flow, value, p)
	flow.targets << SyTarget{
		label:     label
		breakable: true
	}
	mut fall := sy_nowhere
	mut has_default := false
	body := node_field(statement, 'body') or {
		flow.targets.pop()
		return chain
	}
	for case in named_children(body) {
		mut entry := chain
		if node_kind(case) == 'switch_default' {
			has_default = true
		} else if node_kind(case) == 'switch_case' {
			if test := node_field(case, 'value') {
				chain = c.sy_flow_expression(mut flow, test, chain)
				entry = chain
			}
		} else {
			continue
		}
		mut statements := []C.TSNode{}
		for child in named_children(case) {
			if node_kind(child) != 'comment' && !(node_kind(case) == 'switch_case'
				&& node_key(child) == node_key(node_field(case, 'value') or { child })) {
				statements << child
			}
		}
		fall = c.sy_flow_statements(mut flow, statements, entry.join(fall))
	}
	target := flow.targets.pop()
	mut out := fall.join(target.broken)
	if !has_default {
		out = out.join(chain)
	}
	return out
}

fn (c &Checker) sy_flow_try(mut flow SyFlow, statement C.TSNode, p SyPaths) SyPaths {
	mut has_catch := false
	mut has_finally := false
	mut catch_clause := statement
	mut finally_clause := statement
	if handler := node_field(statement, 'handler') {
		has_catch = true
		catch_clause = handler
	}
	if finalizer := node_field(statement, 'finalizer') {
		has_finally = true
		finally_clause = finalizer
	}
	flow.tries << SyTry{
		has_catch:   has_catch
		has_finally: has_finally
	}
	body := node_field(statement, 'body') or {
		flow.tries.pop()
		return p
	}
	mut normal := c.sy_flow_statement(mut flow, body, p, '')
	if has_catch {
		mut t := flow.tries[flow.tries.len - 1]
		entry := if t.thrown_any { t.thrown } else { sy_nowhere }
		flow.tries[flow.tries.len - 1] = SyTry{
			...t
			position:   1
			thrown:     sy_nowhere
			thrown_any: false
		}
		if catch_body := node_field(catch_clause, 'body') {
			normal = normal.join(c.sy_flow_statement(mut flow, catch_body, entry, ''))
		}
	}
	if has_finally {
		t := flow.tries[flow.tries.len - 1]
		flow.tries[flow.tries.len - 1] = SyTry{
			...t
			position: 2
		}
		finally_body := node_field(finally_clause, 'body') or {
			flow.tries.pop()
			return normal
		}
		leaving := t.returned_any || t.thrown_any
		mut leaving_out := sy_nowhere
		if leaving {
			leaving_out = c.sy_flow_statement(mut flow, finally_body, normal.join(t.returned).join(t.thrown),
				'')
		}
		normal = c.sy_flow_statement(mut flow, finally_body, normal, '')
		flow.tries.pop()
		if t.returned_any {
			flow.sy_flow_return(leaving_out)
		}
		if t.thrown_any {
			flow.sy_flow_throw(leaving_out)
		}
		return normal
	}
	flow.tries.pop()
	return normal
}

// sy_flow_expression follows an expression in the order ESLint goes through it: a call of `next`
// or `stop` ends the live paths where it starts; `&&`, `||`, `??`, `?:` and the part of an optional
// chain after its `?.` may not run; the bodies of functions and classes are other code paths. When
// a node that may throw ends (a call, a member access, a `new`, a `yield`, a reference), it is the
// first one of its `try` block when none came before.
fn (c &Checker) sy_flow_expression(mut flow SyFlow, node C.TSNode, paths SyPaths) SyPaths {
	mut p := paths
	kind := node_kind(node)
	match kind {
		'arrow_function', 'function_expression', 'function', 'generator_function', 'class' {
			return p
		}
		'parenthesized_expression' {
			for child in named_children(node) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			return p
		}
		'binary_expression' {
			left := node_field(node, 'left') or { return p }
			right := node_field(node, 'right') or { return p }
			p = c.sy_flow_expression(mut flow, left, p)
			if operator_of(node) in ['&&', '||', '??'] {
				return p.join(c.sy_flow_expression(mut flow, right, p))
			}
			return c.sy_flow_expression(mut flow, right, p)
		}
		'augmented_assignment_expression' {
			left := node_field(node, 'left') or { return p }
			right := node_field(node, 'right') or { return p }
			p = c.sy_flow_expression(mut flow, left, p)
			if operator_of(node) in ['&&=', '||=', '??='] {
				return p.join(c.sy_flow_expression(mut flow, right, p))
			}
			return c.sy_flow_expression(mut flow, right, p)
		}
		'ternary_expression' {
			condition := node_field(node, 'condition') or { return p }
			test := c.sy_flow_expression(mut flow, condition, p)
			mut out := sy_nowhere
			for field in ['consequence', 'alternative'] {
				branch := node_field(node, field) or { continue }
				out = out.join(c.sy_flow_expression(mut flow, branch, test))
			}
			return out
		}
		'call_expression', 'member_expression', 'subscript_expression', 'non_null_expression' {
			after, skipped := c.sy_flow_chain(mut flow, node, p)
			return after.join(skipped)
		}
		'identifier' {
			if code_path_is_reference(node) {
				flow.sy_flow_throwable(p)
			}
			return p
		}
		'new_expression', 'yield_expression' {
			for child in named_children(node) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			flow.sy_flow_throwable(p)
			return p
		}
		else {
			for child in named_children(node) {
				p = c.sy_flow_expression(mut flow, child, p)
			}
			return p
		}
	}
}

// sy_flow_chain follows a call, a member access, a subscript or a `!`, and the chain of them it
// ends (parentheses end a chain): the paths after it, and apart the ones that skip the rest of the
// chain at one of its `?.`, which ESLint joins at the end of the chain (a ChainExpression), so
// that whatever comes after a `?.` in the chain (the arguments of a call too) may not run.
fn (c &Checker) sy_flow_chain(mut flow SyFlow, node C.TSNode, paths SyPaths) (SyPaths, SyPaths) {
	mut p := paths
	mut skipped := sy_nowhere
	kind := node_kind(node)
	// The rule sees a call of `next` or `stop` when the call starts, before its callee.
	if kind == 'call_expression' && c.sy_nhm_is_advancer_call(flow, node) {
		p = SyPaths{
			reach: p.reach
			live:  false
		}
	}
	inner := chain_lhs(node) or { return p, skipped }
	if node_kind(inner) in ['call_expression', 'member_expression', 'subscript_expression',
		'non_null_expression'] {
		p, skipped = c.sy_flow_chain(mut flow, inner, p)
	} else {
		p = c.sy_flow_expression(mut flow, inner, p)
	}
	if is_optional_element(node) {
		skipped = skipped.join(p)
	}
	match kind {
		'call_expression' {
			if args := node_field(node, 'arguments') {
				for argument in named_children(args) {
					p = c.sy_flow_expression(mut flow, argument, p)
				}
			}
			if _ := call_arguments(node) {
				flow.sy_flow_throwable(p)
			}
		}
		'subscript_expression' {
			if index := node_field(node, 'index') {
				p = c.sy_flow_expression(mut flow, index, p)
			}
			flow.sy_flow_throwable(p)
		}
		'member_expression' {
			flow.sy_flow_throwable(p)
		}
		else {}
	}
	return p, skipped
}

// sy_nhm_body_definitely_advances ports bodyDefinitelyAdvances: syntactically, the body calls
// `next` or `stop`, returns such a call or throws before anything that could leave it.
fn (mut c Checker) sy_nhm_body_definitely_advances(flow SyFlow, function C.TSNode) !bool {
	body := node_field(function, 'body') or { return false }
	if node_kind(body) == 'statement_block' {
		return c.sy_nhm_definitely_advances(flow, body)!
	}
	return c.sy_nhm_is_advancer_call(flow, unwrap_parens(body))
}

fn (mut c Checker) sy_nhm_definitely_advances(flow SyFlow, node C.TSNode) !bool {
	match node_kind(node) {
		'statement_block' {
			for statement in named_children(node) {
				if c.sy_nhm_definitely_advances(flow, statement)! {
					return true
				}
				if node_kind(statement) !in ['expression_statement', 'lexical_declaration',
					'variable_declaration', 'empty_statement'] {
					return false
				}
			}
			return false
		}
		'expression_statement' {
			expression := first_named(node) or { return false }
			return c.sy_nhm_is_advancer_call(flow, unwrap_parens(expression))
		}
		'return_statement' {
			argument := first_named(node) or { return false }
			return c.sy_nhm_is_advancer_call(flow, unwrap_parens(argument))
		}
		'throw_statement' {
			return true
		}
		'if_statement' {
			condition := node_field(node, 'condition') or { return false }
			consequence := node_field(node, 'consequence') or { return false }
			alternative := sy_nhm_else_statement(node)
			truthy := c.sy_nhm_truthiness(c.node_type(unwrap_parens(condition)) or {
				TypeResponse{}
			})
			if truthy == 1 {
				return c.sy_nhm_definitely_advances(flow, consequence)!
			}
			if truthy == -1 {
				return if else_statement := alternative {
					c.sy_nhm_definitely_advances(flow, else_statement)!
				} else {
					false
				}
			}
			if !c.sy_nhm_definitely_advances(flow, consequence)! {
				return false
			}
			return if else_statement := alternative {
				c.sy_nhm_definitely_advances(flow, else_statement)!
			} else {
				false
			}
		}
		else {
			return false
		}
	}
}

// sy_nhm_else_statement is the `alternate` of an `if`: the statement of its `else`.
fn sy_nhm_else_statement(statement C.TSNode) ?C.TSNode {
	alternative := node_field(statement, 'alternative')?
	return first_named(alternative)
}

// sy_nhm_truthiness ports typeTruthiness: 1 when every part of the type (of a union) is truthy, -1
// when every one is falsy, 0 otherwise.
fn (mut c Checker) sy_nhm_truthiness(t TypeResponse) int {
	if t.is_null() {
		return 0
	}
	parts := if t.flags & type_flag_union != 0 { c.members_of(t) or { return 0 } } else { [t] }
	mut truthy := false
	mut falsy := false
	for part in parts {
		match c.sy_nhm_constituent_truthiness(part) {
			1 { truthy = true }
			-1 { falsy = true }
			else { return 0 }
		}
	}
	if truthy && !falsy {
		return 1
	}
	if falsy && !truthy {
		return -1
	}
	return 0
}

// sy_nhm_constituent_truthiness ports constituentTruthiness, with TypeScript 7's TypeFlags.
fn (mut c Checker) sy_nhm_constituent_truthiness(t TypeResponse) int {
	flags := t.flags
	if flags & type_flag_boolean_literal != 0 {
		return if (c.type_string(t) or { '' }) == 'false' { -1 } else { 1 }
	}
	if flags & type_flag_string_literal != 0 {
		return if t.value is string && t.value == '' { -1 } else { 1 }
	}
	if flags & type_flag_number_literal != 0 {
		return if t.value.f64() == 0 { -1 } else { 1 }
	}
	if flags & type_flag_bigint_literal != 0 {
		return if t.value.str() == '0' { -1 } else { 1 }
	}
	if flags & (type_flag_undefined | type_flag_null | type_flag_void) != 0 {
		return -1
	}
	// Object, NonPrimitive, ESSymbol (512) and UniqueESSymbol (16384).
	if flags & (type_flag_object | type_flag_non_primitive | u32(512) | u32(16384)) != 0 {
		return 1
	}
	return 0
}
