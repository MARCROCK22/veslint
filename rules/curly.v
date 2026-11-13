module rules

import json2
import time
import treesitter { node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `curly` rule of ESLint 10.6.0, with its options and its fixes.

const cu_messages = {
	'missingCurlyAfter':             "Expected { after '{{name}}'."
	'missingCurlyAfterCondition':    "Expected { after '{{name}}' condition."
	'unexpectedCurlyAfter':          "Unnecessary { after '{{name}}'."
	'unexpectedCurlyAfterCondition': "Unnecessary { after '{{name}}' condition."
}

struct CuOptions {
	mode       string // all, multi, multi-line or multi-or-nest
	consistent bool
}

// cu_options reads the mode and "consistent".
fn cu_options(options []json2.Any) !CuOptions {
	mode := if options.len > 0 { options[0] } else { json2.Any('all') }
	if mode !is string || mode.str() !in ['all', 'multi', 'multi-line', 'multi-or-nest'] {
		return error('the first option of `${curly}` must be "all", "multi", "multi-line" or "multi-or-nest"')
	}
	mut consistent := false
	if options.len > 1 {
		if options[1] !is string || options[1].str() != 'consistent' {
			return error('the second option of `${curly}` must be "consistent"')
		}
		consistent = true
	}
	return CuOptions{
		mode:       mode.str()
		consistent: consistent
	}
}

// CuCheck is a prepared check: the statement, its body, the keyword and whether it is a
// condition's, whether the body has braces and whether it should (-1: either way).
struct CuCheck {
	node      C.TSNode
	body      C.TSNode
	name      string
	condition bool
	actual    bool
mut:
	expected int
}

fn (mut c Checker) lint_curly(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := cu_options(c.rule_options(curly))!
	mut findings := []Finding{}
	kinds := ['if_statement', 'while_statement', 'do_statement', 'for_statement', 'for_in_statement']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		mut checks := []CuCheck{}
		match node_kind(node) {
			'if_statement' {
				// An `else if` is checked with the chain of its first `if`.
				if parent := node_parent(node) {
					if node_kind(parent) == 'else_clause' {
						continue
					}
				}
				mut current := node
				for {
					consequent := node_field(current, 'consequence') or { break }
					checks << c.cu_prepare(root, o, current, consequent, 'if', true)
					alternate := ner_alternate(current) or { break }
					if node_kind(alternate) != 'if_statement' {
						checks << c.cu_prepare(root, o, current, alternate, 'else', false)
						break
					}
					current = alternate
				}
				if o.consistent {
					mut expected := false
					for check in checks {
						if (check.expected >= 0 && check.expected == 1)
							|| (check.expected < 0 && check.actual) {
							expected = true
						}
					}
					for mut check in checks {
						check.expected = if expected { 1 } else { 0 }
					}
				}
			}
			'while_statement' {
				checks << c.cu_prepare(root, o, node, node_field(node, 'body') or { continue },
					'while', true)
			}
			'do_statement' {
				checks << c.cu_prepare(root, o, node, node_field(node, 'body') or { continue },
					'do', false)
			}
			'for_statement' {
				checks << c.cu_prepare(root, o, node, node_field(node, 'body') or { continue },
					'for', true)
			}
			else {
				operator := node_field(node, 'operator') or { continue }
				name := if node_kind(operator) == 'of' { 'for-of' } else { 'for-in' }
				checks << c.cu_prepare(root, o, node, node_field(node, 'body') or { continue },
					name, false)
			}
		}
		for check in checks {
			if check.expected < 0 || (check.expected == 1) == check.actual {
				continue
			}
			data := {
				'name': check.name
			}
			if check.expected == 1 {
				findings << Finding{
					stmt:       position_of(check.body)
					message_id: if check.condition {
						'missingCurlyAfterCondition'
					} else {
						'missingCurlyAfter'
					}
					data:       data
					has_fix:    true
					fix:        fix_replace_range(node_start(check.body), c.es_end(check.body), '{${c.es_text(check.body)}}')
				}
			} else {
				has_fix, fix := c.cu_unexpected_fix(root, check)
				findings << Finding{
					stmt:       position_of(check.body)
					message_id: if check.condition {
						'unexpectedCurlyAfterCondition'
					} else {
						'unexpectedCurlyAfter'
					}
					data:       data
					has_fix:    has_fix
					fix:        fix
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// cu_prepare ports prepareCheck: whether the body should have braces.
fn (mut c Checker) cu_prepare(root C.TSNode, o CuOptions, node C.TSNode, body C.TSNode, name string, condition bool) CuCheck {
	has_block := node_kind(body) == 'statement_block'
	statements := if has_block { ner_statements(body) } else { []C.TSNode{} }
	mut expected := -1
	if has_block && (statements.len != 1 || c.cu_braces_necessary(root, body, statements)) {
		expected = 1
	} else if o.mode == 'multi' {
		expected = 0
	} else if o.mode == 'multi-line' {
		if !c.cu_collapsed_one_liner(root, body) {
			expected = 1
		}
	} else if o.mode == 'multi-or-nest' {
		if has_block {
			statement := statements[0]
			tokens := c.source_tokens(root)
			comments := tokens.comments_before(node_start(statement))
			expected = if !c.cu_one_liner(root, statement) || comments.len > 0 { 1 } else { 0 }
		} else {
			expected = if !c.cu_one_liner(root, body) { 1 } else { 0 }
		}
	} else {
		expected = 1
	}
	return CuCheck{
		node:      node
		body:      body
		name:      name
		condition: condition
		actual:    has_block
		expected:  expected
	}
}

// cu_last_excluding_semicolon is the last token of a node, or the one before it when it is `;`.
fn (mut c Checker) cu_last_excluding_semicolon(root C.TSNode, n C.TSNode) ?SourceToken {
	tokens := c.source_tokens(root)
	last := tokens.before(node_end(n), false)?
	if c.src[last.start..last.end] == ';' {
		return tokens.before(last.start, false)
	}
	return last
}

// cu_collapsed_one_liner ports isCollapsedOneLiner: the token before the body and its last one
// (a `;` aside) are on the same line.
fn (mut c Checker) cu_collapsed_one_liner(root C.TSNode, body C.TSNode) bool {
	tokens := c.source_tokens(root)
	before := tokens.before(node_start(body), false) or { return false }
	last := c.cu_last_excluding_semicolon(root, body) or { return false }
	return !es_has_line_break(c.src[before.start..last.end])
}

// cu_one_liner ports isOneLiner: the statement starts and ends (a `;` aside) on the same line.
fn (mut c Checker) cu_one_liner(root C.TSNode, statement C.TSNode) bool {
	if node_kind(statement) == 'empty_statement' {
		return true
	}
	last := c.cu_last_excluding_semicolon(root, statement) or { return true }
	return !es_has_line_break(c.src[node_start(statement)..last.end])
}

// cu_braces_necessary ports areBracesNecessary for a block with one statement: a lexical
// declaration, or an `if` without `else` that would take an `else` that follows the block.
fn (mut c Checker) cu_braces_necessary(root C.TSNode, block C.TSNode, statements []C.TSNode) bool {
	statement := statements[0]
	if ncd_is_lexical(statement) {
		return true
	}
	if !cu_has_unsafe_if(statement) {
		return false
	}
	tokens := c.source_tokens(root)
	next := tokens.after(node_end(block), false) or { return false }
	return next.kind == .keyword && c.src[next.start..next.end] == 'else'
}

// cu_has_unsafe_if ports hasUnsafeIf: an `if` without `else` ends the statement.
fn cu_has_unsafe_if(n C.TSNode) bool {
	return match node_kind(n) {
		'if_statement' {
			alternate := ner_alternate(n) or { return true }
			cu_has_unsafe_if(alternate)
		}
		'for_statement', 'for_in_statement', 'labeled_statement', 'with_statement',
		'while_statement' {
			cu_has_unsafe_if(node_field(n, 'body') or { return false })
		}
		else {
			false
		}
	}
}

// cu_unexpected_fix is the fix of a body with unnecessary braces: the braces are removed, unless
// the statement after them would need a semicolon.
fn (mut c Checker) cu_unexpected_fix(root C.TSNode, check CuCheck) (bool, Fix) {
	tokens := c.source_tokens(root)
	body := check.body
	open := tokens.after(node_start(body), false) or { return false, Fix{} }
	close := tokens.before(node_end(body), false) or { return false, Fix{} }
	mut needs_space := false
	if node_kind(check.node) == 'do_statement' {
		before := tokens.before(node_start(body), false) or { return false, Fix{} }
		if before.end == node_start(body) {
			first := tokens.after(open.end, false) or { return false, Fix{} }
			needs_space = !cu_can_follow_keyword(first, c.src[first.start..first.end])
		}
	}
	if c.cu_needs_semicolon(root, close) {
		return false, Fix{}
	}
	text := c.src[open.end..close.start]
	return true, fix_replace_range(node_start(body), c.es_end(body), (if needs_space {
		' '
	} else {
		''
	}) + text)
}

// cu_can_follow_keyword ports canTokensBeAdjacent("do", token): a punctuator, a string, a
// template, a number starting with `.` or a private name can follow `do` without a space.
fn cu_can_follow_keyword(token SourceToken, text string) bool {
	return match token.kind {
		.punctuator, .string_, .template, .private_identifier { true }
		.numeric { text.starts_with('.') }
		else { false }
	}
}

// cu_needs_semicolon ports needsSemicolon: what follows the closing brace would continue the last
// statement of the block once the braces are gone.
fn (mut c Checker) cu_needs_semicolon(root C.TSNode, close SourceToken) bool {
	tokens := c.source_tokens(root)
	before := tokens.before(close.start, false) or { return false }
	if c.src[before.start..before.end] == ';' {
		return false
	}
	after := tokens.after(close.end, false) or { return false }
	// The node of the token before: a BlockStatement that is not a function expression's body
	// ends a statement.
	mut last_node := before.node
	if !C.ts_node_is_named(last_node) {
		last_node = node_parent(last_node) or { last_node }
	}
	if node_kind(last_node) == 'statement_block' {
		parent := node_parent(last_node) or { return false }
		if node_kind(parent) !in ['function_expression', 'generator_function', 'arrow_function',
			'method_definition', 'class_static_block', 'module', 'internal_module',
			'ambient_declaration'] {
			return false
		}
	}
	if !es_has_line_break(c.src[before.end..after.start]) {
		return true
	}
	after_text := c.src[after.start..after.end]
	if after_text.len > 0 && after_text[0] in [`(`, `[`, `/`, `\``, `+`, `-`] {
		return true
	}
	before_text := c.src[before.start..before.end]
	return before.kind == .punctuator && before_text in ['++', '--']
}
