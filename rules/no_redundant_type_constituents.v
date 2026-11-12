module rules

import strings
import time
import tsgo { TypeResponse }
import treesitter { node_field, node_kind, node_parent, nodes_of_kinds, position_of }

// Port of the `no-redundant-type-constituents` rule of typescript-eslint 8.62.0 (it has no
// options).

const nrtc_messages = {
	'errorTypeOverrides':  "'{{typeName}}' is an 'error' type that acts as 'any' and overrides all other types in this {{container}} type."
	'literalOverridden':   '{{literal}} is overridden by {{primitive}} in this union type.'
	'overridden':          "'{{typeName}}' is overridden by other types in this {{container}} type."
	'overrides':           "'{{typeName}}' overrides all other types in this {{container}} type."
	'primitiveOverridden': '{{primitive}} is overridden by the {{literal}} in this intersection type.'
}

const nrtc_flag_string = u32(32)
const nrtc_flag_bigint = u32(128)
const nrtc_flag_boolean = u32(256)
const nrtc_flag_template_literal = u32(4194304)

// literalTypeFlags and primitiveTypeFlags, in the rule's order.
const nrtc_literal_flags = [type_flag_bigint_literal, type_flag_boolean_literal,
	type_flag_number_literal, type_flag_string_literal, nrtc_flag_template_literal]
const nrtc_primitive_flags = [nrtc_flag_bigint, nrtc_flag_boolean, type_flag_number, nrtc_flag_string]

// NrtcPart ports the `{ typeFlags, typeName }` of a part of a type node.
struct NrtcPart {
	flags u32
	name  string
}

// NrtcLiteral is a literal part of a union and the type node it comes from.
struct NrtcLiteral {
	value string
	node  C.TSNode
}

// NrtcOverride is a literal of a type node overridden by a primitive of the union.
struct NrtcOverride {
	value     string
	primitive u32
}

// NrtcUnionMember is a member of an intersection whose type is a union (seenUnionTypes).
struct NrtcUnionMember {
	node  C.TSNode
	parts []NrtcPart
}

fn (mut c Checker) lint_no_redundant_type_constituents(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut containers := []C.TSNode{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['union_type', 'intersection_type'], []string{}) {
		parent := node_parent(node) or { continue }
		// tree-sitter nests `A | B | C` as `(A | B) | C`: the inner one is not an ESTree node.
		if node_kind(parent) == node_kind(node) {
			continue
		}
		containers << node
		for member in type_members(node) {
			c.nrtc_spans(member, mut spans)
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	mut cache := map[u64][]NrtcPart{}
	for node in containers {
		if node_kind(node) == 'union_type' {
			c.nrtc_check_union(node, mut cache, mut findings)!
		} else {
			c.nrtc_check_intersection(node, mut cache, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += containers.len
	return findings
}

// nrtc_spans requests the types nrtc_parts may need for a type node.
fn (c &Checker) nrtc_spans(n C.TSNode, mut spans []Span) {
	if c.nrtc_syntactic_part(n) != none {
		return
	}
	if node_kind(n) == 'union_type' {
		for member in type_members(n) {
			c.nrtc_spans(member, mut spans)
		}
		return
	}
	spans << c.type_node_span(n)
}

// nrtc_parts ports getTypeNodeTypePartFlagsCached.
fn (mut c Checker) nrtc_parts(n C.TSNode, mut cache map[u64][]NrtcPart) ![]NrtcPart {
	key := node_key(n)
	if key in cache {
		return cache[key]
	}
	parts := c.nrtc_compute_parts(n, mut cache)!
	cache[key] = parts
	return parts
}

// nrtc_compute_parts ports getTypeNodeTypePartFlags: keywords and literals by their syntax, unions
// by their members, other types by their type (a boolean stays whole).
fn (mut c Checker) nrtc_compute_parts(n C.TSNode, mut cache map[u64][]NrtcPart) ![]NrtcPart {
	if part := c.nrtc_syntactic_part(n) {
		return [part]
	}
	if node_kind(n) == 'union_type' {
		mut out := []NrtcPart{}
		for member in type_members(n) {
			out << c.nrtc_parts(member, mut cache)!
		}
		return out
	}
	t := c.node_type(n) or { return []NrtcPart{} }
	mut out := []NrtcPart{}
	for part in c.nrtc_union_parts_unless_boolean(t)! {
		out << NrtcPart{
			flags: part.flags
			name:  c.nrtc_describe_type(part)!
		}
	}
	return out
}

// nrtc_syntactic_part is the part of a keyword type of keywordNodeTypesToTsTypes or of a
// TSLiteralType of a Literal, with describeLiteralTypeNode as its name.
fn (c &Checker) nrtc_syntactic_part(n C.TSNode) ?NrtcPart {
	match node_kind(n) {
		'predefined_type' {
			text := c.text(n)
			flags := match text {
				'any' { type_flag_any }
				'boolean' { nrtc_flag_boolean }
				'never' { type_flag_never }
				'number' { type_flag_number }
				'string' { nrtc_flag_string }
				'unknown' { type_flag_unknown }
				else { return none }
			}
			return NrtcPart{
				flags: flags
				name:  text
			}
		}
		'type_identifier' {
			// tree-sitter reads the `bigint` keyword as a type name; describeLiteralTypeNode has no
			// case for TSBigIntKeyword.
			if c.text(n) == 'bigint' {
				return NrtcPart{
					flags: nrtc_flag_bigint
					name:  'literal type'
				}
			}
			return none
		}
		'literal_type' {
			literal := first_named(n)?
			text := c.text(literal)
			match node_kind(literal) {
				'string' {
					value := cooked_string(text[1..text.len - 1], false) or { text[1..text.len - 1] }
					return NrtcPart{
						flags: type_flag_string_literal
						name:  nrtc_json_string(value)
					}
				}
				'number' {
					value := js_number_string(text)?
					if text.ends_with('n') {
						return NrtcPart{
							flags: type_flag_bigint_literal
							name:  value + 'n'
						}
					}
					return NrtcPart{
						flags: type_flag_number_literal
						name:  value
					}
				}
				'true', 'false' {
					return NrtcPart{
						flags: type_flag_boolean_literal
						name:  text
					}
				}
				else {
					return none
				}
			}
		}
		else {
			return none
		}
	}
}

// nrtc_union_parts_unless_boolean ports unionTypePartsUnlessBoolean: a boolean (`false | true`) is
// one part.
fn (mut c Checker) nrtc_union_parts_unless_boolean(t TypeResponse) ![]TypeResponse {
	if t.flags & type_flag_union != 0 {
		members := c.members_of(t)!
		if members.len == 2 && is_false_literal(members[0]) && is_true_literal(members[1]) {
			return [t]
		}
		return members
	}
	return [t]
}

// nrtc_describe_type ports describeLiteralType.
fn (mut c Checker) nrtc_describe_type(t TypeResponse) !string {
	value := t.value
	if t.flags & type_flag_string_literal != 0 {
		return nrtc_json_string(if value is string { value } else { '' })
	}
	flags := c.type_flags(t)!
	if flags & type_flag_bigint_literal != 0 {
		return (if value is string { value } else { '0' }) + 'n'
	}
	if t.flags & type_flag_literal_value != 0 {
		return literal_type_name(t)
	}
	if is_error_type(t) && t.alias_symbol != 0 {
		return c.alias_symbol_of(t)!.name
	}
	if flags & type_flag_any != 0 {
		return 'any'
	}
	if flags & type_flag_never != 0 {
		return 'never'
	}
	if flags & type_flag_unknown != 0 {
		return 'unknown'
	}
	if flags & nrtc_flag_template_literal != 0 {
		return 'template literal type'
	}
	if is_true_literal(t) {
		return 'true'
	}
	if is_false_literal(t) {
		return 'false'
	}
	return 'literal type'
}

// nrtc_json_string ports JSON.stringify of a string.
fn nrtc_json_string(s string) string {
	mut sb := strings.new_builder(s.len + 2)
	sb.write_u8(`"`)
	for b in s.bytes() {
		match b {
			`"` {
				sb.write_string('\\"')
			}
			`\\` {
				sb.write_string('\\\\')
			}
			`\n` {
				sb.write_string('\\n')
			}
			`\r` {
				sb.write_string('\\r')
			}
			`\t` {
				sb.write_string('\\t')
			}
			8 {
				sb.write_string('\\b')
			}
			12 {
				sb.write_string('\\f')
			}
			else {
				if b < 0x20 {
					sb.write_string('\\u00')
					sb.write_string('${b:02x}')
				} else {
					sb.write_u8(b)
				}
			}
		}
	}
	sb.write_u8(`"`)
	return sb.str()
}

// nrtc_literal_primitive ports literalToPrimitiveTypeFlags (0 for other flags).
fn nrtc_literal_primitive(flags u32) u32 {
	return match flags {
		type_flag_bigint_literal { nrtc_flag_bigint }
		type_flag_boolean_literal { nrtc_flag_boolean }
		type_flag_number_literal { type_flag_number }
		type_flag_string_literal, nrtc_flag_template_literal { nrtc_flag_string }
		else { u32(0) }
	}
}

// nrtc_primitive_name ports primitiveTypeFlagNames.
fn nrtc_primitive_name(flag u32) string {
	return match flag {
		nrtc_flag_bigint { 'bigint' }
		nrtc_flag_boolean { 'boolean' }
		type_flag_number { 'number' }
		else { 'string' }
	}
}

// nrtc_check_union ports the `TSUnionType:exit` handler.
fn (mut c Checker) nrtc_check_union(node C.TSNode, mut cache map[u64][]NrtcPart, mut findings []Finding) ! {
	mut seen_literals := map[u32][]NrtcLiteral{}
	mut seen_primitives := map[u32]bool{}
	in_return_type := nrtc_is_inside_return_type(node)
	for member in type_members(node) {
		for part in c.nrtc_parts(member, mut cache)! {
			// checkUnionBottomAndTopTypes.
			if part.flags == type_flag_any || part.flags == type_flag_unknown {
				findings << Finding{
					stmt:       position_of(member)
					message_id: if part.flags == type_flag_any && part.name != 'any' {
						'errorTypeOverrides'
					} else {
						'overrides'
					}
					data:       {
						'container': 'union'
						'typeName':  part.name
					}
				}
				continue
			}
			if part.flags == type_flag_never && !in_return_type {
				findings << Finding{
					stmt:       position_of(member)
					message_id: 'overridden'
					data:       {
						'container': 'union'
						'typeName':  'never'
					}
				}
				continue
			}
			for flag in nrtc_literal_flags {
				if part.flags == flag {
					seen_literals[nrtc_literal_primitive(flag)] << NrtcLiteral{
						value: part.name
						node:  member
					}
					break
				}
			}
			for flag in nrtc_primitive_flags {
				if part.flags & flag != 0 {
					seen_primitives[flag] = true
				}
			}
		}
	}
	// overriddenTypeNodes, in insertion order.
	mut order := []u64{}
	mut nodes := map[u64]C.TSNode{}
	mut overridden := map[u64][]NrtcOverride{}
	for primitive, literals in seen_literals {
		if primitive !in seen_primitives {
			continue
		}
		for literal in literals {
			key := node_key(literal.node)
			if key !in nodes {
				order << key
				nodes[key] = literal.node
			}
			overridden[key] << NrtcOverride{
				value:     literal.value
				primitive: primitive
			}
		}
	}
	for key in order {
		mut groups := map[u32][]string{}
		for o in overridden[key] {
			groups[o.primitive] << o.value
		}
		for primitive, values in groups {
			findings << Finding{
				stmt:       position_of(nodes[key])
				message_id: 'literalOverridden'
				data:       {
					'literal':   values.join(' | ')
					'primitive': nrtc_primitive_name(primitive)
				}
			}
		}
	}
}

// nrtc_check_intersection ports the `TSIntersectionType:exit` handler.
fn (mut c Checker) nrtc_check_intersection(node C.TSNode, mut cache map[u64][]NrtcPart, mut findings []Finding) ! {
	mut seen_literals := map[u32][]string{}
	mut seen_primitives := map[u32][]C.TSNode{}
	mut seen_unions := []NrtcUnionMember{}
	for member in type_members(node) {
		parts := c.nrtc_parts(member, mut cache)!
		for part in parts {
			// checkIntersectionBottomAndTopTypes.
			if part.flags in [type_flag_any, type_flag_never, type_flag_unknown] {
				findings << Finding{
					stmt:       position_of(member)
					message_id: if part.flags == type_flag_any && part.name != 'any' {
						'errorTypeOverrides'
					} else if part.flags == type_flag_unknown {
						'overridden'
					} else {
						'overrides'
					}
					data:       {
						'container': 'intersection'
						'typeName':  part.name
					}
				}
				continue
			}
			for flag in nrtc_literal_flags {
				if part.flags == flag {
					seen_literals[nrtc_literal_primitive(flag)] << part.name
					break
				}
			}
			for flag in nrtc_primitive_flags {
				if part.flags == flag {
					seen_primitives[flag] << member
				}
			}
		}
		if parts.len >= 2 {
			seen_unions << NrtcUnionMember{
				node:  member
				parts: parts
			}
		}
	}
	if seen_unions.len > 0 {
		// checkIfUnionsAreAssignable.
		for seen in seen_unions {
			mut primitive := u32(0)
			for part in seen.parts {
				flag := nrtc_literal_primitive(part.flags)
				if flag != 0 && flag in seen_primitives {
					primitive = flag
				} else {
					primitive = 0
					break
				}
			}
			if primitive != 0 {
				findings << Finding{
					stmt:       position_of(seen.node)
					message_id: 'primitiveOverridden'
					data:       {
						'literal':   seen.parts.map(it.name).join(' | ')
						'primitive': nrtc_primitive_name(primitive)
					}
				}
			}
		}
		return
	}
	for primitive, members in seen_primitives {
		literals := seen_literals[primitive] or { continue }
		for member in members {
			findings << Finding{
				stmt:       position_of(member)
				message_id: 'primitiveOverridden'
				data:       {
					'literal':   literals.join(' | ')
					'primitive': nrtc_primitive_name(primitive)
				}
			}
		}
	}
}

// nrtc_is_inside_return_type ports isNodeInsideReturnType: the union is the return type of a
// function or function type (the TSTypeAnnotation of its returnType).
fn nrtc_is_inside_return_type(node C.TSNode) bool {
	parent := type_parent(node) or { return false }
	parent_kind := node_kind(parent)
	if parent_kind in ['function_type', 'constructor_type'] {
		// tree-sitter puts the return type of a function type without a type_annotation.
		return_type := node_field(parent, 'return_type') or { return false }
		return node_key(unwrap_type_parens(return_type)) == node_key(node)
	}
	if parent_kind != 'type_annotation' {
		return false
	}
	function := node_parent(parent) or { return false }
	if node_kind(function) !in ['function_declaration', 'function_expression', 'arrow_function',
		'generator_function_declaration', 'generator_function', 'method_definition', 'method_signature',
		'abstract_method_signature', 'function_signature', 'call_signature', 'construct_signature'] {
		return false
	}
	// The grammar names the return type of a construct signature (`new (): T`) `type`.
	field := if node_kind(function) == 'construct_signature' { 'type' } else { 'return_type' }
	return_type := node_field(function, field) or { return false }
	return node_key(return_type) == node_key(parent)
}
