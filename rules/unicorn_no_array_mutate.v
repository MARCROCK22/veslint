module rules

import estree
import json2
import time

// Port of the `unicorn/no-array-reverse` and `unicorn/no-array-sort` rules of eslint-plugin-unicorn
// 64.0.0 (rules/shared/no-array-mutate-rule.js), with their option and suggestions.

const unar_messages = {
	'error':                          'Use `Array#toReversed()` instead of `Array#reverse()`.'
	'suggestion-apply-replacement':   'Switch to `.toReversed()`.'
	'suggestion-spreading-array':     'The spreading object is an array.'
	'suggestion-not-spreading-array': 'The spreading object is NOT an array.'
}

const unas_messages = {
	'error':                          'Use `Array#toSorted()` instead of `Array#sort()`.'
	'suggestion-apply-replacement':   'Switch to `.toSorted()`.'
	'suggestion-spreading-array':     'The spreading object is an array.'
	'suggestion-not-spreading-array': 'The spreading object is NOT an array.'
}

fn unar_options(options []json2.Any) !bool {
	o := option_object(unicorn_no_array_reverse, options, ['allowExpressionStatement'])!
	return o.bool_value('allowExpressionStatement')!
}

fn unas_options(options []json2.Any) !bool {
	o := option_object(unicorn_no_array_sort, options, ['allowExpressionStatement'])!
	return o.bool_value('allowExpressionStatement')!
}

fn (mut c Checker) lint_unicorn_no_array_reverse(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	allow := unar_options(c.rule_options(unicorn_no_array_reverse))!
	return c.un_no_array_mutate(root, abs_path, mut stats, 'reverse', allow)
}

fn (mut c Checker) lint_unicorn_no_array_sort(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	allow := unas_options(c.rule_options(unicorn_no_array_sort))!
	return c.un_no_array_mutate(root, abs_path, mut stats, 'sort', allow)
}

fn un_no_array_mutate_predicate(t &estree.EsTree, node int, method string) bool {
	if method == 'reverse' {
		return un_is_method_call(t, node, methods: ['reverse'], arguments_length: 0, optional_call: false)
	}
	if !un_is_method_call(t, node, methods: ['sort'], maximum_arguments: 1, optional_call: false) {
		return false
	}
	args := t.list(node, .arguments) or { []int{} }
	return !(args.len > 0 && un_is_node_value_not_function(t, args[0]))
}

fn (mut c Checker) un_no_array_mutate(root C.TSNode, abs_path string, mut stats Stats, method string, allow_expression_statement bool) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	replacement := if method == 'reverse' { 'toReversed' } else { 'toSorted' }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_no_array_mutate_predicate(t, node, method) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		array := t.node(callee, .object) or { continue }
		elements := t.list(array, .elements) or { []int{} }
		// `[...array].reverse()`
		spread_and_mutate := t.typ(array) == .array_expression && elements.len == 1
			&& elements[0] >= 0 && t.typ(elements[0]) == .spread_element
		if allow_expression_statement && !spread_and_mutate {
			parent := t.nodes[node].parent
			statement := if t.typ(parent) == .chain_expression { t.nodes[parent].parent } else { parent }
			if t.typ(statement) == .expression_statement {
				continue
			}
		}
		property := t.node(callee, .property) or { continue }
		fix_method := fix_replace_range(t.nodes[property].start, t.nodes[property].end, replacement)
		mut suggestions := []Suggestion{}
		if spread_and_mutate {
			argument := t.node(elements[0], .argument) or { continue }
			_, fix := c.merge_fixes([
				fix_replace_range(t.nodes[array].start, t.nodes[array].end, c.un_parenthesized_text(t,
					tokens, argument)),
				fix_method,
			])!
			suggestions << Suggestion{
				message_id: 'suggestion-spreading-array'
				fix:        fix
			}
		}
		suggestions << Suggestion{
			message_id: if spread_and_mutate {
				'suggestion-not-spreading-array'
			} else {
				'suggestion-apply-replacement'
			}
			fix:        fix_method
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, property)
			message_id:  'error'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
