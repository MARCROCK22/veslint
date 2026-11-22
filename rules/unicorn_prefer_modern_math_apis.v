module rules

import estree
import math
import time

// Port of the `unicorn/prefer-modern-math-apis` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestions.

const upmma_messages = {
	'prefer-modern-math-apis': 'Prefer `{{replacement}}` over `{{description}}`.'
	'suggestion':              'Replace with `{{replacement}}`.'
}

// The values of the constants of Number and Math that getStaticNumber reads.
const upmma_number_constants = {
	'EPSILON':           2.220446049250313e-16
	'MAX_SAFE_INTEGER':  9007199254740991.0
	'MAX_VALUE':         1.7976931348623157e+308
	'MIN_SAFE_INTEGER':  -9007199254740991.0
	'MIN_VALUE':         5e-324
	'NEGATIVE_INFINITY': math.inf(-1)
	'NaN':               math.nan()
	'POSITIVE_INFINITY': math.inf(1)
}
const upmma_math_constants = {
	'E':       2.718281828459045
	'LN10':    2.302585092994046
	'LN2':     0.6931471805599453
	'LOG10E':  0.4342944819032518
	'LOG2E':   1.4426950408889634
	'PI':      3.141592653589793
	'SQRT1_2': 0.7071067811865476
	'SQRT2':   1.4142135623730951
}

fn upmma_math_property(t &estree.EsTree, node int, property string) bool {
	return un_is_member(t, node, objects: ['Math'], properties: [property], optional: false)
}

// upmma_math_call ports isMathMethodCall: `Math.<method>(x)`.
fn upmma_math_call(t &estree.EsTree, node int, method string) bool {
	return un_is_method_call(t, node,
		objects:          ['Math']
		methods:          [method]
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	)
}

// upmma_pow2 ports isPow2Expression: `x * x` or `x ** 2`.
fn (mut c Checker) upmma_pow2(t &estree.EsTree, node int) bool {
	if t.typ(node) != .binary_expression {
		return false
	}
	operator := t.string_of(node, .operator) or { '' }
	left := t.node(node, .left) or { return false }
	right := t.node(node, .right) or { return false }
	if operator == '*' {
		return c.un_is_same_reference(t, left, right)
	}
	value := t.get(right, .value)
	return operator == '**' && t.typ(right) == .literal && value is f64 && value == 2
}

// upmma_flat_plus ports flatPlusExpression: the terms of nested `+`, and every `+` in `plus`.
fn upmma_flat_plus(t &estree.EsTree, node int, mut plus []int) []int {
	if t.typ(node) == .binary_expression && (t.string_of(node, .operator) or { '' }) == '+' {
		plus << node
		mut out := upmma_flat_plus(t, t.node(node, .left) or { return [node] }, mut plus)
		out << upmma_flat_plus(t, t.node(node, .right) or { return [node] }, mut plus)
		return out
	}
	return [node]
}

// upmma_static_number ports getStaticNumber.
fn (mut c Checker) upmma_static_number(root C.vt_node, t &estree.EsTree, from int) ?f64 {
	mut node := un_unwrap_ts_expression(t, from)
	node = un_unwrap_ts_expression(t, c.un_const_initializer(root, t, node) or { node })
	operator := if t.typ(node) == .unary_expression { t.string_of(node, .operator) or { '' } } else { '' }
	argument := if operator in ['+', '-'] {
		un_unwrap_ts_expression(t, t.node(node, .argument) or { return none })
	} else {
		node
	}
	mut value := 0.0
	name := if t.typ(argument) == .identifier { t.string_of(argument, .name) or { '' } } else { '' }
	if name in ['Infinity', 'NaN', 'undefined'] {
		value = if name == 'Infinity' { math.inf(1) } else { math.nan() }
	} else if un_is_member(t, argument,
		objects:    ['Number']
		properties: upmma_number_constants.keys()
		optional:   false
		computed:   false
	) {
		property := t.node(argument, .property) or { return none }
		value = upmma_number_constants[t.string_of(property, .name) or { '' }] or { return none }
	} else if un_is_member(t, argument,
		objects:    ['Math']
		properties: upmma_math_constants.keys()
		optional:   false
		computed:   false
	) {
		property := t.node(argument, .property) or { return none }
		value = upmma_math_constants[t.string_of(property, .name) or { '' }] or { return none }
	} else {
		literal := un_primitive_literal_value(t, node)?
		if literal.kind == .bigint_ {
			return none
		}
		return js_to_number(literal)
	}
	return if operator == '-' { -value } else { value }
}

// upmma_value_unused ports isNumericValueUnused: the value is thrown away (`void`, a `for`
// update, not the last of a sequence…). The completion value of an expression statement can be
// observed by `eval()`.
fn upmma_value_unused(t &estree.EsTree, from int) bool {
	mut node := from
	for {
		expression := un_outermost_ts_expression(t, node)
		node = t.nodes[expression].parent
		if node < 0 {
			return false
		}
		match t.typ(node) {
			.unary_expression {
				return (t.string_of(node, .operator) or { '' }) in ['void', 'typeof', 'delete']
			}
			.for_statement {
				return (t.node(node, .init) or { -1 }) == expression
					|| (t.node(node, .update) or { -1 }) == expression
			}
			.sequence_expression {
				expressions := t.list(node, .expressions) or { []int{} }
				if expressions.len == 0 || expressions.last() != expression {
					return true
				}
			}
			.conditional_expression {
				if (t.node(node, .test) or { -1 }) == expression {
					return false
				}
			}
			.logical_expression {
				if (t.node(node, .left) or { -1 }) == expression {
					return false
				}
			}
			else {
				return false
			}
		}
	}
	return false
}

// upmma_can_fix_log ports canAutoFixLogCall.
fn (mut c Checker) upmma_can_fix_log(root C.vt_node, t &estree.EsTree, node int, value_node int) bool {
	if upmma_value_unused(t, node) {
		return true
	}
	value := c.upmma_static_number(root, t, value_node) or { return false }
	// These inputs have specified exact results for every logarithm base.
	return value <= 0 || value == 1 || math.is_nan(value) || math.is_inf(value, 0)
}

// upmma_can_fix_squares ports canAutoFixSquareExpressions.
fn (mut c Checker) upmma_can_fix_squares(root C.vt_node, t &estree.EsTree, node int, expressions []int) bool {
	mut values := []f64{}
	for expression in expressions {
		values << c.upmma_static_number(root, t, t.node(expression, .left) or { return false }) or {
			return false
		}
	}
	if upmma_value_unused(t, node) {
		return true
	}
	if values.len > 1 {
		if values.any(math.is_inf(it, 0)) {
			return values.all(!math.is_nan(it))
		}
		return values.all(it == 0) || values.any(math.is_nan(it))
	}
	value := values[0]
	if (t.string_of(expressions[0], .operator) or { '' }) == '**' {
		return value == 0 || math.is_nan(value) || math.is_inf(value, 0)
	}
	// Multiplication and the square root have specified rounding.
	return un_js_object_is(math.sqrt(value * value), math.abs(value))
}

// upmma_with_fix ports getProblemWithFix: the fix, or a suggestion when it can not be automatic.
fn upmma_with_fix(finding Finding, has_fix bool, fix Fix, can_auto_fix bool) Finding {
	if !has_fix {
		return finding
	}
	if can_auto_fix {
		return Finding{
			...finding
			has_fix: true
			fix:     fix
		}
	}
	return Finding{
		...finding
		suggestions: [
			Suggestion{
				message_id: 'suggestion'
				data:       finding.data
				fix:        fix
			},
		]
	}
}

fn (mut c Checker) lint_unicorn_prefer_modern_math_apis(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.call_expression {
				stats.checked++
				if !un_is_method_call(t, node,
					objects:          ['Math']
					methods:          ['sqrt']
					arguments_length: 1
					optional_call:    false
					optional_member:  false
				) {
					continue
				}
				mut plus := []int{}
				expressions := upmma_flat_plus(t, (t.list(node, .arguments) or { continue })[0], mut
					plus)
				if expressions.any(!c.upmma_pow2(t, it)) {
					continue
				}
				method := if expressions.len == 1 { 'abs' } else { 'hypot' }
				property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
				can_auto_fix := c.upmma_can_fix_squares(root, t, node, expressions)
				mut fixes := [fix_replace_range(t.nodes[property].start, t.nodes[property].end, method)]
				for expression in plus {
					left := t.node(expression, .left) or { continue }
					token := c.un_token_after_punctuator(tokens, t.nodes[left].end, '+') or { continue }
					fixes << c.un_replace_token_and_spaces_before(token, ',')
					fixes << c.un_remove_parentheses(t, tokens, expression)
				}
				mut aborted := false
				for expression in expressions {
					left := t.node(expression, .left) or { continue }
					_, left_end := c.un_parenthesized_range(t, tokens, left)
					// The removed range holds the operator and its right operand.
					if un_has_comment_in_range(tokens, left_end, t.nodes[expression].end) {
						aborted = true
						break
					}
					fixes << fix_remove_range(left_end, t.nodes[expression].end)
				}
				has_fix, fix := if aborted { false, Fix{} } else { c.merge_fixes(fixes)! }
				findings << upmma_with_fix(Finding{
					stmt:       c.es_tree_position(t, property)
					message_id: 'prefer-modern-math-apis'
					data:       {
						'replacement': 'Math.${method}(…)'
						'description': 'Math.sqrt(…)'
					}
				}, has_fix, fix, can_auto_fix)
			}
			.binary_expression {
				stats.checked++
				findings << c.upmma_log_checks(root, t, tokens, node)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upmma_log_checks ports the four checks of `Math.log(x)` with a constant.
fn (mut c Checker) upmma_log_checks(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, node int) []Finding {
	mut out := []Finding{}
	operator := t.string_of(node, .operator) or { return out }
	left := t.node(node, .left) or { return out }
	right := t.node(node, .right) or { return out }
	for constant, method in {
		'LOG10E': 'log10'
		'LOG2E':  'log2'
	} {
		if operator != '*' {
			break
		}
		mut log_call := -1
		mut description := ''
		if upmma_math_call(t, left, 'log') && upmma_math_property(t, right, constant) {
			log_call = left
			description = 'Math.log(…) * Math.${constant}'
		} else if upmma_math_call(t, right, 'log') && upmma_math_property(t, left, constant) {
			log_call = right
			description = 'Math.${constant} * Math.log(…)'
		}
		if log_call >= 0 {
			out << c.upmma_log_finding(root, t, tokens, node, log_call, method, description)
		}
	}
	for constant, method in {
		'LN10': 'log10'
		'LN2':  'log2'
	} {
		if operator == '/' && upmma_math_call(t, left, 'log') && upmma_math_property(t, right, constant) {
			out << c.upmma_log_finding(root, t, tokens, node, left, method, 'Math.log(…) / Math.${constant}')
		}
	}
	return out
}

fn (mut c Checker) upmma_log_finding(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, node int, log_call int, method string, description string) Finding {
	value := (t.list(log_call, .arguments) or { []int{} })[0]
	value_start, value_end := c.un_parenthesized_range(t, tokens, value)
	// The replacement is built from the argument alone, so a comment elsewhere would be lost.
	has_fix := !un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, [
		UnRange{value_start, value_end},
	])
	fix := fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Math.${method}(${c.un_parenthesized_text(t,
		tokens, value)})')
	return upmma_with_fix(Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'prefer-modern-math-apis'
		data:       {
			'replacement': 'Math.${method}(…)'
			'description': description
		}
	}, has_fix, fix, c.upmma_can_fix_log(root, t, node, value))
}
