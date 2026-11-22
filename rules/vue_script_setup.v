module rules

import estree
import treesitter { node_end }
import tsgo { TypeResponse }

// defineScriptSetupVisitor of eslint-plugin-vue 10.12.1's lib/utils/index.ts: the compiler
// macros of `<script setup>` and what they define (getComponentPropsFromDefineProps,
// getComponentEmitsFromDefineEmits, getComponentModelFromDefineModel, and the type-based
// declarations of lib/utils/ts-utils: flattenTypeNodes, extractRuntimeProps, extractRuntimeEmits,
// and the properties of a type the checker gives), with hasWithDefaults, getWithDefaults and
// getLeftOfDefineProps.

// vue_macro_names are the macros defineScriptSetupVisitor has events for (onDefinePropsEnter…).
const vue_macro_names = ['defineProps', 'defineEmits', 'defineOptions', 'defineSlots', 'defineExpose',
	'defineModel']

// VueMacro is a call of a compiler macro defineScriptSetupVisitor reports: `call` is the
// CallExpression its on…Enter event gets.
struct VueMacro {
	name string
	call int
}

// vue_macros are the macro calls of the file, in the order of the program: a call of a macro (by
// the name of its Identifier callee) inside `<script setup>` that is the initializer of a
// top-level variable declarator or the expression of a top-level expression statement (the
// candidateMacro), or for defineProps the first argument of a `withDefaults(…)` that is. A file
// without `<script setup>` has none.
fn (mut c Checker) vue_macros(t &estree.EsTree) []VueMacro {
	if c.vue_script_info.macros_built {
		return c.vue_script_info.macros
	}
	c.vue_script_info.macros_built = true
	if !c.vue_script_info.has_setup || t.root < 0 {
		return []
	}
	mut out := []VueMacro{}
	for statement in t.list(t.root, .body) or { []int{} } {
		mut candidates := []int{}
		if t.typ(statement) == .variable_declaration {
			for declarator in t.list(statement, .declarations) or { []int{} } {
				candidates << t.node(declarator, .init) or { -1 }
			}
		} else if t.typ(statement) == .expression_statement {
			candidates << t.node(statement, .expression) or { -1 }
		}
		for candidate in candidates {
			if candidate < 0 || t.typ(candidate) != .call_expression {
				continue
			}
			name := vue_callee_name(t, candidate)
			if name in vue_macro_names && c.vue_script_info.in_script_setup(t, candidate) {
				out << VueMacro{
					name: name
					call: candidate
				}
			} else if name == 'withDefaults' {
				args := t.list(candidate, .arguments) or { []int{} }
				if args.len > 0 && t.typ(args[0]) == .call_expression
					&& vue_callee_name(t, args[0]) == 'defineProps'
					&& c.vue_script_info.in_script_setup(t, args[0]) {
					out << VueMacro{
						name: 'defineProps'
						call: args[0]
					}
				}
			}
		}
	}
	c.vue_script_info.macros = out
	return out
}

// vue_callee_name is the name of the Identifier callee of a call, '' for another callee.
fn vue_callee_name(t &estree.EsTree, call int) string {
	callee := t.node(call, .callee) or { return '' }
	return if t.typ(callee) == .identifier { t.string_of(callee, .name) or { '' } } else { '' }
}

// vue_macros_named are the calls of one macro (the on<Macro>Enter events), in order.
fn (mut c Checker) vue_macros_named(t &estree.EsTree, name string) []int {
	return c.vue_macros(t).filter(it.name == name).map(it.call)
}

// vue_has_with_defaults ports hasWithDefaults: the call is the first argument of `withDefaults`.
fn vue_has_with_defaults(t &estree.EsTree, call int) bool {
	parent := t.nodes[call].parent
	if parent < 0 || t.typ(parent) != .call_expression {
		return false
	}
	args := t.list(parent, .arguments) or { return false }
	return args.len > 0 && args[0] == call && vue_callee_name(t, parent) == 'withDefaults'
}

// vue_left_of_define_props ports getLeftOfDefineProps: the pattern the props (or the
// withDefaults around them) are assigned to in a declarator, -1 for none.
fn vue_left_of_define_props(t &estree.EsTree, call int) int {
	mut target := call
	if vue_has_with_defaults(t, target) {
		target = t.nodes[target].parent
	}
	parent := t.nodes[target].parent
	if parent < 0 || t.typ(parent) != .variable_declarator
		|| (t.node(parent, .init) or { -1 }) != target {
		return -1
	}
	return t.node(parent, .id) or { -1 }
}

// vue_is_using_props_destructure ports isUsingPropsDestructure.
fn vue_is_using_props_destructure(t &estree.EsTree, call int) bool {
	left := vue_left_of_define_props(t, call)
	return left >= 0 && t.typ(left) == .object_pattern
}

// vue_type_arguments are the params of the type arguments of a call.
fn vue_type_arguments(t &estree.EsTree, call int) []int {
	args := t.node(call, .type_arguments) or { return [] }
	return t.list(args, .params) or { [] }
}

// vue_define_props ports getComponentPropsFromDefineProps. Without `with_types` the types the
// checker would read (getComponentPropsFromTypeDefineTypes) are unknown props: for a rule that
// reads only the object and array props, they are the same, and it needs no types.
fn (mut c Checker) vue_define_props(root C.vt_node, t &estree.EsTree, call int, abs_path string, with_types bool, mut stats Stats) []VueProp {
	args := t.list(call, .arguments) or { []int{} }
	if args.len > 0 {
		def := c.vue_object_or_array(root, t, args[0])
		if def >= 0 {
			return vue_props_from_define(t, def)
		}
		return [VueProp{
			kind: .unknown
			node: args[0]
		}]
	}
	params := vue_type_arguments(t, call)
	if params.len > 0 {
		return c.vue_props_from_type_define(root, t, params[0], abs_path, with_types, mut stats)
	}
	return [VueProp{
		kind: .unknown
	}]
}

// vue_define_emits ports getComponentEmitsFromDefineEmits. Without `with_types` the types the
// checker would read (getComponentEmitsFromTypeDefineTypes) are unknown emits.
fn (mut c Checker) vue_define_emits(root C.vt_node, t &estree.EsTree, call int, abs_path string, with_types bool, mut stats Stats) []VueProp {
	args := t.list(call, .arguments) or { []int{} }
	if args.len > 0 {
		def := c.vue_object_or_array(root, t, args[0])
		if def >= 0 {
			return vue_props_from_define(t, def)
		}
		return [VueProp{
			kind: .unknown
			node: args[0]
		}]
	}
	params := vue_type_arguments(t, call)
	if params.len > 0 {
		return c.vue_emits_from_type_define(root, t, params[0], abs_path, with_types, mut stats)
	}
	return [VueProp{
		kind: .unknown
	}]
}

// VueModel is a ComponentModel of getComponentModelFromDefineModel: the model's name (and the
// Literal that gives it, -1 for the default `modelValue`), its options (-1 for null) and its
// type argument (-1 for null).
struct VueModel {
	name      string
	name_node int = -1
	options   int = -1
	type_node int = -1
}

// vue_define_model ports getComponentModelFromDefineModel.
fn vue_define_model(t &estree.EsTree, call int) VueModel {
	args := t.list(call, .arguments) or { []int{} }
	mut name := 'modelValue'
	mut name_node := -1
	mut options := if args.len > 0 && t.typ(args[0]) != .spread_element { args[0] } else { -1 }
	if args.len > 0 {
		candidate := vue_skip_ts_as(t, args[0])
		if t.typ(candidate) == .literal {
			name = vue_literal_string(t, candidate)
			name_node = candidate
			options = if args.len > 1 && t.typ(args[1]) != .spread_element { args[1] } else { -1 }
		}
	}
	params := vue_type_arguments(t, call)
	return VueModel{
		name:      name
		name_node: name_node
		options:   options
		type_node: if params.len > 0 { params[0] } else { -1 }
	}
}

// vue_props_from_type_define ports getComponentPropsFromTypeDefine: the members of the type
// literals and interfaces the type is made of, and the properties the checker gives the other
// types (getComponentPropsFromTypeDefineTypes; unknown without types, or for any, unknown, never
// and null).
fn (mut c Checker) vue_props_from_type_define(root C.vt_node, t &estree.EsTree, node int, abs_path string, with_types bool, mut stats Stats) []VueProp {
	mut out := []VueProp{}
	for def in c.vue_flatten_type_nodes(root, t, node) {
		if t.typ(def) in [.ts_interface_body, .ts_type_literal] {
			for member in vue_type_members(t, def) {
				if t.typ(member) !in [.ts_property_signature, .ts_method_signature] {
					continue
				}
				key := t.node(member, .key) or { continue }
				if t.typ(key) !in [.identifier, .literal] {
					out << VueProp{
						kind: .unknown
						node: key
					}
					continue
				}
				out << VueProp{
					kind:     .type_
					has_name: true
					name:     if t.typ(key) == .identifier {
						t.string_of(key, .name) or { '' }
					} else {
						vue_literal_string(t, key)
					}
					node:     member
					key:      key
				}
			}
			continue
		}
		if !with_types {
			out << VueProp{
				kind: .unknown
				node: def
			}
			continue
		}
		out << c.vue_props_from_type_checker(t, def, abs_path, mut stats)
	}
	return out
}

// vue_props_from_type_checker ports getComponentPropsFromTypeDefineTypes.
fn (mut c Checker) vue_props_from_type_checker(t &estree.EsTree, node int, abs_path string, mut stats Stats) []VueProp {
	unknown := [VueProp{
		kind: .unknown
		node: node
	}]
	typ := c.vue_type_of_type_node(t, node, abs_path, mut stats) or { return unknown }
	if typ.flags & (type_flag_any | type_flag_unknown | type_flag_never | type_flag_null) != 0 {
		return unknown
	}
	properties := c.properties(typ) or { return unknown }
	return properties.map(VueProp{
		kind:     .infer_type
		has_name: true
		name:     it.name
		node:     node
	})
}

// vue_type_of_type_node is checker.getTypeAtLocation of a type node (tsNodeMap.get(node)), none
// when the parser has no program: a type reference is TypeScript's TypeReference, not the
// identifier of its name, which has the same range.
fn (mut c Checker) vue_type_of_type_node(t &estree.EsTree, node int, abs_path string, mut stats Stats) ?TypeResponse {
	if !c.scope_setup.type_information {
		return none
	}
	ts := t.ts_node(node)?
	c.resolve_spans([
		Span{
			key:   node_key(ts)
			first: ts
			end:   node_end(ts)
			kind:  if t.typ(node) == .ts_type_reference { syntax_kind_type_reference } else { 0 }
		},
	], abs_path, mut stats) or { return none }
	return c.node_type(ts)
}

// vue_emits_from_type_define ports getComponentEmitsFromTypeDefine: the type literals,
// interfaces and function types the type is made of (extractRuntimeEmits), and the emits the
// checker gives the other types (getComponentEmitsFromTypeDefineTypes; unknown without types).
fn (mut c Checker) vue_emits_from_type_define(root C.vt_node, t &estree.EsTree, node int, abs_path string, with_types bool, mut stats Stats) []VueProp {
	mut out := []VueProp{}
	for def in c.vue_flatten_type_nodes(root, t, node) {
		if t.typ(def) == .ts_function_type {
			params := t.list(def, .params) or { []int{} }
			vue_extract_event_names(t, if params.len > 0 { params[0] } else { -1 }, def, mut out)
			continue
		}
		if t.typ(def) !in [.ts_interface_body, .ts_type_literal] {
			if with_types {
				out << c.vue_emits_from_type_checker(t, def, abs_path, mut stats)
			} else {
				out << VueProp{
					kind: .unknown
					node: def
				}
			}
			continue
		}
		for member in vue_type_members(t, def) {
			if t.typ(member) == .ts_call_signature_declaration {
				params := t.list(member, .params) or { []int{} }
				vue_extract_event_names(t, if params.len > 0 { params[0] } else { -1 }, member, mut
					out)
			} else if t.typ(member) in [.ts_property_signature, .ts_method_signature] {
				key := t.node(member, .key) or { continue }
				if t.typ(key) !in [.identifier, .literal] {
					out << VueProp{
						kind: .unknown
						node: key
					}
					continue
				}
				out << VueProp{
					kind:     .type_
					has_name: true
					name:     if t.typ(key) == .identifier {
						t.string_of(key, .name) or { '' }
					} else {
						vue_literal_string(t, key)
					}
					node:     member
					key:      key
				}
			}
		}
	}
	return out
}

// vue_extract_event_names ports extractEventNames: the literal types of the first parameter.
fn vue_extract_event_names(t &estree.EsTree, param int, member int, mut out []VueProp) {
	if param < 0 || t.typ(param) != .identifier {
		return
	}
	annotation := t.node(param, .type_annotation) or { return }
	if t.typ(annotation) != .ts_type_annotation {
		return
	}
	type_node := t.node(annotation, .type_annotation) or { return }
	mut literals := []int{}
	if t.typ(type_node) == .ts_literal_type {
		literals << type_node
	} else if t.typ(type_node) == .ts_union_type {
		literals << t.list(type_node, .types) or { []int{} }
	}
	for lt in literals {
		if t.typ(lt) != .ts_literal_type {
			continue
		}
		literal := t.node(lt, .literal) or { continue }
		if t.typ(literal) != .literal {
			continue
		}
		out << VueProp{
			kind:     .type_
			has_name: true
			name:     vue_literal_string(t, literal)
			node:     member
			key:      lt
		}
	}
}

// vue_type_members are the members of a TSTypeLiteral or the body of a TSInterfaceBody.
fn vue_type_members(t &estree.EsTree, node int) []int {
	return if t.typ(node) == .ts_type_literal {
		t.list(node, .members) or { [] }
	} else {
		t.list(node, .body) or { [] }
	}
}

// vue_flatten_type_nodes ports flattenTypeNodes: the parts of unions and intersections, through
// the interfaces (their bodies) and type aliases of the file a type reference names.
fn (mut c Checker) vue_flatten_type_nodes(root C.vt_node, t &estree.EsTree, node int) []int {
	mut traversed := map[int]VueTraversed{}
	return c.vue_flatten_impl(root, t, node, mut traversed)
}

// VueTraversed is the TraversedData of flattenTypeNodes: the nodes found so far for a type alias
// (a Set, in insertion order) and whether it is done.
struct VueTraversed {
mut:
	nodes    []int
	finished bool
}

fn (mut c Checker) vue_flatten_impl(root C.vt_node, t &estree.EsTree, node int, mut traversed map[int]VueTraversed) []int {
	if t.typ(node) in [.ts_union_type, .ts_intersection_type] {
		mut out := []int{}
		for part in t.list(node, .types) or { []int{} } {
			out << c.vue_flatten_impl(root, t, part, mut traversed)
		}
		return out
	}
	if t.typ(node) == .ts_type_reference {
		type_name := t.node(node, .type_name) or { -1 }
		if type_name >= 0 && t.typ(type_name) == .identifier {
			def_node := c.vue_single_type_definition(root, t, type_name)
			if def_node >= 0 && t.typ(def_node) == .ts_interface_declaration {
				return [t.node(def_node, .body) or { return [node] }]
			}
			if def_node >= 0 && t.typ(def_node) == .ts_type_alias_declaration {
				annotation := t.node(def_node, .type_annotation) or { return [node] }
				if data := traversed[annotation] {
					mut out := data.nodes.clone()
					if !data.finished {
						// Include the node: it is probably referenced recursively.
						out << annotation
					}
					return out
				}
				traversed[annotation] = VueTraversed{}
				for e in c.vue_flatten_impl(root, t, annotation, mut traversed) {
					if e !in traversed[annotation].nodes {
						traversed[annotation].nodes << e
					}
				}
				traversed[annotation].finished = true
				return traversed[annotation].nodes.clone()
			}
		}
	}
	return [node]
}

// vue_single_type_definition is the ESTree node of the only definition of the variable an
// Identifier names (findVariable(getScope(node), name)), -1 when it has none or several.
fn (mut c Checker) vue_single_type_definition(root C.vt_node, t &estree.EsTree, id int) int {
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return -1
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	if defs.len != 1 {
		return -1
	}
	return c.es_index_of(t, defs[0].node) or { -1 }
}
