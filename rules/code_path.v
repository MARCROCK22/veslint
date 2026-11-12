module rules

import treesitter { children, named_children, node_field, node_kind, node_parent }

// Whether the end of a function body can be reached, as ESLint 10.6.0's code path analysis
// (linter/code-path-analysis) gives it to the rules that look at the segments at the end of a
// code path. It follows the statements like CodePathState does:
//
// - `return`, `throw`, `break` and `continue` end a path; `break` reaches the end of its target;
// - a loop whose test is a literal that is true (or a `for` without a test) only ends with a
//   `break`; no other condition is evaluated;
// - a `switch` without a `default` may match no case; a case falls through into the next one;
// - a `catch` block is entered from the end of the `try` block and from the first node of that
//   block that may throw (a call, a `new`, a member access, a `yield` or an identifier that is
//   not a declaration), or from a `throw`; in a `catch` block with a `finally`, the first node
//   that may throw makes a path to the `finally` block too, which goes on as a throw;
// - a `finally` block is also entered from the `return` and `throw` paths it has to let through,
//   and what follows the statement is reached only when the `try` or the `catch` block ends and
//   the `finally` block does too.

enum CodePathPosition {
	try
	catch
	finally
}

// CodePathTarget is a break context: a loop or a `switch` (breakable without a label) or a
// labeled statement.
struct CodePathTarget {
	label     string
	breakable bool
	is_loop   bool
mut:
	broken    bool
	continued bool
}

struct CodePathTry {
	has_finalizer bool
mut:
	position CodePathPosition
	thrown   bool
	returned bool
}

struct CodePathState {
mut:
	targets []CodePathTarget
	tries   []CodePathTry
}

const code_path_loop_kinds = ['while_statement', 'do_statement', 'for_statement', 'for_in_statement']

const code_path_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function']

// end_reachable: the end of the statements of a function body (or of a program) is reachable.
fn (c &Checker) end_reachable(statements []C.TSNode) bool {
	mut state := CodePathState{}
	return c.code_path_statements(statements, true, mut state)
}

fn (c &Checker) code_path_statements(statements []C.TSNode, reachable bool, mut state CodePathState) bool {
	mut current := reachable
	for statement in statements {
		current = c.code_path_statement(statement, current, '', mut state)
	}
	return current
}

// code_path_statement: the end of the statement is reachable, given whether its start is.
// `label` is that of the LabeledStatement whose body the statement is.
fn (c &Checker) code_path_statement(statement C.TSNode, reachable bool, label string, mut state CodePathState) bool {
	kind := node_kind(statement)
	match kind {
		'comment' {
			return reachable
		}
		'statement_block' {
			return c.code_path_statements(named_children(statement), reachable, mut state)
		}
		'return_statement' {
			c.code_path_throwable(statement, reachable, mut state)
			if reachable {
				// getReturnContext: the closest `try` with a `finally` it is not in.
				for i := state.tries.len - 1; i >= 0; i-- {
					if state.tries[i].has_finalizer && state.tries[i].position != .finally {
						state.tries[i].returned = true
						break
					}
				}
			}
			return false
		}
		'throw_statement' {
			c.code_path_throwable(statement, reachable, mut state)
			if reachable {
				if index := code_path_throw_context(state) {
					state.tries[index].thrown = true
				}
			}
			return false
		}
		'break_statement', 'continue_statement' {
			if reachable {
				target_label := if name := node_field(statement, 'label') {
					c.text(name)
				} else {
					''
				}
				for i := state.targets.len - 1; i >= 0; i-- {
					target := state.targets[i]
					if kind == 'break_statement' {
						if (target_label == '' && target.breakable)
							|| (target_label != '' && target.label == target_label) {
							state.targets[i].broken = true
							break
						}
					} else if target.is_loop && (target_label == '' || target.label == target_label) {
						state.targets[i].continued = true
						break
					}
				}
			}
			return false
		}
		'if_statement' {
			if condition := node_field(statement, 'condition') {
				c.code_path_throwable(condition, reachable, mut state)
			}
			mut consequent := reachable
			if consequence := node_field(statement, 'consequence') {
				consequent = c.code_path_statement(consequence, reachable, '', mut state)
			}
			mut alternate := reachable
			if alternative := node_field(statement, 'alternative') {
				alternate = c.code_path_statements(named_children(alternative), reachable, mut
					state)
			}
			return consequent || alternate
		}
		'labeled_statement' {
			name := if n := node_field(statement, 'label') { c.text(n) } else { '' }
			body := node_field(statement, 'body') or { return reachable }
			// The label of a loop or of a `switch` is that of its own context.
			if node_kind(body) in code_path_loop_kinds || node_kind(body) == 'switch_statement' {
				return c.code_path_statement(body, reachable, name, mut state)
			}
			state.targets << CodePathTarget{
				label: name
			}
			end := c.code_path_statement(body, reachable, '', mut state)
			target := state.targets.pop()
			return end || target.broken
		}
		'while_statement' {
			condition := node_field(statement, 'condition')
			if test := condition {
				c.code_path_throwable(test, reachable, mut state)
			}
			state.targets << CodePathTarget{
				label:     label
				breakable: true
				is_loop:   true
			}
			if body := node_field(statement, 'body') {
				c.code_path_statement(body, reachable, '', mut state)
			}
			target := state.targets.pop()
			return (reachable && !c.code_path_true_literal(condition)) || target.broken
		}
		'do_statement' {
			state.targets << CodePathTarget{
				label:     label
				breakable: true
				is_loop:   true
			}
			mut body_end := reachable
			if body := node_field(statement, 'body') {
				body_end = c.code_path_statement(body, reachable, '', mut state)
			}
			target := state.targets.pop()
			// The test is reached from the end of the body and from each `continue`.
			test_reachable := body_end || target.continued
			condition := node_field(statement, 'condition')
			if test := condition {
				c.code_path_throwable(test, test_reachable, mut state)
			}
			return (test_reachable && !c.code_path_true_literal(condition)) || target.broken
		}
		'for_statement' {
			if initializer := node_field(statement, 'initializer') {
				c.code_path_throwable(initializer, reachable, mut state)
			}
			// The test is an expression statement, or an empty one when there is none.
			mut test := ?C.TSNode(none)
			if condition := node_field(statement, 'condition') {
				if node_kind(condition) != 'empty_statement' {
					test = condition
					c.code_path_throwable(condition, reachable, mut state)
				}
			}
			state.targets << CodePathTarget{
				label:     label
				breakable: true
				is_loop:   true
			}
			mut body_end := reachable
			if body := node_field(statement, 'body') {
				body_end = c.code_path_statement(body, reachable, '', mut state)
			}
			target := state.targets.pop()
			// The update is reached from the end of the body and from each `continue`.
			if increment := node_field(statement, 'increment') {
				c.code_path_throwable(increment, body_end || target.continued, mut state)
			}
			has_test := test != none
			return (reachable && has_test && !c.code_path_true_literal(test)) || target.broken
		}
		'for_in_statement' {
			if right := node_field(statement, 'right') {
				c.code_path_throwable(right, reachable, mut state)
			}
			if left := node_field(statement, 'left') {
				c.code_path_throwable(left, reachable, mut state)
			}
			state.targets << CodePathTarget{
				label:     label
				breakable: true
				is_loop:   true
			}
			if body := node_field(statement, 'body') {
				c.code_path_statement(body, reachable, '', mut state)
			}
			state.targets.pop()
			// The loop may run no iteration at all.
			return reachable
		}
		'switch_statement' {
			if value := node_field(statement, 'value') {
				c.code_path_throwable(value, reachable, mut state)
			}
			state.targets << CodePathTarget{
				label:     label
				breakable: true
			}
			mut has_default := false
			mut last_end := reachable
			mut fallthrough := false
			mut cases := 0
			if body := node_field(statement, 'body') {
				for switch_case in named_children(body) {
					case_kind := node_kind(switch_case)
					if case_kind !in ['switch_case', 'switch_default'] {
						continue
					}
					cases++
					if case_kind == 'switch_default' {
						has_default = true
					} else if value := node_field(switch_case, 'value') {
						c.code_path_throwable(value, reachable, mut state)
					}
					// What follows the `:`. It is entered when the case matches and from the
					// end of the case before.
					mut after_colon := false
					mut consequent := []C.TSNode{}
					for child in children(switch_case) {
						if !after_colon {
							after_colon = node_kind(child) == ':'
						} else {
							consequent << child
						}
					}
					last_end = c.code_path_statements(consequent, reachable || fallthrough, mut
						state)
					fallthrough = last_end
				}
			}
			target := state.targets.pop()
			if cases == 0 {
				return reachable
			}
			// Without a `default`, no case may match.
			return target.broken || last_end || (!has_default && reachable)
		}
		'try_statement' {
			handler := node_field(statement, 'handler')
			finalizer := node_field(statement, 'finalizer')
			state.tries << CodePathTry{
				has_finalizer: finalizer != none
				position:      .try
			}
			index := state.tries.len - 1
			mut try_end := reachable
			if block := node_field(statement, 'body') {
				try_end = c.code_path_statement(block, reachable, '', mut state)
			}
			mut catch_end := false
			if catch_clause := handler {
				// The end of the `try` block may throw as well.
				catch_entry := try_end || state.tries[index].thrown
				state.tries[index].position = .catch
				state.tries[index].thrown = false
				catch_end = catch_entry
				if body := node_field(catch_clause, 'body') {
					catch_end = c.code_path_statement(body, catch_entry, '', mut state)
				}
			}
			info := state.tries[index]
			if finally_clause := finalizer {
				state.tries[index].position = .finally
				normal := try_end || catch_end
				leaving := info.returned || info.thrown
				mut finally_end := normal || leaving
				if body := node_field(finally_clause, 'body') {
					finally_end = c.code_path_statement(body, normal || leaving, '', mut
						state)
				}
				state.tries.pop()
				// The paths that leave go on to the contexts outside.
				if finally_end && info.returned {
					for i := state.tries.len - 1; i >= 0; i-- {
						if state.tries[i].has_finalizer && state.tries[i].position != .finally {
							state.tries[i].returned = true
							break
						}
					}
				}
				if finally_end && info.thrown {
					if outer := code_path_throw_context(state) {
						state.tries[outer].thrown = true
					}
				}
				return normal && finally_end
			}
			state.tries.pop()
			return try_end || catch_end
		}
		'with_statement' {
			if object := node_field(statement, 'object') {
				c.code_path_throwable(object, reachable, mut state)
			}
			body := node_field(statement, 'body') or { return reachable }
			return c.code_path_statement(body, reachable, '', mut state)
		}
		else {
			c.code_path_throwable(statement, reachable, mut state)
			return reachable
		}
	}
}

// code_path_throw_context ports getThrowContext: the closest `try` statement whose `try` block,
// or whose `catch` block when it has a `finally`, the code is in.
fn code_path_throw_context(state CodePathState) ?int {
	for i := state.tries.len - 1; i >= 0; i-- {
		context := state.tries[i]
		if context.position == .try || (context.has_finalizer && context.position == .catch) {
			return i
		}
	}
	return none
}

// code_path_throwable ports makeFirstThrowablePathInTryOrCatchBlock for the nodes of `node`: in a
// `try` block, the first node that may throw makes a path to the `catch` block (or to the `finally`
// block without one), and in a `catch` block with a `finally`, to the `finally` block, from which
// it goes on as a throw (code_path_throw_context finds that context).
fn (c &Checker) code_path_throwable(node C.TSNode, reachable bool, mut state CodePathState) {
	if !reachable {
		return
	}
	index := code_path_throw_context(state) or { return }
	if state.tries[index].thrown {
		return
	}
	if c.code_path_may_throw(node) {
		state.tries[index].thrown = true
	}
}

// code_path_may_throw: the node has, outside the functions in it, a CallExpression, an
// ImportExpression, a MemberExpression, a NewExpression, a YieldExpression or an Identifier that
// isIdentifierReference takes for a reference.
fn (c &Checker) code_path_may_throw(node C.TSNode) bool {
	kind := node_kind(node)
	if kind in ['call_expression', 'new_expression', 'member_expression', 'subscript_expression',
		'yield_expression'] {
		return true
	}
	if kind in ['identifier', 'undefined', 'type_identifier', 'property_identifier',
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern'] {
		return code_path_is_reference(node)
	}
	// Another function is another code path, and so are the value of a class field and a static
	// block; of a method only a computed key is evaluated here.
	if kind in code_path_function_kinds || kind == 'class_static_block' {
		return false
	}
	if kind in ['method_definition', 'public_field_definition'] {
		for child in named_children(node) {
			if node_kind(child) in ['computed_property_name', 'decorator']
				&& c.code_path_may_throw(child) {
				return true
			}
		}
		return false
	}
	for child in named_children(node) {
		if c.code_path_may_throw(child) {
			return true
		}
	}
	return false
}

// code_path_is_reference ports isIdentifierReference: an Identifier that is not a label, an
// element of an array pattern, the argument of a rest element, the parameter of a `catch`, the
// name of a function, of a class or of a variable declarator, or the key of a property that is
// neither computed nor shorthand.
fn code_path_is_reference(node C.TSNode) bool {
	parent := node_parent(node) or { return true }
	match node_kind(parent) {
		'array_pattern', 'rest_pattern', 'catch_clause' {
			return false
		}
		'class_declaration', 'class', 'abstract_class_declaration', 'variable_declarator' {
			name := node_field(parent, 'name') or { return true }
			return node_key(name) != node_key(node)
		}
		'pair', 'pair_pattern' {
			key := node_field(parent, 'key') or { return true }
			return node_key(key) != node_key(node)
		}
		else {
			return true
		}
	}
}

// code_path_true_literal ports getBooleanValueIfSimpleConstant for the test of a loop: it is a
// Literal whose value is true.
fn (c &Checker) code_path_true_literal(test ?C.TSNode) bool {
	mut node := test or { return false }
	if node_kind(node) == 'expression_statement' {
		node = first_named(node) or { return false }
	}
	node = unwrap_parens(node)
	text := c.text(node)
	match node_kind(node) {
		'true', 'regex' {
			return true
		}
		'string' {
			return text.len > 2
		}
		'number' {
			if text.ends_with('n') {
				return text[..text.len - 1].replace('_', '').trim_left('0xXoObB') != ''
			}
			value := js_number_string(text) or { return false }
			return value !in ['0', 'NaN']
		}
		else {
			return false
		}
	}
}
