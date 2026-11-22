module rules

import estree
import jsregexp
import json2
import time

// Port of the `unicorn/prefer-array-flat` rule of eslint-plugin-unicorn 79.0.0, with its option
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
	description string
	array       int
	optional    bool
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
fn (mut c Checker) upaf_non_array_receiver(root C.vt_node, t &estree.EsTree, node int, pascal &jsregexp.JsRegex) bool {
	initializer := c.un_const_initializer(root, t, node) or { -1 }
	if t.typ(node) == .identifier
		&& (pascal.test(utf16_units(t.string_of(node, .name) or { '' })) or { false })
		&& !(initializer >= 0 && upaf_is_definitely_array(t, initializer)) {
		return true
	}
	return initializer >= 0 && upaf_is_definitely_non_array(t, initializer)
}

fn (mut c Checker) upaf_cases(root C.vt_node, t &estree.EsTree, node int, functions []string, pascal &jsregexp.JsRegex) []UpafCase {
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
			cases << UpafCase{'Array#flatMap()', object, t.flag(callee, .optional) or { false }}
		}
	}
	// `array.reduce((a, b) => a.concat(b), [])`. Only that one is `.flat()`: `[...a, ...b]` spreads
	// every element (`['ab']` gives `['a', 'b']`).
	if un_is_method_call(t, node, methods: ['reduce'], arguments_length: 2, optional_call: false) {
		first := arguments[0]
		params := t.list(first, .params) or { []int{} }
		if t.typ(first) == .arrow_function_expression && !(t.flag(first, .async) or { false })
			&& params.len == 2 && un_is_empty_array(t, arguments[1]) {
			body := t.node(first, .body) or { -1 }
			body_arguments := t.list(body, .arguments) or { []int{} }
			if un_is_method_call(t, body,
				methods:          ['concat']
				arguments_length: 1
				optional_call:    false
				optional_member:  false
			) && un_is_same_identifier(t, params[0], t.node(t.node(body, .callee) or { -1 }, .object) or {
				-1
			}) && un_is_same_identifier(t, params[1], body_arguments[0]) {
				cases << UpafCase{'Array#reduce()', t.node(callee, .object) or { -1 }, t.flag(callee,
					.optional) or { false }}
			}
		}
	}
	// `[].concat(...array)`
	if un_is_method_call(t, node,
		methods:          ['concat']
		arguments_length: 1
		allow_spread:     true
		optional_call:    false
		optional_member:  false
	) && un_is_empty_array(t, t.node(callee, .object) or { -1 })
		&& t.typ(arguments[0]) == .spread_element {
		cases << UpafCase{'[].concat()', t.node(arguments[0], .argument) or { -1 }, false}
	}
	// `[].concat.apply([], array)`, `Array.prototype.concat.call([], ...array)`…
	if un_is_method_call(t, node,
		methods:          ['apply', 'call']
		arguments_length: 2
		allow_spread:     true
		optional_call:    false
		optional_member:  false
	) && un_is_prototype_property(t, t.node(callee, .object) or { -1 }, 'Array', ['concat']) {
		name := t.string_of(t.node(callee, .property) or { -1 }, .name) or { '' }
		second := arguments[1]
		spread := t.typ(second) == .spread_element
		if un_is_empty_array(t, arguments[0])
			&& ((name == 'apply' && !spread) || (name == 'call' && spread)) {
			cases << UpafCase{'Array.prototype.concat()', if spread {
				t.node(second, .argument) or { -1 }
			} else {
				second
			}, false}
		}
	}
	// `_.flatten(array)` and the configured functions
	if un_is_call(t, node, arguments_length: 1, optional: false) && un_is_node_matches(t, callee,
		functions) {
		for name in functions {
			if un_node_matches_name_or_path(t, callee, name) {
				cases << UpafCase{'${name.trim_space()}()', arguments[0], false}
				break
			}
		}
	}
	return cases
}

fn (mut c Checker) lint_unicorn_prefer_array_flat(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut functions := upaf_options(c.rule_options(unicorn_prefer_array_flat))!
	functions << ['_.flatten', 'lodash.flatten', 'underscore.flatten']
	pascal := jsregexp.js_regex_new('^\\p{Lu}', 'u')!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		for found in c.upaf_cases(root, t, node, functions, &pascal) {
			array := found.array
			// `.flat()` is only on arrays (not on typed arrays): a receiver known not to be one, or
			// `arguments`, is left.
			if array < 0 || c.un_is_known_non_array(mut ctx, array) || (t.typ(array) == .identifier
				&& (t.string_of(array, .name) or { '' }) == 'arguments') {
				continue
			}
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
				mut fixed := '${c.un_member_object_text(t, tokens, array, node)}${if found.optional {
					'?'
				} else {
					''
				}}.flat()'
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
