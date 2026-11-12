module rules

import json2
import math
import time
import tsgo { TypeResponse }
import treesitter { Ident, named_children, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `no-unnecessary-condition` rule of typescript-eslint 8.62.0, with all its options and
// its `suggestRemoveOptionalChain` suggestion.

const nuco_messages = {
	'alwaysFalsy':                   'Unnecessary conditional, value is always falsy.'
	'alwaysFalsyFunc':               'This callback should return a conditional, but return is always falsy.'
	'alwaysNullish':                 'Unnecessary conditional, left-hand side of `??` operator is always `null` or `undefined`.'
	'alwaysTruthy':                  'Unnecessary conditional, value is always truthy.'
	'alwaysTruthyFunc':              'This callback should return a conditional, but return is always truthy.'
	'comparisonBetweenLiteralTypes': 'Unnecessary conditional, comparison is always {{trueOrFalse}}, since `{{left}} {{operator}} {{right}}` is {{trueOrFalse}}.'
	'never':                         'Unnecessary conditional, value is `never`.'
	'neverNullish':                  'Unnecessary conditional, expected left-hand side of `??` operator to be possibly null or undefined.'
	'neverOptionalChain':            'Unnecessary optional chain on a non-nullish value.'
	'noOverlapBooleanExpression':    'Unnecessary conditional, the types have no overlap.'
	'noStrictNullCheck':             'This rule requires the `strictNullChecks` compiler option to be turned on to function correctly.'
	'suggestRemoveOptionalChain':    'Remove unnecessary optional chain'
	'typeGuardAlreadyIsType':        'Unnecessary conditional, expression already has the type being checked by the {{typeGuardOrAssertionFunction}}.'
}

// TypePredicateKind: Identifier and AssertsIdentifier.
const predicate_identifier = 1
const predicate_asserts_identifier = 3

const nuco_bool_operators = ['<', '>', '<=', '>=', '==', '===', '!=', '!==']

struct NucoOptions {
	loop_conditions                  string // 'always', 'never' or 'only-allowed-literals'
	allow_without_strict_null_checks bool
	check_type_predicates            bool
}

fn nuco_options(options []json2.Any) !NucoOptions {
	o := option_object(no_unnecessary_condition, options, [
		'allowConstantLoopConditions',
		'allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing',
		'checkTypePredicates',
	])!
	mut loop := 'never'
	if value := o.values['allowConstantLoopConditions'] {
		if value is bool {
			loop = if value { 'always' } else { 'never' }
		} else {
			loop = o.string_value('allowConstantLoopConditions', ['always', 'never',
				'only-allowed-literals'])!
		}
	}
	return NucoOptions{
		loop_conditions:                  loop
		allow_without_strict_null_checks: o.bool_value('allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing')!
		check_type_predicates:            o.bool_value('checkTypePredicates')!
	}
}

fn (mut c Checker) lint_no_unnecessary_condition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nuco_options(c.rule_options(no_unnecessary_condition))!
	nodes := c.nodes_of_kinds(root, ['augmented_assignment_expression', 'binary_expression',
		'call_expression', 'ternary_expression', 'while_statement', 'do_statement', 'for_statement',
		'if_statement', 'member_expression', 'subscript_expression', 'switch_statement'], type_name_kinds)
	mut spans := []Span{}
	for n in nodes {
		c.nuco_spans(n, mut spans)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
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
	for n in nodes {
		c.nuco_visit(n, o, mut findings)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += nodes.len
	return findings
}

// nuco_visit runs the visitors of the rule on a node.
fn (mut c Checker) nuco_visit(n C.TSNode, o NucoOptions, mut findings []Finding) ! {
	match node_kind(n) {
		'augmented_assignment_expression' {
			left := node_field(n, 'left') or { return }
			match operator_of(n) {
				'&&=', '||=' {
					c.nuco_check_node(left, false, unwrap_parens(left), mut findings, 0)!
				}
				'??=' { c.nuco_check_nullish(unwrap_parens(left), mut findings)! }
				else {}
			}
		}
		'binary_expression' {
			left := node_field(n, 'left') or { return }
			operator := operator_of(n)
			if estree_binary_kind(n) == 'LogicalExpression' {
				if operator == '??' {
					c.nuco_check_nullish(unwrap_parens(left), mut findings)!
				} else {
					c.nuco_check_node(left, false, unwrap_parens(left), mut findings, 0)!
				}
			} else if operator in nuco_bool_operators {
				right := node_field(n, 'right') or { return }
				c.nuco_check_comparison(n, unwrap_parens(left), unwrap_parens(right), operator, mut
					findings)!
			}
		}
		'call_expression' {
			if !is_chain_element(n) {
				return
			}
			callee := node_field(n, 'function') or { return }
			if node_kind(callee) == 'import' {
				return
			}
			c.nuco_check_call(n, o, mut findings)!
			if is_optional_element(n) {
				c.nuco_check_optional_chain(n, mut findings)!
			}
		}
		'member_expression', 'subscript_expression' {
			if is_optional_element(n) {
				c.nuco_check_optional_chain(n, mut findings)!
			}
		}
		'ternary_expression', 'if_statement' {
			test := node_field(n, 'condition') or { return }
			c.nuco_check_node(test, false, unwrap_parens(test), mut findings, 0)!
		}
		'while_statement', 'do_statement', 'for_statement' {
			c.nuco_check_loop(n, o, mut findings)!
		}
		'switch_statement' {
			discriminant := unwrap_parens(node_field(n, 'value') or { return })
			body := node_field(n, 'body') or { return }
			for case in named_children(body) {
				if node_kind(case) != 'switch_case' {
					continue
				}
				test := unwrap_parens(node_field(case, 'value') or { continue })
				c.nuco_check_comparison(test, discriminant, test, '===', mut findings)!
			}
		}
		else {}
	}
}

// nuco_spans adds the nodes whose types the visitors of `n` may need (a superset).
fn (c &Checker) nuco_spans(n C.TSNode, mut spans []Span) {
	match node_kind(n) {
		'augmented_assignment_expression' {
			if left := node_field(n, 'left') {
				c.nuco_check_spans(left, mut spans, 0)
				nuco_chain_spans(unwrap_parens(left), mut spans)
			}
		}
		'binary_expression' {
			if left := node_field(n, 'left') {
				c.nuco_check_spans(left, mut spans, 0)
				nuco_chain_spans(unwrap_parens(left), mut spans)
				// The left operand of a comparison is compared as a whole (`!a < b`), not as a
				// condition.
				if operator_of(n) in nuco_bool_operators {
					spans << node_span(unwrap_parens(left))
				}
			}
			if right := node_field(n, 'right') {
				nuco_expr_spans(unwrap_parens(right), mut spans)
			}
		}
		'call_expression' {
			spans << node_span(n)
			nuco_chain_spans(n, mut spans)
			if args := call_arguments(n) {
				for arg in args {
					a := unwrap_parens(arg)
					nuco_expr_spans(a, mut spans)
					if node_kind(a) in ['arrow_function', 'function_expression'] {
						if body := node_field(a, 'body') {
							if node_kind(body) == 'statement_block' {
								statements := named_children(body)
								if statements.len == 1 && node_kind(statements[0]) == 'return_statement' {
									if value := first_named(statements[0]) {
										c.nuco_check_spans(value, mut spans, 0)
									}
								}
							} else {
								c.nuco_check_spans(body, mut spans, 0)
							}
						}
					}
				}
			}
		}
		'member_expression', 'subscript_expression' {
			if is_optional_element(n) {
				nuco_chain_spans(n, mut spans)
			}
		}
		'ternary_expression', 'if_statement', 'while_statement', 'do_statement', 'for_statement' {
			if test := node_field(n, 'condition') {
				// `for (;;)` has no test.
				if node_kind(test) == 'empty_statement' {
					return
				}
				nuco_expr_spans(unwrap_parens(test), mut spans)
				c.nuco_check_spans(test, mut spans, 0)
			}
		}
		'switch_statement' {
			if value := node_field(n, 'value') {
				spans << node_span(unwrap_parens(value))
			}
			if body := node_field(n, 'body') {
				for case in named_children(body) {
					if test := node_field(case, 'value') {
						spans << node_span(unwrap_parens(test))
					}
				}
			}
		}
		else {}
	}
}

// nuco_check_spans adds the nodes checkNode looks at for `expression`.
fn (c &Checker) nuco_check_spans(expression C.TSNode, mut spans []Span, depth int) {
	if depth > max_expression_depth {
		return
	}
	e := unwrap_parens(expression)
	if node_kind(e) == 'unary_expression' && operator_of(e) == '!' {
		if argument := node_field(e, 'argument') {
			c.nuco_check_spans(argument, mut spans, depth + 1)
		}
		return
	}
	if estree_binary_kind(e) == 'LogicalExpression' && operator_of(e) != '??' {
		if right := node_field(e, 'right') {
			c.nuco_check_spans(right, mut spans, depth + 1)
		}
		return
	}
	nuco_expr_spans(e, mut spans)
}

// nuco_expr_spans adds a node and the parts of a member access or a call.
fn nuco_expr_spans(e C.TSNode, mut spans []Span) {
	spans << node_span(e)
	if is_member(e) {
		if object := node_field(e, 'object') {
			spans << node_span(unwrap_parens(object))
		}
		if property := member_property(e) {
			spans << node_span(property)
		}
	} else if node_kind(e) == 'call_expression' {
		if callee := node_field(e, 'function') {
			spans << node_span(unwrap_parens(callee))
		}
	}
}

// nuco_chain_spans adds the elements of the chain that ends at `n`, with their parts.
fn nuco_chain_spans(n C.TSNode, mut spans []Span) {
	mut node := n
	for depth := 0; depth < max_expression_depth && is_chain_element(node); depth++ {
		nuco_expr_spans(node, mut spans)
		lhs := chain_lhs(node) or { return }
		node = unwrap_parens(lhs)
		nuco_expr_spans(node, mut spans)
	}
}

// nuco_constrained is getConstrainedTypeAtLocation of a node, or the null type if tsgo does not
// know it.
fn (mut c Checker) nuco_constrained(n C.TSNode) !TypeResponse {
	t := c.node_type(unwrap_parens(n)) or { return TypeResponse{} }
	return c.constrained(t)!
}

// nuco_check_node ports checkNode: reports a condition whose type is always truthy, always falsy
// or `never`, at `report`.
fn (mut c Checker) nuco_check_node(expression C.TSNode, unary_not bool, report C.TSNode, mut findings []Finding, depth int) ! {
	if depth > max_expression_depth {
		c.too_deep++
		return
	}
	e := unwrap_parens(expression)
	if node_kind(e) == 'unary_expression' && operator_of(e) == '!' {
		argument := node_field(e, 'argument') or { return }
		return c.nuco_check_node(argument, !unary_not, report, mut findings, depth + 1)
	}
	if !c.no_unchecked_indexed_access && c.is_array_index_expression(e)! {
		return
	}
	if estree_binary_kind(e) == 'LogicalExpression' && operator_of(e) != '??' {
		right := node_field(e, 'right') or { return }
		return c.nuco_check_node(right, false, unwrap_parens(right), mut findings, depth + 1)
	}
	t := c.nuco_constrained(e)!
	if t.is_null() {
		return
	}
	if c.is_conditional_always_necessary(t)! {
		return
	}
	message_id := if c.type_flags(t)! & type_flag_never != 0 {
		'never'
	} else if !c.is_possibly_truthy(t)! {
		if unary_not { 'alwaysTruthy' } else { 'alwaysFalsy' }
	} else if !c.is_possibly_falsy(t)! {
		if unary_not { 'alwaysFalsy' } else { 'alwaysTruthy' }
	} else {
		''
	}
	if message_id != '' {
		findings << Finding{
			stmt:       position_of(report)
			message_id: message_id
		}
	}
}

// nuco_check_nullish ports checkNodeForNullish: the left side of `??` (or `??=`).
fn (mut c Checker) nuco_check_nullish(n C.TSNode, mut findings []Finding) ! {
	t := c.nuco_constrained(n)!
	if t.is_null() {
		return
	}
	if c.type_flags(t)! & (type_flag_any | type_flag_unknown | type_flag_type_parameter | type_flag_type_variable) != 0 {
		return
	}
	mut message_id := ''
	if c.type_flags(t)! & type_flag_never != 0 {
		message_id = 'never'
	} else if !c.is_possibly_nullish(t)!
		&& !(estree_type(n) == 'MemberExpression' && c.is_nullable_member_expression(n)!) {
		if c.no_unchecked_indexed_access || (!c.is_array_index_expression(n)!
			&& !(estree_type(n) == 'ChainExpression' && node_kind(n) != 'non_null_expression'
				&& c.option_chain_contains_option_array_index(n)!)) {
			message_id = 'neverNullish'
		}
	} else if c.is_always_nullish(t)! {
		message_id = 'alwaysNullish'
	}
	if message_id != '' {
		findings << Finding{
			stmt:       position_of(n)
			message_id: message_id
		}
	}
}

// nuco_check_comparison ports checkIfBoolExpressionIsNecessaryConditional, reporting at `node`.
fn (mut c Checker) nuco_check_comparison(node C.TSNode, left C.TSNode, right C.TSNode, operator string, mut findings []Finding) ! {
	left_type := c.nuco_constrained(left)!
	if left_type.is_null() {
		return
	}
	right_type := c.nuco_constrained(right)!
	if right_type.is_null() {
		return
	}
	if left_value := nuco_static_value(left_type) {
		if right_value := nuco_static_value(right_type) {
			result := js_compare(left_value, operator, right_value)
			true_or_false := if result { 'true' } else { 'false' }
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'comparisonBetweenLiteralTypes'
				data:       {
					'left':        c.type_string(left_type)!
					'operator':    operator
					'right':       c.type_string(right_type)!
					'trueOrFalse': true_or_false
				}
			}
			return
		}
	}
	// Workaround for https://github.com/microsoft/TypeScript/issues/37160.
	if !c.strict_null_checks {
		return
	}
	loose := operator in ['==', '!=']
	if (left_type.flags == type_flag_undefined
		&& !c.nuco_comparable(right_type, type_flag_undefined | type_flag_void, loose)!)
		|| (right_type.flags == type_flag_undefined
			&& !c.nuco_comparable(left_type, type_flag_undefined | type_flag_void, loose)!)
		|| (left_type.flags == type_flag_null && !c.nuco_comparable(right_type, type_flag_null, loose)!)
		|| (right_type.flags == type_flag_null && !c.nuco_comparable(left_type, type_flag_null, loose)!) {
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'noOverlapBooleanExpression'
		}
	}
}

// nuco_comparable is the isComparable of checkIfBoolExpressionIsNecessaryConditional.
fn (mut c Checker) nuco_comparable(t TypeResponse, flag u32, loose bool) !bool {
	mut flags := flag | type_flag_any | type_flag_unknown | type_flag_type_parameter | type_flag_type_variable
	if loose {
		flags |= type_flag_null | type_flag_undefined | type_flag_void
	}
	return c.type_flags(t)! & flags != 0
}

// nuco_check_loop ports checkIfLoopIsNecessaryConditional.
fn (mut c Checker) nuco_check_loop(n C.TSNode, o NucoOptions, mut findings []Finding) ! {
	condition := node_field(n, 'condition') or { return }
	// `for (;;)`
	if node_kind(condition) == 'empty_statement' {
		return
	}
	test := unwrap_parens(condition)
	if o.loop_conditions == 'only-allowed-literals' && node_kind(test) in ['true', 'false', 'number'] {
		if node_kind(test) != 'number' {
			return
		}
		text := c.text(test)
		if !text.ends_with('n') {
			value := js_number_string(text) or { '' }
			if value in ['0', '1'] {
				return
			}
		}
	}
	if o.loop_conditions == 'always' {
		t := c.nuco_constrained(test)!
		if is_true_literal(t) {
			return
		}
	}
	c.nuco_check_node(test, false, test, mut findings, 0)!
}

// nuco_check_call ports checkCallExpression: type predicates and array predicate callbacks.
fn (mut c Checker) nuco_check_call(call C.TSNode, o NucoOptions, mut findings []Finding) ! {
	if o.check_type_predicates {
		c.nuco_check_type_predicates(call, mut findings)!
	}
	callee := unwrap_parens(node_field(call, 'function') or { return })
	name := c.static_member_string(callee) or { return }
	if name !in array_predicate_methods {
		return
	}
	callbacks := c.array_predicate_callback(call)!
	if callbacks.len == 0 {
		return
	}
	callback := callbacks[0]
	if node_kind(callback) in ['arrow_function', 'function_expression'] {
		body := node_field(callback, 'body') or { return }
		// `() => something`
		if node_kind(body) != 'statement_block' {
			return c.nuco_check_node(body, false, unwrap_parens(body), mut findings, 0)
		}
		// `() => { return something; }`
		statements := named_children(body)
		if statements.len == 1 && node_kind(statements[0]) == 'return_statement' {
			if value := first_named(statements[0]) {
				return c.nuco_check_node(value, false, unwrap_parens(value), mut findings, 0)
			}
		}
	}
	callback_type := c.nuco_constrained(callback)!
	if callback_type.is_null() {
		return
	}
	signatures := c.call_signatures_of(callback_type)!
	if signatures.len == 0 {
		return
	}
	mut falsy := false
	mut truthy := false
	for sig in signatures {
		return_type := c.return_type(sig.id)!
		// getConstraintInfo: the base constraint of a type parameter.
		constraint := if return_type.flags & type_flag_type_parameter != 0 {
			c.base_constraint(return_type)!
		} else {
			return_type
		}
		if constraint.is_null() || c.type_flags(constraint)! & (type_flag_any | type_flag_unknown) != 0 {
			return
		}
		if c.is_possibly_falsy(constraint)! {
			falsy = true
		}
		if c.is_possibly_truthy(constraint)! {
			truthy = true
		}
		if falsy && truthy {
			return
		}
	}
	message_id := if !falsy { 'alwaysTruthyFunc' } else { 'alwaysFalsyFunc' }
	findings << Finding{
		stmt:       position_of(callback)
		message_id: message_id
	}
}

// nuco_check_type_predicates ports the checkTypePredicates part of checkCallExpression, with
// findTruthinessAssertedArgument and findTypeGuardAssertedArgument.
fn (mut c Checker) nuco_check_type_predicates(call C.TSNode, mut findings []Finding) ! {
	mut checkable := []C.TSNode{}
	for arg in call_arguments(call) or { return } {
		if node_kind(arg) == 'spread_element' {
			break
		}
		checkable << unwrap_parens(arg)
	}
	if checkable.len == 0 {
		return
	}
	signature := c.resolved_signature(call)!
	if signature.id == 0 {
		return
	}
	predicate := c.type_predicate(signature.id)!
	if !predicate.found {
		return
	}
	index := predicate.parameter_index
	if predicate.kind == predicate_asserts_identifier && predicate.typ.is_null() {
		if index >= 0 && index < checkable.len {
			c.nuco_check_node(checkable[index], false, checkable[index], mut findings, 0)!
		}
	}
	if predicate.kind !in [predicate_asserts_identifier, predicate_identifier]
		|| predicate.typ.is_null() || index < 0 || index >= checkable.len {
		return
	}
	argument := checkable[index]
	argument_type := c.nuco_constrained(argument)!
	if argument_type.is_null() {
		return
	}
	guard := predicate.typ
	if argument_type.flags & (type_flag_any | type_flag_unknown) != 0
		|| !c.assignable(argument_type.id, guard.id)! {
		return
	}
	if c.assignable(guard.id, argument_type.id)!
		|| guard.flags & type_flag_union != 0 {
		findings << Finding{
			stmt:       position_of(argument)
			message_id: 'typeGuardAlreadyIsType'
			data:       {
				'typeGuardOrAssertionFunction': if predicate.kind == predicate_asserts_identifier {
					'assertion function'
				} else {
					'type guard'
				}
			}
		}
	}
}

// nuco_check_optional_chain ports checkOptionalChain for an element with its own `?.`.
fn (mut c Checker) nuco_check_optional_chain(n C.TSNode, mut findings []Finding) ! {
	if !c.no_unchecked_indexed_access && c.option_chain_contains_option_array_index(n)! {
		return
	}
	to_check := unwrap_parens(chain_lhs(n) or { return })
	if c.is_optionable_expression(to_check)! {
		return
	}
	token := if node_kind(n) == 'call_expression' { '?.' } else { 'optional_chain' }
	// The suggestion replaces the `?.` with `.` in a member access with a name, and removes it in a
	// computed one and in a call.
	replacement := if node_kind(n) == 'member_expression' { '.' } else { '' }
	for child in children_of_kind(n, token) {
		_, suggestion := c.suggestion('suggestRemoveOptionalChain', map[string]string{},
			[fix_replace(child, replacement)])!
		findings << Finding{
			stmt:        position_of(child)
			message_id:  'neverOptionalChain'
			suggestions: [suggestion]
		}
		break
	}
}

// option_chain_contains_option_array_index ports optionChainContainsOptionArrayIndex.
fn (mut c Checker) option_chain_contains_option_array_index(n C.TSNode) !bool {
	mut node := n
	for depth := 0; depth < max_expression_depth; depth++ {
		lhs := unwrap_parens(chain_lhs(node) or { return false })
		if is_optional_element(node) && c.is_array_index_expression(lhs)! {
			return true
		}
		if estree_type(lhs) !in ['MemberExpression', 'CallExpression'] {
			return false
		}
		node = lhs
	}
	return false
}

// is_array_index_expression ports isArrayIndexExpression: `x[i]` on an array, or on a tuple with a
// non-literal index.
fn (mut c Checker) is_array_index_expression(n C.TSNode) !bool {
	if estree_type(n) != 'MemberExpression' || node_kind(n) != 'subscript_expression' {
		return false
	}
	object := node_field(n, 'object') or { return false }
	t := c.nuco_constrained(object)!
	if t.is_null() {
		return false
	}
	parts := c.constituents(t)!
	for part in parts {
		if c.is_array(part)! {
			return true
		}
	}
	index := member_property(n) or { return false }
	if estree_type(index) == 'Literal' {
		return false
	}
	for part in parts {
		if c.is_tuple(part)! {
			return true
		}
	}
	return false
}

// is_conditional_always_necessary ports isConditionalAlwaysNecessary: `any`, `unknown` or a type
// variable in some part of the type.
fn (mut c Checker) is_conditional_always_necessary(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		if part.flags & (type_flag_any | type_flag_unknown | type_flag_type_variable) != 0 {
			return true
		}
	}
	return false
}

// is_nullable_member_expression ports isNullableMemberExpression.
fn (mut c Checker) is_nullable_member_expression(n C.TSNode) !bool {
	object := unwrap_parens(node_field(n, 'object') or { return false })
	object_type := c.node_type(object) or { return false }
	property := member_property(n) or { return false }
	if node_kind(n) == 'subscript_expression' {
		property_type := c.node_type(property) or { return false }
		return c.is_nullable_property_type(object_type, property_type, 0)!
	}
	name := c.text(property)
	for prop in c.properties(object_type)! {
		if nuco_symbol_name(prop.name) == name {
			return prop.flags & symbol_flag_optional != 0
		}
	}
	return false
}

// nuco_symbol_name is the name TypeScript's symbol.name gives a property. A private one (`#x`)
// is named after its declaration, while its symbol has a name of its own, which tsgo gives as
// `__#<id>@#x` (getSymbolNameForPrivateIdentifier).
fn nuco_symbol_name(name string) string {
	if name.starts_with('__#') {
		if at := name.index('@') {
			return name[at + 1..]
		}
	}
	return unescape_name(name)
}

// is_nullable_property_type ports isNullablePropertyType.
fn (mut c Checker) is_nullable_property_type(object_type TypeResponse, property_type TypeResponse, depth int) !bool {
	if property_type.flags & type_flag_union != 0 {
		if depth > max_type_depth {
			return false
		}
		for part in c.members_of(property_type)! {
			if c.is_nullable_property_type(object_type, part, depth + 1)! {
				return true
			}
		}
		return false
	}
	if property_type.flags & (type_flag_number_literal | type_flag_string_literal) != 0 {
		name := literal_type_name(property_type)
		prop := c.property(object_type, name)!
		if !prop.is_null() {
			return c.type_flags(c.symbol_type(prop.id)!)! & pnc_nullable_flags != 0
		}
	}
	type_name := c.type_name(property_type, 0)!
	for info in c.index_infos(object_type.id)! {
		if c.type_name(info.key_type, 0)! == type_name {
			return true
		}
	}
	return false
}

// is_optionable_expression ports isOptionableExpression: the object of a `?.` may be nullish on
// its own.
fn (mut c Checker) is_optionable_expression(n C.TSNode) !bool {
	t := c.nuco_constrained(n)!
	if t.is_null() {
		return true
	}
	estree := estree_type(n)
	own_nullable := if estree == 'MemberExpression' {
		!c.nullable_origin_from_object(n)!
	} else if estree == 'CallExpression' {
		!c.nullable_origin_from_callee(n)!
	} else {
		true
	}
	return c.is_conditional_always_necessary(t)!
		|| (own_nullable && c.type_flags(t)! & pnc_nullable_flags != 0)
}

// nullable_origin_from_object ports isMemberExpressionNullableOriginFromObject: `a.b` is nullable
// only because `a` is.
fn (mut c Checker) nullable_origin_from_object(n C.TSNode) !bool {
	object := node_field(n, 'object') or { return false }
	previous := c.nuco_constrained(object)!
	if previous.is_null() {
		return false
	}
	property := member_property(n) or { return false }
	if previous.flags & type_flag_union == 0 || estree_type(property) != 'Identifier' {
		return false
	}
	computed := node_kind(n) == 'subscript_expression'
	mut own_nullable := false
	for part in c.members_of(previous)! {
		if computed {
			property_type := c.nuco_constrained(property)!
			if property_type.is_null() {
				continue
			}
			if c.is_nullable_property_type(part, property_type, 0)! {
				own_nullable = true
				break
			}
			continue
		}
		prop := c.property(part, c.identifier_name(property))!
		if !prop.is_null() {
			if c.type_flags(c.symbol_type(prop.id)!)! & pnc_nullable_flags != 0 {
				own_nullable = true
				break
			}
			continue
		}
		for info in c.index_infos(part.id)! {
			if c.type_name(info.key_type, 0)! == 'string' && (c.no_unchecked_indexed_access
				|| c.type_flags(info.value_type)! & pnc_nullable_flags != 0) {
				own_nullable = true
				break
			}
		}
		if own_nullable {
			break
		}
	}
	return !own_nullable && c.type_flags(previous)! & pnc_nullable_flags != 0
}

// nullable_origin_from_callee ports isCallExpressionNullableOriginFromCallee.
fn (mut c Checker) nullable_origin_from_callee(n C.TSNode) !bool {
	callee := node_field(n, 'function') or { return false }
	previous := c.nuco_constrained(callee)!
	if previous.is_null() {
		return false
	}
	if previous.flags & type_flag_union == 0 {
		return false
	}
	for part in c.members_of(previous)! {
		for sig in c.signatures_of(part, signature_kind_call)! {
			if c.type_flags(c.return_type(sig.id)!)! & pnc_nullable_flags != 0 {
				return false
			}
		}
	}
	return c.type_flags(previous)! & pnc_nullable_flags != 0
}

// is_possibly_nullish ports isPossiblyNullish (unlike isNullableType, not `any` or `unknown`).
fn (mut c Checker) is_possibly_nullish(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		if part.flags & (type_flag_null | type_flag_undefined | type_flag_void) != 0 {
			return true
		}
	}
	return false
}

// is_always_nullish ports isAlwaysNullish.
fn (mut c Checker) is_always_nullish(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		if part.flags & (type_flag_null | type_flag_undefined) == 0 {
			return false
		}
	}
	return true
}

// is_possibly_truthy ports isPossiblyTruthy: some part of the union whose intersection parts are
// all not falsy.
fn (mut c Checker) is_possibly_truthy(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		mut all := true
		for inner in c.intersection_parts(part)! {
			if is_falsy_type(inner) {
				all = false
				break
			}
		}
		if all {
			return true
		}
	}
	return false
}

// is_possibly_falsy ports isPossiblyFalsy.
fn (mut c Checker) is_possibly_falsy(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		for inner in c.intersection_parts(part)! {
			if !is_truthy_literal(inner) && inner.flags & type_flag_possibly_falsy != 0 {
				return true
			}
		}
	}
	return false
}

// is_falsy_type ports isFalsyType of ts-api-utils (own flags).
fn is_falsy_type(t TypeResponse) bool {
	if t.flags & (type_flag_undefined | type_flag_null | type_flag_void) != 0 {
		return true
	}
	if t.flags & type_flag_literal_value != 0 {
		return !literal_truthy(t)
	}
	return is_false_literal(t)
}

// is_truthy_literal ports isTruthyLiteral.
fn is_truthy_literal(t TypeResponse) bool {
	if is_true_literal(t) {
		return true
	}
	return t.flags & type_flag_literal_value != 0 && literal_truthy(t)
}

// literal_truthy is `!!value` for a string, number or BigInt literal type.
fn literal_truthy(t TypeResponse) bool {
	value := t.value
	if t.flags & type_flag_bigint_literal != 0 {
		text := if value is string { value } else { '0' }
		return text.trim_left('-') != '0'
	}
	if value is string {
		return value != ''
	}
	if value is f64 {
		return value != 0 && !math.is_nan(value)
	}
	return false
}

// literal_type_name is `type.value.toString()` of a string or number literal type.
fn literal_type_name(t TypeResponse) string {
	value := t.value
	if value is string {
		return value
	}
	if value is f64 {
		return js_number_to_string(value)
	}
	return ''
}

// nuco_static_value ports toStaticValue.
fn nuco_static_value(t TypeResponse) ?JsValue {
	if t.flags & type_flag_boolean_literal != 0 {
		return JsValue{
			kind:    .boolean_
			boolean: is_true_literal(t)
		}
	}
	if t.flags == type_flag_undefined {
		return JsValue{
			kind: .undefined_
		}
	}
	if t.flags == type_flag_null {
		return JsValue{
			kind: .null_
		}
	}
	if t.flags & type_flag_literal_value == 0 {
		return none
	}
	value := t.value
	if t.flags & type_flag_bigint_literal != 0 {
		if value is string {
			return JsValue{
				kind: .bigint_
				text: value
			}
		}
		return none
	}
	if value is string {
		return JsValue{
			kind: .string_
			text: value
		}
	}
	if value is f64 {
		return JsValue{
			kind:   .number_
			number: value
		}
	}
	return none
}
