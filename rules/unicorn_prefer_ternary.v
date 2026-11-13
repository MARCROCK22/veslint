module rules

import estree
import json2
import time

// Port of the `unicorn/prefer-ternary` rule of eslint-plugin-unicorn 64.0.0, with its fix.

const upt_messages = {
	'prefer-ternary': 'This `if` statement can be replaced by a ternary expression.'
}

fn upt_options(options []json2.Any) !bool {
	if options.len == 0 {
		return false
	}
	value := options[0]
	return value is string && value == 'only-single-line'
}

// UptOperand is a branch of the merge: a node, or a text (`undefined` for a bare `return`).
struct UptOperand {
	node int = -1
	text string
}

// UptMerge is what merge gives: the text before and after the ternary and its two branches.
struct UptMerge {
	throw_    bool
	before    string
	after     string = ';'
	consequent UptOperand
	alternate  UptOperand
}

fn upt_is_ternary(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .conditional_expression
}

// upt_body ports getNodeBody: the only statement of a block, the expression of a statement.
fn upt_body(t &estree.EsTree, node int) int {
	if t.typ(node) == .expression_statement {
		return upt_body(t, t.node(node, .expression) or { return node })
	}
	if t.typ(node) == .block_statement {
		body := (t.list(node, .body) or { []int{} }).filter(t.typ(it) != .empty_statement)
		if body.len == 1 {
			return upt_body(t, body[0])
		}
	}
	return node
}

fn upt_argument(t &estree.EsTree, node int) UptOperand {
	argument := t.node(node, .argument) or { return UptOperand{
		text: 'undefined'
	} }
	return UptOperand{
		node: argument
	}
}

// upt_merge ports merge: `return a` and `return b` become `return test ? a : b`, and the same for
// `yield`, `await`, `throw` (only at the top) and assignments to the same reference. none when
// the top branches cannot be merged.
fn (mut c Checker) upt_merge(t &estree.EsTree, tokens &SourceTokens, m UptMerge, node int, top bool) ?UptMerge {
	consequent := m.consequent.node
	alternate := m.alternate.node
	if consequent < 0 || alternate < 0 || t.typ(consequent) != t.typ(alternate) {
		// Two texts (`undefined`) have the same (undefined) type, and nothing else to merge.
		if top && !(m.consequent.node < 0 && m.alternate.node < 0) {
			return none
		}
		return m
	}
	typ := t.typ(consequent)
	argument := t.node(consequent, .argument) or { -1 }
	alternate_argument := t.node(alternate, .argument) or { -1 }
	no_ternary := !upt_is_ternary(t, argument) && !upt_is_ternary(t, alternate_argument)
	if typ == .return_statement && no_ternary {
		return c.upt_merge(t, tokens, UptMerge{
			before:     '${m.before}return '
			after:      m.after
			consequent: upt_argument(t, consequent)
			alternate:  upt_argument(t, alternate)
		}, node, false)
	}
	delegate := t.flag(consequent, .delegate) or { false }
	if typ == .yield_expression && delegate == (t.flag(alternate, .delegate) or { false })
		&& no_ternary {
		return c.upt_merge(t, tokens, UptMerge{
			before:     '${m.before}yield${if delegate { '*' } else { '' }} ('
			after:      ')${m.after}'
			consequent: upt_argument(t, consequent)
			alternate:  upt_argument(t, alternate)
		}, node, false)
	}
	if typ == .await_expression && no_ternary {
		return c.upt_merge(t, tokens, UptMerge{
			before:     '${m.before}await ('
			after:      ')${m.after}'
			consequent: UptOperand{
				node: argument
			}
			alternate:  UptOperand{
				node: alternate_argument
			}
		}, node, false)
	}
	if top && typ == .throw_statement && no_ternary {
		// A `throw` is not checked when nested. An `if` that is not in a block takes `{}`.
		parent := t.nodes[node].parent
		need_braces := parent >= 0 && t.typ(parent) != .block_statement
		return UptMerge{
			throw_:     true
			before:     '${m.before}${if need_braces { '{\n{{INDENT_STRING}}' } else { '' }}const {{ERROR_NAME}} = '
			after:      ';\n{{INDENT_STRING}}throw {{ERROR_NAME}};${if need_braces { '\n}' } else { '' }}'
			consequent: UptOperand{
				node: argument
			}
			alternate:  UptOperand{
				node: alternate_argument
			}
		}
	}
	if typ == .assignment_expression {
		operator := t.string_of(consequent, .operator) or { '' }
		left := t.node(consequent, .left) or { -1 }
		right := t.node(consequent, .right) or { -1 }
		alternate_left := t.node(alternate, .left) or { -1 }
		alternate_right := t.node(alternate, .right) or { -1 }
		if operator == t.string_of(alternate, .operator) or { '' } && !upt_is_ternary(t, left)
			&& !upt_is_ternary(t, alternate_left) && !upt_is_ternary(t, right)
			&& !upt_is_ternary(t, alternate_right)
			&& c.un_is_same_reference(t, left, alternate_left) {
			return c.upt_merge(t, tokens, UptMerge{
				before:     '${m.before}${c.un_parenthesized_text(t, tokens, left)} ${operator} '
				after:      m.after
				consequent: UptOperand{
					node: right
				}
				alternate:  UptOperand{
					node: alternate_right
				}
			}, node, false)
		}
	}
	if top {
		return none
	}
	return m
}

// upt_text ports getText: the node with its parentheses, and parentheses it needs as a branch.
fn (c &Checker) upt_text(t &estree.EsTree, tokens &SourceTokens, operand UptOperand) string {
	if operand.node < 0 {
		return operand.text
	}
	node := operand.node
	mut text := c.un_parenthesized_text(t, tokens, node)
	if !c.un_is_parenthesized(t, tokens, node) && t.typ(node) in [.await_expression,
		.assignment_expression, .yield_expression, .sequence_expression, .ts_as_expression,
		.ts_type_assertion] {
		text = '(${text})'
	}
	return text
}

fn upt_single_line(t &estree.EsTree, node int) bool {
	start_line, _ := t.line_column(t.nodes[node].start)
	end_line, _ := t.line_column(t.nodes[node].end)
	return start_line == end_line
}

fn (mut c Checker) lint_unicorn_prefer_ternary(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	only_single_line := upt_options(c.rule_options(unicorn_prefer_ternary))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// The names the fixes gave to new variables, by scope.
	mut generated := map[int][]string{}
	for node in un_enter_order(t) {
		if t.typ(node) != .if_statement {
			continue
		}
		stats.checked++
		parent := t.nodes[node].parent
		test := t.node(node, .test) or { continue }
		if (t.typ(parent) == .if_statement && t.node(parent, .alternate) or { -1 } == node)
			|| t.typ(test) == .conditional_expression {
			continue
		}
		consequent_node := t.node(node, .consequent) or { continue }
		alternate_node := t.node(node, .alternate) or { continue }
		consequent := upt_body(t, consequent_node)
		alternate := upt_body(t, alternate_node)
		if only_single_line && [consequent, alternate, test].any(!upt_single_line(t, it)) {
			continue
		}
		result := c.upt_merge(t, tokens, UptMerge{
			consequent: UptOperand{
				node: consequent
			}
			alternate:  UptOperand{
				node: alternate
			}
		}, node, true) or { continue }
		// No fix when there are comments.
		if tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len > 0 {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'prefer-ternary'
			}
			continue
		}
		mut before := result.before
		mut after := result.after
		if result.throw_ {
			tree := c.scope_tree(root)
			scopes := un_scopes(tree, tree.get_scope(t.ts_node(node) or { continue }))
			taken := generated.clone()
			error_name := un_available_variable_name(tree, 'error', scopes, fn [scopes, taken] (name string) bool {
				return scopes.all(name !in (taken[it] or { []string{} }))
			}) or { continue }
			for scope in scopes {
				mut scope_names := generated[scope] or { []string{} }
				if error_name !in scope_names {
					scope_names << error_name
				}
				generated[scope] = scope_names
			}
			indent := c.un_indent_string(t, node)
			after = after.replace_once('{{INDENT_STRING}}', indent).replace_once('{{ERROR_NAME}}',
				error_name)
			before = before.replace_once('{{INDENT_STRING}}', indent).replace_once('{{ERROR_NAME}}',
				error_name)
		}
		mut fixed := '${before}${c.upt_text(t, tokens, UptOperand{ node: test })} ? ${c.upt_text(t,
			tokens, result.consequent)} : ${c.upt_text(t, tokens, result.alternate)}${after}'
		if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), fixed) {
			fixed = ';${fixed}'
		}
		mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)]
		if result.throw_ {
			// extendFixRange to the whole program.
			fixes << fix_insert_at(t.nodes[t.root].start, '')
			fixes << fix_insert_at(t.nodes[t.root].end, '')
		}
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-ternary'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
