module rules

import estree
import jsregexp
import json2
import time

// Port of the `unicorn/prefer-array-flat` rule of eslint-plugin-unicorn 64.0.0, with its option
// and fix.

const upaf_messages = {
	'prefer-array-flat': 'Prefer `Array#flat()` over `{{description}}` to flatten an array.'
}

fn upaf_options(options []json2.Any) ![]string {
	o := option_object(unicorn_prefer_array_flat, options, ['functions'])!
	list := o.values['functions'] or { return []string{} }
	if list is []json2.Any {
		return list.map(it.str())
	}
	return []string{}
}

// UpafCase is a case the rule reports: `array` is the array to flatten.
struct UpafCase {
	description    string
	array          int
	optional       bool
	switch_toarray bool
}

fn upaf_is_definitely_array(t &estree.EsTree, node int) bool {
	callee := t.node(node, .callee) or { -1 }
	return t.typ(node) == .array_expression || (t.typ(node) == .new_expression
		&& t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'Array')
}

fn upaf_is_definitely_non_array(t &estree.EsTree, node int) bool {
	callee := t.node(node, .callee) or { -1 }
	return t.typ(node) in [.object_expression, .literal, .template_literal, .arrow_function_expression,
		.function_expression, .class_expression] || (t.typ(node) == .new_expression
		&& t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) != 'Array')
}

// upaf_non_array_receiver ports isObviouslyNonArrayFlatMapReceiver.
fn (mut c Checker) upaf_non_array_receiver(root C.TSNode, t &estree.EsTree, node int, pascal &jsregexp.JsRegex) bool {
	initializer := c.un_const_initializer(root, t, node) or { -1 }
	if t.typ(node) == .identifier
		&& (pascal.test(utf16_units(t.string_of(node, .name) or { '' })) or { false })
		&& !(initializer >= 0 && upaf_is_definitely_array(t, initializer)) {
		return true
	}
	return initializer >= 0 && upaf_is_definitely_non_array(t, initializer)
}

fn (mut c Checker) upaf_cases(root C.TSNode, t &estree.EsTree, node int, functions []string, pascal &jsregexp.JsRegex) []UpafCase {
	mut cases := []UpafCase{}
	callee := t.node(node, .callee) or { -1 }
	arguments := t.list(node, .arguments) or { []int{} }
	// `array.flatMap(x => x)`
	if un_is_method_call(t, node, methods: ['flatMap'], arguments_length: 1, optional_call: false) {
		first := arguments[0]
		params := t.list(first, .params) or { []int{} }
		object := t.node(callee, .object) or { -1 }
		if t.typ(first) == .arrow_function_expression && !(t.flag(first, .async) or { false })
			&& params.len == 1
			&& un_is_same_identifier(t, params[0], t.node(first, .body) or { -1 })
			&& !c.upaf_non_array_receiver(root, t, object, pascal) {
			cases << UpafCase{'Array#flatMap()', object, t.flag(callee, .optional) or { false }, false}
		}
	}
	// `array.reduce((a, b) => a.concat(b), [])`, `array.reduce((a, b) => [...a, ...b], [])`
	if un_is_method_call(t, node, methods: ['reduce'], arguments_length: 2, optional_call: false) {
		first := arguments[0]
		params := t.list(first, .params) or { []int{} }
		if t.typ(first) == .arrow_function_expression && !(t.flag(first, .async) or { false })
			&& params.len == 2 && un_is_empty_array(t, arguments[1]) {
			body := t.node(first, .body) or { -1 }
			body_arguments := t.list(body, .arguments) or { []int{} }
			elements := t.list(body, .elements) or { []int{} }
			concat := un_is_method_call(t, body,
				methods:          ['concat']
				arguments_length: 1
				optional_call:    false
				optional_member:  false
			) && un_is_same_identifier(t, params[0], t.node(t.node(body, .callee) or { -1 }, .object) or {
				-1
			}) && un_is_same_identifier(t, params[1], body_arguments[0])
			spread := t.typ(body) == .array_expression && elements.len == 2 && elements.all(fn [t,
				elements, params] (e int) bool {
				if e < 0 || t.typ(e) != .spread_element {
					return false
				}
				argument := t.node(e, .argument) or { return false }
				return t.typ(argument) == .identifier
					&& un_is_same_identifier(t, params[elements.index(e)], argument)
			})
			if concat || spread {
				cases << UpafCase{'Array#reduce()', t.node(callee, .object) or { -1 }, t.flag(callee,
					.optional) or { false }, false}
			}
		}
	}
	// `[].concat(maybeArray)`, `[].concat(...array)`
	if un_is_method_call(t, node,
		methods:          ['concat']
		arguments_length: 1
		allow_spread:     true
		optional_call:    false
		optional_member:  false
	) && un_is_empty_array(t, t.node(callee, .object) or { -1 }) {
		first := arguments[0]
		spread := t.typ(first) == .spread_element
		cases << UpafCase{'[].concat()', if spread { t.node(first, .argument) or { -1 } } else { first }, false, !spread}
	}
	// `[].concat.apply([], array)`, `Array.prototype.concat.call([], maybeArray)`…
	if un_is_method_call(t, node,
		methods:          ['apply', 'call']
		arguments_length: 2
		allow_spread:     true
		optional_call:    false
		optional_member:  false
	) && un_is_prototype_property(t, t.node(callee, .object) or { -1 }, 'Array', ['concat']) {
		is_call := t.string_of(t.node(callee, .property) or { -1 }, .name) or { '' } == 'call'
		second := arguments[1]
		spread := t.typ(second) == .spread_element
		if un_is_empty_array(t, arguments[0]) && (is_call || !spread) {
			cases << UpafCase{'Array.prototype.concat()', if spread {
				t.node(second, .argument) or { -1 }
			} else {
				second
			}, false, !spread && is_call}
		}
	}
	// `_.flatten(array)` and the configured functions
	if un_is_call(t, node, arguments_length: 1, optional: false) && un_is_node_matches(t, callee,
		functions) {
		for name in functions {
			if un_node_matches_name_or_path(t, callee, name) {
				cases << UpafCase{'${name.trim_space()}()', arguments[0], false, false}
				break
			}
		}
	}
	return cases
}

fn (mut c Checker) lint_unicorn_prefer_array_flat(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut functions := upaf_options(c.rule_options(unicorn_prefer_array_flat))!
	functions << ['_.flatten', 'lodash.flatten', 'underscore.flatten']
	pascal := jsregexp.js_regex_new('^\\p{Lu}', 'u')!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		for found in c.upaf_cases(root, t, node, functions, &pascal) {
			array := found.array
			mut finding := Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'prefer-array-flat'
				data:       {
					'description': found.description
				}
			}
			// Don't fix if it has comments.
			if tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len == tokens.comments_inside(t.nodes[array].start,
				t.nodes[array].end).len {
				mut fixed := c.un_parenthesized_text(t, tokens, array)
				if found.switch_toarray {
					fixed = '[${fixed}]'
				} else if !c.un_is_parenthesized(t, tokens, array)
					&& c.un_member_object_needs_parens(t, tokens, array) {
					fixed = '(${fixed})'
				}
				fixed = '${fixed}${if found.optional { '?' } else { '' }}.flat()'
				if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), fixed) {
					fixed = ';${fixed}'
				}
				mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)]
				fixes << c.un_fix_space_around_keyword(t, tokens, node)
				has_fix, fix := c.merge_fixes(fixes)!
				finding = Finding{
					...finding
					has_fix: has_fix
					fix:     fix
				}
			}
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
