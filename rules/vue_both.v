module rules

import estree
import vue

// Helpers of the vue/* rules that read both the template and the script (batch VR5): the
// references of the template, and the script's side of the same lib/utils/index.ts functions.

// vue_unresolved_template_refs are the references of the template's expression containers to
// something no element defines (`reference.variable == null`: a property of the instance) named
// `name`, in the order of the traversal (VExpressionContainer listeners).
fn (mut c Checker) vue_unresolved_template_refs(name string) []vue.Expr {
	mut out := []vue.Expr{}
	for v in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[v]
		if node.typ != .v_expression_container {
			continue
		}
		for r in node.references {
			reference := &c.vue.doc.references[r]
			if reference.variable < 0 && reference.name == name {
				out << reference.id
			}
		}
	}
	return out
}

// vue_this_members_named are the MemberExpressions of the script inside a Vue object
// (defineVueVisitor's listeners) whose property is the Identifier `name` and whose object isThis.
fn (mut c Checker) vue_this_members_named(root C.TSNode, abs_path string, name string) []int {
	s := c.vue_script(root, abs_path) or { return [] }
	t := c.es_tree(root, abs_path) or { return [] }
	if s.objects.len == 0 {
		return []
	}
	mut out := []int{}
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .member_expression || s.owner_of(node) < 0 {
			continue
		}
		property := t.node(node, .property) or { continue }
		if t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != name {
			continue
		}
		if c.vue_is_this(root, t, t.node(node, .object) or { -1 }) {
			out << node
		}
	}
	return out
}

// vue_literal_truthy is Boolean(literal.value) of a Literal.
fn vue_literal_truthy(t &estree.EsTree, node int) bool {
	v := t.get(node, .value)
	return match v {
		string { v != '' }
		bool { v }
		f64 { v != 0 && v == v }
		estree.BigIntValue { v.digits.trim_left('-') != '0' }
		estree.RegExpValue { true }
		else { false }
	}
}

// vue_options_objects are the objects whose options a rule reads, in the order its listeners
// read them: each Vue object at its `ObjectExpression:exit` (executeOnVue) and, when
// `with_define_options`, the object argument of each `defineOptions` of `<script setup>` at its
// CallExpression (onDefineOptionsEnter).
fn (mut c Checker) vue_options_objects(root C.TSNode, abs_path string, with_define_options bool) []int {
	s := c.vue_script(root, abs_path) or { return [] }
	t := c.es_tree(root, abs_path) or { return [] }
	mut options_calls := map[int]bool{}
	if with_define_options {
		for call in c.vue_macros_named(t, 'defineOptions') {
			options_calls[call] = true
		}
	}
	if s.objects.len == 0 && options_calls.len == 0 {
		return []
	}
	mut out := []int{}
	for step in t.steps() {
		node := step.node
		if step.leave {
			if s.object_type(node) != .none_ {
				out << node
			}
		} else if node in options_calls {
			args := t.list(node, .arguments) or { []int{} }
			if args.len > 0 && t.typ(args[0]) == .object_expression {
				out << args[0]
			}
		}
	}
	return out
}

// VueRegisteredComponent is an item of getRegisteredComponents: the Property and its static name.
struct VueRegisteredComponent {
	node int
	name string
}

// vue_registered_components ports getRegisteredComponents: the properties with a non-empty
// static name of the first `components` property of the object whose value is an object.
fn vue_registered_components(t &estree.EsTree, object int) []VueRegisteredComponent {
	components := vue_find_property(t, object, 'components', fn [t] (p int) bool {
		return t.typ(vue_property_value(t, p)) == .object_expression
	})
	if components < 0 {
		return []
	}
	mut out := []VueRegisteredComponent{}
	for p in t.list(vue_property_value(t, components), .properties) or { []int{} } {
		if !vue_is_property(t, p) {
			continue
		}
		name := vue_static_property_name(t, p) or { continue }
		if name != '' {
			out << VueRegisteredComponent{
				node: p
				name: name
			}
		}
	}
	return out
}
