module rules

import estree
import time

// Port of the `unicorn/prefer-logical-operator-over-ternary` rule of eslint-plugin-unicorn 79.0.0
// (it has no options), with its suggestions. It reads types through withTypeInformation and isBoolean
// (utils/is-boolean.js). The fix of a boolean ternary (`a ? true : b` to `Boolean(a) || b`) is only
// given outside TypeScript files (canFixBooleanTernary), so never in veslint; it is ported anyway.

const uploot_messages = {
	'prefer-logical-operator-over-ternary/error':                     'Prefer using a logical operator over a ternary.'
	'prefer-logical-operator-over-ternary/optional-chain-error':      'Prefer using optional chaining over a ternary.'
	'prefer-logical-operator-over-ternary/suggestion':                'Switch to `{{operator}}` operator.'
	'prefer-logical-operator-over-ternary/optional-chain-suggestion': 'Switch to optional chaining.'
}

// uploot_fix ports fix: `left operator right` in place of the conditional expression.
fn (c &Checker) uploot_fix(t &estree.EsTree, tokens &SourceTokens, conditional int, left int, right int, operator string, negate_left bool, coerce_left bool) !Fix {
	mut parts := []string{}
	for index, node in [left, right] {
		parts << if index == 0 && negate_left {
			c.unb_negated_expression_text(t, tokens, node)
		} else if index == 0 && coerce_left {
			'Boolean(${c.unb_call_argument_text(t, tokens, node)})'
		} else {
			c.unb_logical_child_text(t, tokens, node, operator)
		}
	}
	mut text := parts.join(' ${operator} ')
	// Switching a ternary to a logical expression preserves precedence, but removing a leading
	// negation or comparison can expose a block or declaration prefix.
	if !negate_left && !coerce_left && !c.un_is_parenthesized(t, tokens, left)
		&& !un_logical_child_needs_parens(t, left, operator)
		&& c.unb_should_add_parens_to_expression_start(t, tokens, left, conditional) {
		text = '(${text})'
	}
	// ASI
	if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[conditional].start, false), text) {
		text = ';${text}'
	}
	mut fixes := c.unb_fix_space_around_keyword(t, tokens, conditional)
	fixes << fix_replace_range(t.nodes[conditional].start, t.nodes[conditional].end, text)
	_, fix := c.merge_fixes(fixes)!
	return fix
}

// uploot_boolean_literal_type_value ports getBooleanLiteralTypeValue: 1 for `true`, 0 for
// `false`, -1 for any other type.
fn uploot_boolean_literal_type_value(t &estree.EsTree, n int) int {
	mut node := n
	if node >= 0 && t.typ(node) == .ts_type_annotation {
		node = t.node(node, .type_annotation) or { -1 }
	}
	if node < 0 || t.typ(node) != .ts_literal_type {
		return -1
	}
	value := t.get(t.node(node, .literal) or { return -1 }, .value)
	return if value is bool { uploot_bool_int(value) } else { -1 }
}

fn uploot_bool_int(value bool) int {
	return if value { 1 } else { 0 }
}

// uploot_is_const_assertion ports isConstAssertion: the `const` of `as const`.
fn uploot_is_const_assertion(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .ts_type_reference {
		return false
	}
	name := t.node(node, .type_name) or { return false }
	return t.typ(name) == .identifier && (t.string_of(name, .name) or { '' }) == 'const'
}

// uploot_constant_variable_definition ports getConstantVariableDefinition: the only definition of
// the variable of the identifier, a `const` of it with an initializer declared before it in the
// same function (not in a `switch`).
fn (mut c Checker) uploot_constant_variable_definition(root C.vt_node, t &estree.EsTree, node int) ?ScopeDefinition {
	tree := c.scope_tree(root)
	scope := c.unb_scope_of(root, t, node)
	v := c.unb_find_variable(root, t, node)
	def := c.unb_single_definition(root, v)?
	if def.kind != .variable || def.parent_kind != 'const' || !unb_is_simple_declarator(def)
		|| def.init == none {
		return none
	}
	variable_scope := tree.variables[v].scope
	if tree.scopes[scope].variable_scope != tree.scopes[variable_scope].variable_scope
		|| tree.scopes[variable_scope].kind == .switch_statement {
		return none
	}
	declarator := c.es_index_of(t, def.node)?
	if t.nodes[declarator].end > t.nodes[node].start {
		return none
	}
	return def
}

// uploot_unwrap_constant_aliases ports unwrapConstantAliases: the initializer of the constants
// the identifier stands for.
fn (mut c Checker) uploot_unwrap_constant_aliases(root C.vt_node, t &estree.EsTree, n int) int {
	mut node := n
	for t.typ(node) == .identifier {
		def := c.uploot_constant_variable_definition(root, t, node) or { break }
		node = c.es_index_of(t, def.init or { break }) or { break }
	}
	return node
}

// uploot_boolean_constant_value ports getBooleanConstantValue: the boolean a branch always is,
// through type assertions (which must agree with it), TypeScript's type of an identifier and
// constants.
fn (mut c Checker) uploot_boolean_constant_value(t &estree.EsTree, n int, mut ctx UnbTypeContext) ?bool {
	mut node := n
	mut annotations := []int{}
	for node >= 0 {
		if t.typ(node) == .literal {
			value := t.get(node, .value)
			if value is bool {
				if annotations.any(uploot_boolean_literal_type_value(t, it) != uploot_bool_int(value)) {
					return none
				}
				return value
			}
		}
		if t.typ(node) in [.ts_non_null_expression, .ts_satisfies_expression] {
			node = t.node(node, .expression) or { return none }
			continue
		}
		if t.typ(node) in [.ts_as_expression, .ts_type_assertion] {
			annotation := t.node(node, .type_annotation) or { -1 }
			if !uploot_is_const_assertion(t, annotation) {
				annotations << annotation
			}
			node = t.node(node, .expression) or { return none }
			continue
		}
		if t.typ(node) != .identifier {
			return none
		}
		if typ := c.unb_type_of(t, node, ctx.abs_path, mut ctx.stats) {
			name := c.type_string(typ) or { '' }
			if name in ['true', 'false'] {
				value := name == 'true'
				return if annotations.all(uploot_boolean_literal_type_value(t, it) == uploot_bool_int(value)) {
					value
				} else {
					none
				}
			}
		}
		def := c.uploot_constant_variable_definition(ctx.root, t, node) or { return none }
		if name := c.es_index_of(t, def.name) {
			if annotation := t.node(name, .type_annotation) {
				annotations << annotation
			}
		}
		node = c.es_index_of(t, def.init or { return none }) or { return none }
	}
	return none
}

// uploot_in_with_statement: an ancestor of the node is a `with` statement.
fn uploot_in_with_statement(t &estree.EsTree, node int) bool {
	for parent := t.nodes[node].parent; parent >= 0; parent = t.nodes[parent].parent {
		if t.typ(parent) == .with_statement {
			return true
		}
	}
	return false
}

// uploot_is_boolean_ternary_expression ports isBooleanTernaryExpression: isBoolean, false where
// it overflows the stack.
fn (mut c Checker) uploot_is_boolean_ternary_expression(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	return c.unb_is_boolean(t, node, mut ctx) or { false }
}

// uploot_boolean_ternary_problem ports getBooleanTernaryProblem: `a ? true : b` and `a ? b : false`
// where `b` is a boolean.
// (whether there is one, the problem)
fn (mut c Checker) uploot_boolean_ternary_problem(t &estree.EsTree, tokens &SourceTokens, conditional int, mut ctx UnbTypeContext) !(bool, Finding) {
	if uploot_in_with_statement(t, conditional) {
		return false, Finding{}
	}
	test := t.node(conditional, .test) or { return false, Finding{} }
	consequent := t.node(conditional, .consequent) or { return false, Finding{} }
	alternate := t.node(conditional, .alternate) or { return false, Finding{} }
	consequent_value := c.uploot_boolean_constant_value(t, consequent, mut ctx)
	alternate_value := c.uploot_boolean_constant_value(t, alternate, mut ctx)
	is_consequent_boolean_constant := consequent_value != none
	if is_consequent_boolean_constant == (alternate_value != none) {
		return false, Finding{}
	}
	boolean_value := consequent_value or { alternate_value or { false } }
	right := if is_consequent_boolean_constant { alternate } else { consequent }
	// Keep potentially non-boolean results explicit instead of hiding them behind a logical
	// operator.
	if !c.uploot_is_boolean_ternary_expression(t, right, mut ctx) {
		return false, Finding{}
	}
	negate_left := (consequent_value or { true }) == false || (alternate_value or { false }) == true
	// canFixBooleanTernary: never in a TypeScript file.
	can_fix := false
	mut finding := Finding{
		stmt:       c.es_tree_position(t, conditional)
		message_id: 'prefer-logical-operator-over-ternary/error'
	}
	if can_fix && !c.unb_would_remove_comments(tokens, unb_node_range(t, conditional), [
		c.unb_parenthesized_range(t, tokens, test),
		c.unb_parenthesized_range(t, tokens, right),
	], false) {
		coerce_left := !negate_left && !c.uploot_is_boolean_ternary_expression(t,
			c.uploot_unwrap_constant_aliases(ctx.root, t, test), mut ctx)
		finding = Finding{
			...finding
			has_fix: true
			fix:     c.uploot_fix(t, tokens, conditional, test, right, if boolean_value {
				'||'
			} else {
				'&&'
			}, negate_left, coerce_left)!
		}
	}
	return true, finding
}

// uploot_optional_chain_text ports getOptionalChainText: the member expression with `?.` (or
// `?.[`) in place of its access operator.
fn (c &Checker) uploot_optional_chain_text(t &estree.EsTree, tokens &SourceTokens, member int) string {
	operator_start, operator_end := c.unb_member_access_operator_range(t, tokens, member)
	return c.src[t.nodes[member].start..operator_start] + if t.flag(member, .computed) or { false } {
		'?.['
	} else {
		'?.'
	} + c.src[operator_end..t.nodes[member].end]
}

// uploot_problem ports getProblem: the suggestions of `left operator right`, none when they would
// drop a comment of the ternary.
fn (c &Checker) uploot_problem(t &estree.EsTree, tokens &SourceTokens, conditional int, left int, right int, operators []string) !Finding {
	position := c.es_tree_position(t, conditional)
	if c.unb_would_remove_comments(tokens, unb_node_range(t, conditional), [
		c.unb_parenthesized_range(t, tokens, left),
		c.unb_parenthesized_range(t, tokens, right),
	], false) {
		return Finding{
			stmt:       position
			message_id: 'prefer-logical-operator-over-ternary/error'
		}
	}
	mut suggestions := []Suggestion{}
	for operator in operators {
		suggestions << Suggestion{
			message_id: 'prefer-logical-operator-over-ternary/suggestion'
			data:       {
				'operator': operator
			}
			fix:        c.uploot_fix(t, tokens, conditional, left, right, operator, false, false)!
		}
	}
	return Finding{
		stmt:        position
		message_id:  'prefer-logical-operator-over-ternary/error'
		suggestions: suggestions
	}
}

// uploot_is_unsafe_optional_chain_replacement_context ports
// isUnsafeOptionalChainReplacementContext: the ternary (through TypeScript wrappers) is deleted,
// called or a tag, where an optional chain would behave differently.
fn uploot_is_unsafe_optional_chain_replacement_context(t &estree.EsTree, conditional int) bool {
	node := unb_outermost_ts(t, conditional)
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return (t.typ(parent) == .unary_expression && (t.string_of(parent, .operator) or { '' }) == 'delete'
		&& t.node(parent, .argument) or { -1 } == node)
		|| (t.typ(parent) == .call_expression && t.node(parent, .callee) or { -1 } == node)
		|| (t.typ(parent) == .tagged_template_expression && t.node(parent, .tag) or { -1 } == node)
}

// uploot_nullish_ternary_problem ports getNullishTernaryProblem: `a == null ? b : a` and
// `a == null ? undefined : a.b`: (whether there is one, the problem).
fn (mut c Checker) uploot_nullish_ternary_problem(t &estree.EsTree, tokens &SourceTokens, conditional int) !(bool, Finding) {
	test := t.node(conditional, .test) or { return false, Finding{} }
	consequent := t.node(conditional, .consequent) or { return false, Finding{} }
	alternate := t.node(conditional, .alternate) or { return false, Finding{} }
	nullish_test := c.unb_nullish_test(t, test) or { return false, Finding{} }
	reference := nullish_test.reference
	// The test and the branch can spell the same reference differently, for example
	// `b?.c == null ? undefined : b.c`. The test's spelling is the safe one to keep.
	if nullish_test.is_true_when_nullish && c.unb_is_same_node(t, reference, alternate) {
		return true, c.uploot_problem(t, tokens, conditional, reference, consequent, ['??'])!
	}
	if !nullish_test.is_true_when_nullish && c.unb_is_same_node(t, reference, consequent) {
		return true, c.uploot_problem(t, tokens, conditional, reference, alternate, ['??'])!
	}
	nullish_branch := if nullish_test.is_true_when_nullish { consequent } else { alternate }
	non_nullish_branch := if nullish_test.is_true_when_nullish { alternate } else { consequent }
	if !un_is_undefined(t, nullish_branch) || t.typ(non_nullish_branch) != .member_expression
		|| (t.flag(non_nullish_branch, .optional) or { false })
		|| !c.unb_is_same_reference(t, unb_unwrap_ts(t, reference), unb_unwrap_ts(t, t.node(non_nullish_branch,
			.object) or { return false, Finding{} }))
		|| uploot_is_unsafe_optional_chain_replacement_context(t, conditional) {
		return false, Finding{}
	}
	mut text := c.uploot_optional_chain_text(t, tokens, non_nullish_branch)
	position := c.es_tree_position(t, conditional)
	// getCommentSafeProblem
	if c.unb_would_remove_comments(tokens, unb_node_range(t, conditional), [], false) {
		return true, Finding{
			stmt:       position
			message_id: 'prefer-logical-operator-over-ternary/optional-chain-error'
		}
	}
	if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[conditional].start, false), text) {
		text = ';${text}'
	}
	mut fixes := [
		fix_replace_range(t.nodes[conditional].start, t.nodes[conditional].end, text),
	]
	fixes << c.unb_fix_space_around_keyword(t, tokens, conditional)
	_, fix := c.merge_fixes(fixes)!
	return true, Finding{
		stmt:        position
		message_id:  'prefer-logical-operator-over-ternary/optional-chain-error'
		suggestions: [
			Suggestion{
				message_id: 'prefer-logical-operator-over-ternary/optional-chain-suggestion'
				fix:        fix
			},
		]
	}
}

fn uploot_is_boolean_literal(t &estree.EsTree, node int) bool {
	return t.typ(node) == .literal && t.get(node, .value) is bool
}

// uploot_check ports the ConditionalExpression listener: (whether it reports, the problem).
fn (mut c Checker) uploot_check(t &estree.EsTree, tokens &SourceTokens, node int, mut ctx UnbTypeContext) !(bool, Finding) {
	test := t.node(node, .test) or { return false, Finding{} }
	consequent := t.node(node, .consequent) or { return false, Finding{} }
	alternate := t.node(node, .alternate) or { return false, Finding{} }
	if (uploot_is_boolean_literal(t, consequent) && uploot_is_boolean_literal(t, alternate))
		|| (!uploot_in_with_statement(t, node)
			&& c.uploot_boolean_constant_value(t, consequent, mut ctx) != none
			&& c.uploot_boolean_constant_value(t, alternate, mut ctx) != none) {
		return false, Finding{}
	}
	has_boolean_problem, boolean_problem := c.uploot_boolean_ternary_problem(t, tokens, node, mut
		ctx)!
	if has_boolean_problem {
		return true, boolean_problem
	}
	has_nullish_problem, nullish_problem := c.uploot_nullish_ternary_problem(t, tokens, node)!
	if has_nullish_problem {
		return true, nullish_problem
	}
	// `foo ? foo : bar`
	if c.unb_is_same_node(t, test, consequent) {
		return true, c.uploot_problem(t, tokens, node, test, alternate, ['??', '||'])!
	}
	// `!bar ? foo : bar`
	if t.typ(test) == .unary_expression && (t.string_of(test, .operator) or { '' }) == '!'
		&& (t.flag(test, .prefix) or { false }) {
		argument := t.node(test, .argument) or { return false, Finding{} }
		if c.unb_is_same_node(t, argument, alternate) {
			return true, c.uploot_problem(t, tokens, node, argument, consequent, ['??', '||'])!
		}
	}
	return false, Finding{}
}

fn (mut c Checker) lint_unicorn_prefer_logical_operator_over_ternary(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .conditional_expression {
			continue
		}
		stats.checked++
		reported, finding := c.uploot_check(t, tokens, node, mut ctx)!
		if reported {
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
