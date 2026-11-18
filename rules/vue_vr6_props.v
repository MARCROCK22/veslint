module rules

import estree
import treesitter { node_field, node_kind }
import tsgo { SymbolResponse, TypeResponse }

// What the props rules of the VR6 batch read of `defineProps` that vue_script_setup.v does not
// compute (eslint-plugin-vue 10.12.1): the `types` and `required` of a type prop
// (extractRuntimeProps and inferRuntimeType of lib/utils/ts-utils/ts-ast.ts, with
// inferRuntimeTypeFromTypeNode through the checker), the defaults of `withDefaults`
// (getWithDefaultsProps, getWithDefaultsPropExpressions) and of a props destructure
// (getPropsDestructure, getDefaultPropExpressionsForPropsDestructure).

// Vx6TypeProp is what a type prop has besides its name: whether it is required (not `?`) and
// its runtime types.
struct Vx6TypeProp {
	required bool
	types    []string
}

const vx6_symbol_flag_function = u32(16)
const vx6_symbol_flag_method = u32(8192)
const vx6_object_flag_class_or_interface = u32(1 | 2)
const vx6_object_flag_array_like = u32(8 | 256 | 16384) // Tuple, EvolvingArray, ArrayLiteral

// vx6_type_prop is the `required` and `types` of a type prop whose node is a
// TSPropertySignature or TSMethodSignature.
fn (mut c Checker) vx6_type_prop(root C.TSNode, t &estree.EsTree, member int, abs_path string, mut stats Stats) Vx6TypeProp {
	required := !(t.flag(member, .optional) or { false })
	if t.typ(member) == .ts_method_signature {
		return Vx6TypeProp{required, ['Function']}
	}
	annotation := t.node(member, .type_annotation) or { return Vx6TypeProp{required, ['null']} }
	typ := t.node(annotation, .type_annotation) or { return Vx6TypeProp{required, ['null']} }
	mut checked := map[int]bool{}
	return Vx6TypeProp{required, c.vx6_infer_runtime_type(root, t, typ, abs_path, mut checked, mut
		stats)}
}

// vx6_infer_runtime_type ports inferRuntimeType.
fn (mut c Checker) vx6_infer_runtime_type(root C.TSNode, t &estree.EsTree, node int, abs_path string, mut checked map[int]bool, mut stats Stats) []string {
	match t.typ(node) {
		.ts_string_keyword, .ts_template_literal_type {
			return ['String']
		}
		.ts_number_keyword {
			return ['Number']
		}
		.ts_boolean_keyword {
			return ['Boolean']
		}
		.ts_object_keyword {
			return ['Object']
		}
		.ts_type_literal {
			mut types := []string{}
			for m in t.list(node, .members) or { []int{} } {
				kind := if t.typ(m) in [.ts_call_signature_declaration,
					.ts_construct_signature_declaration] {
					'Function'
				} else {
					'Object'
				}
				if kind !in types {
					types << kind
				}
			}
			return if types.len > 0 { types } else { ['Object'] }
		}
		.ts_function_type {
			return ['Function']
		}
		.ts_array_type, .ts_tuple_type {
			return ['Array']
		}
		.ts_symbol_keyword {
			return ['Symbol']
		}
		.ts_literal_type {
			literal := t.node(node, .literal) or { -1 }
			if literal >= 0 && t.typ(literal) == .literal {
				value := t.get(literal, .value)
				if value is bool {
					return ['Boolean']
				}
				if value is string {
					return ['String']
				}
				if value is f64 || value is estree.BigIntValue {
					return ['Number']
				}
			}
			return c.vx6_infer_from_type_node(t, node, abs_path, mut stats)
		}
		.ts_type_reference {
			name_node := t.node(node, .type_name) or { -1 }
			if name_node >= 0 && t.typ(name_node) == .identifier {
				name := t.string_of(name_node, .name) or { '' }
				if types := c.vx6_infer_type_reference(root, t, node, name, abs_path, mut checked, mut
					stats)
				{
					return types
				}
			}
			return c.vx6_infer_from_type_node(t, node, abs_path, mut stats)
		}
		.ts_union_type, .ts_intersection_type {
			mut types := []string{}
			for part in t.list(node, .types) or { []int{} } {
				for kind in c.vx6_infer_runtime_type(root, t, part, abs_path, mut checked, mut
					stats) {
					if kind !in types {
						types << kind
					}
				}
			}
			return types
		}
		else {
			return c.vx6_infer_from_type_node(t, node, abs_path, mut stats)
		}
	}
}

// vx6_infer_type_reference is the TSTypeReference case of inferRuntimeType for an identifier
// name: none when it falls through to the checker.
fn (mut c Checker) vx6_infer_type_reference(root C.TSNode, t &estree.EsTree, node int, name string, abs_path string, mut checked map[int]bool, mut stats Stats) ?[]string {
	if ts := t.ts_node(node) {
		tree := c.scope_tree(root)
		v := tree.find_variable(tree.get_scope(ts), name, t.nodes[node].start)
		if v >= 0 && tree.variables[v].defs.len == 1 {
			def := tree.variables[v].defs[0]
			kind := node_kind(def.node)
			if kind == 'interface_declaration' {
				return ['Object']
			}
			if kind == 'type_alias_declaration' {
				if value := node_field(def.node, 'value') {
					if es := c.es_index_of(t, value) {
						if es !in checked {
							checked[es] = true
							return c.vx6_infer_runtime_type(root, t, es, abs_path, mut checked, mut
								stats)
						}
					}
				}
			} else if kind == 'enum_declaration' {
				if es := c.es_index_of(t, def.node) {
					return c.vx6_infer_enum_type(t, es, abs_path, mut stats)
				}
			}
		}
	}
	mut candidates := [name]
	if name.starts_with('Readonly') {
		candidates << name[8..]
	}
	for candidate in candidates {
		if candidate in ['Array', 'Function', 'Object', 'Set', 'Map', 'WeakSet', 'WeakMap', 'Date'] {
			return [candidate]
		}
	}
	params := vx6_type_arguments_of(t, node)
	match name {
		'Record', 'Partial', 'Readonly', 'Pick', 'Omit', 'Required', 'InstanceType' {
			return ['Object']
		}
		'Uppercase', 'Lowercase', 'Capitalize', 'Uncapitalize' {
			return ['String']
		}
		'Parameters', 'ConstructorParameters' {
			return ['Array']
		}
		'NonNullable' {
			if params.len > 0 {
				return c.vx6_infer_runtime_type(root, t, params[0], abs_path, mut checked, mut
					stats).filter(it != 'null')
			}
		}
		'Extract' {
			if params.len > 1 {
				return c.vx6_infer_runtime_type(root, t, params[1], abs_path, mut checked, mut
					stats)
			}
		}
		'Exclude', 'OmitThisParameter' {
			if params.len > 0 {
				return c.vx6_infer_runtime_type(root, t, params[0], abs_path, mut checked, mut
					stats)
			}
		}
		else {}
	}
	return none
}

// vx6_type_arguments_of are the params of the type arguments of a type reference.
fn vx6_type_arguments_of(t &estree.EsTree, node int) []int {
	args := t.node(node, .type_arguments) or { return [] }
	return t.list(args, .params) or { [] }
}

// vx6_infer_enum_type ports inferEnumType.
fn (mut c Checker) vx6_infer_enum_type(t &estree.EsTree, decl int, abs_path string, mut stats Stats) []string {
	mut types := []string{}
	body := t.node(decl, .body) or { -1 }
	members := if body >= 0 { t.list(body, .members) or { []int{} } } else { []int{} }
	for m in members {
		init := t.node(m, .initializer) or { continue }
		if t.typ(init) == .literal {
			value := t.get(init, .value)
			kind := if value is string {
				'String'
			} else if value is f64 || value is estree.BigIntValue {
				'Number'
			} else if value is bool {
				'Boolean'
			} else {
				''
			}
			if kind != '' && kind !in types {
				types << kind
			}
		} else {
			for kind in c.vx6_infer_from_type_node(t, init, abs_path, mut stats) {
				if kind !in types {
					types << kind
				}
			}
		}
	}
	return if types.len > 0 { types } else { ['Number'] }
}

// vx6_infer_from_type_node ports inferRuntimeTypeFromTypeNode: ['null'] without types.
fn (mut c Checker) vx6_infer_from_type_node(t &estree.EsTree, node int, abs_path string, mut stats Stats) []string {
	typ := c.vue_type_of_type_node(t, node, abs_path, mut stats) or { return ['null'] }
	return c.vx6_infer_runtime_type_internal(typ, 0) or { ['null'] }
}

// vx6_infer_runtime_type_internal ports inferRuntimeTypeInternal.
fn (mut c Checker) vx6_infer_runtime_type_internal(typ TypeResponse, depth int) ![]string {
	mut types := []string{}
	if depth > 20 {
		return types
	}
	if typ.flags & type_flag_type_parameter != 0 {
		constraint := c.constraint_of(typ) or { return types }
		if constraint.id == 0 {
			return types
		}
		for kind in c.vx6_infer_runtime_type_internal(constraint, depth + 1)! {
			if kind !in types {
				types << kind
			}
		}
		return types
	}
	// checker.getNonNullableType: the union without null and undefined (never for them alone).
	mut targets := []TypeResponse{}
	for part in c.constituents(typ)! {
		if part.flags & (type_flag_null | type_flag_undefined) == 0 {
			c.vx6_iterate_types(part, mut targets, 0)!
		}
	}
	if targets.len == 0 {
		// never
		return ['null']
	}
	for target in targets {
		kind := c.vx6_runtime_kind(target)!
		if kind != '' && kind !in types {
			types << kind
		}
	}
	if types.len == 0 {
		types << 'null'
	}
	return types
}

// vx6_iterate_types ports iterateTypes: a reference to a generic type is its target, a union
// (other than boolean) its constituents.
fn (mut c Checker) vx6_iterate_types(typ TypeResponse, mut out []TypeResponse, depth int) ! {
	if depth > 20 {
		return
	}
	if typ.flags & type_flag_object != 0 && typ.object_flags & object_flag_reference != 0
		&& typ.target != 0 && typ.target != typ.id {
		c.vx6_iterate_types(c.target_of(typ)!, mut out, depth + 1)!
		return
	}
	if typ.flags & type_flag_union != 0 && typ.flags & type_flag_boolean_like == 0 {
		for part in c.members_of(typ)! {
			c.vx6_iterate_types(part, mut out, depth + 1)!
		}
		return
	}
	out << typ
}

// vx6_runtime_kind is the runtime type inferRuntimeTypeInternal gives one target type ('' for
// none).
fn (mut c Checker) vx6_runtime_kind(target TypeResponse) !string {
	if target.flags & (type_flag_any | type_flag_unknown | type_flag_never | type_flag_null) != 0 {
		return 'null'
	}
	if target.flags & type_flag_string_like != 0 {
		return 'String'
	}
	if target.flags & (type_flag_number_like | type_flag_bigint_like) != 0 {
		return 'Number'
	}
	if target.flags & type_flag_boolean_like != 0 {
		return 'Boolean'
	}
	mut symbol := SymbolResponse{}
	if target.symbol != 0 {
		symbol = c.symbol_of(target)!
	}
	if symbol.flags & (vx6_symbol_flag_function | vx6_symbol_flag_method) != 0
		|| (c.call_signatures_of(target)!).len > 0 {
		return 'Function'
	}
	is_object := target.flags & type_flag_object != 0
	if (is_object && target.object_flags & vx6_object_flag_array_like != 0)
		|| (is_object && target.object_flags & vx6_object_flag_class_or_interface != 0
		&& symbol.parent == 0 && symbol.name in ['Array', 'ReadonlyArray']) {
		return 'Array'
	}
	if is_object {
		return 'Object'
	}
	return ''
}

// vx6_with_defaults_props ports getWithDefaultsProps: the Properties of the object literal of
// `withDefaults(defineProps(…), {…})`, by static name (a later one wins).
fn vx6_with_defaults_props(t &estree.EsTree, call int) map[string]int {
	mut out := map[string]int{}
	if !vue_has_with_defaults(t, call) {
		return out
	}
	args := t.list(t.nodes[call].parent, .arguments) or { return out }
	if args.len < 2 || t.typ(args[1]) != .object_expression {
		return out
	}
	for p in t.list(args[1], .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		if name := vue_static_property_name(t, p) {
			out[name] = p
		}
	}
	return out
}

// Vx6WithDefaults is getWithDefaultsPropExpressions: the default expression of each prop (a
// value of -1 for undefined) and whether the object could not be read statically.
struct Vx6WithDefaults {
mut:
	props       map[string]int
	has_unknown bool
}

// vx6_with_defaults_expressions ports getWithDefaultsPropExpressions (collectPropExpressions:
// through `const` references and spreads).
fn (mut c Checker) vx6_with_defaults_expressions(root C.TSNode, t &estree.EsTree, call int) Vx6WithDefaults {
	mut out := Vx6WithDefaults{}
	if !vue_has_with_defaults(t, call) {
		return out
	}
	args := t.list(t.nodes[call].parent, .arguments) or { return out }
	if args.len < 2 {
		return out
	}
	mut visited := map[int]bool{}
	out.has_unknown = !c.vx6_collect_prop_expressions(root, t, args[1], mut out.props, mut
		visited)
	return out
}

fn (mut c Checker) vx6_collect_prop_expressions(root C.TSNode, t &estree.EsTree, node int, mut result map[string]int, mut visited map[int]bool) bool {
	object := c.vue_object_or_array(root, t, node)
	if object < 0 || t.typ(object) != .object_expression {
		return false
	}
	if object in visited {
		return true
	}
	visited[object] = true
	mut resolved := true
	for p in t.list(object, .properties) or { []int{} } {
		if t.typ(p) == .spread_element {
			argument := t.node(p, .argument) or { -1 }
			if argument < 0 || !c.vx6_collect_prop_expressions(root, t, argument, mut result, mut
				visited) {
				resolved = false
			}
			continue
		}
		name := vue_static_property_name(t, p) or {
			resolved = false
			continue
		}
		result[name] = t.node(p, .value) or { -1 }
	}
	return resolved
}

// vx6_props_destructure ports getPropsDestructure: the Properties of the object pattern the
// props are destructured into, by static name.
fn vx6_props_destructure(t &estree.EsTree, call int) map[string]int {
	mut out := map[string]int{}
	left := vue_left_of_define_props(t, call)
	if left < 0 || t.typ(left) != .object_pattern {
		return out
	}
	for p in t.list(left, .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		if name := vue_static_property_name(t, p) {
			out[name] = p
		}
	}
	return out
}

// Vx6DestructureDefault is an entry of getDefaultPropExpressionsForPropsDestructure.
struct Vx6DestructureDefault {
	prop       int
	expression int
}

// vx6_destructure_defaults ports getDefaultPropExpressionsForPropsDestructure: the props whose
// destructured value has a default (`{ a = 1 }`).
fn vx6_destructure_defaults(t &estree.EsTree, call int) map[string]Vx6DestructureDefault {
	mut out := map[string]Vx6DestructureDefault{}
	for name, p in vx6_props_destructure(t, call) {
		value := t.node(p, .value) or { continue }
		if t.typ(value) != .assignment_pattern {
			continue
		}
		out[name] = Vx6DestructureDefault{
			prop:       p
			expression: t.node(value, .right) or { continue }
		}
	}
	return out
}

// vx6_literal_truthy is Boolean(literal.value) of a Literal.
fn vx6_literal_truthy(t &estree.EsTree, literal int) bool {
	value := t.get(literal, .value)
	return match value {
		bool { value }
		string { value != '' }
		f64 { value != 0 && value == value }
		estree.BigIntValue { value.digits.trim_left('0') != '' }
		estree.RegExpValue { true }
		else { false }
	}
}

// vx6_define_props_calls are the defineProps calls of `<script setup>` (onDefinePropsEnter).
fn (mut c Checker) vx6_define_props_calls(t &estree.EsTree) []int {
	return c.vue_macros_named(t, 'defineProps')
}

// vx6_property_value_of is `findProperty(object, name)?.value`: -1 for none.
fn vx6_property_value_of(t &estree.EsTree, object int, name string) int {
	p := vue_find_property(t, object, name, none)
	return if p >= 0 { vue_property_value(t, p) } else { -1 }
}
