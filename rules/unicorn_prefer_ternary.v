module rules

import estree
import json2
import time
import treesitter

// Port of the `unicorn/prefer-ternary` rule of eslint-plugin-unicorn 79.0.0, with its fix and its
// suggestions. Branches that share a shape with one varying part become a minimal ternary
// (shared/minimal-ternary.js, the unb_minimal_* helpers of unicorn_utils_b.v), and a `let` with an
// initializer followed by an `if` that reassigns it gets a suggestion. It reads types through
// withTypeInformation: the targets of merged assignments, the branches of a minimal ternary, and a
// `let` without a type annotation is not reported when there is type information.

const upt_messages = {
	'prefer-ternary':            'This `if` statement can be replaced by a ternary expression.'
	'prefer-ternary/suggestion': 'Use a ternary expression.'
}

// UptOptions are the options of the rule: 'always' or 'only-single-line', and the options of
// minimalTernaryOptionsSchema.
struct UptOptions {
	only_single_line bool
	minimal          UnbMinimalOptions
}

fn upt_options(options []json2.Any) !UptOptions {
	mut only_single_line := false
	if options.len > 0 {
		value := options[0]
		only_single_line = value is string && value == 'only-single-line'
	}
	return UptOptions{
		only_single_line: only_single_line
		minimal:          if options.len > 1 {
			unb_minimal_options(unicorn_prefer_ternary, options[1..])!
		} else {
			UnbMinimalOptions{}
		}
	}
}

// UptMerge is what merge gives: the text before the ternary and its two branches.
struct UptMerge {
	before     string
	consequent int
	alternate  int
}

// UptMinimal is what getMinimalBranches gives: the branches of a minimal ternary under the
// `throw`, `await` and `yield` they share.
struct UptMinimal {
	consequent int
	alternate  int
	wrappers   []int
}

// upt_has_ternary ports hasTernary: a ternary in the node, not inside a function or a class.
fn upt_has_ternary(t &estree.EsTree, node int) bool {
	if t.typ(node) == .conditional_expression {
		return true
	}
	// Functions and classes have their own ternary nesting context.
	if unb_is_function(t, node) || t.typ(node) in [.class_expression, .class_declaration] {
		return false
	}
	return t.children(node).any(upt_has_ternary(t, it))
}

// upt_has_complex_structure ports hasComplexStructure: a statement or class body, or a multiline
// object, array, JSX element or template literal, in the node.
fn upt_has_complex_structure(t &estree.EsTree, node int) bool {
	if t.typ(node) in [.block_statement, .class_body] {
		return true
	}
	if t.typ(node) in [.object_expression, .array_expression, .jsx_element, .jsx_fragment,
		.template_literal] && !upt_single_line(t, node) {
		return true
	}
	return t.children(node).any(upt_has_complex_structure(t, it))
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

fn upt_single_line(t &estree.EsTree, node int) bool {
	start_line, _ := t.line_column(t.nodes[node].start)
	end_line, _ := t.line_column(t.nodes[node].end)
	return start_line == end_line
}

fn upt_is_arrow_function(t &estree.EsTree, node int) bool {
	return t.typ(unb_unwrap_ts(t, node)) == .arrow_function_expression
}

fn upt_is_boolean_literal(t &estree.EsTree, node int) bool {
	return t.typ(node) == .literal && t.get(node, .value) is bool
}

// upt_is_mergeable_return_statement ports isMergeableReturnStatement: bare returns stay explicit
// exits.
fn upt_is_mergeable_return_statement(t &estree.EsTree, consequent int, alternate int) bool {
	if t.typ(consequent) != .return_statement || t.typ(alternate) != .return_statement {
		return false
	}
	consequent_argument := t.node(consequent, .argument) or { return false }
	alternate_argument := t.node(alternate, .argument) or { return false }
	return !upt_has_ternary(t, consequent_argument) && !upt_has_ternary(t, alternate_argument)
		&& !(upt_is_boolean_literal(t, consequent_argument)
			&& upt_is_boolean_literal(t, alternate_argument))
}

// upt_has_same_assignment_target_types ports hasSameAssignmentTargetTypes: the targets and what is
// inside them have the same types (but the pattern containers, whose types are synthesized).
fn (mut c Checker) upt_has_same_assignment_target_types(t &estree.EsTree, consequent int, alternate int, mut ctx UnbTypeContext) bool {
	if alternate < 0 {
		return false
	}
	if t.typ(consequent) !in [.array_pattern, .object_pattern, .rest_element, .property,
		.assignment_pattern] {
		if consequent_type := c.unb_type_of(t, consequent, ctx.abs_path, mut ctx.stats) {
			if alternate_type := c.unb_type_of(t, alternate, ctx.abs_path, mut ctx.stats) {
				if consequent_type.id != alternate_type.id {
					return false
				}
			}
		}
	}
	alternate_children := t.children(alternate)
	for index, child in t.children(consequent) {
		if !c.upt_has_same_assignment_target_types(t, child, if index < alternate_children.len {
			alternate_children[index]
		} else {
			-1
		}, mut ctx) {
			return false
		}
	}
	return true
}

// upt_is_mergeable_assignment_expression ports isMergeableAssignmentExpression: `=` assignments to
// the same identifier, or to the same destructuring pattern, whose target types are the same.
fn (mut c Checker) upt_is_mergeable_assignment_expression(t &estree.EsTree, tokens &SourceTokens, consequent int, alternate int, mut ctx UnbTypeContext) bool {
	if t.typ(consequent) != .assignment_expression || t.typ(alternate) != .assignment_expression {
		return false
	}
	// Keep member target evaluation and compound/logical reads after the condition.
	if t.string_of(consequent, .operator) or { '' } != '='
		|| t.string_of(alternate, .operator) or { '' } != '=' {
		return false
	}
	consequent_left := t.node(consequent, .left) or { return false }
	alternate_left := t.node(alternate, .left) or { return false }
	consequent_right := t.node(consequent, .right) or { return false }
	alternate_right := t.node(alternate, .right) or { return false }
	if upt_has_ternary(t, consequent_right) || upt_has_ternary(t, alternate_right) {
		return false
	}
	// Direct arrow assignments infer their names from the identifier target.
	same_identifier := t.typ(unb_unwrap_ts(t, consequent_left)) == .identifier
		&& !upt_is_arrow_function(t, consequent_right) && !upt_is_arrow_function(t, alternate_right)
		&& c.unb_is_same_reference(t, consequent_left, alternate_left)
	// Token matching ignores line breaks, which can change statement semantics.
	same_pattern := !same_identifier && t.typ(consequent_left) == t.typ(alternate_left)
		&& t.typ(consequent_left) in [.array_pattern, .object_pattern]
		&& !upt_has_complex_structure(t, consequent_left)
		&& !upt_has_complex_structure(t, alternate_left)
		&& c.unb_is_same_tokens(unb_node_tokens(t, tokens, consequent_left), unb_node_tokens(t,
			tokens, alternate_left))
	if !same_identifier && !same_pattern {
		return false
	}
	// Moving the target outside the branches can lose narrowed contextual types.
	if !c.scope_setup.type_information {
		return true
	}
	return c.unb_is_same_tokens(unb_node_tokens(t, tokens, consequent_left), unb_node_tokens(t,
		tokens, alternate_left))
		&& c.upt_has_same_assignment_target_types(t, consequent_left, alternate_left, mut ctx)
}

// upt_merge ports merge: `return a` and `return b` become `return test ? a : b`, and the same for
// `=` assignments to the same target. With `return_false`, none when the branches cannot be
// merged at all.
fn (mut c Checker) upt_merge(t &estree.EsTree, tokens &SourceTokens, before string, consequent int, alternate int, return_false bool, mut ctx UnbTypeContext) ?UptMerge {
	if t.typ(consequent) != t.typ(alternate) {
		if return_false {
			return none
		}
		return UptMerge{before, consequent, alternate}
	}
	if upt_is_mergeable_return_statement(t, consequent, alternate) {
		return c.upt_merge(t, tokens, '${before}return ', t.node(consequent, .argument)?,
			t.node(alternate, .argument)?, false, mut ctx)
	}
	if c.upt_is_mergeable_assignment_expression(t, tokens, consequent, alternate, mut ctx) {
		left := t.node(consequent, .left)?
		operator := t.string_of(consequent, .operator)?
		next_before := '${before}${c.un_parenthesized_text(t, tokens, left)} ${operator} '
		consequent_right := t.node(consequent, .right)?
		alternate_right := t.node(alternate, .right)?
		// Destructuring evaluates its RHS before its targets; keep nested assignments after the condition.
		if t.typ(left) in [.array_pattern, .object_pattern] {
			return UptMerge{next_before, consequent_right, alternate_right}
		}
		return c.upt_merge(t, tokens, next_before, consequent_right, alternate_right, false, mut
			ctx)
	}
	if return_false {
		return none
	}
	return UptMerge{before, consequent, alternate}
}

// upt_minimal_branches ports getMinimalBranches: the branches under the `throw`, `await` and
// `yield` they share, when they make a minimal ternary.
fn (mut c Checker) upt_minimal_branches(t &estree.EsTree, tokens &SourceTokens, consequent_node int, alternate_node int, o UnbMinimalOptions, mut ctx UnbTypeContext) ?UptMinimal {
	mut consequent := consequent_node
	mut alternate := alternate_node
	mut wrappers := []int{}
	for t.typ(consequent) == t.typ(alternate)
		&& t.typ(consequent) in [.throw_statement, .await_expression, .yield_expression] {
		consequent_argument := t.node(consequent, .argument) or { break }
		alternate_argument := t.node(alternate, .argument) or { break }
		if (t.flag(consequent, .delegate) or { false }) != (t.flag(alternate, .delegate) or {
			false
		}) {
			break
		}
		wrappers << consequent
		consequent = consequent_argument
		alternate = alternate_argument
	}
	if c.unb_is_minimal_ternary(t, tokens, consequent, alternate, o, mut ctx) {
		return UptMinimal{consequent, alternate, wrappers}
	}
	return none
}

// upt_text ports getText: getConditionalExpressionChildText, and parentheses for an arrow function
// that is the test of the `if`.
fn (c &Checker) upt_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	text := c.unb_conditional_child_text(t, tokens, node)
	parent := t.nodes[node].parent
	if t.typ(node) == .arrow_function_expression && parent >= 0 && t.typ(parent) == .if_statement
		&& !c.un_is_parenthesized(t, tokens, node) {
		return '(${text})'
	}
	return text
}

fn upt_reference_inside(reference ScopeReference, t &estree.EsTree, target int) bool {
	return treesitter.node_start(reference.identifier) >= t.nodes[target].start
		&& treesitter.node_end(reference.identifier) <= t.nodes[target].end
}

// upt_let_plus_if_problem ports getLetPlusIfProblem: an initialized `let` followed by one
// conditional reassignment, with a suggestion.
fn (mut c Checker) upt_let_plus_if_problem(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, node int, o UptOptions, mut ctx UnbTypeContext) ![]Finding {
	consequent_body := upt_body(t, t.node(node, .consequent) or { return []Finding{} })
	if t.typ(consequent_body) != .assignment_expression
		|| t.string_of(consequent_body, .operator) or { '' } != '=' {
		return []Finding{}
	}
	left := t.node(consequent_body, .left) or { return []Finding{} }
	right := t.node(consequent_body, .right) or { return []Finding{} }
	if t.typ(left) != .identifier {
		return []Finding{}
	}
	previous := unb_sibling(t, node, -1)
	if previous < 0 || t.typ(previous) != .variable_declaration
		|| t.string_of(previous, .kind) or { '' } != 'let'
		|| (t.list(previous, .declarations) or { []int{} }).len != 1 {
		return []Finding{}
	}
	declarator := (t.list(previous, .declarations) or { return []Finding{} })[0]
	id := t.node(declarator, .id) or { return []Finding{} }
	if t.typ(id) != .identifier || t.string_of(id, .name) or { '' } != t.string_of(left, .name) or {
		''
	} {
		return []Finding{}
	}
	init := t.node(declarator, .init) or { return []Finding{} }
	// Inferred declaration types can lose contextual typing after introducing a ternary.
	if (c.scope_setup.type_information && t.node(id, .type_annotation) == none)
		|| upt_is_arrow_function(t, init) || upt_is_arrow_function(t, right) {
		return []Finding{}
	}
	test := t.node(node, .test) or { return []Finding{} }
	for expression in [test, right, init] {
		if upt_has_ternary(t, expression) || upt_has_complex_structure(t, expression)
			|| (o.only_single_line && !upt_single_line(t, expression)) {
			return []Finding{}
		}
	}
	// The rewrite builds `test ? right : init`, so the initializer moves from before the test to after it. A test with a side effect would observe the change.
	if unb_has_side_effect(t, init, false) || unb_has_side_effect(t, test, false) {
		return []Finding{}
	}
	// The `let` declaration right before the `if` declares it
	v := c.unb_find_variable(root, t, left)
	if v < 0 {
		return []Finding{}
	}
	tree := c.scope_tree(root)
	references := tree.variables[v].references.map(tree.references[it])
	if references.any(upt_reference_inside(it, t, test) || upt_reference_inside(it, t, right)) {
		return []Finding{}
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'prefer-ternary'
	}
	// Report commented decisions without offering edits that would remove comments.
	if c.unb_would_remove_comments(tokens, UnbRange{t.nodes[previous].start, t.nodes[node].end}, []UnbRange{},
		false) {
		return [finding]
	}
	has_other_writes := references.any(!it.init && it.write && !upt_reference_inside(it, t, node))
	ternary := '${c.upt_text(t, tokens, test)} ? ${c.upt_text(t, tokens, right)} : ${c.upt_text(t, tokens, init)}'
	let_token := tokens.after(t.nodes[previous].start, false) or { return [finding] }
	init_start, init_end := c.un_parenthesized_range(t, tokens, init)
	mut add_semicolon := false
	if next_token := tokens.after(t.nodes[node].end, false) {
		add_semicolon = c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[previous].end,
			false), c.token_text(next_token))
	}
	_, fix := c.merge_fixes([
		fix_replace_range(let_token.start, let_token.end, if has_other_writes {
			'let'
		} else {
			'const'
		}),
		fix_replace_range(init_start, init_end, ternary),
		fix_replace_range(t.nodes[previous].end, t.nodes[node].end, if add_semicolon {
			';'
		} else {
			''
		}),
	])!
	return [
		Finding{
			...finding
			suggestions: [
				Suggestion{
					message_id: 'prefer-ternary/suggestion'
					fix:        fix
				},
			]
		},
	]
}

// upt_is_let_bracket is /^let\s*\[/u: a statement that would start like a `let` declaration.
fn upt_is_let_bracket(text string) bool {
	if !text.starts_with('let') {
		return false
	}
	return text[3..].trim_left(' \t\n\r\v\f ﻿  ').starts_with('[')
}

// upt_fix ports the fix of getIfBranchesProblem: none where it aborts.
fn (c &Checker) upt_fix(t &estree.EsTree, tokens &SourceTokens, node int, replacement UnbRange, consequent int, result ?UptMerge, minimal ?UptMinimal, is_type_safe bool) ?Fix {
	test := t.node(node, .test)?
	mut fixed := ?string(none)
	if m := minimal {
		if result == none || is_type_safe {
			fixed = c.unb_minimal_expression_text(t, tokens, m.consequent, m.alternate, test)
		}
	}
	if f := fixed {
		if upt_is_let_bracket(f) {
			fixed = none
		}
	}
	mut text := ''
	if f := fixed {
		m := minimal?
		text = f
		for i := m.wrappers.len - 1; i >= 0; i-- {
			wrapper := m.wrappers[i]
			if t.typ(wrapper) == .await_expression {
				text = if unb_should_add_parens_to_await_argument(t, t.node(wrapper, .argument)?) {
					'await (${text})'
				} else {
					'await ${text}'
				}
			} else if t.typ(wrapper) == .yield_expression {
				text = 'yield${if t.flag(wrapper, .delegate) or { false } { '*' } else { '' }} ${text}'
			} else {
				text = 'throw ${text}'
			}
		}
		if result == none && m.wrappers.len == 0 && t.typ(m.consequent) == .object_expression {
			text = '(${text})'
		}
		before := if r := result { r.before } else { '' }
		text = '${before}${text}'
	} else {
		r := result?
		text = '${r.before}${c.upt_text(t, tokens, test)} ? ${c.upt_text(t, tokens, r.consequent)} : ${c.upt_text(t, tokens, r.alternate)}'
	}
	if t.typ(consequent) == .assignment_expression
		&& t.typ(t.node(consequent, .left) or { consequent }) == .object_pattern {
		text = '(${text})'
	}
	text += ';'
	if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), text) {
		text = ';${text}'
	}
	return fix_replace_range(replacement.start, replacement.end, text)
}

// upt_if_branches_problem ports getIfBranchesProblem: an `if` with an `else`, or followed by a
// `return` (`alternate_node`).
fn (mut c Checker) upt_if_branches_problem(t &estree.EsTree, tokens &SourceTokens, node int, alternate_node int, o UptOptions, mut ctx UnbTypeContext) []Finding {
	parent := t.nodes[node].parent
	test := t.node(node, .test) or { return []Finding{} }
	if (parent >= 0 && t.typ(parent) == .if_statement && t.node(parent, .alternate) or { -1 } == node)
		|| upt_has_ternary(t, test) {
		return []Finding{}
	}
	consequent := upt_body(t, t.node(node, .consequent) or { return []Finding{} })
	alternate := upt_body(t, alternate_node)
	if o.only_single_line && [consequent, alternate, test].any(!upt_single_line(t, it)) {
		return []Finding{}
	}
	result := c.upt_merge(t, tokens, '', consequent, alternate, true, mut ctx)
	mut branch_consequent := consequent
	mut branch_alternate := alternate
	if r := result {
		branch_consequent = r.consequent
		branch_alternate = r.alternate
	}
	minimal := c.upt_minimal_branches(t, tokens, branch_consequent, branch_alternate, o.minimal, mut
		ctx)
	if (result == none && minimal == none)
		|| [test, branch_consequent, branch_alternate].any(upt_has_complex_structure(t, it))
		|| (result == none && [consequent, alternate].any(upt_has_ternary(t, it))) {
		return []Finding{}
	}
	is_flat_return := t.node(node, .alternate) == none
	replacement := if is_flat_return {
		UnbRange{t.nodes[node].start, t.nodes[alternate_node].end}
	} else {
		unb_node_range(t, node)
	}
	mut comment_range := replacement
	if is_flat_return {
		if trailing_comment := c.unb_last_trailing_comment_on_same_line(t, tokens, alternate_node) {
			comment_range = UnbRange{replacement.start, trailing_comment.end}
		}
	}
	mut is_type_safe := false
	if m := minimal {
		is_type_safe = c.unb_is_type_safe_to_minimize(t, tokens, m.consequent, m.alternate, mut
			ctx)
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'prefer-ternary'
	}
	// Report commented decisions without offering edits that would remove comments.
	if c.unb_would_remove_comments(tokens, comment_range, []UnbRange{}, false) {
		return [finding]
	}
	if result != none || is_type_safe {
		if fix := c.upt_fix(t, tokens, node, replacement, consequent, result, minimal, is_type_safe) {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		}
	} else if m := minimal {
		if t.typ(m.consequent) == .object_expression {
			if fix := c.upt_fix(t, tokens, node, replacement, consequent, result, minimal,
				is_type_safe)
			{
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'prefer-ternary/suggestion'
							fix:        fix
						},
					]
				}
			}
		}
	}
	return [finding]
}

fn (mut c Checker) lint_unicorn_prefer_ternary(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := upt_options(c.rule_options(unicorn_prefer_ternary))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in un_enter_order(t) {
		if t.typ(node) != .if_statement {
			continue
		}
		stats.checked++
		if alternate := t.node(node, .alternate) {
			findings << c.upt_if_branches_problem(t, tokens, node, alternate, o, mut ctx)
			continue
		}
		previous := unb_sibling(t, node, -1)
		if previous >= 0 && t.typ(previous) == .if_statement
			&& t.node(previous, .alternate) == none
			&& t.typ(upt_body(t, t.node(previous, .consequent) or { previous })) == .return_statement {
			continue
		}
		next := unb_sibling(t, node, 1)
		mut problems := []Finding{}
		if next >= 0 && t.typ(next) == .return_statement {
			problems = c.upt_if_branches_problem(t, tokens, node, next, o, mut ctx)
		}
		if problems.len == 0 {
			problems = c.upt_let_plus_if_problem(root, t, tokens, node, o, mut ctx)!
		}
		findings << problems
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
