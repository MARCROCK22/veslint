module rules

import estree
import time

// Port of the `unicorn/prefer-modern-math-apis` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fixes.

const upmma_messages = {
	'prefer-modern-math-apis': 'Prefer `{{replacement}}` over `{{description}}`.'
}

fn upmma_math_property(t &estree.EsTree, node int, property string) bool {
	return un_is_static_properties(t, node, 'Math', [property])
}

// upmma_math_call ports isMathMethodCall: `Math.<method>(x)` with one argument that is not spread.
fn upmma_math_call(t &estree.EsTree, node int, method string) bool {
	if t.typ(node) != .call_expression || (t.flag(node, .optional) or { false })
		|| !upmma_math_property(t, t.node(node, .callee) or { return false }, method) {
		return false
	}
	args := t.list(node, .arguments) or { return false }
	return args.len == 1 && t.typ(args[0]) != .spread_element
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

// upmma_flat_plus ports flatPlusExpression: the terms of nested `+`.
fn upmma_flat_plus(t &estree.EsTree, node int) []int {
	if t.typ(node) == .binary_expression && (t.string_of(node, .operator) or { '' }) == '+' {
		mut out := upmma_flat_plus(t, t.node(node, .left) or { return [node] })
		out << upmma_flat_plus(t, t.node(node, .right) or { return [node] })
		return out
	}
	return [node]
}

fn (mut c Checker) lint_unicorn_prefer_modern_math_apis(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
				expressions := upmma_flat_plus(t, (t.list(node, .arguments) or { continue })[0])
				if expressions.any(!c.upmma_pow2(t, it)) {
					continue
				}
				method := if expressions.len == 1 { 'abs' } else { 'hypot' }
				property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
				mut fixes := [fix_replace_range(t.nodes[property].start, t.nodes[property].end, method)]
				mut plus := []int{}
				if expressions.len > 1 {
					for expression in expressions {
						parent := t.nodes[expression].parent
						if parent !in plus {
							plus << parent
						}
					}
				}
				for expression in plus {
					left := t.node(expression, .left) or { continue }
					token := c.un_token_after_punctuator(tokens, t.nodes[left].end, '+') or { continue }
					fixes << c.un_replace_token_and_spaces_before(token, ',')
					fixes << c.un_remove_parentheses(t, tokens, expression)
				}
				for expression in expressions {
					left := t.node(expression, .left) or { continue }
					_, left_end := c.un_parenthesized_range(t, tokens, left)
					fixes << fix_remove_range(left_end, t.nodes[expression].end)
				}
				has_fix, fix := c.merge_fixes(fixes)!
				findings << Finding{
					stmt:       c.es_tree_position(t, property)
					message_id: 'prefer-modern-math-apis'
					data:       {
						'replacement': 'Math.${method}(…)'
						'description': 'Math.sqrt(…)'
					}
					has_fix:    has_fix
					fix:        fix
				}
			}
			.binary_expression {
				stats.checked++
				findings << c.upmma_log_checks(t, tokens, node)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upmma_log_checks ports the four checks of `Math.log(x)` with a constant.
fn (c &Checker) upmma_log_checks(t &estree.EsTree, tokens &SourceTokens, node int) []Finding {
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
			out << c.upmma_log_finding(t, tokens, node, log_call, method, description)
		}
	}
	for constant, method in {
		'LN10': 'log10'
		'LN2':  'log2'
	} {
		if operator == '/' && upmma_math_call(t, left, 'log') && upmma_math_property(t, right, constant) {
			out << c.upmma_log_finding(t, tokens, node, left, method, 'Math.log(…) / Math.${constant}')
		}
	}
	return out
}

fn (c &Checker) upmma_log_finding(t &estree.EsTree, tokens &SourceTokens, node int, log_call int, method string, description string) Finding {
	value := (t.list(log_call, .arguments) or { []int{} })[0]
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'prefer-modern-math-apis'
		data:       {
			'replacement': 'Math.${method}(…)'
			'description': description
		}
		has_fix:    true
		fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Math.${method}(${c.un_parenthesized_text(t,
			tokens, value)})')
	}
}
