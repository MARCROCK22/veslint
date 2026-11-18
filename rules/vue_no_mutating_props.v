module rules

import estree
import json2
import time
import vue

// Port of the `vue/no-mutating-props` rule of eslint-plugin-vue 10.12.1 (option shallowOnly,
// default false): a mutation (assignment, update, delete, a mutating array method, Object.assign)
// of a prop or of a member of it: through `this` in a Vue object, the props parameter of a setup
// function (and the variables destructured from it), the variable of defineProps (and those
// destructured from it), and in the template (a prop by its name or through the props variable;
// v-model and `v-bind.sync` values). With shallowOnly, only a prop itself assigned or updated.

const vue_no_mutating_props_messages = {
	'unexpectedMutation': 'Unexpected mutation of "{{key}}" prop.'
}

// vnmp_globals_white_listed are GLOBALS_WHITE_LISTED, which a template reference names as a
// global and not as a prop.
const vnmp_globals_white_listed = ['Infinity', 'undefined', 'NaN', 'isFinite', 'isNaN', 'parseFloat',
	'parseInt', 'decodeURI', 'decodeURIComponent', 'encodeURI', 'encodeURIComponent', 'Math', 'Number',
	'Date', 'Array', 'Object', 'Boolean', 'String', 'RegExp', 'Map', 'Set', 'JSON', 'Intl', 'BigInt']

fn vnmp_options(options []json2.Any) !bool {
	o := option_object(vue_no_mutating_props, options, ['shallowOnly'])!
	return o.bool_value('shallowOnly')!
}

// VnmpProps is a PropsInfo: the props variable's name ('' for none) and the prop names.
struct VnmpProps {
mut:
	name string
	set  map[string]bool
}

// VnmpCtx is what the rule's functions share.
struct VnmpCtx {
	shallow_only bool
mut:
	findings []Finding
}

fn (mut c Checker) lint_vue_no_mutating_props(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut x := VnmpCtx{
		shallow_only: vnmp_options(c.rule_options(vue_no_mutating_props))!
	}
	s := c.vue_script(root, abs_path) or { return x.findings }
	t := c.es_tree(root, abs_path) or { return x.findings }
	mut props_map := map[int]VnmpProps{}
	// vueObjectData: the object (or defineProps call) whose props the template uses, -1 for none.
	mut data_object := -1
	mut data_type := ''
	mut define_props := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineProps') {
		define_props[call] = true
	}
	if s.objects.len > 0 || define_props.len > 0 {
		for step in t.steps() {
			node := step.node
			if step.leave {
				typ := s.object_type(node)
				if typ != .none_ && typ != .instance && data_type !in ['export', 'setup'] {
					data_object = node
					data_type = vue_object_type_name(typ)
				}
				continue
			}
			if node in define_props {
				props_map[node] = c.vnmp_define_props(root, t, node, abs_path, mut x, mut stats)
				data_object = node
				data_type = 'setup'
			}
			owner := s.owner_of(node)
			if owner < 0 {
				continue
			}
			if owner == node {
				mut info := VnmpProps{}
				for prop in vue_props_from_options(t, node) {
					if prop.has_name {
						info.set[prop.name] = true
					}
				}
				props_map[node] = info
			}
			if s.vue_function_kind(t, node) == 'setup' {
				params := t.list(node, .params) or { []int{} }
				if params.len > 0 && t.typ(params[0]) !in [.rest_element, .array_pattern] {
					mut patterns := []VnmpPattern{}
					c.vnmp_pattern_properties(t, params[0], [], mut patterns)
					for p in patterns {
						c.vnmp_verify_prop_variable(root, t, p.node, p.path, mut x)
					}
				}
			}
			// 'MemberExpression > :matches(Identifier, ThisExpression)'
			if t.typ(node) !in [.identifier, .this_expression] {
				continue
			}
			parent := t.nodes[node].parent
			if parent < 0 || t.typ(parent) != .member_expression
				|| (t.node(parent, .object) or { -1 }) != node || !c.vue_is_this(root, t, node) {
				continue
			}
			stats.checked++
			name := vue_static_property_name(t, parent) or { '' }
			if name != '' && name in props_map[owner].set {
				c.vnmp_verify_mutating(t, parent, name, false, vue_script_parent, mut x)
			}
		}
	}
	if data_object >= 0 && c.vue_has_template() {
		c.vnmp_template(props_map[data_object] or { VnmpProps{} }, mut x, mut stats)
	}
	stats.eval_ms += ms(sw.elapsed())
	return x.findings
}

// vnmp_define_props is onDefinePropsEnter: the props of the call (those not named like a
// white-listed global or a variable of the global or module scope) and the variables the props
// are kept in, whose mutations it reports.
fn (mut c Checker) vnmp_define_props(root C.TSNode, t &estree.EsTree, call int, abs_path string, mut x VnmpCtx, mut stats Stats) VnmpProps {
	tree := c.scope_tree(root)
	mut defined := map[string]bool{}
	for v in tree.scopes[0].variables {
		if tree.variables[v].defs.len > 0 {
			defined[tree.variables[v].name] = true
		}
	}
	module := vue_module_scope(tree)
	if module >= 0 {
		for v in tree.scopes[module].variables {
			if tree.variables[v].defs.len > 0 {
				defined[tree.variables[v].name] = true
			}
		}
	}
	mut info := VnmpProps{}
	for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
		if prop.has_name && prop.name !in vnmp_globals_white_listed && prop.name !in defined {
			info.set[prop.name] = true
		}
	}
	mut target := call
	if vue_has_with_defaults(t, target) {
		target = t.nodes[target].parent
	}
	parent := t.nodes[target].parent
	if parent < 0 || t.typ(parent) != .variable_declarator
		|| (t.node(parent, .init) or { -1 }) != target {
		return info
	}
	mut patterns := []VnmpPattern{}
	c.vnmp_pattern_properties(t, t.node(parent, .id) or { return info }, [], mut patterns)
	for p in patterns {
		if p.path.len == 0 {
			info.name = vue_identifier_name(t, p.node)
		} else {
			info.set[vue_identifier_name(t, p.node)] = true
		}
		c.vnmp_verify_prop_variable(root, t, p.node, p.path, mut x)
	}
	return info
}

// VnmpPattern is an item of iteratePatternProperties: an Identifier of a pattern and the path of
// property names to it.
struct VnmpPattern {
	node int
	path []string
}

// vnmp_pattern_properties is iteratePatternProperties.
fn (c &Checker) vnmp_pattern_properties(t &estree.EsTree, param int, path []string, mut out []VnmpPattern) {
	if param < 0 {
		return
	}
	match t.typ(param) {
		.identifier {
			out << VnmpPattern{param, path}
		}
		.rest_element {
			c.vnmp_pattern_properties(t, t.node(param, .argument) or { -1 }, path, mut out)
		}
		.assignment_pattern {
			c.vnmp_pattern_properties(t, t.node(param, .left) or { -1 }, path, mut out)
		}
		.object_pattern {
			for p in t.list(param, .properties) or { []int{} } {
				if t.typ(p) == .property {
					mut next := path.clone()
					next << c.vnmp_property_name_text(t, p)
					c.vnmp_pattern_properties(t, t.node(p, .value) or { -1 }, next, mut out)
				} else if t.typ(p) == .rest_element {
					c.vnmp_pattern_properties(t, t.node(p, .argument) or { -1 }, path, mut out)
				}
			}
		}
		.array_pattern {
			for i, element in t.list(param, .elements) or { []int{} } {
				if element >= 0 {
					mut next := path.clone()
					next << i.str()
					c.vnmp_pattern_properties(t, element, next, mut out)
				}
			}
		}
		else {}
	}
}

// vnmp_property_name_text is getPropertyNameText of a MemberExpression or an AssignmentProperty.
fn (c &Checker) vnmp_property_name_text(t &estree.EsTree, node int) string {
	if name := vue_static_property_name(t, node) {
		if name != '' {
			return name
		}
	}
	if t.flag(node, .computed) or { false } {
		expr := if t.typ(node) == .property {
			t.node(node, .key) or { return '?unknown?' }
		} else {
			t.node(node, .property) or { return '?unknown?' }
		}
		return '[${c.src[t.nodes[expr].start..t.nodes[expr].end]}]'
	}
	return '?unknown?'
}

// vnmp_is_shallow_only_invalid is isShallowOnlyInvalid.
fn vnmp_is_shallow_only_invalid(m VueMutation, is_root_props bool, shallow_only bool) bool {
	return !shallow_only || (m.path_nodes.len == (if is_root_props { 1 } else { 0 })
		&& m.kind in ['assignment', 'update'])
}

// vnmp_verify_mutating is verifyMutating.
fn (c &Checker) vnmp_verify_mutating(t &estree.EsTree, props int, name string, is_root_props bool, parent_of VueParentFn, mut x VnmpCtx) {
	m := vue_find_mutating(t, props, parent_of) or { return }
	if vnmp_is_shallow_only_invalid(m, is_root_props, x.shallow_only) {
		x.findings << c.vue_report(t.nodes[m.node].start, t.nodes[m.node].end, 'unexpectedMutation',
			{
				'key': name
			})
	}
}

// vnmp_verify_prop_variable is verifyPropVariable: the mutations through the reads of the
// variable a prop (or the props) is kept in.
fn (mut c Checker) vnmp_verify_prop_variable(root C.TSNode, t &estree.EsTree, prop int, path []string, mut x VnmpCtx) {
	v := c.unb_find_variable(root, t, prop)
	if v < 0 {
		return
	}
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if !reference.read {
			continue
		}
		id := c.es_index_of(t, reference.identifier) or { continue }
		m := vue_find_mutating(t, id, vue_script_parent) or { continue }
		if !vnmp_is_shallow_only_invalid(m, path.len == 0, x.shallow_only) {
			continue
		}
		mut name := ''
		if path.len == 0 {
			if m.path_nodes.len == 0 {
				continue
			}
			name = c.vnmp_property_name_text(t, m.path_nodes[0])
		} else {
			if m.path_nodes.len == 0 && m.kind != 'call' {
				continue
			}
			name = path[0]
		}
		x.findings << c.vue_report(t.nodes[m.node].start, t.nodes[m.node].end, 'unexpectedMutation',
			{
				'key': name
			})
	}
}

// vnmp_template is the rule's template listeners, with the props of vueObjectData.
fn (mut c Checker) vnmp_template(info VnmpProps, mut x VnmpCtx, mut stats Stats) {
	doc := c.vue.doc
	roots := &VueTemplateRoots{
		...c.vue_template_roots()
	}
	mut container := -1
	mut attr := -1
	for step in c.vue_template_steps() {
		n := step.node
		if n.kind == .vnode {
			node := &doc.nodes[n.v]
			if node.typ == .v_attribute {
				attr = if step.leave { -1 } else { n.v }
			} else if node.typ == .v_expression_container {
				container = if step.leave { -1 } else { n.v }
				if !step.leave && attr >= 0 {
					c.vnmp_model_value(n.v, attr, info, roots, mut x)
				}
			}
			continue
		}
		if step.leave || n.kind != .estree || container < 0 {
			continue
		}
		es := &doc.snippets[n.snippet].es
		snippet := n.snippet
		parent_of := fn [roots, snippet] (t &estree.EsTree, node int) int {
			return roots.parent(t, snippet, node)
		}
		parent := parent_of(es, n.es)
		if es.typ(n.es) == .this_expression {
			// 'VExpressionContainer MemberExpression > ThisExpression'
			if parent < 0 || es.typ(parent) != .member_expression
				|| (es.node(parent, .object) or { -1 }) != n.es {
				continue
			}
			stats.checked++
			name := vue_static_property_name(es, parent) or { '' }
			if name != '' && name in info.set {
				c.vnmp_verify_mutating(es, parent, name, false, parent_of, mut x)
			}
		} else if es.typ(n.es) == .identifier {
			// 'VExpressionContainer Identifier'
			if !c.vnmp_is_vm_reference(es, n.snippet, n.es, container, parent_of) {
				continue
			}
			stats.checked++
			id_name := vue_identifier_name(es, n.es)
			is_root_props := info.name == id_name
			mut name := id_name
			if is_root_props && parent >= 0 && es.typ(parent) == .member_expression {
				if member := vue_static_property_name(es, parent) {
					if member != '' {
						name = member
					}
				}
			}
			if name != '' && (is_root_props || name in info.set) {
				c.vnmp_verify_mutating(es, n.es, name, is_root_props, parent_of, mut x)
			}
		}
	}
}

// vnmp_is_vm_reference is isVmReference: an Identifier that is not a property name, and a
// reference of its expression container to something no element defines.
fn (c &Checker) vnmp_is_vm_reference(es &estree.EsTree, snippet int, node int, container int, parent_of VueParentFn) bool {
	if es.typ(node) != .identifier {
		return false
	}
	parent := parent_of(es, node)
	if parent >= 0 {
		if es.typ(parent) == .member_expression {
			if (es.node(parent, .property) or { -1 }) == node {
				return false
			}
		} else if es.typ(parent) == .property && (es.node(parent, .key) or { -1 }) == node
			&& !(es.flag(parent, .computed) or { false }) {
			return false
		}
	}
	for r in c.vue.doc.nodes[container].references {
		reference := &c.vue.doc.references[r]
		if reference.variable < 0 && reference.id.kind == .estree && reference.id.snippet == snippet
			&& reference.id.node == node {
			return true
		}
	}
	return false
}

// vnmp_model_value is the listener of the children of the expression containers in a v-model or
// `v-bind.sync`: the value itself is a prop, a member of the props variable or `this.prop`.
fn (mut c Checker) vnmp_model_value(container int, attr int, info VnmpProps, roots &VueTemplateRoots, mut x VnmpCtx) {
	doc := c.vue.doc
	a := &doc.nodes[attr]
	if !a.directive {
		return
	}
	dir_name := c.vue_directive_name(attr)
	if dir_name !in ['model', 'bind'] {
		return
	}
	if dir_name == 'bind' && c.vue_directive_modifiers(attr).all(doc.nodes[it].name != 'sync') {
		return
	}
	expression := doc.nodes[container].expression
	if expression.kind != .estree {
		// A V* child (VOnExpression, VForExpression…) is not a member chain.
		return
	}
	snippet := expression.snippet
	es := &doc.snippets[snippet].es
	parent_of := fn [roots, snippet] (t &estree.EsTree, node int) int {
		return roots.parent(t, snippet, node)
	}
	nodes := vue_member_chaining(es, expression.node)
	first := nodes[0]
	mut name := ''
	if c.vnmp_is_vm_reference(es, snippet, first, container, parent_of) {
		first_name := vue_identifier_name(es, first)
		if first_name == info.name {
			if x.shallow_only && nodes.len > 2 {
				return
			}
			name = if nodes.len > 1 { c.vnmp_property_name_text(es, nodes[1]) } else { '' }
			if name == '' {
				name = first_name
			}
		} else {
			if x.shallow_only && nodes.len > 1 {
				return
			}
			name = first_name
			if name == '' || name !in info.set {
				return
			}
		}
	} else if es.typ(first) == .this_expression {
		if x.shallow_only && nodes.len > 2 {
			return
		}
		if nodes.len < 2 {
			return
		}
		name = vue_static_property_name(es, nodes[1]) or { '' }
		if name == '' || name !in info.set {
			return
		}
	} else {
		return
	}
	start, end := c.vue_expr_range(vue.Expr{
		kind:    .estree
		snippet: snippet
		node:    expression.node
	})
	x.findings << c.vue_report(start, end, 'unexpectedMutation', {
		'key': name
	})
}
