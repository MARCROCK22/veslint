module rules

import estree
import time

// Port of the `unicorn/no-array-for-each` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix and suggestion.

const unafe_messages = {
	'no-array-for-each/error':      'Use `for…of` instead of `.forEach(…)`.'
	'no-array-for-each/suggestion': 'Switch to `for…of`.'
}

const unafe_ignored_objects = ['React.Children', 'Children', 'R', 'pIteration', 'Effect']

fn unafe_strip_chain(t &estree.EsTree, node int) int {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) == .chain_expression && t.node(parent, .expression) or { -1 } == node {
		return parent
	}
	return node
}

// unafe_return_statements are the `return` statements of the function itself (functionInfo).
fn unafe_return_statements(t &estree.EsTree, function int) []int {
	mut out := []int{}
	start, end := t.nodes[function].start, t.nodes[function].end
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .return_statement || t.nodes[node].start < start || t.nodes[node].end > end {
			continue
		}
		mut current := t.nodes[node].parent
		for current >= 0 && t.typ(current) !in [.function_declaration, .function_expression,
			.arrow_function_expression] {
			current = t.nodes[current].parent
		}
		if current == function {
			out << node
		}
	}
	out.sort_with_compare(fn [t] (a &int, b &int) int {
		return t.nodes[*a].start - t.nodes[*b].start
	})
	return out
}

fn unafe_in_continue_able(t &estree.EsTree, return_statement int, callback int) bool {
	mut node := return_statement
	for node >= 0 && node != callback {
		if t.typ(node) in [.while_statement, .do_while_statement, .for_statement, .for_of_statement,
			.for_in_statement] {
			return true
		}
		node = t.nodes[node].parent
	}
	return false
}

// unafe_parameter_variables are the variables of the parameters of the callback
// (getDeclaredVariables, the parameters).
fn unafe_parameter_variables(tree &ScopeTree, scope int) []int {
	return tree.scopes[scope].variables.filter(tree.variables[it].defs.len > 0
		&& tree.variables[it].defs[0].kind == .parameter)
}

fn (mut c Checker) unafe_is_fixable(root C.TSNode, t &estree.EsTree, call int) bool {
	arguments := t.list(call, .arguments) or { return false }
	if (t.flag(call, .optional) or { false }) || arguments.len != 1 {
		return false
	}
	// Check ancestors, we only fix `ExpressionStatement`
	call_or_chain := unafe_strip_chain(t, call)
	parent := t.nodes[call_or_chain].parent
	if t.typ(parent) != .expression_statement && !(t.typ(parent) == .arrow_function_expression
		&& t.node(parent, .body) or { -1 } == call_or_chain) {
		return false
	}
	callback := arguments[0]
	if t.typ(callback) !in [.function_expression, .arrow_function_expression]
		|| (t.flag(callback, .async) or { false }) || (t.flag(callback, .generator) or { false }) {
		return false
	}
	parameters := t.list(callback, .params) or { return false }
	if !(parameters.len == 1 || parameters.len == 2)
		|| (parameters.len == 1 && t.typ(parameters[0]) == .assignment_pattern)
		|| (parameters.len == 2 && t.typ(parameters[1]) != .identifier)
		|| parameters.any(t.typ(it) == .rest_element || t.node(it, .type_annotation) != none) {
		return false
	}
	tree := c.scope_tree(root)
	function_scope := tree.function_scope_of(t.ts_node(callback) or { return false })
	if function_scope < 0 {
		return false
	}
	// isFunctionParametersSafeToFix
	scope := tree.get_scope(t.ts_node(call) or { return false })
	call_start, call_end := t.nodes[call].start, t.nodes[call].end
	for v in tree.scopes[function_scope].variables {
		variable := tree.variables[v]
		if !variable.defs.any(it.kind == .parameter) {
			continue
		}
		if variable.defs.len != 1 {
			return false
		}
		name := variable.name
		for identifier in 0 .. t.nodes.len {
			if t.typ(identifier) != .identifier || t.nodes[identifier].start < call_start
				|| t.nodes[identifier].end > call_end
				|| (t.string_of(identifier, .name) or { '' }) != name
				|| !un_is_reference_identifier(t, identifier) {
				continue
			}
			found := tree.find_variable(scope, name, t.nodes[identifier].start)
			if found < 0 {
				return false
			}
			mut s := scope
			for s >= 0 {
				if s == tree.variables[found].scope {
					return false
				}
				s = tree.scopes[s].upper
			}
		}
	}
	// Check `ReturnStatement`s in `callback`
	if unafe_return_statements(t, callback).any(unafe_in_continue_able(t, it, callback)) {
		return false
	}
	return !c.un_is_function_self_used_inside(root, t, callback)
}

fn (mut c Checker) lint_unicorn_no_array_for_each(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: ['forEach']) {
			continue
		}
		iterable := t.node(node, .callee) or { continue }
		if un_is_node_matches(t, t.node(iterable, .object) or { continue }, unafe_ignored_objects) {
			continue
		}
		property := t.node(iterable, .property) or { continue }
		finding := Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'no-array-for-each/error'
		}
		if !c.unafe_is_fixable(root, t, node) {
			findings << finding
			continue
		}
		has_fix, fix := c.merge_fixes(c.unafe_fix(root, t, tokens, node) or {
			findings << finding
			continue
		})!
		if (t.flag(iterable, .optional) or { false }) && un_has_side_effect(t, iterable) {
			findings << Finding{
				...finding
				suggestions: [Suggestion{
					message_id: 'no-array-for-each/suggestion'
					fix:        fix
				}]
			}
		} else {
			findings << Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unafe_expression_statement_needs_parens ports shouldAddParenthesesToExpressionStatementExpression.
fn unafe_expression_statement_needs_parens(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.object_expression {
			true
		}
		.assignment_expression {
			left := t.node(node, .left) or { -1 }
			left >= 0 && t.typ(left) in [.object_pattern, .array_pattern]
		}
		else {
			false
		}
	}
}

// unafe_fix ports getFixFunction.
fn (mut c Checker) unafe_fix(root C.TSNode, t &estree.EsTree, tokens &SourceTokens, call int) ?[]Fix {
	callback := (t.list(call, .arguments) or { return none })[0]
	parameters := t.list(callback, .params) or { return none }
	callee := t.node(call, .callee)?
	iterable_object := t.node(callee, .object)?
	is_optional_object := t.flag(callee, .optional) or { false }
	ancestor := t.nodes[unafe_strip_chain(t, call)].parent
	object_text := c.un_text(t, iterable_object)
	tree := c.scope_tree(root)
	function_scope := tree.function_scope_of(t.ts_node(callback)?)
	mut fixes := []Fix{}
	// `(( foo.forEach(bar => bar) ))`
	fixes << c.un_remove_parentheses(t, tokens, call)
	// Replace these with `for (const … of …) `
	should_use_entries := parameters.len == 2
	reassigned := unafe_parameter_variables(tree, function_scope).any(tree.variables[it].references.any(!tree.references[it].init
		&& tree.references[it].write))
	mut head := 'for (${if reassigned { 'let' } else { 'const' }} '
	element_text := c.un_text(t, parameters[0])
	head += if should_use_entries {
		'[${c.un_text(t, parameters[1])}, ${element_text}]'
	} else {
		element_text
	}
	head += ' of '
	parenthesize := c.un_is_parenthesized(t, tokens, iterable_object) || (is_optional_object
		&& should_use_entries && c.un_member_object_needs_parens(t, tokens, iterable_object))
	head += if parenthesize { '(${object_text})' } else { object_text }
	if should_use_entries {
		head += '.entries()'
	}
	head += ') '
	body := t.node(callback, .body)?
	body_start, _ := c.un_parenthesized_range(t, tokens, body)
	fixes << fix_replace_range(t.nodes[call].start, body_start, head)
	// Parenthesized callback function: its `)`
	for token in c.un_parentheses(t, tokens, callback) {
		if c.token_is(token, ')') {
			fixes << fix_remove_range(token.start, token.end)
		}
	}
	inside := tokens.inside(t.nodes[call].start, t.nodes[call].end, false)
	if inside.len < 2 {
		return none
	}
	penultimate := inside[inside.len - 2]
	last := inside.last()
	// The possible trailing comma of `Array#forEach()`
	if c.token_is(penultimate, ',') {
		fixes << fix_remove_range(penultimate.start, penultimate.end)
	}
	// The closing parenthesis of `Array#forEach()`
	fixes << fix_remove_range(last.start, last.end)
	for return_statement in unafe_return_statements(t, callback) {
		fixes << c.unafe_replace_return(t, tokens, return_statement)?
	}
	if t.typ(ancestor) == .expression_statement {
		// Remove the `;` if it's not needed anymore
		statement_last := un_last_token(t, tokens, ancestor)?
		if c.token_is(statement_last, ';') && t.typ(body) == .block_statement {
			fixes << fix_remove_range(statement_last.start, statement_last.end)
		}
	} else if t.typ(ancestor) == .arrow_function_expression {
		fixes << fix_insert_at(t.nodes[call].start, '{ ')
		fixes << fix_insert_at(t.nodes[call].end, ' }')
	}
	fixes << c.un_fix_space_around_keyword(t, tokens, t.nodes[call].parent)
	if is_optional_object {
		fixes << fix_insert_at(t.nodes[call].start, 'if (${object_text}) ')
	}
	// Prevent possible variable conflicts
	parent := t.nodes[call].parent
	fixes << fix_insert_at(t.nodes[parent].start, '')
	fixes << fix_insert_at(t.nodes[parent].end, '')
	return fixes
}

// unafe_replace_return ports replaceReturnStatement: `return x;` becomes `x; continue;`.
fn (c &Checker) unafe_replace_return(t &estree.EsTree, tokens &SourceTokens, return_statement int) ?[]Fix {
	return_token := un_first_token(t, tokens, return_statement, 0)?
	argument := t.node(return_statement, .argument) or {
		return [fix_replace_range(return_token.start, return_token.end, 'continue')]
	}
	mut fixes := [fix_remove_range(return_token.start, return_token.end)]
	previous := tokens.before(return_token.start, false)
	next := tokens.after(return_token.end, false)?
	mut text_before := ''
	mut text_after := ''
	should_add_parentheses := !c.un_is_parenthesized(t, tokens, argument)
		&& unafe_expression_statement_needs_parens(t, argument)
	if should_add_parentheses {
		text_before = '(${text_before}'
		text_after = '${text_after})'
	}
	parent := t.nodes[return_statement].parent
	insert_braces := match t.typ(parent) {
		.if_statement {
			t.node(parent, .consequent) or { -1 } == return_statement
				|| t.node(parent, .alternate) or { -1 } == return_statement
		}
		.with_statement {
			t.node(parent, .body) or { -1 } == return_statement
		}
		else {
			false
		}
	}
	if insert_braces {
		text_before = '{ ${text_before}'
	} else if c.un_needs_semicolon(t, tokens, previous, if should_add_parentheses {
		'('
	} else {
		c.token_text(next)
	}) {
		text_before = ';${text_before}'
	}
	if text_before != '' {
		fixes << fix_insert_at(next.start, text_before)
	}
	if text_after != '' {
		fixes << fix_insert_at(t.nodes[argument].end, text_after)
	}
	last := un_last_token(t, tokens, return_statement)?
	end := t.nodes[return_statement].end
	if !c.token_is(last, ';') {
		fixes << fix_insert_at(end, ';')
	}
	fixes << fix_insert_at(end, ' continue;')
	if insert_braces {
		fixes << fix_insert_at(end, ' }')
	}
	return fixes
}
