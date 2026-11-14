module rules

import estree
import math
import time

// Port of the `unicorn/prefer-negative-index` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix and its suggestion.

const upni_messages = {
	'prefer-negative-index':            'Prefer negative index over length minus index for `{{method}}`.'
	'prefer-negative-index/suggestion': 'Use a negative index.'
}

const un_typed_arrays = ['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array',
	'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array', 'Float64Array', 'BigInt64Array',
	'BigUint64Array']

struct UpniMethod {
	arguments_indexes []int
	support_objects   []string
}

fn upni_method(name string) ?UpniMethod {
	return match name {
		'slice' {
			UpniMethod{[0, 1], ['Array', 'String', 'ArrayBuffer', ...un_typed_arrays]}
		}
		'subarray' {
			UpniMethod{[0, 1], un_typed_arrays}
		}
		'splice', 'toSpliced' {
			UpniMethod{[0], ['Array']}
		}
		'at' {
			UpniMethod{[0], ['Array', 'String', ...un_typed_arrays]}
		}
		else {
			none
		}
	}
}

fn upni_member_name(t &estree.EsTree, node int) string {
	if node >= 0 && t.typ(node) == .member_expression {
		property := t.node(node, .property) or { return '' }
		if t.typ(property) == .identifier {
			return t.string_of(property, .name) or { '' }
		}
	}
	return ''
}

struct UpniParsed {
	method    string
	target    int
	arguments []int
}

// upni_is_method_owner ports isMethodOwner: `[]`, `''` (for `slice`) or `<Object>.prototype` of an
// object that has the method.
fn upni_is_method_owner(t &estree.EsTree, node int, method string, m UpniMethod) bool {
	if un_is_empty_array(t, node) {
		return true
	}
	if method == 'slice' && (un_static_string_value(t, node) or { 'x' }) == '' {
		return true
	}
	if upni_member_name(t, node) != 'prototype' {
		return false
	}
	object := t.node(node, .object) or { return false }
	return t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) in m.support_objects
}

fn upni_parse(t &estree.EsTree, node int) ?UpniParsed {
	callee := t.node(node, .callee)?
	original := t.list(node, .arguments) or { []int{} }
	name := upni_member_name(t, callee)
	if _ := upni_method(name) {
		return UpniParsed{name, t.node(callee, .object)?, original}
	}
	if name != 'call' && name != 'apply' {
		return none
	}
	object := t.node(callee, .object)?
	method := upni_member_name(t, object)
	m := upni_method(method)?
	if !upni_is_method_owner(t, t.node(object, .object)?, method, m) {
		return none
	}
	target := if original.len > 0 { original[0] } else { -1 }
	if name == 'call' {
		return UpniParsed{method, target, if original.len > 0 { original[1..] } else { []int{} }}
	}
	if original.len < 2 || t.typ(original[1]) != .array_expression {
		return none
	}
	return UpniParsed{method, target, t.list(original[1], .elements) or { []int{} }}
}

// upni_length_node ports getNegativeIndexLengthNode: the `.length` of `<object>.length - n` (n a
// positive safe integer), through nested subtractions.
fn (mut c Checker) upni_length_node(t &estree.EsTree, from int, object int) ?int {
	if from < 0 {
		return none
	}
	node := un_unwrap_ts_expression(t, from)
	if t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return none
	}
	right := un_unwrap_ts_expression(t, t.node(node, .right)?)
	value := t.get(right, .value)
	// `slice(length - n)` and `slice(-n)` only agree for a whole number of elements.
	if t.typ(right) != .literal || !(value is f64 && value > 0 && value == math.trunc(value)
		&& value <= 9007199254740991.0) {
		return none
	}
	left := t.node(node, .left)?
	if c.un_is_length_of(t, left, object) {
		return left
	}
	return c.upni_length_node(t, left, object)
}

fn (mut c Checker) lint_unicorn_prefer_negative_index(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		callee := t.node(node, .callee) or { continue }
		if t.typ(callee) != .member_expression {
			continue
		}
		parsed := upni_parse(t, node) or { continue }
		m := upni_method(parsed.method) or { continue }
		mut length_arguments := []int{}
		for index in m.arguments_indexes {
			if index < parsed.arguments.len && parsed.arguments[index] >= 0 {
				argument := parsed.arguments[index]
				if _ := c.upni_length_node(t, argument, parsed.target) {
					length_arguments << argument
				}
			}
		}
		if length_arguments.len == 0 {
			continue
		}
		mut fixes := []Fix{}
		mut aborted := false
		for argument in length_arguments {
			length_node := c.upni_length_node(t, argument, parsed.target) or { continue }
			// removeLengthNode: no fix when a comment would be lost.
			start, end := c.un_parenthesized_range(t, tokens, length_node)
			if un_has_comment_in_range(tokens, start, end) {
				aborted = true
				break
			}
			fixes << fix_remove_range(start, c.un_remove_spaces_after(end).end)
			// `foo.length - 1` would be left as `- 1` instead of `-1`.
			operator := tokens.after(end, false) or { continue }
			number := tokens.after(operator.end, false) or { continue }
			between := c.src[operator.end..number.start]
			if c.token_is(operator, '-') && number.kind == .numeric && between.len > 0
				&& between.runes().all(is_js_space(it)) {
				fixes << fix_remove_range(operator.end, number.start)
			}
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-negative-index'
			data:       {
				'method': parsed.method
			}
		}
		if !aborted {
			has_fix, fix := c.merge_fixes(fixes)!
			// `length - 1` and `-1` agree for every length, larger offsets do not when they exceed it.
			if length_arguments.all(c.un_is_length_minus_one_of(t, it, parsed.target)) {
				finding = Finding{
					...finding
					has_fix: has_fix
					fix:     fix
				}
			} else if has_fix {
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'prefer-negative-index/suggestion'
							fix:        fix
						},
					]
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
