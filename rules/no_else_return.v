module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-else-return` rule of ESLint 10.6.0, with its option and its fix.

const ner_messages = {
	'unexpected': "Unnecessary 'else' after 'return'."
}

const ner_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition']

// ner_allow_else_if reads allowElseIf.
fn ner_allow_else_if(options []json2.Any) !bool {
	o := option_object(no_else_return, options, ['allowElseIf'])!
	return o.bool_value('allowElseIf')!
}

fn (mut c Checker) lint_no_else_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_else_if := ner_allow_else_if(c.rule_options(no_else_return))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['if_statement'], []) {
		stats.checked++
		// Only an `if` in a list of statements (STATEMENT_LIST_PARENTS).
		if !ner_in_statement_list(node) {
			continue
		}
		mut report := ?C.TSNode(none)
		if allow_else_if {
			// The consequents of the whole if-else-if chain return, and the chain ends in `else`.
			mut consequents := []C.TSNode{}
			mut current := node
			mut alternate := ?C.TSNode(none)
			mut complete := true
			for node_kind(current) == 'if_statement' {
				next := ner_alternate(current) or {
					complete = false
					break
				}
				consequents << node_field(current, 'consequence') or {
					complete = false
					break
				}
				alternate = next
				current = next
			}
			if complete && consequents.all(ner_always_returns(it)) {
				report = alternate
			}
		} else {
			if alternate := ner_alternate(node) {
				consequent := node_field(node, 'consequence') or { continue }
				if ner_always_returns(consequent) {
					report = alternate
				}
			}
		}
		if else_node := report {
			has_fix, fix := c.ner_fix(root, node_parent(node_parent(else_node) or { continue }) or {
				continue
			}, else_node)
			findings << Finding{
				stmt:       position_of(else_node)
				message_id: 'unexpected'
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ner_in_statement_list: the parent is a Program, a BlockStatement, a StaticBlock or a SwitchCase.
fn ner_in_statement_list(n C.TSNode) bool {
	parent := node_parent(n) or { return false }
	return match node_kind(parent) {
		'program', 'switch_case', 'switch_default' {
			true
		}
		'statement_block' {
			grand := node_parent(parent) or { return true }
			node_kind(grand) !in ['module', 'internal_module', 'ambient_declaration']
		}
		else {
			false
		}
	}
}

// ner_alternate is the ESTree `alternate` of an IfStatement: the statement of its `else`.
fn ner_alternate(n C.TSNode) ?C.TSNode {
	clause := node_field(n, 'alternative')?
	return first_named(clause)
}

// ner_statements are the statements of a block, comments aside.
fn ner_statements(block C.TSNode) []C.TSNode {
	return named_children(block).filter(node_kind(it) != 'comment')
}

// ner_naive_has_return ports naiveHasReturn: a `return`, or a block whose last statement is one.
fn ner_naive_has_return(n C.TSNode) bool {
	if node_kind(n) == 'statement_block' {
		statements := ner_statements(n)
		return statements.len > 0 && node_kind(statements.last()) == 'return_statement'
	}
	return node_kind(n) == 'return_statement'
}

// ner_return_or_if ports checkForReturnOrIf: a `return`, or an `if` with an `else` where both
// branches naively return.
fn ner_return_or_if(n C.TSNode) bool {
	if node_kind(n) == 'return_statement' {
		return true
	}
	if node_kind(n) != 'if_statement' {
		return false
	}
	alternate := ner_alternate(n) or { return false }
	consequent := node_field(n, 'consequence') or { return false }
	return ner_naive_has_return(alternate) && ner_naive_has_return(consequent)
}

// ner_always_returns ports alwaysReturns.
fn ner_always_returns(n C.TSNode) bool {
	if node_kind(n) == 'statement_block' {
		return ner_statements(n).any(ner_return_or_if(it))
	}
	return ner_return_or_if(n)
}

// ner_fix ports the fix of displayReport: the `else` and the braces of its block are removed,
// when that cannot change the meaning; the replacement covers the enclosing function
// (FixTracker.retainEnclosingFunction).
fn (mut c Checker) ner_fix(root C.TSNode, if_node C.TSNode, else_node C.TSNode) (bool, Fix) {
	if !c.ner_safe_from_collisions(root, if_node, else_node) {
		return false, Fix{}
	}
	tokens := c.source_tokens(root)
	else_end := c.es_end(else_node)
	start_token := tokens.after(node_start(else_node), false) or { return false, Fix{} }
	else_token := tokens.before(start_token.start, false) or { return false, Fix{} }
	last_if_token := tokens.before(else_token.start, false) or { return false, Fix{} }
	is_block := c.src[start_token.start..start_token.end] == '{'
	first_of_else := if is_block {
		tokens.after(start_token.end, false) or { return false, Fix{} }
	} else {
		start_token
	}
	consequent := node_field(if_node, 'consequence') or { return false, Fix{} }
	if_block_maybe_unsafe := node_kind(consequent) != 'statement_block'
		&& c.src[last_if_token.start..last_if_token.end] != ';'
	if if_block_maybe_unsafe && ner_starts_unsafe(c.src[first_of_else.start..first_of_else.end]) {
		return false, Fix{}
	}
	end_token := tokens.before(else_end, false) or { return false, Fix{} }
	last_of_else := tokens.before(end_token.start, false) or { return false, Fix{} }
	if c.src[last_of_else.start..last_of_else.end] != ';' {
		if next := tokens.after(end_token.end, false) {
			next_text := c.src[next.start..next.end]
			same_line := !es_has_line_break(c.src[last_of_else.start..next.start])
			if ner_starts_unsafe(next_text) || (same_line && next_text != '}') {
				return false, Fix{}
			}
		}
	}
	source := c.src[node_start(else_node)..else_end]
	fixed := if is_block { source[1..source.len - 1] } else { source }
	// The range of the enclosing function, or of the program (from its first token to the end).
	mut retain_start := if first := tokens.after(0, false) { first.start } else { 0 }
	mut retain_end := c.src.len
	if function := ner_upper_function(else_node) {
		retain_start = ner_function_start(function)
		retain_end = c.es_end(function)
	}
	start := if retain_start < else_token.start { retain_start } else { else_token.start }
	end := if retain_end > else_end { retain_end } else { else_end }
	return true, fix_replace_range(start, end, c.src[start..else_token.start] + fixed +
		c.src[else_end..end])
}

// ner_starts_unsafe: a token that would continue the previous statement (/^[([/+`-]/).
fn ner_starts_unsafe(text string) bool {
	return text.len > 0 && text[0] in [`(`, `[`, `/`, `+`, `\``, `-`]
}

// ner_upper_function ports getUpperFunction: the closest function around the node.
fn ner_upper_function(n C.TSNode) ?C.TSNode {
	mut current := n
	for {
		current = node_parent(current)?
		if node_kind(current) in ner_function_kinds {
			return current
		}
	}
	return none
}

// ner_function_start is where the ESTree function starts: a method's FunctionExpression starts
// at its type parameters or its parameters.
fn ner_function_start(function C.TSNode) int {
	if node_kind(function) == 'method_definition' {
		if type_parameters := node_field(function, 'type_parameters') {
			return node_start(type_parameters)
		}
		if parameters := node_field(function, 'parameters') {
			return node_start(parameters)
		}
	}
	return node_start(function)
}

// ner_safe_from_collisions ports isSafeFromNameCollisions: the variables of the `else` block can
// move to the scope of the `if`.
fn (mut c Checker) ner_safe_from_collisions(root C.TSNode, if_node C.TSNode, else_node C.TSNode) bool {
	if node_kind(else_node) in ['function_declaration', 'generator_function_declaration'] {
		return false
	}
	if node_kind(else_node) != 'statement_block' {
		return true
	}
	tree := c.scope_tree(root)
	scope := tree.get_scope(if_node)
	key := node_key(else_node)
	else_scopes := tree.scopes[scope].children.filter(node_key(tree.scopes[it].block) == key)
	if else_scopes.len == 0 {
		return true
	}
	else_names := tree.scopes[else_scopes[0]].variables.map(tree.variables[it].name)
	return ner_safe_to_declare(tree, else_names, scope)
}

// ner_safe_to_declare ports isSafeToDeclare: declaring the new names in the scope makes no conflict.
fn ner_safe_to_declare(tree &ScopeTree, new_names []string, scope int) bool {
	if new_names.len == 0 {
		return true
	}
	s := tree.scopes[scope]
	function_scope := s.variable_scope
	for v in s.variables {
		variable := tree.variables[v]
		if variable.name in new_names && variable.defs.len > 0 {
			return false
		}
	}
	// Redeclaring a catch variable would be a syntax error.
	if scope != function_scope && s.upper >= 0 && tree.scopes[s.upper].kind == .catch_clause {
		if tree.scopes[s.upper].variables.any(tree.variables[it].name in new_names) {
			return false
		}
	}
	// Implicit variables with references (in the global scope).
	for v in s.variables {
		variable := tree.variables[v]
		if variable.name in new_names && variable.defs.len == 0 && variable.references.len > 0 {
			return false
		}
	}
	// The references that go through the scope: they would resolve to the new variables.
	for r in 0 .. tree.references.len {
		reference := tree.references[r]
		if reference.name !in new_names || !ner_scope_within(tree, reference.from, scope) {
			continue
		}
		if reference.resolved < 0
			|| !ner_scope_within(tree, tree.variables[reference.resolved].scope, scope) {
			return false
		}
	}
	// A `var` of the function declared inside this block.
	if scope != function_scope {
		for v in tree.scopes[function_scope].variables {
			variable := tree.variables[v]
			if variable.name !in new_names {
				continue
			}
			for def in variable.defs {
				if s.start <= node_start(def.node) && node_end(def.node) <= s.end {
					return false
				}
			}
		}
	}
	return true
}

// ner_scope_within: `inner` is `outer` or one of its descendants.
fn ner_scope_within(tree &ScopeTree, inner int, outer int) bool {
	mut s := inner
	for s >= 0 {
		if s == outer {
			return true
		}
		s = tree.scopes[s].upper
	}
	return false
}
