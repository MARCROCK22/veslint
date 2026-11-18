module svelte_compiler

import math
import strconv

// Helpers of src/compiler/utils/ast.js, is-reference and src/utils.js.

// object is the left-most identifier of a member expression or identifier (-1: none).
fn (t &Tree) object(expression int) int {
	mut e := expression
	for t.typ(e) == 'MemberExpression' {
		e = t.get(e, .object)
	}
	return if t.typ(e) == 'Identifier' { e } else { -1 }
}

// unwrap_pattern: the identifiers and member expressions of a pattern.
fn (t &Tree) unwrap_pattern(pattern int, mut nodes []int) {
	match t.typ(pattern) {
		'Identifier', 'MemberExpression' {
			nodes << pattern
		}
		'ObjectPattern' {
			for prop in t.list(pattern, .properties) {
				if t.typ(prop) == 'RestElement' {
					t.unwrap_pattern(t.get(prop, .argument), mut nodes)
				} else {
					t.unwrap_pattern(t.get(prop, .value), mut nodes)
				}
			}
		}
		'ArrayPattern' {
			for el in t.list(pattern, .elements) {
				if el >= 0 {
					t.unwrap_pattern(el, mut nodes)
				}
			}
		}
		'RestElement' {
			t.unwrap_pattern(t.get(pattern, .argument), mut nodes)
		}
		'AssignmentPattern' {
			t.unwrap_pattern(t.get(pattern, .left), mut nodes)
		}
		else {}
	}
}

fn (t &Tree) unwrap(pattern int) []int {
	mut nodes := []int{}
	t.unwrap_pattern(pattern, mut nodes)
	return nodes
}

// extract_identifiers: the identifiers of a pattern.
fn (t &Tree) extract_identifiers(pattern int) []int {
	return t.unwrap(pattern).filter(t.typ(it) == 'Identifier')
}

// extract_rest_flags: for each identifier of extract_identifiers(pattern), whether it is the
// argument of a `...rest` (extract_paths' is_rest).
fn (t &Tree) extract_paths(param int, mut ids []int, mut rest []bool) {
	match t.typ(param) {
		'Identifier' {
			ids << param
			rest << false
		}
		'ObjectPattern' {
			for prop in t.list(param, .properties) {
				if t.typ(prop) == 'RestElement' {
					arg := t.get(prop, .argument)
					if t.typ(arg) == 'Identifier' {
						ids << arg
						rest << true
					} else {
						t.extract_paths(arg, mut ids, mut rest)
					}
				} else {
					t.extract_paths(t.get(prop, .value), mut ids, mut rest)
				}
			}
		}
		'ArrayPattern' {
			for el in t.list(param, .elements) {
				if el < 0 {
					continue
				}
				if t.typ(el) == 'RestElement' {
					arg := t.get(el, .argument)
					if t.typ(arg) == 'Identifier' {
						ids << arg
						rest << true
					} else {
						t.extract_paths(arg, mut ids, mut rest)
					}
				} else {
					t.extract_paths(el, mut ids, mut rest)
				}
			}
		}
		'AssignmentPattern' {
			left := t.get(param, .left)
			if t.typ(left) == 'Identifier' {
				ids << left
				rest << false
			} else {
				t.extract_paths(left, mut ids, mut rest)
			}
		}
		else {}
	}
}

// extract_identifiers_from_destructuring: the leaf identifiers of a `let:` directive's expression.
fn (t &Tree) extract_identifiers_from_destructuring(node int, mut nodes []int) {
	match t.typ(node) {
		'Identifier' {
			nodes << node
		}
		'ObjectExpression' {
			for prop in t.list(node, .properties) {
				if t.typ(prop) == 'Property' {
					t.extract_identifiers_from_destructuring(t.get(prop, .value), mut nodes)
				} else {
					t.extract_identifiers_from_destructuring(t.get(prop, .argument), mut nodes)
				}
			}
		}
		'ArrayExpression' {
			for el in t.list(node, .elements) {
				if el >= 0 {
					t.extract_identifiers_from_destructuring(el, mut nodes)
				}
			}
		}
		else {}
	}
}

// is_reference is the is-reference package.
fn (t &Tree) is_reference(node int, parent int) bool {
	typ := t.typ(node)
	if typ == 'MemberExpression' {
		return !t.flag(node, .computed) && t.is_reference(t.get(node, .object), node)
	}
	if typ != 'Identifier' {
		return false
	}
	return match t.typ(parent) {
		'MemberExpression' { t.flag(parent, .computed) || node == t.get(parent, .object) }
		'MethodDefinition' { t.flag(parent, .computed) }
		'MetaProperty' { t.get(parent, .meta) == node }
		'PropertyDefinition', 'Property' {
			t.flag(parent, .computed) || node == t.get(parent, .value)
		}
		'ExportSpecifier', 'ImportSpecifier' { node == t.get(parent, .local) }
		'LabeledStatement', 'BreakStatement', 'ContinueStatement' { false }
		else { true }
	}
}

// unwrap_optional: the expression of a ChainExpression.
fn (t &Tree) unwrap_optional(node int) int {
	return if t.typ(node) == 'ChainExpression' { t.get(node, .expression) } else { node }
}

// has_await_expression: an `await` outside nested functions.
fn (t &Tree) has_await_expression(node int) bool {
	if node < 0 {
		return false
	}
	typ := t.typ(node)
	if typ == 'AwaitExpression' {
		return true
	}
	if typ in ['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression'] {
		return false
	}
	for ch in t.children(node) {
		if t.has_await_expression(ch) {
			return true
		}
	}
	return false
}

// get_name: a property key's name (nodes.js).
fn (t &Tree) get_name(node int) ?string {
	return match t.typ(node) {
		'Literal' { t.lit_string(node) }
		'PrivateIdentifier' { '#' + t.name(node) }
		'Identifier' { t.name(node) }
		else { none }
	}
}

// lit_string is String(node.value) of a Literal.
fn (t &Tree) lit_string(node int) string {
	return match t.lit_kind(node) {
		.string { t.text(node, .value) }
		.number { js_number_string(t.lit_num(node)) }
		.boolean {
			if t.flag(node, .value) { 'true' } else { 'false' }
		}
		.null_ { 'null' }
		.bigint { t.text(node, .bigint) }
		.regexp { '/' + t.text(node, .regex) }
	}
}

// Attributes (utils/ast.js).

// attr_value_kind: the kind of an Attribute's value: true, a node, a list.
fn (t &Tree) attr_is_true(attr int) bool {
	p := t.prop(attr, .value) or { return false }
	return p.kind == .boolean && p.b
}

fn (t &Tree) attr_is_list(attr int) bool {
	p := t.prop(attr, .value) or { return false }
	return p.kind == .list
}

fn (t &Tree) is_text_attribute(attr int) bool {
	if !t.attr_is_list(attr) {
		return false
	}
	v := t.list(attr, .value)
	return v.len == 1 && t.typ(v[0]) == 'Text'
}

fn (t &Tree) is_expression_attribute(attr int) bool {
	p := t.prop(attr, .value) or { return false }
	if p.kind == .node {
		return true
	}
	if p.kind == .list {
		return p.list.len == 1 && t.typ(p.list[0]) == 'ExpressionTag'
	}
	return false
}

fn (t &Tree) get_attribute_expression(attr int) int {
	p := t.prop(attr, .value) or { return -1 }
	if p.kind == .list {
		return if p.list.len > 0 { t.get(p.list[0], .expression) } else { -1 }
	}
	if p.kind == .node {
		return t.get(p.idx, .expression)
	}
	return -1
}

// get_attribute_chunks: the Text and ExpressionTag nodes of a value.
fn (t &Tree) get_attribute_chunks(attr int) []int {
	p := t.prop(attr, .value) or { return [] }
	return match p.kind {
		.list { p.list }
		.node { [p.idx] }
		else { []int{} }
	}
}

fn (t &Tree) is_event_attribute(attr int) bool {
	return t.is_expression_attribute(attr) && t.name(attr).starts_with('on')
}

// text_value: the data of a text attribute.
fn (t &Tree) text_value(attr int) string {
	v := t.list(attr, .value)
	return if v.len > 0 { t.text(v[0], .data) } else { '' }
}

// src/utils.js.

fn is_void(name string) bool {
	return name in void_element_names || name.to_lower() == '!doctype'
}

fn is_svg(name string) bool {
	return name in svg_elements
}

fn is_mathml(name string) bool {
	return name in mathml_elements
}

fn is_rune(name string) bool {
	return name in rune_names
}

fn is_state_creation_rune(name string) bool {
	return name in ['$state', '$state.raw', '$derived', '$derived.by']
}

fn is_reserved(word string) bool {
	return word in reserved_words
}

fn is_content_editable_binding(name string) bool {
	return name in content_editable_bindings
}

// is_custom_element_node (nodes.js): a RegularElement whose name has a `-` or that has an `is`.
fn (t &Tree) is_custom_element_node(node int) bool {
	if t.typ(node) != 'RegularElement' {
		return false
	}
	if t.name(node).contains('-') {
		return true
	}
	for a in t.list(node, .attributes) {
		if t.typ(a) == 'Attribute' && t.name(a) == 'is' {
			return true
		}
	}
	return false
}

// is_component_node (nodes.js).
fn (t &Tree) is_component_node(node int) bool {
	return t.typ(node) in ['Component', 'SvelteComponent', 'SvelteSelf']
}

// js_number_string ports ECMAScript Number::toString(10) from the shortest digits that keep the
// value (as rules/literals.v js_number_to_string).
fn js_number_string(x f64) string {
	if math.is_nan(x) {
		return 'NaN'
	}
	if x == 0 {
		return '0'
	}
	if x < 0 {
		return '-' + js_number_string(-x)
	}
	if math.is_inf(x, 1) {
		return 'Infinity'
	}
	sci := strconv.ftoa_64(x)
	mantissa, exponent := sci.split_once('e') or { return sci }
	digits := mantissa.replace('.', '')
	k := digits.len
	n := exponent.int() + 1
	if k <= n && n <= 21 {
		return digits + '0'.repeat(n - k)
	}
	if 0 < n && n <= 21 {
		return '${digits[..n]}.${digits[n..]}'
	}
	if -6 < n && n <= 0 {
		return '0.${'0'.repeat(-n)}${digits}'
	}
	sign := if n - 1 < 0 { '-' } else { '+' }
	e := math.abs(n - 1)
	if k == 1 {
		return '${digits}e${sign}${e}'
	}
	return '${digits[..1]}.${digits[1..]}e${sign}${e}'
}
