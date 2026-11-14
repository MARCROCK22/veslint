module rules

import estree
import time

// Port of the `unicorn/no-array-method-this-argument` rule of eslint-plugin-unicorn 64.0.0 (it has
// no options), with its fix and suggestions.

const unamta_messages = {
	'error-prototype-method': 'Do not use the `this` argument in `Array#{{method}}()`.'
	'error-static-method':    'Do not use the `this` argument in `Array.{{method}}()`.'
	'suggestion-remove':      'Remove this argument.'
	'suggestion-bind':        'Use a bound function.'
}

const unamta_ignored = ['lodash.every', '_.every', 'underscore.every', 'lodash.filter', '_.filter',
	'underscore.filter', 'Vue.filter', 'R.filter', 'lodash.find', '_.find', 'underscore.find', 'R.find',
	'lodash.findLast', '_.findLast', 'underscore.findLast', 'R.findLast', 'lodash.findIndex',
	'_.findIndex', 'underscore.findIndex', 'R.findIndex', 'lodash.findLastIndex', '_.findLastIndex',
	'underscore.findLastIndex', 'R.findLastIndex', 'lodash.flatMap', '_.flatMap', 'lodash.forEach',
	'_.forEach', 'React.Children.forEach', 'Children.forEach', 'R.forEach', 'lodash.map', '_.map',
	'underscore.map', 'React.Children.map', 'Children.map', 'jQuery.map', '$.map', 'R.map',
	'lodash.some', '_.some', 'underscore.some']

fn (mut c Checker) lint_unicorn_no_array_method_this_argument(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		arguments := t.list(node, .arguments) or { continue }
		// Prototype methods
		if un_is_method_call(t, node,
			methods:          ['every', 'filter', 'find', 'findLast', 'findIndex', 'findLastIndex',
				'flatMap', 'forEach', 'map', 'some']
			arguments_length: 2
			optional_call:    false
		) && !un_is_node_matches(t, t.node(node, .callee) or { continue }, unamta_ignored)
			&& !un_is_node_value_not_function(t, arguments[0]) {
			findings << c.unamta_problem(t, tokens, node, arguments[0], arguments[1], 'error-prototype-method')!
		}
		// `Array.from()` and `Array.fromAsync()`
		if un_is_method_call(t, node,
			objects:          ['Array']
			methods:          ['from', 'fromAsync']
			arguments_length: 3
			optional_call:    false
			optional_member:  false
		) && !un_is_node_value_not_function(t, arguments[1]) {
			findings << c.unamta_problem(t, tokens, node, arguments[1], arguments[2], 'error-static-method')!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) unamta_problem(t &estree.EsTree, tokens &SourceTokens, call int, callback int, this_argument int, message_id string) !Finding {
	property := t.node(t.node(call, .callee) or { -1 }, .property) or { -1 }
	finding := Finding{
		stmt:       c.es_tree_position(t, this_argument)
		message_id: message_id
		data:       {
			'method': t.string_of(property, .name) or { '' }
		}
	}
	remove := c.un_remove_argument(t, tokens, this_argument) or { return finding }
	if t.typ(callback) == .arrow_function_expression {
		if un_has_side_effect(t, this_argument) {
			return Finding{
				...finding
				suggestions: [Suggestion{
					message_id: 'suggestion-remove'
					fix:        remove
				}]
			}
		}
		return Finding{
			...finding
			has_fix: true
			fix:     remove
		}
	}
	mut fixes := [remove]
	parentheses := c.un_parentheses(t, tokens, callback)
	last_end := if parentheses.len > 0 { parentheses.last().end } else { t.nodes[callback].end }
	if parentheses.len == 0 && c.un_member_object_needs_parens(t, tokens, callback) {
		fixes << fix_insert_at(t.nodes[callback].start, '(')
		fixes << fix_insert_at(last_end, ')')
	}
	fixes << fix_insert_at(last_end, '.bind(${c.un_parenthesized_text(t, tokens, this_argument)})')
	_, bind := c.merge_fixes(fixes)!
	return Finding{
		...finding
		suggestions: [
			Suggestion{
				message_id: 'suggestion-remove'
				fix:        remove
			},
			Suggestion{
				message_id: 'suggestion-bind'
				fix:        bind
			},
		]
	}
}
