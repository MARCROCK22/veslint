module rules

import estree
import tsgo { TypeResponse }

// The type tracker of eslint-plugin-regexp 3.3.3 (lib/utils/type-tracker/tracker.ts), for the
// `regexp/*` rules (regexp_utils.v). With typescript-eslint's parser the tracker has its
// esTreeNodeToTSNodeMap (`usedTS`), so a node that is not a literal or a template literal gets its
// type from the program's checker (getTypeByTs) and never from the inference of JavaScript and
// JSDoc it does with espree; without a program (no checker) such a node has no type. veslint asks
// tsgo (the `regexp/*` rules that use it need types). The types are TypeInfo's names (typeNames):
// none is null.

const rx_object_flag_class_or_interface = u32(3)
const rx_object_flag_tuple = u32(8)
const rx_object_flag_evolving_array = u32(256)
const rx_object_flag_array_literal = u32(16384)

// rx_type ports getType of the tracker: the names of the type of an expression (sorted, each once),
// none for null.
fn (mut c Checker) rx_type(root C.vt_node, t &estree.EsTree, abs_path string, node int) ?[]string {
	if node < 0 {
		return none
	}
	if t.typ(node) == .literal {
		v := t.get(node, .value)
		match v {
			string {
				return ['String']
			}
			bool {
				return ['Boolean']
			}
			f64 {
				return ['Number']
			}
			else {}
		}
		if t.prop(node, .regex) != none {
			return ['RegExp']
		}
		if t.prop(node, .bigint) != none {
			return ['BigInt']
		}
		if v is estree.Null || v is estree.Undefined {
			return ['null']
		}
	} else if t.typ(node) == .template_literal {
		return ['String']
	}
	// getTypeByTs: the type of the node's TypeScript node, from the checker.
	if !c.scope_setup.type_information {
		return none
	}
	ts := t.ts_node(node) or { return none }
	mut stats := Stats{}
	c.resolve_node_types([ts], abs_path, mut stats) or { return none }
	typ := c.node_type(ts) or { return none }
	if typ.is_null() {
		return none
	}
	return c.rx_type_from_ts_type(typ, 0)
}

// rx_type_from_ts_type ports getTypeFromTsType.
fn (mut c Checker) rx_type_from_ts_type(typ TypeResponse, depth int) ?[]string {
	if depth > 50 {
		return none
	}
	if typ.flags & type_flag_string_like != 0 {
		return ['String']
	}
	if typ.flags & type_flag_number_like != 0 {
		return ['Number']
	}
	if typ.flags & type_flag_boolean_like != 0 {
		return ['Boolean']
	}
	if typ.flags & type_flag_bigint_like != 0 {
		return ['BigInt']
	}
	if typ.flags & (type_flag_any | type_flag_unknown) != 0 {
		return none
	}
	if rx_is_array_like_object(typ) {
		return ['Array']
	}
	if typ.flags & type_flag_object != 0 && typ.object_flags & object_flag_reference != 0 {
		target := c.target_of(typ) or { TypeResponse{} }
		if !target.is_null() && target.id != typ.id {
			return c.rx_type_from_ts_type(target, depth + 1)
		}
	}
	if typ.flags & type_flag_type_parameter != 0 {
		constraint := c.base_constraint(typ) or { return none }
		if constraint.is_null() || constraint.id == typ.id {
			return none
		}
		return c.rx_type_from_ts_type(constraint, depth + 1)
	}
	if typ.flags & (type_flag_union | type_flag_intersection) != 0 {
		members := c.members_of(typ) or { return none }
		mut out := []string{}
		for member in members {
			type_names := c.rx_type_from_ts_type(member, depth + 1) or { continue }
			for name in type_names {
				if name !in out {
					out << name
				}
			}
		}
		if out.len == 0 {
			return none
		}
		out.sort()
		return out
	}
	if typ.flags & type_flag_object != 0 && typ.object_flags & rx_object_flag_class_or_interface != 0 {
		symbol := c.symbol_of(typ) or { return none }
		name := if symbol.name.starts_with('Readonly') { symbol.name['Readonly'.len..] } else { symbol.name }
		return [name]
	}
	if typ.flags & type_flag_object != 0 {
		return ['Object']
	}
	return [c.type_string(typ) or { return none }]
}

// rx_is_array_like_object ports isArrayLikeObject.
fn rx_is_array_like_object(typ TypeResponse) bool {
	return typ.flags & type_flag_object != 0 && typ.object_flags & (rx_object_flag_array_literal | rx_object_flag_evolving_array | rx_object_flag_tuple) != 0
}

// rx_is_string ports TypeTracker#isString.
fn (mut c Checker) rx_is_string(root C.vt_node, t &estree.EsTree, abs_path string, node int) bool {
	type_names := c.rx_type(root, t, abs_path, node) or { return false }
	return 'String' in type_names
}

// rx_maybe_string ports TypeTracker#maybeString: with typescript-eslint's parser (usedTS), isString.
fn (mut c Checker) rx_maybe_string(root C.vt_node, t &estree.EsTree, abs_path string, node int) bool {
	return c.rx_is_string(root, t, abs_path, node)
}

// rx_is_regexp ports TypeTracker#isRegExp.
fn (mut c Checker) rx_is_regexp(root C.vt_node, t &estree.EsTree, abs_path string, node int) bool {
	type_names := c.rx_type(root, t, abs_path, node) or { return false }
	return 'RegExp' in type_names
}

// rx_types ports TypeTracker#getTypes.
fn (mut c Checker) rx_types(root C.vt_node, t &estree.EsTree, abs_path string, node int) []string {
	return c.rx_type(root, t, abs_path, node) or { [] }
}

// rx_ts_is_any ports isAny of ts-util.ts.
fn rx_ts_is_any(typ TypeResponse) bool {
	return typ.flags & type_flag_any != 0
}

// rx_ts_is_null ports isNull of ts-util.ts.
fn rx_ts_is_null(typ TypeResponse) bool {
	return typ.flags & type_flag_null != 0
}

// rx_ts_is_union_or_intersection ports isUnionOrIntersection of ts-util.ts.
fn rx_ts_is_union_or_intersection(typ TypeResponse) bool {
	return typ.flags & (type_flag_union | type_flag_intersection) != 0
}

// rx_ts_is_class_or_interface ports isClassOrInterface of ts-util.ts.
fn rx_ts_is_class_or_interface(typ TypeResponse) bool {
	return typ.flags & type_flag_object != 0 && typ.object_flags & rx_object_flag_class_or_interface != 0
}
