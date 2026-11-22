module rules

import estree
import time

// Port of the `unicorn/prefer-math-trunc` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its suggestions.

const upmt_messages = {
	'error-bitwise':      'Use `Math.trunc` instead of `{{operator}} {{value}}`.'
	'error-bitwise-not':  'Use `Math.trunc` instead of `~~`.'
	'error-parse-int':        'Use `Math.trunc` instead of `{{name}}(String(...), 10)`.'
	'suggestion-bitwise':     'Replace `{{operator}} {{value}}` with `Math.trunc`.'
	'suggestion-bitwise-not': 'Replace `~~` with `Math.trunc`.'
	'suggestion-parse-int':   'Replace `{{name}}(String(...), 10)` with `Math.trunc`.'
}

fn upmt_is_bitwise_not(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .unary_expression
		&& (t.string_of(node, .operator) or { '' }) == '~'
}

// upmt_call is mathTruncFunctionCall.
fn (c &Checker) upmt_call(t &estree.EsTree, tokens &SourceTokens, node int) string {
	return 'Math.trunc(${c.unb_call_argument_text(t, tokens, node)})'
}

// upmt_parse_int_name ports getParseIntName: `parseInt(…, …)` or `Number.parseInt(…, …)` of the
// globals; '' for anything else.
fn (mut c Checker) upmt_parse_int_name(root C.vt_node, t &estree.EsTree, node int) string {
	callee := t.node(node, .callee) or { return '' }
	if un_is_call(t, node, names: ['parseInt'], arguments_length: 2, optional: false)
		&& c.es_is_global_reference(root, t.ts_node(callee) or { return '' }) {
		return 'parseInt'
	}
	if un_is_method_call(t, node,
		objects:          ['Number']
		methods:          ['parseInt']
		arguments_length: 2
		optional_call:    false
		optional_member:  false
		computed:         false
	) && c.es_is_global_reference(root, t.ts_node(t.node(callee, .object) or { return '' }) or {
		return ''
	}) {
		return 'Number.parseInt'
	}
	return ''
}

// upmt_is_string_call ports isStringCall: `String(…)` of the global.
fn (mut c Checker) upmt_is_string_call(root C.vt_node, t &estree.EsTree, node int) bool {
	if !un_is_call(t, node, names: ['String'], arguments_length: 1, optional: false) {
		return false
	}
	return c.es_is_global_reference(root, t.ts_node(t.node(node, .callee) or { return false }) or {
		return false
	})
}

fn (mut c Checker) lint_unicorn_prefer_math_trunc(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ == .call_expression {
			stats.checked++
			name := c.upmt_parse_int_name(root, t, node)
			if name == '' {
				continue
			}
			args := t.list(node, .arguments) or { continue }
			string_call := args[0]
			if !c.upmt_is_string_call(root, t, string_call) || !unb_is_number_literal_of(t, args[1], 10) {
				continue
			}
			mut finding := Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error-parse-int'
				data:       {
					'name': name
				}
			}
			call_tokens := c.un_call_tokens(t, tokens, string_call) or { continue }
			if !c.unb_would_remove_comments(tokens, unb_node_range(t, node), [
				UnbRange{call_tokens.opening.end, call_tokens.closing.start},
			], false) {
				arguments_text := c.unb_call_arguments_text(t, tokens, string_call, true) or { continue }
				mut fixes := [
					fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Math.trunc(${arguments_text})'),
				]
				fixes << c.unb_fix_space_around_keyword(t, tokens, node)
				_, fix := c.merge_fixes(fixes)!
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'suggestion-parse-int'
							data:       finding.data
							fix:        fix
						},
					]
				}
			}
			findings << finding
			continue
		}
		if typ in [.binary_expression, .assignment_expression] {
			stats.checked++
			operator := t.string_of(node, .operator) or { continue }
			left := t.node(node, .left) or { continue }
			right := t.node(node, .right) or { continue }
			assignment := typ == .assignment_expression
			bare := if assignment { operator[..operator.len - 1] } else { operator }
			value := t.get(right, .value)
			if t.typ(right) != .literal || !(value is f64 && value == 0) || bare !in ['|', '>>', '<<', '^'] {
				continue
			}
			mut finding := Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error-bitwise'
				data:       {
					'operator': operator
					'value':    un_raw(t, right)
				}
			}
			// Comments in the copied operand are kept; an assignment copies the left operand twice,
			// so then there is no suggestion with comments.
			preserved := if assignment {
				[]UnbRange{}
			} else {
				[c.unb_parenthesized_range(t, tokens, left)]
			}
			if (!assignment || !unb_has_side_effect(t, left, false))
				&& !c.unb_would_remove_comments(tokens, unb_node_range(t, node), preserved, false) {
				fixed := c.upmt_call(t, tokens, left)
				mut fixes := []Fix{}
				if assignment {
					operator_token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or {
						continue
					}
					fixes << fix_replace_range(operator_token.start, operator_token.end, '=')
					fixes << fix_replace_range(t.nodes[right].start, t.nodes[right].end, fixed)
				} else {
					fixes << c.unb_fix_space_around_keyword(t, tokens, node)
					fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)
				}
				_, fix := c.merge_fixes(fixes)!
				// Every one of these coerces through ToInt32, which wraps where Math.trunc does not.
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'suggestion-bitwise'
							data:       finding.data
							fix:        fix
						},
					]
				}
			}
			findings << finding
			continue
		}
		if typ == .unary_expression {
			stats.checked++
			argument := t.node(node, .argument) or { continue }
			if !upmt_is_bitwise_not(t, node) || !upmt_is_bitwise_not(t, argument)
				|| upmt_is_bitwise_not(t, t.node(argument, .argument) or { -1 }) {
				continue
			}
			inner := t.node(argument, .argument) or { continue }
			mut finding := Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error-bitwise-not'
			}
			// `~~` wraps through ToInt32 too: only a suggestion, and none that would lose comments.
			if !c.unb_would_remove_comments(tokens, unb_node_range(t, node), [
				c.unb_parenthesized_range(t, tokens, inner),
			], false) {
				mut fixes := [
					fix_replace_range(t.nodes[node].start, t.nodes[node].end, c.upmt_call(t, tokens,
						inner)),
				]
				fixes << c.unb_fix_space_around_keyword(t, tokens, node)
				_, fix := c.merge_fixes(fixes)!
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'suggestion-bitwise-not'
							fix:        fix
						},
					]
				}
			}
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
