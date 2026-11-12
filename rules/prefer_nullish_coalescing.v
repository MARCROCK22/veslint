module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { Ident, children, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `prefer-nullish-coalescing` rule of typescript-eslint 8.62.0, with all its options
// and its suggestions.

const pnc_messages = {
	'noStrictNullCheck':           'This rule requires the `strictNullChecks` compiler option to be turned on to function correctly.'
	'preferNullishOverAssignment': 'Prefer using nullish coalescing operator (`??{{ equals }}`) instead of an assignment expression, as it is simpler to read.'
	'preferNullishOverOr':         'Prefer using nullish coalescing operator (`??{{ equals }}`) instead of a logical {{ description }} (`||{{ equals }}`), as it is a safer operator.'
	'preferNullishOverTernary':    'Prefer using nullish coalescing operator (`??{{ equals }}`) instead of a ternary expression, as it is simpler to read.'
	'suggestNullish':              'Fix to nullish coalescing operator (`??{{ equals }}`).'
}

// TypeFlags of isNullableType: Any | Unknown | Null | Undefined | Void.
const pnc_nullable_flags = u32(1 | 2 | 8 | 4 | 16)

struct PncOptions {
	allow_without_strict_null_checks bool
	ignore_boolean_coercion          bool
	ignore_conditional_tests         bool
	ignore_if_statements             bool
	ignore_mixed_logical_expressions bool
	ignore_ternary_tests             bool
	ignorable_flags                  u32 // the TypeFlags of the ignored primitives
}

fn pnc_options(options []json2.Any) !PncOptions {
	o := option_object(prefer_nullish_coalescing, options, [
		'allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing',
		'ignoreBooleanCoercion',
		'ignoreConditionalTests',
		'ignoreIfStatements',
		'ignoreMixedLogicalExpressions',
		'ignorePrimitives',
		'ignoreTernaryTests',
	])!
	mut flags := u32(0)
	if primitives := o.values['ignorePrimitives'] {
		if primitives is bool && primitives {
			flags = type_flag_bigint_like | type_flag_boolean_like | type_flag_number_like | type_flag_string_like
		} else if primitives is map[string]json2.Any {
			p := option_object(prefer_nullish_coalescing, [json2.Any(primitives)], [
				'bigint',
				'boolean',
				'number',
				'string',
			])!
			if p.bool_value('bigint')! {
				flags |= type_flag_bigint_like
			}
			if p.bool_value('boolean')! {
				flags |= type_flag_boolean_like
			}
			if p.bool_value('number')! {
				flags |= type_flag_number_like
			}
			if p.bool_value('string')! {
				flags |= type_flag_string_like
			}
		} else {
			return error('option `ignorePrimitives` of `${prefer_nullish_coalescing}` must be true or an object')
		}
	}
	return PncOptions{
		allow_without_strict_null_checks: o.bool_value('allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing')!
		ignore_boolean_coercion:          o.bool_value('ignoreBooleanCoercion')!
		ignore_conditional_tests:         o.bool_value('ignoreConditionalTests')!
		ignore_if_statements:             o.bool_value('ignoreIfStatements')!
		ignore_mixed_logical_expressions: o.bool_value('ignoreMixedLogicalExpressions')!
		ignore_ternary_tests:             o.bool_value('ignoreTernaryTests')!
		ignorable_flags:                  flags
	}
}

// PncCheck is what still decides a candidate once its syntax matches: the type of `test`.
enum PncCheck {
	none            // fixable without looking at types
	eligible        // isTruthinessCheckEligibleForPreferNullish: the type of `test`
	undefined_check // only `=== undefined`-like checks: `test` must not be nullable by null
	null_check      // only `=== null`-like checks: `test` must not include undefined
}

// PncCandidate is a finding of the rule, pending the type check of `test`.
struct PncCandidate {
	report     Ident
	message_id string
	data       map[string]string
	check      PncCheck
	test       C.TSNode
	// For the suggestion:
	node      C.TSNode // the `||` or `||=` expression, the conditional or the `if`
	other     C.TSNode // a conditional: its nullish branch; an `if`: its assignment (without parentheses)
	statement C.TSNode // an `if`: the statement of the assignment
	block     bool     // an `if`: its consequent is a block
}

fn (mut c Checker) lint_prefer_nullish_coalescing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := pnc_options(c.rule_options(prefer_nullish_coalescing))!
	if o.ignore_boolean_coercion {
		// is_boolean_constructor_context reads the scopes of the file.
		c.scope_tree(root)
	}
	mut candidates := []PncCandidate{}
	nodes := c.nodes_of_kinds(root, ['augmented_assignment_expression', 'binary_expression',
		'ternary_expression', 'if_statement'], []string{})
	for n in nodes {
		match node_kind(n) {
			'augmented_assignment_expression', 'binary_expression' {
				if operator_of(n) == '||=' {
					c.pnc_or(n, 'assignment', '=', o, mut candidates)
				} else if operator_of(n) == '||' {
					c.pnc_or(n, 'or', '', o, mut candidates)
				}
			}
			'ternary_expression' {
				if !o.ignore_ternary_tests {
					c.pnc_ternary(n, o, mut candidates)
				}
			}
			else {
				if !o.ignore_if_statements {
					c.pnc_if(n, o, mut candidates)
				}
			}
		}
	}
	c.resolve_spans(candidates.filter(it.check != .none).map(node_span(it.test)), abs_path, mut
		stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	if !c.strict_null_checks && !o.allow_without_strict_null_checks {
		// ESLint reports it at line 0, column 0 (shown as 0:1).
		findings << Finding{
			stmt:       Ident{
				row: -1
			}
			message_id: 'noStrictNullCheck'
		}
	}
	for cand in candidates {
		if c.pnc_passes(cand, o)! {
			ok, suggestion := c.suggestion('suggestNullish', {
				'equals': cand.data['equals']
			}, c.pnc_fixes(cand))!
			findings << Finding{
				stmt:        cand.report
				message_id:  cand.message_id
				data:        cand.data
				suggestions: if ok { [suggestion] } else { []Suggestion{} }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

// pnc_passes applies the type part of the checks of a candidate.
fn (mut c Checker) pnc_passes(cand PncCandidate, o PncOptions) !bool {
	if cand.check == .none {
		return true
	}
	t := c.node_type(cand.test) or { return false }
	if cand.check == .eligible {
		return c.pnc_type_eligible(t, o)!
	}
	flags := c.type_flags(t)!
	if flags & (type_flag_any | type_flag_unknown) != 0 {
		return false
	}
	return if cand.check == .undefined_check {
		flags & type_flag_null == 0
	} else {
		flags & type_flag_undefined == 0
	}
}

// pnc_type_eligible ports isTypeEligibleForPreferNullish.
fn (mut c Checker) pnc_type_eligible(t TypeResponse, o PncOptions) !bool {
	flags := c.type_flags(t)!
	if flags & pnc_nullable_flags == 0 {
		return false
	}
	if o.ignorable_flags == 0 {
		return true
	}
	// `any` or `unknown` could be any primitive.
	if flags & (type_flag_any | type_flag_unknown) != 0 {
		return false
	}
	for part in c.type_constituents(t)! {
		for inner in c.intersection_parts(part)! {
			if c.type_flags(inner)! & o.ignorable_flags != 0 {
				return false
			}
		}
	}
	return true
}

// pnc_or ports checkAndFixWithPreferNullishOverOr for `a || b` and `a ||= b`: reported at the
// operator if the type of `a` is eligible.
fn (c &Checker) pnc_or(n C.TSNode, description string, equals string, o PncOptions, mut candidates []PncCandidate) {
	if o.ignore_conditional_tests && c.is_conditional_test(n) {
		return
	}
	if o.ignore_boolean_coercion && c.is_boolean_constructor_context(n) {
		return
	}
	if o.ignore_mixed_logical_expressions && c.is_mixed_logical_expression(n) {
		return
	}
	left := unwrap_parens(node_field(n, 'left') or { return })
	operator := node_field(n, 'operator') or { return }
	candidates << PncCandidate{
		report:     position_of(operator)
		message_id: 'preferNullishOverOr'
		data:       {
			'description': description
			'equals':      equals
		}
		check:      .eligible
		test:       left
		node:       n
	}
}

// pnc_ternary handles the ConditionalExpression visitor.
fn (c &Checker) pnc_ternary(n C.TSNode, o PncOptions, mut candidates []PncCandidate) {
	test := unwrap_parens(node_field(n, 'condition') or { return })
	operator, inside := c.pnc_test_operator(test) or { return }
	consequence := unwrap_parens(node_field(n, 'consequence') or { return })
	alternative := unwrap_parens(node_field(n, 'alternative') or { return })
	non_nullish := if operator in ['', '!=', '!=='] { consequence } else { alternative }
	check, left := c.pnc_params(n, test, non_nullish, inside, operator, o) or { return }
	candidates << PncCandidate{
		report:     position_of(n)
		message_id: 'preferNullishOverTernary'
		data:       {
			'equals': ''
		}
		check:      check
		test:       left
		node:       n
		other:      if operator in ['', '!=', '!=='] { alternative } else { consequence }
	}
}

// pnc_if handles the IfStatement visitor: `if (!a) a = b;` and the like.
fn (c &Checker) pnc_if(n C.TSNode, o PncOptions, mut candidates []PncCandidate) {
	if _ := node_field(n, 'alternative') {
		return
	}
	consequence := node_field(n, 'consequence') or { return }
	mut statement := consequence
	if node_kind(consequence) == 'statement_block' {
		body := named_children(consequence)
		if body.len != 1 {
			return
		}
		statement = body[0]
	}
	if node_kind(statement) != 'expression_statement' {
		return
	}
	assignment := unwrap_parens(first_named(statement) or { return })
	if node_kind(assignment) !in ['assignment_expression', 'augmented_assignment_expression'] {
		return
	}
	left := unwrap_parens(node_field(assignment, 'left') or { return })
	if !c.is_member_access_like(left) {
		return
	}
	test := unwrap_parens(node_field(n, 'condition') or { return })
	operator, inside := c.pnc_test_operator(test) or { return }
	if operator !in ['!', '==', '==='] {
		return
	}
	check, test_node := c.pnc_params(n, test, left, inside, operator, o) or { return }
	candidates << PncCandidate{
		report:     position_of(n)
		message_id: 'preferNullishOverAssignment'
		data:       {
			'equals': '='
		}
		check:      check
		test:       test_node
		node:       n
		other:      assignment
		statement:  statement
		block:      node_kind(consequence) == 'statement_block'
	}
}

// pnc_fixes ports the fixer of the suggestion of each of the three reports.
fn (mut c Checker) pnc_fixes(cand PncCandidate) []Fix {
	return match cand.message_id {
		'preferNullishOverOr' { c.pnc_or_fixes(cand.node) }
		'preferNullishOverTernary' { c.pnc_ternary_fixes(cand) }
		else { c.pnc_if_fixes(cand) }
	}
}

// pnc_is_logical_or ports isLogicalOrOperator: a LogicalExpression with `||`.
fn pnc_is_logical_or(n C.TSNode) bool {
	return node_kind(n) == 'binary_expression' && operator_of(n) == '||'
}

// pnc_or_fixes: the operator becomes `??` or `??=`; inside another `||` the new expression gets
// parentheses, which start after the `&&` of its left side if there is one (`&&` and `??` cannot
// be mixed without them).
fn (c &Checker) pnc_or_fixes(n C.TSNode) []Fix {
	operator := node_field(n, 'operator') or { return []Fix{} }
	left := unwrap_parens(node_field(n, 'left') or { return []Fix{} })
	right := unwrap_parens(node_field(n, 'right') or { return []Fix{} })
	mut fixes := []Fix{}
	if parent := estree_parent(n) {
		if pnc_is_logical_or(parent) {
			mut open := left
			if estree_binary_kind(left) == 'LogicalExpression' {
				inner_left := unwrap_parens(node_field(left, 'left') or { return []Fix{} })
				if !pnc_is_logical_or(inner_left) {
					open = unwrap_parens(node_field(left, 'right') or { return []Fix{} })
				}
			}
			fixes << fix_insert_before(open, '(')
			fixes << fix_insert_after(right, ')')
		}
	}
	fixes << fix_replace(operator, c.text(operator).replace('||', '??'))
	return fixes
}

// pnc_ternary_fixes: the conditional becomes `left ?? nullishBranch`, each side with the
// parentheses it has; a nullish branch without them gets some unless it binds tighter than `??`.
fn (mut c Checker) pnc_ternary_fixes(cand PncCandidate) []Fix {
	branch := es_child(cand.other)
	branch_text := c.text_with_parentheses(branch)
	replacement := if c.is_parenthesized(branch)
		|| estree_operator_precedence(branch.node) > precedence_coalesce {
		branch_text
	} else {
		'(${branch_text})'
	}
	left := c.text_with_parentheses(es_child(cand.test))
	return [fix_replace(cand.node, '${left} ?? ${replacement}')]
}

// pnc_if_fixes: the `if` becomes `left ??= right;`, with the comments right before the assignment
// in front and, for a block, the comments right after its statement behind.
fn (mut c Checker) pnc_if_fixes(cand PncCandidate) []Fix {
	tokens := c.source_tokens(cand.node)
	separator := if cand.block { '\n' } else { ' ' }
	before := c.pnc_format_comments(tokens.comments_before(node_start(cand.other)), separator)
	after := if cand.block {
		c.pnc_format_comments(tokens.comments_after(c.tokens.last_end(node_end(cand.statement))),
			'\n')
	} else {
		''
	}
	left := c.text_with_parentheses(es_child(node_field(cand.other, 'left') or { return []Fix{} }))
	right := c.text_with_parentheses(es_child(node_field(cand.other, 'right') or {
		return []Fix{}
	}))
	start := node_start(cand.node)
	end := c.tokens.last_end(node_end(cand.node))
	mut fixes := []Fix{}
	if before != '' {
		fixes << fix_insert_at(start, before)
	}
	fixes << fix_replace_range(start, end, '${left} ??= ${right};')
	if after != '' {
		fixes << fix_insert_at(end, ' ${after[..after.len - 1]}')
	}
	return fixes
}

// pnc_format_comments ports formatComments: each comment as it is written, followed by the
// separator.
fn (c &Checker) pnc_format_comments(comments []SourceToken, separator string) string {
	return comments.map(c.token_text(it) + separator).join('')
}

// pnc_test_operator ports getOperatorAndNodesInsideTestExpression; none is a null operator.
fn (c &Checker) pnc_test_operator(test C.TSNode) ?(string, []C.TSNode) {
	if c.is_member_access_like(test) || node_kind(test) == 'unary_expression' {
		if node_kind(test) != 'unary_expression' {
			return '', []C.TSNode{}
		}
		argument := unwrap_parens(node_field(test, 'argument') or { return none })
		if operator_of(test) == '!' && c.is_member_access_like(argument) {
			return '!', []C.TSNode{}
		}
		return none
	}
	estree := estree_binary_kind(test)
	if estree == 'BinaryExpression' {
		left := unwrap_parens(node_field(test, 'left') or { return none })
		right := unwrap_parens(node_field(test, 'right') or { return none })
		operator := operator_of(test)
		if operator in ['==', '!=', '===', '!=='] {
			return operator, [left, right]
		}
		return none
	}
	if estree != 'LogicalExpression' {
		return none
	}
	left := unwrap_parens(node_field(test, 'left') or { return none })
	right := unwrap_parens(node_field(test, 'right') or { return none })
	if estree_binary_kind(left) != 'BinaryExpression' || estree_binary_kind(right) != 'BinaryExpression' {
		return none
	}
	if c.is_nullish_comparison(left) || c.is_nullish_comparison(right) {
		return none
	}
	ll := unwrap_parens(node_field(left, 'left') or { return none })
	lr := unwrap_parens(node_field(left, 'right') or { return none })
	rl := unwrap_parens(node_field(right, 'left') or { return none })
	rr := unwrap_parens(node_field(right, 'right') or { return none })
	lo := operator_of(left)
	ro := operator_of(right)
	inside := [ll, lr, rl, rr]
	match operator_of(test) {
		'||' {
			if lo == '===' && ro == '===' {
				return '===', inside
			}
			if ((lo == '===' || ro == '===') && (lo == '==' || ro == '=='))
				|| (lo == '==' && ro == '==') {
				return '==', inside
			}
		}
		'&&' {
			if lo == '!==' && ro == '!==' {
				return '!==', inside
			}
			if ((lo == '!==' || ro == '!==') && (lo == '!=' || ro == '!='))
				|| (lo == '!=' && ro == '!=') {
				return '!=', inside
			}
		}
		else {}
	}
	return none
}

// pnc_params ports getNullishCoalescingParams: the node whose type decides and how; none when the
// construct is not fixable without looking at types.
fn (c &Checker) pnc_params(n C.TSNode, test C.TSNode, non_nullish C.TSNode, inside []C.TSNode, operator string, o PncOptions) ?(PncCheck, C.TSNode) {
	if inside.len == 0 {
		left := if node_kind(test) == 'unary_expression' {
			unwrap_parens(node_field(test, 'argument') or { return none })
		} else {
			test
		}
		if !c.similar_member_access(left, non_nullish) {
			return none
		}
		if o.ignore_conditional_tests && c.is_conditional_test(n) {
			return none
		}
		// A conditional that is itself an argument of a call is still checked.
		if o.ignore_boolean_coercion && c.is_boolean_constructor_context(n)
			&& !(node_kind(n) == 'ternary_expression' && pnc_is_call_argument(n)) {
			return none
		}
		return PncCheck.eligible, left
	}
	mut has_null := false
	mut has_undefined := false
	mut left := ?C.TSNode(none)
	for node in inside {
		if node_kind(node) == 'null' {
			has_null = true
		} else if is_undefined_identifier(node) {
			has_undefined = true
		} else if c.similar_member_access(node, non_nullish) {
			if left == none {
				left = node
			}
		} else {
			return none
		}
	}
	found := left?
	if has_undefined == has_null {
		return if has_undefined { PncCheck.none, found } else { none }
	}
	if operator in ['==', '!='] {
		return PncCheck.none, found
	}
	return if has_undefined { PncCheck.undefined_check, found } else { PncCheck.null_check, found }
}

// pnc_is_call_argument: the ESTree parent of `n` is a CallExpression (tree-sitter puts the
// `arguments` node in between).
fn pnc_is_call_argument(n C.TSNode) bool {
	arguments := estree_parent(n) or { return false }
	if node_kind(arguments) != 'arguments' {
		return false
	}
	call := node_parent(arguments) or { return false }
	return node_kind(call) == 'call_expression'
}

// is_boolean_constructor_context ports isBooleanConstructorContext: through logical expressions,
// the branches of a conditional and the last expression of a sequence, `n` is an argument of a
// call to the built-in `Boolean` (isBuiltInBooleanCall: the call has no declaration of `Boolean`
// in its own scope). It reads the scopes of the file, which the caller has built.
fn (c &Checker) is_boolean_constructor_context(n C.TSNode) bool {
	mut node := n
	for depth := 0; depth < max_expression_depth; depth++ {
		parent := estree_parent(node) or { return false }
		match node_kind(parent) {
			'binary_expression' {
				if estree_binary_kind(parent) != 'LogicalExpression' {
					return false
				}
			}
			'ternary_expression' {
				condition := unwrap_parens(node_field(parent, 'condition') or { return false })
				if node_key(condition) == node_key(node) {
					return false
				}
			}
			'sequence_expression' {
				expressions := named_children(parent)
				if expressions.len == 0 || node_key(unwrap_parens(expressions.last())) != node_key(node) {
					return false
				}
			}
			'arguments' {
				call := node_parent(parent) or { return false }
				if node_kind(call) != 'call_expression' {
					return false
				}
				callee := unwrap_parens(node_field(call, 'function') or { return false })
				if node_kind(callee) != 'identifier' || c.text(callee) != 'Boolean' {
					return false
				}
				scopes := c.file_scopes
				variable := scopes.own_variable(scopes.get_scope(call), 'Boolean')
				return variable < 0 || scopes.variables[variable].defs.len == 0
			}
			else {
				return false
			}
		}
		node = parent
	}
	return false
}

// is_conditional_test ports isConditionalTest: `n` is (part of) the test of a condition.
fn (c &Checker) is_conditional_test(n C.TSNode) bool {
	mut node := n
	for depth := 0; depth < max_expression_depth; depth++ {
		parent := estree_parent(node) or { return false }
		match node_kind(parent) {
			'binary_expression' {
				if estree_binary_kind(parent) != 'LogicalExpression' {
					return false
				}
			}
			'ternary_expression' {
				condition := unwrap_parens(node_field(parent, 'condition') or { return false })
				if node_key(condition) == node_key(node) {
					return true
				}
			}
			'sequence_expression' {
				expressions := named_children(parent)
				if expressions.len == 0 || node_key(unwrap_parens(expressions.last())) != node_key(node) {
					return false
				}
			}
			'unary_expression' {
				if operator_of(parent) != '!' {
					return false
				}
			}
			'if_statement', 'while_statement', 'do_statement', 'for_statement' {
				condition := unwrap_parens(node_field(parent, 'condition') or { return false })
				return node_key(condition) == node_key(node)
			}
			else {
				return false
			}
		}
		node = parent
	}
	return false
}

// is_mixed_logical_expression ports isMixedLogicalExpression: an `||` chain that touches an `&&`.
fn (c &Checker) is_mixed_logical_expression(n C.TSNode) bool {
	mut seen := map[string]bool{}
	mut queue := []C.TSNode{}
	pnc_push_around(n, mut queue)
	mut i := 0
	for i < queue.len && i < 10 * max_expression_depth {
		current := queue[i]
		i++
		key := '${node_key(current)}:${node_kind(current)}'
		if key in seen {
			continue
		}
		seen[key] = true
		if estree_binary_kind(current) == 'LogicalExpression' {
			operator := operator_of(current)
			if operator == '&&' {
				return true
			}
			if operator == '||' {
				pnc_push_around(current, mut queue)
			}
		}
	}
	return false
}

// pnc_push_around queues the ESTree parent and the operands of `n`.
fn pnc_push_around(n C.TSNode, mut queue []C.TSNode) {
	if parent := estree_parent(n) {
		queue << parent
	}
	if left := node_field(n, 'left') {
		queue << unwrap_parens(left)
	}
	if right := node_field(n, 'right') {
		queue << unwrap_parens(right)
	}
}

// is_nullish_comparison ports isNodeNullishComparison: `null === undefined` and the like.
fn (c &Checker) is_nullish_comparison(n C.TSNode) bool {
	left := unwrap_parens(node_field(n, 'left') or { return false })
	right := unwrap_parens(node_field(n, 'right') or { return false })
	return (node_kind(left) == 'null' || is_undefined_identifier(left))
		&& (node_kind(right) == 'null' || is_undefined_identifier(right))
}

fn is_undefined_identifier(n C.TSNode) bool {
	return node_kind(n) == 'undefined'
}

// is_member_access_like: an ESTree Identifier, MemberExpression or ChainExpression.
fn (c &Checker) is_member_access_like(n C.TSNode) bool {
	kind := node_kind(n)
	return kind in ['identifier', 'undefined', 'member_expression', 'subscript_expression']
		|| estree_type(n) == 'ChainExpression'
}

// similar_member_access ports areNodesSimilarMemberAccess: the same member access sequence,
// whatever the optional chaining (`a.b.c` and `a?.b.c` are similar).
fn (c &Checker) similar_member_access(a C.TSNode, b C.TSNode) bool {
	x := unwrap_parens(a)
	y := unwrap_parens(b)
	if is_member(x) && is_member(y) {
		if !c.similar_member_access(node_field(x, 'object') or { return false }, node_field(y,
			'object') or { return false })
		{
			return false
		}
		px := member_property(x) or { return false }
		py := member_property(y) or { return false }
		x_computed := node_kind(x) == 'subscript_expression'
		y_computed := node_kind(y) == 'subscript_expression'
		if x_computed == y_computed {
			return c.node_equal(px, py)
		}
		// `a['b']` and `a.b`.
		if x_computed && estree_type(px) == 'Literal' && node_kind(py) == 'property_identifier' {
			return c.literal_string_value(px) or { return false } == c.identifier_name(py)
		}
		if y_computed && estree_type(py) == 'Literal' && node_kind(px) == 'property_identifier' {
			return c.literal_string_value(py) or { return false } == c.identifier_name(px)
		}
		return false
	}
	return c.node_equal(x, y)
}

// node_equal ports isNodeEqual: the same `this`, literal value, identifier name or member access.
fn (c &Checker) node_equal(a C.TSNode, b C.TSNode) bool {
	x := unwrap_parens(a)
	y := unwrap_parens(b)
	tx := estree_type(x)
	if tx != estree_type(y) {
		return false
	}
	match tx {
		'ThisExpression' {
			return true
		}
		'Literal' {
			vx := c.literal_value(x) or { return false }
			vy := c.literal_value(y) or { return false }
			return vx == vy
		}
		'Identifier' {
			return c.identifier_name(x) == c.identifier_name(y)
		}
		'MemberExpression' {
			px := member_property(x) or { return false }
			py := member_property(y) or { return false }
			return c.node_equal(px, py)
				&& c.node_equal(node_field(x, 'object') or { return false }, node_field(y, 'object') or {
					return false
				})
		}
		else {
			return false
		}
	}
}

// literal_value is a key for `Literal.value` that is equal for two literals exactly when their
// values are `===`: the type and String(value). A regular expression is never equal to another.
fn (c &Checker) literal_value(n C.TSNode) ?string {
	match node_kind(n) {
		'string' {
			return 's:' + c.literal_string_value(n)?
		}
		'number' {
			text := c.text(n)
			value := js_number_string(text)?
			return if text.ends_with('n') { 'b:${value}' } else { 'n:${value}' }
		}
		'true', 'false', 'null' {
			return node_kind(n)
		}
		else {
			return none
		}
	}
}

// literal_string_value is the value of a string literal, with its escapes applied.
fn (c &Checker) literal_string_value(n C.TSNode) ?string {
	if node_kind(n) != 'string' {
		return none
	}
	quoted := c.text(n)
	if quoted.len < 2 {
		return none
	}
	return cooked_string(quoted[1..quoted.len - 1], false)
}
