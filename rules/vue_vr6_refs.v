module rules

import estree
import treesitter { node_kind }

// lib/utils/ref-object-references.ts of eslint-plugin-vue 10.12.1 (iterateDefineRefs,
// extractRefObjectReferences); the destructuring of `toRefs(…)` is read with
// vue_property_references.v (extractFromPattern, allProperties and getNestNodes). Nodes are
// ESTree indexes.

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
		mut x := c.vpr_new_extractor(root, t, false, false)
		references := c.vpr_from_pattern(mut x, pattern)
		for property in c.vpr_all_properties(mut x, references) {
			for nest in c.vpr_get_nest_nodes(mut x, references, property.name) {
				if nest.expression {
					c.vx6r_process_member_expression(root, t, mut refs, nest.node.node, ctx)
				} else {
					c.vx6r_process_pattern(root, t, mut refs, nest.node.node, ctx)
				}
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
