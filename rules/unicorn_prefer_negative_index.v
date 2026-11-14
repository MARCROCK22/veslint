module rules

import estree
import time

// Port of the `unicorn/prefer-negative-index` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const upni_messages = {
	'prefer-negative-index': 'Prefer negative index over length minus index for `{{method}}`.'
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
		'with' {
			UpniMethod{[0], ['Array', ...un_typed_arrays]}
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

fn upni_parse(t &estree.EsTree, node int) ?UpniParsed {
	callee := t.node(node, .callee)?
	original := t.list(node, .arguments) or { []int{} }
	method := upni_member_name(t, callee)
	if _ := upni_method(method) {
		return UpniParsed{method, t.node(callee, .object)?, original}
	}
	if method != 'call' && method != 'apply' {
		return none
	}
	object := t.node(callee, .object)?
	inner := upni_member_name(t, object)
	m := upni_method(inner)?
	parent_callee := t.node(object, .object)?
	parent_object := t.node(parent_callee, .object) or { -1 }
	if un_is_empty_array(t, parent_callee) || (inner == 'slice'
		&& un_is_literal_string(t, parent_callee, ''))
		|| (upni_member_name(t, parent_callee) == 'prototype' && parent_object >= 0
		&& t.typ(parent_object) == .identifier
		&& (t.string_of(parent_object, .name) or { '' }) in m.support_objects) {
		target := if original.len > 0 { original[0] } else { -1 }
		if method == 'apply' {
			if original.len < 2 || t.typ(original[1]) != .array_expression {
				return none
			}
			return UpniParsed{inner, target, t.list(original[1], .elements) or { []int{} }}
		}
		return UpniParsed{inner, target, if original.len > 0 { original[1..] } else { []int{} }}
	}
	return none
}

// upni_length_node ports getNegativeIndexLengthNode.
fn (c &Checker) upni_length_node(t &estree.EsTree, node int, object int) ?int {
	if node < 0 || t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return none
	}
	right := t.node(node, .right)?
	value := t.get(right, .value)
	if t.typ(right) != .literal || !(value is f64 && value > 0) {
		return none
	}
	left := t.node(node, .left)?
	if t.typ(left) == .member_expression && !(t.flag(left, .computed) or { false })
		&& !(t.flag(left, .optional) or { false }) && upni_member_name(t, left) == 'length'
		&& c.un_is_same_reference(t, t.node(left, .object)?, object) {
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
		mut fixes := []Fix{}
		for index in m.arguments_indexes {
			if index >= parsed.arguments.len {
				continue
			}
			length_node := c.upni_length_node(t, parsed.arguments[index], parsed.target) or { continue }
			// removeLengthNode
			start, end := c.un_parenthesized_range(t, tokens, length_node)
			fixes << fix_remove_range(start, c.un_remove_spaces_after(end).end)
		}
		if fixes.len == 0 {
			continue
		}
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-negative-index'
			data:       {
				'method': parsed.method
			}
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
