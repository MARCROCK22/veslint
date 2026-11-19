module rules

import estree

// extractPropertyReferences of eslint-plugin-regexp 3.3.3 (lib/utils/ast-utils/
// extract-property-references.ts), for the `regexp/*` rules (regexp_utils.v): the properties read
// from the value of an expression (`x.foo`, `const {foo} = x`, `for (… of x)`), through variables,
// destructurings and shallow copies (`[...x]`, `{...x}`). Each reference can give the references
// of its own value (upstream a generator, `extractPropertyReferences`): `sub` says how to compute
// them (rx_property_references_of).

// RxPropRefKind is the `type` of a PropertyReference.
enum RxPropRefKind {
	unknown
	member
	destructuring
	iteration
}

// RxPropSubKind is how the references of a reference's value are found: none (an `unknown`
// reference without them), those of an expression (rx_property_references), those of a pattern
// (rx_property_references_for_pattern) or those of the left side of a for-of statement.
enum RxPropSubKind {
	none
	expression
	pattern
	for_of
}

// RxPropRef is a PropertyReference: `name` for member and destructuring references, and the
// node its own references come from (`sub`, `sub_node`).
struct RxPropRef {
	kind     RxPropRefKind
	name     string
	node     int
	sub      RxPropSubKind
	sub_node int = -1
}

// rx_property_references_of ports `ref.extractPropertyReferences()`.
fn (mut c Checker) rx_property_references_of(root C.TSNode, t &estree.EsTree, ref RxPropRef) []RxPropRef {
	return match ref.sub {
		.none {
			[]RxPropRef{}
		}
		.expression {
			c.rx_property_references(root, t, ref.sub_node)
		}
		.pattern {
			c.rx_property_references_for_pattern(root, t, ref.sub_node)
		}
		.for_of {
			mut left := t.node(ref.sub_node, .left) or { -1 }
			if left >= 0 && t.typ(left) == .variable_declaration {
				declarations := t.list(left, .declarations) or { []int{} }
				left = if declarations.len > 0 { t.node(declarations[0], .id) or { -1 } } else { -1 }
			}
			c.rx_property_references_for_pattern(root, t, left)
		}
	}
}

// rx_property_references ports extractPropertyReferences.
fn (mut c Checker) rx_property_references(root C.TSNode, t &estree.EsTree, node int) []RxPropRef {
	if rx_is_shallow_copy(t, node) {
		return c.rx_property_references_for_shallow_copy(root, t, node)
	}
	mut out := []RxPropRef{}
	for ref in c.rx_expression_references(root, t, node) {
		match ref.kind {
			.member {
				out << c.rx_property_references_for_member(root, t, ref.other)
			}
			.destructuring {
				out << c.rx_property_references_for_pattern(root, t, ref.other)
			}
			.iteration {
				out << RxPropRef{
					kind:     .iteration
					node:     ref.other
					sub:      .for_of
					sub_node: ref.other
				}
			}
			else {
				if ref.node != node && rx_is_shallow_copy(t, ref.node) {
					out << c.rx_property_references_for_shallow_copy(root, t, ref.node)
					return out
				}
				out << RxPropRef{
					kind: .unknown
					node: ref.node
				}
			}
		}
	}
	return out
}

// rx_property_references_for_pattern ports extractPropertyReferencesForPattern
// (iteratePropertyReferencesForPattern).
fn (mut c Checker) rx_property_references_for_pattern(root C.TSNode, t &estree.EsTree, node int) []RxPropRef {
	mut target := node
	for target >= 0 && t.typ(target) == .assignment_pattern {
		target = t.node(target, .left) or { -1 }
	}
	if target < 0 {
		return [RxPropRef{
			kind: .unknown
			node: node
		}]
	}
	mut out := []RxPropRef{}
	match t.typ(target) {
		.identifier {
			for expr_ref in c.rx_expression_references_for_variable(root, t, target) {
				out << c.rx_property_references(root, t, expr_ref.node)
			}
		}
		.object_pattern {
			for prop in t.list(target, .properties) or { []int{} } {
				if t.typ(prop) == .rest_element {
					out << c.rx_property_references_for_pattern(root, t, t.node(prop, .argument) or {
						-1
					})
					continue
				}
				value := t.node(prop, .value) or { -1 }
				if name := c.rx_property_of(root, t, prop) {
					out << RxPropRef{
						kind:     .destructuring
						name:     name
						node:     prop
						sub:      .pattern
						sub_node: value
					}
				} else {
					out << RxPropRef{
						kind:     .unknown
						node:     target
						sub:      .pattern
						sub_node: value
					}
				}
			}
		}
		.array_pattern {
			elements := t.list(target, .elements) or { []int{} }
			mut index := 0
			for index < elements.len {
				element := elements[index]
				if element < 0 {
					index++
					continue
				}
				if t.typ(element) == .rest_element {
					for ref in c.rx_property_references_for_pattern(root, t, t.node(element,
						.argument) or { -1 })
					{
						out << rx_offset_ref(ref, index)
					}
					index++
					break
				}
				out << RxPropRef{
					kind:     .destructuring
					name:     '${index}'
					node:     element
					sub:      .pattern
					sub_node: element
				}
				index++
			}
			for index < elements.len {
				element := elements[index]
				index++
				if element < 0 {
					continue
				}
				out << RxPropRef{
					kind:     .unknown
					node:     element
					sub:      .pattern
					sub_node: element
				}
			}
		}
		else {
			out << RxPropRef{
				kind: .unknown
				node: target
			}
		}
	}
	return out
}

// rx_is_shallow_copy ports isShallowCopy: the argument of a spread in an object or array literal.
fn rx_is_shallow_copy(t &estree.EsTree, node int) bool {
	parent := rx_parent(t, node)
	if parent >= 0 && t.typ(parent) == .spread_element {
		spread_parent := rx_parent(t, parent)
		return spread_parent >= 0
			&& t.typ(spread_parent) in [.object_expression, .array_expression]
	}
	return false
}

// rx_property_references_for_member ports iteratePropertyReferencesForMemberExpression.
fn (mut c Checker) rx_property_references_for_member(root C.TSNode, t &estree.EsTree, node int) RxPropRef {
	if name := c.rx_property_of(root, t, node) {
		return RxPropRef{
			kind:     .member
			name:     name
			node:     node
			sub:      .expression
			sub_node: node
		}
	}
	return RxPropRef{
		kind:     .unknown
		node:     node
		sub:      .expression
		sub_node: node
	}
}

// rx_property_references_for_shallow_copy ports iteratePropertyReferencesForShallowCopy.
fn (mut c Checker) rx_property_references_for_shallow_copy(root C.TSNode, t &estree.EsTree, node int) []RxPropRef {
	spread := rx_parent(t, node)
	spread_parent := rx_parent(t, spread)
	if t.typ(spread_parent) == .object_expression {
		return c.rx_property_references(root, t, spread_parent)
	}
	elements := t.list(spread_parent, .elements) or { []int{} }
	index := elements.index(spread)
	if index == 0 {
		return c.rx_property_references(root, t, spread_parent)
	}
	has_spread := elements[..if index < 0 { 0 } else { index }].any(it >= 0
		&& t.typ(it) == .spread_element)
	mut out := []RxPropRef{}
	for ref in c.rx_property_references(root, t, spread_parent) {
		if has_spread {
			out << RxPropRef{
				kind:     .unknown
				node:     ref.node
				sub:      ref.sub
				sub_node: ref.sub_node
			}
		} else {
			out << rx_offset_ref(ref, -index)
		}
	}
	return out
}

// rx_property_of ports getProperty: the name a member expression reads or a property destructures
// (a string or number literal key, a static computed one, an identifier); none otherwise.
fn (mut c Checker) rx_property_of(root C.TSNode, t &estree.EsTree, node int) ?string {
	if t.typ(node) == .member_expression {
		property := t.node(node, .property)?
		if t.flag(node, .computed) or { false } {
			if t.typ(property) == .literal {
				if value := rx_literal_name(t, property) {
					return value
				}
			}
			return c.rx_string_if_constant(root, t, property)
		}
		if t.typ(property) == .identifier {
			return t.string_of(property, .name)
		}
		return none
	}
	if t.typ(node) == .property {
		key := t.node(node, .key)?
		if t.typ(key) == .literal {
			if value := rx_literal_name(t, key) {
				return value
			}
		}
		if t.flag(node, .computed) or { false } {
			return c.rx_string_if_constant(root, t, key)
		}
		if t.typ(key) == .identifier {
			return t.string_of(key, .name)
		}
	}
	return none
}

// rx_literal_name is String(value) of a string or number literal.
fn rx_literal_name(t &estree.EsTree, node int) ?string {
	v := t.get(node, .value)
	if v is string {
		return v
	}
	if v is f64 {
		return js_number_to_string(v)
	}
	return none
}

// rx_offset_ref ports offsetRef: the index a member or destructuring reference names, shifted.
fn rx_offset_ref(ref RxPropRef, offset int) RxPropRef {
	if ref.kind in [.member, .destructuring] {
		// Number(name): a name that is not a number is kept.
		if ref.name.len > 0 && (ref.name.bytes().all(it.is_digit())
			|| (ref.name[0] == `-` && ref.name.len > 1 && ref.name[1..].bytes().all(it.is_digit()))) {
			return RxPropRef{
				...ref
				name: '${ref.name.int() + offset}'
			}
		}
	}
	return ref
}
