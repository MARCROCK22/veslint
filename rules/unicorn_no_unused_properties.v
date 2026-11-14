module rules

import estree
import time

// Port of the `unicorn/no-unused-properties` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options): the properties of an object literal (or of the type literal of an annotation) held by
// a variable that are never read through it.

const unup_messages = {
	'no-unused-properties': 'Property `{{name}}` is defined but never used.'
}

// UnupReference is a reference of unicorn's walk: the identifier of a scope reference (`init` for
// the initializer of its declaration), or the node that reads the object one level deeper (a
// member expression, a declarator or an assignment). `node` -1: an identifier without ESTree node,
// kept as a use.
struct UnupReference {
	node int
	init bool
}

fn (mut c Checker) lint_unicorn_no_unused_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	for v in 0 .. tree.variables.len {
		variable := tree.variables[v]
		if variable.scope < 0 || tree.scopes[variable.scope].kind == .global {
			continue
		}
		stats.checked++
		if variable.defs.len != 1 || !variable.references.any(tree.references[it].read) {
			continue
		}
		node := c.unup_definition_node(t, variable.defs[0])
		if node < 0 {
			continue
		}
		mut references := []UnupReference{}
		for r in variable.references {
			reference := tree.references[r]
			references << UnupReference{
				node: c.es_index_of(t, reference.identifier) or { -1 }
				init: reference.init
			}
		}
		c.unup_report_object(t, node, references, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unup_definition_node ports getDefinitionNode: the name of a parameter with a type annotation,
// else the node of the definition; -1 without ESTree node.
fn (mut c Checker) unup_definition_node(t &estree.EsTree, def ScopeDefinition) int {
	if def.kind == .parameter {
		if name := c.es_index_of(t, def.name) {
			if t.typ(name) == .identifier && t.node(name, .type_annotation) != none {
				return name
			}
		}
	}
	mut node := c.es_index_of(t, def.node) or { return -1 }
	// The declarator of `for (const [a] of …)` shares its node with its pattern.
	for def.kind == .variable && t.typ(node) != .variable_declarator && t.nodes[node].parent >= 0 {
		parent := t.nodes[node].parent
		parent_ts := t.ts_node(parent) or { break }
		if node_key(parent_ts) != node_key(def.node) {
			break
		}
		node = parent
	}
	return node
}

// unup_type_annotation ports getTypeAnnotation: `node.typeAnnotation.typeAnnotation`, -1 if none.
fn unup_type_annotation(t &estree.EsTree, node int) int {
	if node < 0 {
		return -1
	}
	annotation := t.node(node, .type_annotation) or { return -1 }
	return t.node(annotation, .type_annotation) or { -1 }
}

// unup_property_container ports getPropertyContainer: the object literal of the initializer or
// value of the node, or the type literal of its annotation; -1 if none.
fn unup_property_container(t &estree.EsTree, node int) int {
	mut value := t.node(node, .init) or { -1 }
	if value < 0 {
		value = t.node(node, .value) or { -1 }
	}
	value = un_unwrap_ts_expression(t, value)
	if value >= 0 && t.typ(value) == .object_expression {
		return value
	}
	mut type_annotation := unup_type_annotation(t, node)
	// getIdentifierTypeAnnotation: a declarator without initializer has none.
	if type_annotation < 0 && !(t.typ(node) == .variable_declarator && t.node(node, .init) == none) {
		type_annotation = unup_type_annotation(t, t.node(node, .id) or { -1 })
	}
	if type_annotation >= 0 && t.typ(type_annotation) == .ts_type_literal {
		return type_annotation
	}
	return -1
}

// unup_properties ports getProperties: the properties of an object literal, or the property
// signatures of a type literal.
fn unup_properties(t &estree.EsTree, container int) []int {
	if t.typ(container) == .object_expression {
		return t.list(container, .properties) or { []int{} }
	}
	return (t.list(container, .members) or { []int{} }).filter(t.typ(it) == .ts_property_signature)
}

// unup_has_method ports hasMethod: an object literal with a method, an accessor or a property
// whose value is a function expression.
fn unup_has_method(t &estree.EsTree, container int) bool {
	if t.typ(container) != .object_expression {
		return false
	}
	for property in t.list(container, .properties) or { []int{} } {
		if t.typ(property) != .property {
			continue
		}
		value := t.node(property, .value) or { -1 }
		if (t.flag(property, .method) or { false })
			|| (t.string_of(property, .kind) or { '' }) in ['get', 'set']
			|| (value >= 0 && t.typ(value) == .function_expression) {
			return true
		}
	}
	return false
}

// unup_key_name ports getPropertyKeyName: the name of an identifier, the value of a literal, or a
// static string; none for other keys. A regular expression is a value equal to no other.
fn unup_key_name(t &estree.EsTree, key int) ?JsValue {
	if key < 0 {
		return none
	}
	match t.typ(key) {
		.identifier, .jsx_identifier {
			return JsValue{
				kind: .string_
				text: t.string_of(key, .name)?
			}
		}
		.literal {
			if t.prop(key, .regex) != none {
				// A RegExp object: `===` to no other, String() gives its text.
				return JsValue{
					kind:    .undefined_
					boolean: true
					text:    unup_raw(t, key)
				}
			}
			return un_literal_js_value(t, key)
		}
		else {
			text := un_static_string_value(t, key)?
			return JsValue{
				kind: .string_
				text: text
			}
		}
	}
}

// unup_key_names_equal ports `===` of two key names.
fn unup_key_names_equal(a JsValue, b JsValue) bool {
	if a.kind != b.kind {
		return false
	}
	return match a.kind {
		.undefined_ { false }
		.number_ { a.number == b.number }
		.boolean_ { a.boolean == b.boolean }
		.null_ { true }
		else { a.text == b.text }
	}
}

// unup_property_keys_equal ports propertyKeysEqual.
fn unup_property_keys_equal(t &estree.EsTree, a int, b int) bool {
	name_a := unup_key_name(t, a) or { return false }
	name_b := unup_key_name(t, b) or { return false }
	return unup_key_names_equal(name_a, name_b)
}

// unup_is_dynamic_key: a computed key that is not a literal nor a static string
// (isComputedProperty and isMemberExpressionComputedBeyondPrediction).
fn unup_is_dynamic_key(t &estree.EsTree, node int, key int) bool {
	return (t.flag(node, .computed) or { false }) && t.typ(key) != .literal
		&& un_static_string_value(t, key) == none
}

// unup_pattern_matches_key ports objectPatternMatchesObjectExpressionPropertyKey.
fn unup_pattern_matches_key(t &estree.EsTree, pattern int, key int) bool {
	for property in t.list(pattern, .properties) or { []int{} } {
		if t.typ(property) == .rest_element {
			return true
		}
		property_key := t.node(property, .key) or { continue }
		// `const {[name]: value} = object` can read any property, like a rest element
		if unup_is_dynamic_key(t, property, property_key)
			|| unup_property_keys_equal(t, property_key, key) {
			return true
		}
	}
	return false
}

// unup_next_reference ports the step of reportProperties for one reference and the key of a
// property: the reference that reads the property, none when it does not read it.
fn unup_next_reference(t &estree.EsTree, reference UnupReference, key int) ?UnupReference {
	if reference.node < 0 {
		return reference
	}
	outermost := un_outermost_ts_expression(t, reference.node)
	parent := t.nodes[outermost].parent
	if parent < 0 {
		return reference
	}
	if reference.init {
		declaration := t.nodes[parent].parent
		if t.typ(parent) == .variable_declarator && declaration >= 0
			&& t.typ(declaration) == .variable_declaration && t.nodes[declaration].parent >= 0
			&& t.typ(t.nodes[declaration].parent) == .export_named_declaration {
			return UnupReference{
				node: parent
			}
		}
		return none
	}
	match t.typ(parent) {
		.member_expression, .jsx_member_expression {
			grandparent := t.nodes[parent].parent
			property := t.node(parent, .property) or { -1 }
			if (grandparent >= 0 && t.typ(grandparent) == .assignment_expression)
				|| (grandparent >= 0 && t.typ(grandparent) == .call_expression
				&& (t.node(grandparent, .callee) or { -1 }) == parent)
				|| (property >= 0 && unup_is_dynamic_key(t, parent, property))
				|| unup_property_keys_equal(t, property, key) {
				return UnupReference{
					node: parent
				}
			}
			return none
		}
		.variable_declarator {
			id := t.node(parent, .id) or { -1 }
			if id >= 0 && t.typ(id) == .object_pattern {
				if unup_pattern_matches_key(t, id, key) {
					return UnupReference{
						node: parent
					}
				}
				return none
			}
		}
		.assignment_expression {
			left := t.node(parent, .left) or { -1 }
			if left >= 0 && t.typ(left) == .object_pattern {
				if unup_pattern_matches_key(t, left, key) {
					return UnupReference{
						node: parent
					}
				}
				return none
			}
		}
		else {}
	}
	return reference
}

// unup_report_object ports reportObject and reportProperties.
fn (mut c Checker) unup_report_object(t &estree.EsTree, node int, references []UnupReference, mut findings []Finding) {
	container := unup_property_container(t, node)
	if container < 0 || unup_has_method(t, container) {
		return
	}
	for property in unup_properties(t, container) {
		key := t.node(property, .key) or { continue }
		if unup_is_dynamic_key(t, property, key) {
			continue
		}
		if name := unup_key_name(t, key) {
			if name.kind == .string_ && name.text == '__proto__' {
				continue
			}
		}
		mut next_references := []UnupReference{}
		for reference in references {
			if next := unup_next_reference(t, reference, key) {
				next_references << next
			}
		}
		if next_references.len == 0 {
			name := unup_key_name(t, key) or { JsValue{
				kind: .undefined_
			} }
			findings << Finding{
				stmt:       c.es_tree_position(t, property)
				message_id: 'no-unused-properties'
				data:       {
					'name': unup_display_name(name)
				}
			}
			continue
		}
		c.unup_report_object(t, property, next_references, mut findings)
	}
}

// unup_display_name is the key name as ESLint puts it in the message (String(value)).
fn unup_display_name(name JsValue) string {
	return match name.kind {
		.undefined_ { if name.boolean { name.text } else { 'undefined' } }
		.null_ { 'null' }
		.boolean_ { name.boolean.str() }
		.number_ { js_number_to_string(name.number) }
		else { name.text }
	}
}

// unup_raw is the raw text of a literal.
fn unup_raw(t &estree.EsTree, node int) string {
	return t.string_of(node, .raw) or { '' }
}
