module rules

import estree
import time

// Port of the `unicorn/prefer-type-error` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix.

const upte_messages = {
	'prefer-type-error': '`new Error()` is too unspecific for a type check. Use `new TypeError()` instead.'
}

const upte_type_checks = ['isArguments', 'isArray', 'isArrayBuffer', 'isArrayLike',
	'isArrayLikeObject', 'isBigInt', 'isBoolean', 'isBuffer', 'isDate', 'isElement', 'isError',
	'isFinite', 'isFunction', 'isInteger', 'isLength', 'isMap', 'isNaN', 'isNative', 'isNil', 'isNull',
	'isNumber', 'isObject', 'isObjectLike', 'isPlainObject', 'isPrototypeOf', 'isRegExp',
	'isSafeInteger', 'isSet', 'isString', 'isSymbol', 'isTypedArray', 'isUndefined', 'isView',
	'isWeakMap', 'isWeakSet', 'isWindow', 'isXMLDoc']

// upte_type_check_identifier ports isTypecheckingIdentifier: `call` is -1 for no call.
fn upte_type_check_identifier(t &estree.EsTree, node int, call int, member bool) bool {
	if call < 0 || (t.list(call, .arguments) or { []int{} }).len == 0 || t.typ(node) != .identifier {
		return false
	}
	name := t.string_of(node, .name) or { '' }
	return (member && name in upte_type_checks) || (!member && name in ['isNaN', 'isFinite'])
}

fn upte_type_check_member(t &estree.EsTree, node int, call int) bool {
	if upte_type_check_identifier(t, t.node(node, .property) or { return false }, call, true) {
		return true
	}
	object := t.node(node, .object) or { return false }
	return t.typ(object) == .member_expression && upte_type_check_member(t, object, call)
}

// upte_error_constructor ports isErrorConstructor.
fn upte_error_constructor(t &estree.EsTree, node int) bool {
	if t.typ(node) == .identifier {
		return utne_is_error_name(t.string_of(node, .name) or { '' })
	}
	if t.typ(node) == .member_expression && !(t.flag(node, .optional) or { false })
		&& !(t.flag(node, .computed) or { false }) {
		property := t.node(node, .property) or { return false }
		return t.typ(property) == .identifier
			&& utne_is_error_name(t.string_of(property, .name) or { '' })
	}
	return false
}

// upte_type_check_expression ports isTypecheckingExpression.
fn upte_type_check_expression(t &estree.EsTree, node int, call int) bool {
	operator := t.string_of(node, .operator) or { '' }
	return match t.typ(node) {
		.identifier {
			upte_type_check_identifier(t, node, call, false)
		}
		.member_expression {
			upte_type_check_member(t, node, call)
		}
		.call_expression {
			upte_type_check_expression(t, t.node(node, .callee) or { return false }, node)
		}
		.unary_expression {
			operator == 'typeof' || (operator == '!'
				&& upte_type_check_expression(t, t.node(node, .argument) or { return false }, -1))
		}
		.binary_expression {
			if operator == 'instanceof' {
				!upte_error_constructor(t, t.node(node, .right) or { return false })
			} else {
				upte_type_check_expression(t, t.node(node, .left) or { return false }, call)
					|| upte_type_check_expression(t, t.node(node, .right) or { return false }, call)
			}
		}
		.logical_expression {
			upte_type_check_expression(t, t.node(node, .left) or { return false }, call)
				&& upte_type_check_expression(t, t.node(node, .right) or { return false }, call)
		}
		else {
			false
		}
	}
}

fn (mut c Checker) lint_unicorn_prefer_type_error(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .throw_statement {
			continue
		}
		stats.checked++
		argument := t.node(node, .argument) or { continue }
		if !un_is_new(t, argument, names: ['Error']) {
			continue
		}
		// isLone: the only statement of its parent's `body`.
		parent := t.nodes[node].parent
		if parent < 0 || (t.list(parent, .body) or { continue }).len != 1 {
			continue
		}
		outer := t.nodes[parent].parent
		if outer < 0 || t.typ(outer) != .if_statement
			|| !upte_type_check_expression(t, t.node(outer, .test) or { continue }, -1) {
			continue
		}
		callee := t.node(argument, .callee) or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, callee)
			message_id: 'prefer-type-error'
			has_fix:    true
			fix:        fix_insert_at(t.nodes[callee].start, 'Type')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
