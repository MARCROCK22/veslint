module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { Ident, node_field, node_kind, nodes_of_kind, position_of }

// Port of the `no-unnecessary-boolean-literal-compare` rule of typescript-eslint 8.62.0, with all
// its options and its fix.

const nublc_messages = {
	'comparingNullableToFalse':       'This expression unnecessarily compares a nullable boolean value to false instead of using the ?? operator to provide a default.'
	'comparingNullableToTrueDirect':  'This expression unnecessarily compares a nullable boolean value to true instead of using it directly.'
	'comparingNullableToTrueNegated': 'This expression unnecessarily compares a nullable boolean value to true instead of negating it.'
	'direct':                         'This expression unnecessarily compares a boolean value to a boolean instead of using it directly.'
	'negated':                        'This expression unnecessarily compares a boolean value to a boolean instead of negating it.'
	'noStrictNullCheck':              'This rule requires the `strictNullChecks` compiler option to be turned on to function correctly.'
}

struct NublcOptions {
	allow_nullable_to_false          bool
	allow_nullable_to_true           bool
	allow_without_strict_null_checks bool
}

fn nublc_options(options []json2.Any) !NublcOptions {
	o := option_object(no_unnecessary_boolean_literal_compare, options, [
		'allowComparingNullableBooleansToFalse',
		'allowComparingNullableBooleansToTrue',
		'allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing',
	])!
	return NublcOptions{
		allow_nullable_to_false:          o.bool_value('allowComparingNullableBooleansToFalse')!
		allow_nullable_to_true:           o.bool_value('allowComparingNullableBooleansToTrue')!
		allow_without_strict_null_checks: o.bool_value('allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing')!
	}
}

// NublcKind is what getBooleanComparison finds in the type of the compared expression.
enum NublcKind {
	skip     // neither a boolean nor a nullable boolean: the rule does not apply
	boolean  // a boolean
	nullable // a nullable boolean
}

// NublcComparison ports the result of deconstructComparison: an equality against a boolean
// literal.
struct NublcComparison {
	node       C.TSNode // the BinaryExpression
	expression C.TSNode // the compared expression, without parentheses
	literal    bool     // the value of the boolean literal
	negated    bool     // `!=` or `!==`
}

fn (mut c Checker) lint_no_unnecessary_boolean_literal_compare(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nublc_options(c.rule_options(no_unnecessary_boolean_literal_compare))!
	mut comparisons := []NublcComparison{}
	for node in c.nodes_of_kind(root, c'binary_expression') {
		comparisons << nublc_deconstruct(node) or { continue }
	}
	c.resolve_spans(comparisons.map(node_span(it.expression)), abs_path, mut stats)!
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
	for comparison in comparisons {
		kind := c.nublc_boolean_comparison(comparison.expression)!
		if kind == .skip {
			continue
		}
		nullable := kind == .nullable
		if nullable {
			if comparison.literal && o.allow_nullable_to_true {
				continue
			}
			if !comparison.literal && o.allow_nullable_to_false {
				continue
			}
		}
		message_id := if nullable {
			if comparison.literal {
				if comparison.negated {
					'comparingNullableToTrueNegated'
				} else {
					'comparingNullableToTrueDirect'
				}
			} else {
				'comparingNullableToFalse'
			}
		} else if comparison.negated {
			'negated'
		} else {
			'direct'
		}
		finding := Finding{
			stmt:       position_of(comparison.node)
			message_id: message_id
		}
		findings << c.with_fixes(finding, [c.nublc_fix(comparison, nullable)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += comparisons.len
	return findings
}

// nublc_fix ports the fixer: the comparison, with the `!` around it if it has one, becomes the
// compared expression, negated if the whole is a negation and with `?? true` if it is a nullable
// boolean compared to false, in the parentheses each step needs.
fn (c &Checker) nublc_fix(comparison NublcComparison, nullable bool) Fix {
	node := es_child(comparison.node)
	mut mutated := node
	mut wrapped := false
	if parent := node.parent() {
		if !parent.chain && node_kind(parent.node) == 'unary_expression'
			&& operator_of(parent.node) == '!' {
			mutated = parent
			wrapped = true
		}
	}
	// Whether the truth table of the replaced expression is negated, ignoring the nullish cases.
	overall_negated := (wrapped != comparison.negated) != !comparison.literal
	expression := es_child(comparison.expression)
	mut text := c.text(expression.node)
	mut may_need_parentheses := !is_strong_precedence_node(expression)
	// In `maybeNullish === false`, nullish values have the same truth table as `true`.
	if nullable && !comparison.literal {
		if may_need_parentheses {
			text = '(${text})'
		}
		text = '${text} ?? true'
		may_need_parentheses = true
	}
	if overall_negated {
		if may_need_parentheses {
			text = '(${text})'
		}
		text = '!${text}'
		may_need_parentheses = false
	}
	if may_need_parentheses && is_weak_precedence_parent(mutated) {
		text = '(${text})'
	}
	return fix_replace(mutated.node, text)
}

// nublc_deconstruct ports deconstructComparison: an equality operator with a boolean literal on
// the right or, failing that, on the left.
fn nublc_deconstruct(node C.TSNode) ?NublcComparison {
	operator := operator_of(node)
	if operator !in ['!=', '!==', '==', '==='] {
		return none
	}
	left := unwrap_parens(node_field(node, 'left')?)
	right := unwrap_parens(node_field(node, 'right')?)
	for pair in [[right, left], [left, right]] {
		against, expression := pair[0], pair[1]
		kind := node_kind(against)
		if kind !in ['true', 'false'] {
			continue
		}
		return NublcComparison{
			node:       node
			expression: expression
			literal:    kind == 'true'
			negated:    operator.starts_with('!')
		}
	}
	return none
}

// nublc_boolean_comparison ports getBooleanComparison on the type of the compared expression.
fn (mut c Checker) nublc_boolean_comparison(expression C.TSNode) !NublcKind {
	t := c.node_type(expression) or { return .skip }
	// getConstraintInfo: a type parameter is replaced by its constraint (skip if it has none).
	mut constraint := t
	if t.flags & type_flag_type_parameter != 0 {
		constraint = c.base_constraint(t)!
		if constraint.is_null() {
			return .skip
		}
	}
	// isBooleanType: tsutils.isTypeFlagSet, on the type's own flags.
	if constraint.flags & type_flag_boolean_like != 0 {
		return .boolean
	}
	if c.nublc_is_nullable_boolean(constraint)! {
		return .nullable
	}
	return .skip
}

// nublc_is_nullable_boolean ports isNullableBoolean: a union of booleans and at least one of null
// or undefined.
fn (mut c Checker) nublc_is_nullable_boolean(t TypeResponse) !bool {
	if t.flags & type_flag_union == 0 {
		return false
	}
	types := c.members_of(t)!
	non_nullish := types.filter(it.flags & (type_flag_undefined | type_flag_null) == 0)
	if non_nullish.len == 0 || non_nullish.len == types.len {
		return false
	}
	return non_nullish.all(it.flags & type_flag_boolean_like != 0)
}
