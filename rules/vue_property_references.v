module rules

import estree
import vue

// Port of lib/utils/property-references.ts of eslint-plugin-vue 10.12.1
// (definePropertyReferenceExtractor and mergePropertyReferences, without getNestNodes, which
// no rule of this port reads): what properties of a value (`this`, the props, a variable, a
// function parameter, the names of the template's expressions) the code reads, and what it reads
// of those properties. An IPropertyReferences is a VprRef in the extractor's arena (`refs`),
// vpr_any and vpr_never being ANY and NEVER; its methods are vpr_has_property, vpr_all_properties
// and vpr_get_nest.
//
// A node is named by its tree and its index there (VprNode): tree 0 is the script's EsTree,
// tree s + 1 the EsTree of the template's (or a style's) snippet s. In a snippet, the parent of
// an expression's root is the V* node around it (VprExtractor.roots).

const vpr_any = 0
const vpr_never = 1

// VprNode is an ESTree node of the script (tree 0) or of a snippet (tree snippet + 1).
struct VprNode {
	tree int
	node int
}

fn (n VprNode) key() u64 {
	return (u64(n.tree) << 32) | u64(u32(n.node))
}

enum VprKind as u8 {
	any
	never
	member       // PropertyReferencesForMember: `node` the MemberExpression, `name`
	object       // PropertyReferencesForObject: `properties`
	unknown_call // extractFromUnknownCall: `node` the CallExpression (script)
	path         // extractFromPath: `segments`, `node` the name node
	name_literal // extractFromNameLiteral: `name`, `node`
	name         // extractFromName: `name`, `node`, `nest`
	to_refs      // extractFromToRefs: `refs[0]` the base
	merge        // PropertyReferencesForMerge: `refs`
}

// VprNest is what getNest of an extractFromName gives for its name.
enum VprNest as u8 {
	any        // ANY
	expression // extractFromExpression(nest_node, within)
	to_ref     // extractFromExpression(nest_node (a toRef call), false).getNest('value')
}

// VprRef is an IPropertyReferences.
struct VprRef {
	kind       VprKind
	node       VprNode
	name       string
	within     bool             // isWithinTemplate of a member
	properties map[string][]int // object: the Property nodes of the script, by name
	segments   []string
	nest       VprNest
	nest_node  VprNode
	refs       []int
}

// VprHasOptions are IHasPropertyOption.
struct VprHasOptions {
	unknown_call_as_any  bool
	external_call_as_any bool
}

// VprProperty is an entry of allProperties: a name and its nodes.
struct VprProperty {
	name  string
	nodes []VprNode
}

// VprExtractor is what definePropertyReferenceExtractor returns, with its caches.
struct VprExtractor {
	unknown_member_as_unreferenced bool
	return_as_unreferenced         bool
	root                           C.TSNode
	t                              &estree.EsTree = unsafe { nil }
mut:
	refs          []VprRef
	cache_expr    map[u64]int
	cache_pattern map[int]int
	cache_fn      map[string]int
	to_ref_built  bool
	to_ref_nodes  map[int]bool
	to_refs_nodes map[int]bool
	functional    bool
	// roots: the parent V* node of each root of a snippet (template and styles).
	roots map[u64]int
}

// vpr_new_extractor is definePropertyReferenceExtractor.
fn (mut c Checker) vpr_new_extractor(root C.TSNode, t &estree.EsTree, unknown_member_as_unreferenced bool, return_as_unreferenced bool) VprExtractor {
	mut x := VprExtractor{
		unknown_member_as_unreferenced: unknown_member_as_unreferenced
		return_as_unreferenced:         return_as_unreferenced
		root:                           root
		t:                              unsafe { t }
		refs:                           [VprRef{
			kind: .any
		}, VprRef{
			kind: .never
		}]
	}
	if c.is_vue() {
		doc := c.vue.doc
		if doc.template_body >= 0 {
			x.functional = c.vue_has_attribute(doc.template_body, 'functional', none)
		}
		mut vnodes := c.vue_template_vnodes().clone()
		for style in doc.top_elements('style') {
			for child in doc.nodes[style].children {
				if doc.nodes[child].typ == .v_expression_container {
					vnodes << child
				}
			}
		}
		for v in vnodes {
			for child in vue_tnode_children(doc, vue_vnode(v)) {
				if child.kind == .estree {
					x.roots[VprNode{child.snippet + 1, child.es}.key()] = v
				}
			}
		}
	}
	return x
}

// vpr_tree is the EsTree of a tree.
fn (c &Checker) vpr_tree(x &VprExtractor, tree int) &estree.EsTree {
	return if tree == 0 { x.t } else { &c.vue.doc.snippets[tree - 1].es }
}

// vpr_range is the range of a node in the file.
fn (c &Checker) vpr_range(x &VprExtractor, n VprNode) (int, int) {
	if n.tree == 0 {
		return x.t.nodes[n.node].start, x.t.nodes[n.node].end
	}
	return c.vue_expr_range(vpr_estree_expr(n.tree - 1, n.node))
}

// VprParent is the parent of a node: an ESTree node of the same tree (`node`), or a V* node
// (`vnode`), or none (both -1).
struct VprParent {
	node  int = -1
	vnode int = -1
}

fn (c &Checker) vpr_parent(x &VprExtractor, n VprNode) VprParent {
	if n.tree > 0 {
		if v := x.roots[n.key()] {
			return VprParent{
				vnode: v
			}
		}
	}
	return VprParent{
		node: c.vpr_tree(x, n.tree).nodes[n.node].parent
	}
}

fn (mut x VprExtractor) add(r VprRef) int {
	x.refs << r
	return x.refs.len - 1
}

// vpr_merge is mergePropertyReferences.
fn vpr_merge(mut x VprExtractor, refs []int) int {
	if refs.len == 0 {
		return vpr_never
	}
	if refs.len == 1 {
		return refs[0]
	}
	return x.add(VprRef{
		kind: .merge
		refs: refs
	})
}

// vpr_has_property is IPropertyReferences.hasProperty.
fn (mut c Checker) vpr_has_property(mut x VprExtractor, r int, name string, o VprHasOptions) bool {
	ref := x.refs[r]
	return match ref.kind {
		.any {
			true
		}
		.never {
			false
		}
		.member, .name_literal, .name {
			name == ref.name
		}
		.object {
			name in ref.properties
		}
		.unknown_call {
			o.unknown_call_as_any || (o.external_call_as_any
				&& c.vpr_is_external_callee(x, x.t.node(ref.node.node, .callee) or { -1 }))
		}
		.path {
			name == ref.segments[0]
		}
		.to_refs {
			c.vpr_has_property(mut x, ref.refs[0], name, o)
		}
		.merge {
			mut found := false
			for sub in ref.refs {
				if c.vpr_has_property(mut x, sub, name, o) {
					found = true
					break
				}
			}
			found
		}
	}
}

// vpr_all_properties is IPropertyReferences.allProperties, in its order.
fn (mut c Checker) vpr_all_properties(mut x VprExtractor, r int) []VprProperty {
	ref := x.refs[r]
	match ref.kind {
		.any, .never, .unknown_call {
			return []
		}
		.member {
			property := c.vpr_tree(x, ref.node.tree).node(ref.node.node, .property) or { -1 }
			return [VprProperty{ref.name, [VprNode{ref.node.tree, property}]}]
		}
		.object {
			mut out := []VprProperty{}
			for name, properties in ref.properties {
				out << VprProperty{name, properties.map(VprNode{0, x.t.node(it, .key) or { -1 }})}
			}
			return out
		}
		.path {
			return [VprProperty{ref.segments[0], [ref.node]}]
		}
		.name_literal, .name {
			return [VprProperty{ref.name, [ref.node]}]
		}
		.to_refs {
			return c.vpr_all_properties(mut x, ref.refs[0])
		}
		.merge {
			mut out := []VprProperty{}
			mut index := map[string]int{}
			for sub in ref.refs {
				for p in c.vpr_all_properties(mut x, sub) {
					if i := index[p.name] {
						mut nodes := out[i].nodes.clone()
						for n in p.nodes {
							if n !in nodes {
								nodes << n
							}
						}
						out[i] = VprProperty{p.name, nodes}
					} else {
						index[p.name] = out.len
						out << VprProperty{p.name, p.nodes.clone()}
					}
				}
			}
			return out
		}
	}
}

// vpr_get_nest is IPropertyReferences.getNest.
fn (mut c Checker) vpr_get_nest(mut x VprExtractor, r int, name string) int {
	ref := x.refs[r]
	match ref.kind {
		.any, .unknown_call {
			return vpr_any
		}
		.never {
			return vpr_never
		}
		.member {
			return if name == ref.name {
				c.vpr_from_expression(mut x, ref.node, ref.within)
			} else {
				vpr_never
			}
		}
		.object {
			properties := ref.properties[name] or { return vpr_never }
			mut nest := []int{}
			for p in properties {
				nest << c.vpr_nest_from_pattern(mut x, x.t.node(p, .value) or { -1 })
			}
			return vpr_merge(mut x, nest)
		}
		.path {
			if name != ref.segments[0] {
				return vpr_never
			}
			return vpr_from_segments(mut x, ref.segments[1..], ref.node)
		}
		.name_literal {
			return if name == ref.name { vpr_any } else { vpr_never }
		}
		.name {
			if name != ref.name {
				return vpr_never
			}
			return match ref.nest {
				.any {
					vpr_any
				}
				.expression {
					c.vpr_from_expression(mut x, ref.nest_node, ref.within)
				}
				.to_ref {
					base := c.vpr_from_expression(mut x, ref.nest_node, false)
					c.vpr_get_nest(mut x, base, 'value')
				}
			}
		}
		.to_refs {
			nest := c.vpr_get_nest(mut x, ref.refs[0], name)
			return c.vpr_get_nest(mut x, nest, 'value')
		}
		.merge {
			mut nest := []int{}
			for sub in ref.refs {
				if c.vpr_has_property(mut x, sub, name, VprHasOptions{}) {
					nest << c.vpr_get_nest(mut x, sub, name)
				}
			}
			return vpr_merge(mut x, nest)
		}
	}
}

// vpr_nest_from_pattern is getNestFromPattern.
fn (mut c Checker) vpr_nest_from_pattern(mut x VprExtractor, pattern int) int {
	if pattern < 0 {
		return vpr_any
	}
	return match x.t.typ(pattern) {
		.object_pattern { c.vpr_from_object_pattern(mut x, pattern) }
		.identifier { c.vpr_from_identifier(mut x, pattern) }
		.assignment_pattern { c.vpr_nest_from_pattern(mut x, x.t.node(pattern, .left) or { -1 }) }
		else { vpr_any }
	}
}

// vpr_from_expression is extractFromExpression.
fn (mut c Checker) vpr_from_expression(mut x VprExtractor, n VprNode, within bool) int {
	key := n.key()
	if cached := x.cache_expr[key] {
		return cached
	}
	x.cache_expr[key] = vpr_any
	result := c.vpr_from_expression_uncached(mut x, n, within)
	x.cache_expr[key] = result
	return result
}

fn (mut c Checker) vpr_from_expression_uncached(mut x VprExtractor, n VprNode, within bool) int {
	parent := c.vpr_parent(x, n)
	if parent.vnode >= 0 {
		// A V* parent: only a VExpressionContainer is maybe used externally.
		return if c.vue.doc.nodes[parent.vnode].typ == .v_expression_container {
			vpr_any
		} else {
			vpr_never
		}
	}
	if parent.node < 0 {
		return vpr_never
	}
	t := c.vpr_tree(x, n.tree)
	p := parent.node
	match t.typ(p) {
		.assignment_expression {
			if !within && (t.node(p, .right) or { -1 }) == n.node
				&& (t.string_of(p, .operator) or { '' }) == '=' {
				return c.vpr_from_pattern(mut x, t.node(p, .left) or { -1 })
			}
			return vpr_never
		}
		.variable_declarator {
			if !within && (t.node(p, .init) or { -1 }) == n.node {
				return c.vpr_from_pattern(mut x, t.node(p, .id) or { -1 })
			}
			return vpr_never
		}
		.member_expression {
			if (t.node(p, .object) or { -1 }) != n.node {
				return vpr_never
			}
			name := vue_static_property_name(t, p) or { '' }
			if name == r'$props' {
				grand := c.vpr_parent(x, VprNode{n.tree, p})
				if grand.node >= 0 && t.typ(grand.node) == .member_expression {
					prop_name := vue_static_property_name(t, grand.node) or { '' }
					if prop_name == '' {
						return if x.unknown_member_as_unreferenced { vpr_never } else { vpr_any }
					}
					return x.add(VprRef{
						kind:   .member
						node:   VprNode{n.tree, grand.node}
						name:   prop_name
						within: within
					})
				}
			}
			if name != '' {
				return x.add(VprRef{
					kind:   .member
					node:   VprNode{n.tree, p}
					name:   name
					within: within
				})
			}
			return if x.unknown_member_as_unreferenced { vpr_never } else { vpr_any }
		}
		.call_expression {
			arg_index := (t.list(p, .arguments) or { []int{} }).index(n.node)
			if within || arg_index < 0 {
				return vpr_never
			}
			return c.vpr_from_call(mut x, p, arg_index)
		}
		.chain_expression {
			return c.vpr_from_expression(mut x, VprNode{n.tree, p}, within)
		}
		.arrow_function_expression, .property, .array_expression {
			return if c.vpr_is_maybe_externally_used(x, n, parent) { vpr_any } else { vpr_never }
		}
		.return_statement {
			if x.return_as_unreferenced {
				return vpr_never
			}
			return if c.vpr_is_maybe_externally_used(x, n, parent) { vpr_any } else { vpr_never }
		}
		else {
			return vpr_never
		}
	}
}

// vpr_is_maybe_externally_used is isMaybeExternallyUsed of extractFromExpression's `node`.
fn (c &Checker) vpr_is_maybe_externally_used(x &VprExtractor, n VprNode, target VprParent) bool {
	if target.vnode >= 0 {
		return c.vue.doc.nodes[target.vnode].typ == .v_expression_container
	}
	if target.node < 0 {
		return false
	}
	t := c.vpr_tree(x, n.tree)
	return match t.typ(target.node) {
		.return_statement {
			true
		}
		.array_expression {
			c.vpr_is_maybe_externally_used(x, n, c.vpr_parent(x, VprNode{n.tree, target.node}))
		}
		.property {
			object := c.vpr_parent(x, VprNode{n.tree, target.node})
			if object.node < 0 {
				false
			} else {
				c.vpr_is_maybe_externally_used(x, n, c.vpr_parent(x, VprNode{n.tree, object.node}))
			}
		}
		.arrow_function_expression {
			(t.node(target.node, .body) or { -1 }) == n.node
		}
		else {
			false
		}
	}
}

// vpr_from_pattern is extractFromPattern (a pattern of the script).
fn (mut c Checker) vpr_from_pattern(mut x VprExtractor, pattern int) int {
	if pattern < 0 {
		return vpr_never
	}
	if cached := x.cache_pattern[pattern] {
		return cached
	}
	x.cache_pattern[pattern] = vpr_any
	mut node := pattern
	for x.t.typ(node) == .assignment_pattern {
		node = x.t.node(node, .left) or { break }
	}
	result := match x.t.typ(node) {
		.object_pattern { c.vpr_from_object_pattern(mut x, node) }
		.identifier { c.vpr_from_identifier(mut x, node) }
		else { vpr_never }
	}
	x.cache_pattern[pattern] = result
	return result
}

// vpr_from_object_pattern is extractFromObjectPattern.
fn (mut c Checker) vpr_from_object_pattern(mut x VprExtractor, pattern int) int {
	mut properties := map[string][]int{}
	for p in x.t.list(pattern, .properties) or { []int{} } {
		if x.t.typ(p) != .property {
			// If use RestElement, everything is used!
			return vpr_any
		}
		name := vue_static_property_name(x.t, p) or { '' }
		if name == '' {
			// If cannot trace name, everything is used!
			return vpr_any
		}
		properties[name] << p
	}
	return x.add(VprRef{
		kind:       .object
		properties: properties
	})
}

// vpr_from_identifier is extractFromIdentifier: what the references of its variable read.
fn (mut c Checker) vpr_from_identifier(mut x VprExtractor, id int) int {
	v := c.vue_find_variable(x.root, x.t, id)
	if v < 0 {
		return vpr_never
	}
	references := c.scope_tree(x.root).variables[v].references.clone()
	mut refs := []int{}
	for r in references {
		ref_id := c.es_index_of(x.t, c.scope_tree(x.root).references[r].identifier) or {
			continue
		}
		refs << c.vpr_from_expression(mut x, VprNode{0, ref_id}, false)
	}
	return vpr_merge(mut x, refs)
}

// vpr_from_call is extractFromCall.
fn (mut c Checker) vpr_from_call(mut x VprExtractor, call int, arg_index int) int {
	callee := x.t.node(call, .callee) or { -1 }
	if callee < 0 || x.t.typ(callee) != .identifier {
		return x.add(VprRef{
			kind: .unknown_call
			node: VprNode{0, call}
		})
	}
	function := c.vpr_find_function(x, callee, 0)
	if function < 0 {
		if arg_index == 0 {
			c.vpr_build_to_ref_set(mut x)
			if call in x.to_ref_nodes {
				return c.vpr_from_to_ref(mut x, call)
			}
			if call in x.to_refs_nodes {
				return c.vpr_from_to_refs(mut x, call)
			}
		}
		return x.add(VprRef{
			kind: .unknown_call
			node: VprNode{0, call}
		})
	}
	return c.vpr_from_function_param(mut x, function, arg_index)
}

// vpr_find_function is findFunction: the function a callee names (through `const` aliases), -1
// for none.
fn (mut c Checker) vpr_find_function(x &VprExtractor, id int, depth int) int {
	if depth > 100 {
		return -1
	}
	v := c.vue_find_variable(x.root, x.t, id)
	if v < 0 {
		return -1
	}
	defs := c.scope_tree(x.root).variables[v].defs
	if defs.len != 1 {
		return -1
	}
	def := defs[0]
	if node := c.es_index_of(x.t, def.node) {
		if x.t.typ(node) == .function_declaration {
			return node
		}
	}
	if def.kind == .variable && def.parent_kind == 'const' {
		init_ts := def.init or { return -1 }
		init := c.es_index_of(x.t, init_ts) or { return -1 }
		if x.t.typ(init) in [.function_expression, .arrow_function_expression] {
			return init
		}
		if x.t.typ(init) == .identifier {
			return c.vpr_find_function(x, init, depth + 1)
		}
	}
	return -1
}

// vpr_is_external_callee is isExternalCallee: the callee is an import (or a member of one) or a
// global.
fn (mut c Checker) vpr_is_external_callee(x &VprExtractor, callee int) bool {
	mut node := callee
	for node >= 0 && x.t.typ(node) == .member_expression {
		node = x.t.node(node, .object) or { -1 }
	}
	if node < 0 || x.t.typ(node) != .identifier {
		return false
	}
	v := c.vue_find_variable(x.root, x.t, node)
	if v < 0 {
		return true
	}
	return c.scope_tree(x.root).variables[v].defs.all(it.kind == .import_binding)
}

// vpr_build_to_ref_set is getToRefSet: the calls of `toRef` and `toRefs` imported from Vue (or
// global).
fn (mut c Checker) vpr_build_to_ref_set(mut x VprExtractor) {
	if x.to_ref_built {
		return
	}
	x.to_ref_built = true
	for name in ['toRef', 'toRefs'] {
		for call in c.vpr_traced_calls(x.root, x.t, name) {
			if name == 'toRef' {
				x.to_ref_nodes[call] = true
			} else {
				x.to_refs_nodes[call] = true
			}
		}
	}
}

// vpr_traced_calls are the calls iterateReferencesTraceMap gives for `{ [name]: { [CALL]: true } }`:
// those of the function imported from the Vue modules, then of the global.
fn (mut c Checker) vpr_traced_calls(root C.TSNode, t &estree.EsTree, name string) []int {
	call_trace := EsTrace{
		call: true
	}
	esm := EsTrace{
		esm:      true
		children: {
			name: call_trace
		}
	}
	mut esm_map := map[string]EsTrace{}
	for module in vue_composition_modules {
		esm_map[module] = esm
	}
	mut traced := c.es_esm_references(root, esm_map)
	traced << c.es_global_references(root, {
		name: call_trace
	})
	mut out := []int{}
	for r in traced {
		if call := c.es_index_of(t, r.node) {
			out << call
		}
	}
	return out
}

// vpr_from_function_param is extractFromFunctionParam.
fn (mut c Checker) vpr_from_function_param(mut x VprExtractor, function int, arg_index int) int {
	key := '${function}:${arg_index}'
	if cached := x.cache_fn[key] {
		return cached
	}
	x.cache_fn[key] = vpr_never
	params := x.t.list(function, .params) or { []int{} }
	if arg_index >= params.len {
		return vpr_never
	}
	result := c.vpr_from_pattern(mut x, params[arg_index])
	x.cache_fn[key] = result
	return result
}

// vpr_from_path is extractFromPath: the segments of a watcher's path.
fn (mut c Checker) vpr_from_path(mut x VprExtractor, path string, node int) int {
	return vpr_from_segments(mut x, path.split('.'), VprNode{0, node})
}

fn vpr_from_segments(mut x VprExtractor, segments []string, node VprNode) int {
	if segments.len == 0 {
		return vpr_any
	}
	return x.add(VprRef{
		kind:     .path
		segments: segments.clone()
		node:     node
	})
}

// vpr_from_name_literal is extractFromNameLiteral.
fn (mut c Checker) vpr_from_name_literal(mut x VprExtractor, node int) int {
	if node < 0 || x.t.typ(node) !in [.literal, .template_literal] {
		return vpr_never
	}
	name := vue_string_literal_value(x.t, node, false) or { '' }
	if name == '' {
		return vpr_never
	}
	return x.add(VprRef{
		kind: .name_literal
		name: name
		node: VprNode{0, node}
	})
}

// vpr_from_name is extractFromName (getNest gives ANY).
fn vpr_from_name(mut x VprExtractor, name string, node VprNode) int {
	return x.add(VprRef{
		kind: .name
		name: name
		node: node
	})
}

// vpr_from_name_nest is extractFromName with getNest giving extractFromExpression(nest, within).
fn vpr_from_name_nest(mut x VprExtractor, name string, node VprNode, nest VprNode, within bool) int {
	return x.add(VprRef{
		kind:      .name
		name:      name
		node:      node
		nest:      .expression
		nest_node: nest
		within:    within
	})
}

// vpr_from_to_ref is extractFromToRef.
fn (mut c Checker) vpr_from_to_ref(mut x VprExtractor, call int) int {
	args := x.t.list(call, .arguments) or { []int{} }
	if args.len < 2 || x.t.typ(args[1]) !in [.literal, .template_literal] {
		return vpr_any
	}
	name := vue_string_literal_value(x.t, args[1], false) or { '' }
	if name == '' {
		return vpr_any
	}
	return x.add(VprRef{
		kind:      .name
		name:      name
		node:      VprNode{0, args[1]}
		nest:      .to_ref
		nest_node: VprNode{0, call}
	})
}

// vpr_from_to_refs is extractFromToRefs.
fn (mut c Checker) vpr_from_to_refs(mut x VprExtractor, call int) int {
	base := c.vpr_from_expression(mut x, VprNode{0, call}, false)
	return x.add(VprRef{
		kind: .to_refs
		refs: [base]
	})
}

// vpr_from_container is extractFromVExpressionContainer: the names a container of the template
// reads (with ignore_globals, not those of the global scope).
fn (mut c Checker) vpr_from_container(mut x VprExtractor, container int, ignore_globals bool) int {
	doc := c.vue.doc
	mut refs := []int{}
	for r in doc.nodes[container].references {
		reference := &doc.references[r]
		if reference.variable >= 0 || reference.id.kind != .estree {
			continue
		}
		tree := reference.id.snippet + 1
		es := &doc.snippets[reference.id.snippet].es
		id := reference.id.node
		name := vue_identifier_name(es, id)
		if ignore_globals && name in c.scope_tree(x.root).scopes[0].set {
			continue
		}
		if x.functional {
			if name == 'props' {
				refs << c.vpr_from_expression(mut x, VprNode{tree, id}, true)
			}
			continue
		}
		mut reference_id := id
		if name == r'$props' {
			parent := c.vpr_parent(x, VprNode{tree, id})
			if parent.node >= 0 && es.typ(parent.node) == .member_expression {
				property := es.node(parent.node, .property) or { -1 }
				if property >= 0 && es.typ(property) == .identifier {
					reference_id = property
				}
			}
		}
		node := VprNode{tree, reference_id}
		refs << vpr_from_name_nest(mut x, vue_identifier_name(es, reference_id), node, node,
			true)
	}
	return vpr_merge(mut x, refs)
}

// vpr_from_style_variables is extractFromStyleVariablesContext of getStyleVariablesContext: the
// names the `v-bind()` of the top-level <style> elements read; none without a style.
fn (mut c Checker) vpr_from_style_variables(mut x VprExtractor) ?int {
	if !c.is_vue() {
		return none
	}
	doc := c.vue.doc
	styles := doc.top_elements('style')
	if styles.len == 0 {
		return none
	}
	mut refs := []int{}
	for style in styles {
		for child in doc.nodes[style].children {
			if doc.nodes[child].typ != .v_expression_container {
				continue
			}
			for r in doc.nodes[child].references {
				reference := &doc.references[r]
				if reference.variable >= 0 || reference.id.kind != .estree {
					continue
				}
				es := &doc.snippets[reference.id.snippet].es
				node := VprNode{reference.id.snippet + 1, reference.id.node}
				refs << vpr_from_name_nest(mut x, vue_identifier_name(es, reference.id.node),
					node, node, true)
			}
		}
	}
	return vpr_merge(mut x, refs)
}

// vpr_estree_expr is the Expr of a node of a snippet.
fn vpr_estree_expr(snippet int, node int) vue.Expr {
	return vue.Expr{
		kind:    .estree
		snippet: snippet
		node:    node
	}
}
