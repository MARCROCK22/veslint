module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `use-isnan` rule of ESLint 10.6.0, with its options and its suggestions.

const uin_messages = {
	'comparisonWithNaN':          'Use the isNaN function to compare with NaN.'
	'switchNaN':                  "'switch(NaN)' can never match a case clause. Use Number.isNaN instead of the switch."
	'caseNaN':                    "'case NaN' can never match. Use Number.isNaN before the switch."
	'indexOfNaN':                 "Array prototype method '{{ methodName }}' cannot find NaN."
	'replaceWithIsNaN':           'Replace with Number.isNaN.'
	'replaceWithCastingAndIsNaN': 'Replace with Number.isNaN and cast to a Number.'
	'replaceWithFindIndex':       'Replace with Array.prototype.{{ methodName }}.'
}

const uin_comparison_operators = ['<', '>', '<=', '>=', '==', '===', '!=', '!==']

struct UinOptions {
	enforce_for_switch_case bool
	enforce_for_index_of    bool
}

// uin_options reads enforceForSwitchCase and enforceForIndexOf.
fn uin_options(options []json2.Any) !UinOptions {
	o := option_object(use_isnan, options, ['enforceForSwitchCase', 'enforceForIndexOf'])!
	return UinOptions{
		enforce_for_switch_case: o.bool_value('enforceForSwitchCase')!
		enforce_for_index_of:    o.bool_value('enforceForIndexOf')!
	}
}

fn (mut c Checker) lint_use_isnan(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := uin_options(c.rule_options(use_isnan))!
	mut findings := []Finding{}
	// In the order of the traversal: an expression before the ones inside it.
	for node in c.nodes_of_kinds(root, ['binary_expression', 'switch_statement', 'call_expression'], []) {
		stats.checked++
		match node_kind(node) {
			'binary_expression' {
				c.uin_binary(node, mut findings)!
			}
			'switch_statement' {
				if o.enforce_for_switch_case {
					c.uin_switch(node, mut findings)
				}
			}
			else {
				if o.enforce_for_index_of {
					c.uin_call(node, mut findings)!
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uin_is_nan ports isNaNIdentifier: `NaN` or `Number.NaN`, also as the last expression of a
// SequenceExpression.
fn (c &Checker) uin_is_nan(n C.TSNode) bool {
	node := es_sequence_last(n)
	return c.es_is_specific_id(node, 'NaN') || c.es_is_specific_member_access(node, 'Number', 'NaN')
}

// uin_binary ports checkBinaryExpression: a comparison with NaN. An equality whose NaN is not a
// SequenceExpression gets the suggestion `Number.isNaN(value)`, and `==` and `!=` also
// `Number.isNaN(Number(value))`, with `!` for an inequality; a value that is a SequenceExpression
// is wrapped in parentheses.
fn (mut c Checker) uin_binary(node C.TSNode, mut findings []Finding) ! {
	operator := c.text(node_field(node, 'operator') or { return })
	if operator !in uin_comparison_operators {
		return
	}
	left := node_field(node, 'left') or { return }
	right := node_field(node, 'right') or { return }
	left_nan := c.uin_is_nan(left)
	if !left_nan && !c.uin_is_nan(right) {
		return
	}
	nan_node := unwrap_parens(if left_nan { left } else { right })
	mut suggestions := []Suggestion{}
	if operator in ['==', '===', '!=', '!=='] && node_kind(nan_node) != 'sequence_expression' {
		compared := unwrap_parens(if left_nan { right } else { left })
		mut value := c.text(compared)
		if node_kind(compared) == 'sequence_expression' {
			value = '(${value})'
		}
		negation := if operator.starts_with('!') { '!' } else { '' }
		_, is_nan := c.suggestion('replaceWithIsNaN', map[string]string{}, [
			fix_replace(node, '${negation}Number.isNaN(${value})'),
		])!
		suggestions << is_nan
		if operator in ['==', '!='] {
			_, cast := c.suggestion('replaceWithCastingAndIsNaN', map[string]string{}, [
				fix_replace(node, '${negation}Number.isNaN(Number(${value}))'),
			])!
			suggestions << cast
		}
	}
	findings << Finding{
		stmt:        position_of(node)
		message_id:  'comparisonWithNaN'
		suggestions: suggestions
	}
}

// uin_switch ports checkSwitchStatement: `switch (NaN)`, then each `case NaN:`.
fn (c &Checker) uin_switch(node C.TSNode, mut findings []Finding) {
	if discriminant := node_field(node, 'value') {
		if c.uin_is_nan(discriminant) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'switchNaN'
			}
		}
	}
	body := node_field(node, 'body') or { return }
	for switch_case in named_children(body) {
		if node_kind(switch_case) != 'switch_case' {
			continue
		}
		test := node_field(switch_case, 'value') or { continue }
		if c.uin_is_nan(test) {
			findings << Finding{
				stmt:       position_of(switch_case)
				message_id: 'caseNaN'
			}
		}
	}
}

// uin_call ports checkCallExpression: `indexOf(NaN)` and `lastIndexOf(NaN)` called on something,
// with at most two arguments. With NaN alone, and not as a SequenceExpression, the suggestion is
// findIndex or findLastIndex with Number.isNaN (the name in double quotes for a computed
// property).
fn (mut c Checker) uin_call(node C.TSNode, mut findings []Finding) ! {
	callee := unwrap_parens(node_field(node, 'function') or { return })
	if node_kind(callee) !in ['member_expression', 'subscript_expression'] {
		return
	}
	method := c.es_static_property_name(callee) or { return }
	if method !in ['indexOf', 'lastIndexOf'] {
		return
	}
	arguments := (call_arguments(node) or { return }).filter(node_kind(it) != 'comment')
	if arguments.len == 0 || arguments.len > 2 || !c.uin_is_nan(arguments[0]) {
		return
	}
	mut suggestions := []Suggestion{}
	first := unwrap_parens(arguments[0])
	if node_kind(first) != 'sequence_expression' && arguments.len == 1 {
		find_method := if method == 'indexOf' { 'findIndex' } else { 'findLastIndex' }
		computed := node_kind(callee) == 'subscript_expression'
		property := if computed {
			unwrap_parens(node_field(callee, 'index') or { return })
		} else {
			node_field(callee, 'property') or { return }
		}
		_, suggestion := c.suggestion('replaceWithFindIndex', {
			'methodName': find_method
		}, [
			fix_replace(property, if computed { '"${find_method}"' } else { find_method }),
			fix_replace(first, 'Number.isNaN'),
		])!
		suggestions << suggestion
	}
	findings << Finding{
		stmt:        position_of(node)
		message_id:  'indexOfNaN'
		data:        {
			'methodName': method
		}
		suggestions: suggestions
	}
}
