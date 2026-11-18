module rules

import estree
import treesitter { node_kind }

// lib/utils/ref-object-references.ts of eslint-plugin-vue 10.12.1 (iterateDefineRefs,
// extractRefObjectReferences), with the part of lib/utils/property-references.ts that the
// destructuring of `toRefs(…)` reads (the nest nodes of a pattern). Nodes are ESTree indexes.

// vx6r_define_names are the functions iterateDefineRefs traces.
const vx6r_define_names = ['ref', 'computed', 'toRef', 'customRef', 'shallowRef', 'useTemplateRef',
	'toRefs']

// Vx6rRef is a RefObjectReference: `pattern` for the 'pattern' type; `declarator` and
// `declaration` of an identifier reference (-1 for null).
struct Vx6rRef {
	node         int
	pattern      bool
	method       string
	define       int
	define_chain []int
	declarator   int = -1
	declaration  int = -1
	is_id        bool // a RefObjectReferenceForIdentifier
}

// Vx6rRefs is the RefObjectReferenceExtractor of a file.
struct Vx6rRefs {
mut:
	refs      map[int]Vx6rRef
	order     []int // the nodes of refs, in insertion order
	processed map[int]bool
}

fn (r &Vx6rRefs) get(node int) ?Vx6rRef {
	return r.refs[node] or { return none }
}

fn (mut r Vx6rRefs) set(node int, ref Vx6rRef) {
	if node !in r.refs {
		r.order << node
	}
	r.refs[node] = ref
}

struct Vx6rCtx {
	method       string
	define       int
	define_chain []int
}

// vx6r_extract ports extractRefObjectReferences.
fn (mut c Checker) vx6r_extract(root C.TSNode, t &estree.EsTree) Vx6rRefs {
	mut refs := Vx6rRefs{}
	// iterateDefineRefs
	for d in c.vue_composition_api_calls(root, t, vx6r_define_names) {
		c.vx6r_process_define_ref(root, t, mut refs, d.call, d.name)
	}
	for call in c.vx6r_define_models(root, t) {
		c.vx6r_process_define_model(root, t, mut refs, call)
	}
	return refs
}

// vx6r_define_models ports iterateDefineModels: the calls of `defineModel` as an implicit global
// (a variable without definitions, or a reference through the global scope).
fn (mut c Checker) vx6r_define_models(root C.TSNode, t &estree.EsTree) []int {
	tree := c.scope_tree(root)
	mut ids := []C.TSNode{}
	for v in tree.variables {
		if v.name == 'defineModel' && v.scope == 0 && v.defs.len == 0 {
			for r in v.references {
				ids << tree.references[r].identifier
			}
		}
	}
	for r in tree.references {
		if r.name == 'defineModel' && r.resolved < 0 {
			ids << r.identifier
		}
	}
	mut out := []int{}
	for id in ids {
		es := c.es_index_of(t, id) or { continue }
		parent := t.nodes[es].parent
		if parent >= 0 && t.typ(parent) == .call_expression
			&& (t.node(parent, .callee) or { -1 }) == es {
			out << parent
		}
	}
	return out
}

// vx6r_assigned_pattern is the pattern a call is assigned to (`const p = call`, `p = call`), -1
// for none.
fn vx6r_assigned_pattern(t &estree.EsTree, node int) int {
	parent := t.nodes[node].parent
	if parent < 0 {
		return -1
	}
	if t.typ(parent) == .variable_declarator {
		return t.node(parent, .id) or { -1 }
	}
	if t.typ(parent) == .assignment_expression && (t.string_of(parent, .operator) or { '' }) == '=' {
		return t.node(parent, .left) or { -1 }
	}
	return -1
}

fn (mut c Checker) vx6r_process_define_ref(root C.TSNode, t &estree.EsTree, mut refs Vx6rRefs, node int, method string) {
	pattern := vx6r_assigned_pattern(t, node)
	if pattern < 0 {
		if method != 'toRefs' {
			refs.set(node, Vx6rRef{
				node:         node
				method:       method
				define:       node
				define_chain: [node]
			})
		}
		return
	}
	ctx := Vx6rCtx{method, node, [node]}
	if method == 'toRefs' {
		mut visited := map[int]bool{}
		for nest in c.vx6r_nest_from_pattern(root, t, pattern, mut visited) {
			if nest.expression {
				c.vx6r_process_member_expression(root, t, mut refs, nest.node, ctx)
			} else {
				c.vx6r_process_pattern(root, t, mut refs, nest.node, ctx)
			}
		}
	} else {
		c.vx6r_process_pattern(root, t, mut refs, pattern, ctx)
	}
}

fn (mut c Checker) vx6r_process_define_model(root C.TSNode, t &estree.EsTree, mut refs Vx6rRefs, node int) {
	mut pattern := vx6r_assigned_pattern(t, node)
	if pattern < 0 {
		return
	}
	if t.typ(pattern) == .array_pattern {
		elements := t.list(pattern, .elements) or { []int{} }
		if elements.len > 0 && elements[0] >= 0 {
			pattern = elements[0]
		}
	}
	c.vx6r_process_pattern(root, t, mut refs, pattern, Vx6rCtx{'defineModel', node, [node]})
}

// vx6r_process_expression: an expression assigned to a pattern passes the ref on to it.
fn (mut c Checker) vx6r_process_expression(root C.TSNode, t &estree.EsTree, mut refs Vx6rRefs, node int, ctx Vx6rCtx) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	mut chain := [node]
	chain << ctx.define_chain
	next := Vx6rCtx{ctx.method, ctx.define, chain}
	if t.typ(parent) == .assignment_expression {
		if (t.string_of(parent, .operator) or { '' }) == '='
			&& (t.node(parent, .right) or { -1 }) == node {
			c.vx6r_process_pattern(root, t, mut refs, t.node(parent, .left) or { return false },
				next)
			return true
		}
	} else if t.typ(parent) == .variable_declarator && (t.node(parent, .init) or { -1 }) == node {
		c.vx6r_process_pattern(root, t, mut refs, t.node(parent, .id) or { return false },
			next)
		return true
	}
	return false
}

fn (mut c Checker) vx6r_process_member_expression(root C.TSNode, t &estree.EsTree, mut refs Vx6rRefs, node int, ctx Vx6rCtx) {
	if c.vx6r_process_expression(root, t, mut refs, node, ctx) {
		return
	}
	refs.set(node, Vx6rRef{
		node:         node
		method:       ctx.method
		define:       ctx.define
		define_chain: ctx.define_chain
	})
}

fn (mut c Checker) vx6r_process_pattern(root C.TSNode, t &estree.EsTree, mut refs Vx6rRefs, node int, ctx Vx6rCtx) {
	match t.typ(node) {
		.identifier {
			c.vx6r_process_identifier_pattern(root, t, mut refs, node, ctx)
		}
		.object_pattern {
			refs.set(node, Vx6rRef{
				node:         node
				pattern:      true
				method:       ctx.method
				define:       ctx.define
				define_chain: ctx.define_chain
			})
		}
		.assignment_pattern {
			c.vx6r_process_pattern(root, t, mut refs, t.node(node, .left) or { return },
				ctx)
		}
		else {}
	}
}

fn (mut c Checker) vx6r_process_identifier_pattern(root C.TSNode, t &estree.EsTree, mut refs Vx6rRefs, node int, ctx Vx6rCtx) {
	if node in refs.processed {
		return
	}
	refs.processed[node] = true
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return
	}
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		id := c.es_index_of(t, reference.identifier) or { continue }
		mut def := ScopeDefinition{}
		mut has_def := false
		if reference.resolved >= 0 && tree.variables[reference.resolved].defs.len == 1
			&& tree.variables[reference.resolved].defs[0].kind == .variable {
			def = tree.variables[reference.resolved].defs[0]
			has_def = true
		}
		if (has_def && node_key(def.name) == node_key(reference.identifier))
			|| (reference.read && c.vx6r_process_expression(root, t, mut refs, id, ctx)) {
			continue
		}
		mut declarator := -1
		mut declaration := -1
		if has_def {
			declarator = c.vx6r_es_node(t, def.node, 'variable_declarator')
			if declarator >= 0 {
				declaration = t.nodes[declarator].parent
			}
		}
		refs.set(id, Vx6rRef{
			node:         id
			pattern:      reference.write
			method:       ctx.method
			define:       ctx.define
			define_chain: ctx.define_chain
			declarator:   declarator
			declaration:  declaration
			is_id:        true
		})
	}
}

// vx6r_es_node is the ESTree node of a tree-sitter node of that kind (or of its nearest ancestor
// of that kind), -1 for none.
fn (mut c Checker) vx6r_es_node(t &estree.EsTree, n C.TSNode, kind string) int {
	mut node := n
	for node_kind(node) != kind {
		node = treesitter.node_parent(node) or { return -1 }
	}
	return c.es_index_of(t, node) or { -1 }
}

// Vx6rNest is a NestPropertyNode: the member expression (`expression`) or the pattern of a
// property.
struct Vx6rNest {
	expression bool
	node       int
}

// vx6r_nest_from_pattern are the nest nodes of every property of a pattern
// (extractFromPattern(…).allProperties() and getNestNodes of each, in that order).
fn (mut c Checker) vx6r_nest_from_pattern(root C.TSNode, t &estree.EsTree, pattern int, mut visited map[int]bool) []Vx6rNest {
	mut node := pattern
	for node >= 0 && t.typ(node) == .assignment_pattern {
		node = t.node(node, .left) or { return [] }
	}
	if node < 0 || node in visited {
		return []
	}
	visited[node] = true
	match t.typ(node) {
		.object_pattern {
			return vx6r_merge(vx6r_object_named(t, node))
		}
		.identifier {
			return c.vx6r_nest_from_identifier(root, t, node, mut visited)
		}
		else {
			return []
		}
	}
}

// vx6r_nest_from_identifier is extractFromIdentifier: the nest nodes of the references of the
// variable, merged by name.
fn (mut c Checker) vx6r_nest_from_identifier(root C.TSNode, t &estree.EsTree, node int, mut visited map[int]bool) []Vx6rNest {
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return []
	}
	tree := c.scope_tree(root)
	mut named := []Vx6rNamedNest{}
	for r in tree.variables[v].references {
		id := c.es_index_of(t, tree.references[r].identifier) or { continue }
		named << c.vx6r_nest_from_expression(root, t, id, mut visited)
	}
	return vx6r_merge(named)
}

struct Vx6rNamedNest {
	name string
	nest Vx6rNest
}

// vx6r_merge orders the nest nodes by the first appearance of their names (a merged
// allProperties), then by reference.
fn vx6r_merge(named []Vx6rNamedNest) []Vx6rNest {
	mut name_list := []string{}
	for n in named {
		if n.name !in name_list {
			name_list << n.name
		}
	}
	mut out := []Vx6rNest{}
	for name in name_list {
		for n in named {
			if n.name == name {
				out << n.nest
			}
		}
	}
	return out
}

// vx6r_nest_from_expression is extractFromExpression's nest nodes, with their names.
fn (mut c Checker) vx6r_nest_from_expression(root C.TSNode, t &estree.EsTree, node int, mut visited map[int]bool) []Vx6rNamedNest {
	parent := t.nodes[node].parent
	if parent < 0 {
		return []
	}
	match t.typ(parent) {
		.assignment_expression {
			if (t.node(parent, .right) or { -1 }) == node
				&& (t.string_of(parent, .operator) or { '' }) == '=' {
				return c.vx6r_named(root, t, t.node(parent, .left) or { -1 }, mut visited)
			}
		}
		.variable_declarator {
			if (t.node(parent, .init) or { -1 }) == node {
				return c.vx6r_named(root, t, t.node(parent, .id) or { -1 }, mut visited)
			}
		}
		.member_expression {
			if (t.node(parent, .object) or { -1 }) != node {
				return []
			}
			name := vue_static_property_name(t, parent) or { '' }
			grand := t.nodes[parent].parent
			if name == '\$props' && grand >= 0 && t.typ(grand) == .member_expression {
				prop_name := vue_static_property_name(t, grand) or { '' }
				if prop_name == '' {
					return []
				}
				return [Vx6rNamedNest{prop_name, Vx6rNest{true, grand}}]
			}
			if name != '' {
				return [Vx6rNamedNest{name, Vx6rNest{true, parent}}]
			}
		}
		.call_expression {
			args := t.list(parent, .arguments) or { []int{} }
			index := args.index(node)
			callee := t.node(parent, .callee) or { -1 }
			if index < 0 || callee < 0 || t.typ(callee) != .identifier {
				return []
			}
			function := c.vx6r_find_function(root, t, callee, 0)
			if function < 0 {
				// toRef/toRefs and unknown calls give no nest nodes here.
				return []
			}
			params := t.list(function, .params) or { []int{} }
			if index >= params.len {
				return []
			}
			return c.vx6r_named(root, t, params[index], mut visited)
		}
		.chain_expression {
			return c.vx6r_nest_from_expression(root, t, parent, mut visited)
		}
		else {}
	}
	return []
}

// vx6r_named are the nest nodes of a pattern with their names.
fn (mut c Checker) vx6r_named(root C.TSNode, t &estree.EsTree, pattern int, mut visited map[int]bool) []Vx6rNamedNest {
	mut node := pattern
	for node >= 0 && t.typ(node) == .assignment_pattern {
		node = t.node(node, .left) or { return [] }
	}
	if node < 0 {
		return []
	}
	if t.typ(node) == .object_pattern {
		return vx6r_object_named(t, node)
	}
	if t.typ(node) == .identifier {
		if node in visited {
			return []
		}
		visited[node] = true
		v := c.unb_find_variable(root, t, node)
		if v < 0 {
			return []
		}
		tree := c.scope_tree(root)
		mut out := []Vx6rNamedNest{}
		for r in tree.variables[v].references {
			id := c.es_index_of(t, tree.references[r].identifier) or { continue }
			out << c.vx6r_nest_from_expression(root, t, id, mut visited)
		}
		return out
	}
	return []
}

// vx6r_find_function is property-references' findFunction.
fn (mut c Checker) vx6r_find_function(root C.TSNode, t &estree.EsTree, id int, depth int) int {
	if depth > 10 {
		return -1
	}
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return -1
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	if defs.len != 1 {
		return -1
	}
	def := defs[0]
	if node_kind(def.node) == 'function_declaration' {
		return c.es_index_of(t, def.node) or { -1 }
	}
	if def.kind == .variable && def.parent_kind == 'const' {
		init := def.init or { return -1 }
		es := c.es_index_of(t, unwrap_parens(init)) or { return -1 }
		if t.typ(es) in [.function_expression, .arrow_function_expression] {
			return es
		}
		if t.typ(es) == .identifier {
			return c.vx6r_find_function(root, t, es, depth + 1)
		}
	}
	return -1
}

// vx6r_object_named is PropertyReferencesForObject of an object pattern: the nest nodes of each
// property (its value through defaults, when an identifier, member expression or pattern), with
// the property's name; none (ANY) when a property is a rest element or has no static name.
fn vx6r_object_named(t &estree.EsTree, node int) []Vx6rNamedNest {
	mut out := []Vx6rNamedNest{}
	for p in t.list(node, .properties) or { []int{} } {
		if t.typ(p) != .property {
			return []
		}
		name := vue_static_property_name(t, p) or { return [] }
		if name == '' {
			return []
		}
		mut value := t.node(p, .value) or { -1 }
		for value >= 0 && t.typ(value) == .assignment_pattern {
			value = t.node(value, .left) or { -1 }
		}
		if value >= 0 && t.typ(value) in [.identifier, .member_expression, .object_pattern,
			.array_pattern] {
			out << Vx6rNamedNest{name, Vx6rNest{false, value}}
		}
	}
	return out
}
