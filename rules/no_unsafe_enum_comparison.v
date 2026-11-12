module rules

import time
import tsgo { TypeResponse, handle_index, handle_path }
import treesitter { named_children, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `no-unsafe-enum-comparison` rule of typescript-eslint 8.62.0 (it has no options), with
// its `replaceValueWithEnum` suggestion.

const nuec_messages = {
	'mismatchedCase':       'The case statement does not have a shared enum type with the switch predicate.'
	'mismatchedCondition':  'The two values in this comparison do not have a shared enum type.'
	'replaceValueWithEnum': 'Replace with an enum value comparison.'
}

// The operators of `BinaryExpression[operator=/^[<>!=]?={0,2}$/]`.
const nuec_operators = ['<', '>', '<=', '>=', '==', '!=', '===', '!==']

// TypeFlags.EnumLike and TypeFlags.EnumLiteral of TypeScript 7.1.0-beta.
const nuec_enum_like = u32(98304)
const nuec_enum_literal = u32(32768)

// SymbolFlags.EnumMember of TypeScript 7.1.0-beta.
const nuec_symbol_enum_member = u32(8)

// SyntaxKind.StringLiteral of TypeScript 7.1.0-beta.
const nuec_kind_string_literal = u32(10)

// NuecComparison is a comparison or a `case`, with the ESTree nodes of both sides.
struct NuecComparison {
	node       C.TSNode
	left       C.TSNode
	right      C.TSNode
	message_id string
}

fn (mut c Checker) lint_no_unsafe_enum_comparison(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut comparisons := []NuecComparison{}
	for node in c.nodes_of_kinds(root, ['binary_expression', 'switch_statement'], []string{}) {
		if node_kind(node) == 'binary_expression' {
			if operator_of(node) !in nuec_operators {
				continue
			}
			left := node_field(node, 'left') or { continue }
			right := node_field(node, 'right') or { continue }
			comparisons << NuecComparison{
				node:       node
				left:       unwrap_parens(left)
				right:      unwrap_parens(right)
				message_id: 'mismatchedCondition'
			}
			continue
		}
		discriminant := unwrap_parens(node_field(node, 'value') or { continue })
		body := node_field(node, 'body') or { continue }
		for case in named_children(body) {
			if node_kind(case) != 'switch_case' {
				continue
			}
			test := node_field(case, 'value') or { continue }
			comparisons << NuecComparison{
				node:       case
				left:       discriminant
				right:      unwrap_parens(test)
				message_id: 'mismatchedCase'
			}
		}
	}
	mut spans := []Span{}
	for comparison in comparisons {
		spans << node_span(comparison.left)
		spans << node_span(comparison.right)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut base_types := map[int]TypeResponse{}
	mut findings := []Finding{}
	for comparison in comparisons {
		left := c.node_type(comparison.left) or { continue }
		right := c.node_type(comparison.right) or { continue }
		if !c.nuec_is_mismatched(left, right, mut base_types)! {
			continue
		}
		mut suggestions := []Suggestion{}
		if comparison.message_id == 'mismatchedCondition' {
			// Without an enum key for either side the fixer returns null: no suggestion.
			ok, suggestion := c.suggestion('replaceValueWithEnum', map[string]string{},
				c.nuec_replace_value_with_enum(comparison, left, right)!)!
			if ok {
				suggestions << suggestion
			}
		}
		findings << Finding{
			stmt:        position_of(comparison.node)
			message_id:  comparison.message_id
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += comparisons.len
	return findings
}

// nuec_is_mismatched ports isMismatchedComparison.
fn (mut c Checker) nuec_is_mismatched(left TypeResponse, right TypeResponse, mut base_types map[int]TypeResponse) !bool {
	left_enum_types := c.nuec_enum_types(left, mut base_types)!
	right_enum_types := c.nuec_enum_types(right, mut base_types)!
	if left_enum_types.len == 0 && right_enum_types.len == 0 {
		return false
	}
	// Comparisons that share an enum type are allowed.
	for t in left_enum_types {
		if right_enum_types.any(it.id == t.id) {
			return false
		}
	}
	left_parts := c.constituents(left)!
	right_parts := c.constituents(right)!
	// A type in both sides makes the comparison safe.
	for part in left_parts {
		if right_parts.any(it.id == part.id) {
			return false
		}
	}
	return c.nuec_type_violates(left_parts, right)! || c.nuec_type_violates(right_parts, left)!
}

// nuec_enum_types ports getEnumTypes: the enum of each enum literal of the union (getBaseEnumType).
fn (mut c Checker) nuec_enum_types(t TypeResponse, mut base_types map[int]TypeResponse) ![]TypeResponse {
	mut out := []TypeResponse{}
	for part in c.constituents(t)! {
		if part.flags & nuec_enum_literal != 0 {
			out << c.nuec_base_enum_type(part, mut base_types)!
		}
	}
	return out
}

// nuec_base_enum_type ports getBaseEnumType: the type of the enum declaration of a member (the
// parent of the member's declaration, which may be in any file), or the type itself.
fn (mut c Checker) nuec_base_enum_type(t TypeResponse, mut base_types map[int]TypeResponse) !TypeResponse {
	if t.id in base_types {
		return base_types[t.id]
	}
	mut result := t
	symbol := c.symbol_of(t)!
	if !symbol.is_null() && symbol.flags & nuec_symbol_enum_member != 0
		&& symbol.value_declaration != '' {
		tree := c.declaration_ast(handle_path(symbol.value_declaration))!
		parent := tree.node_parent(handle_index(symbol.value_declaration))
		if parent != 0 {
			types := c.client.types_at_locations(c.snapshot, c.project, [
				tree.node_handle(parent),
			])!
			if types.len == 1 && !types[0].is_null() {
				result = types[0]
			}
		}
	}
	base_types[t.id] = result
	return result
}

// nuec_type_violates ports typeViolates: the enums of one side have number (or string) values and
// the other side is number-like (or string-like).
fn (mut c Checker) nuec_type_violates(parts []TypeResponse, other TypeResponse) !bool {
	mut has_number := false
	mut has_string := false
	for part in parts {
		// getEnumValueType, with the own flags (tsutils.isTypeFlagSet).
		if part.flags & nuec_enum_like != 0 {
			if part.flags & type_flag_number_literal != 0 {
				has_number = true
			} else {
				has_string = true
			}
		}
	}
	return (has_number && c.nuec_every_part_like(other, type_flag_number | type_flag_number_like)!)
		|| (has_string && c.nuec_every_part_like(other, u32(32) | type_flag_string_like)!)
}

// nuec_every_part_like ports isNumberLike and isStringLike: every union part has an intersection
// part with those flags (own flags).
fn (mut c Checker) nuec_every_part_like(t TypeResponse, flags u32) !bool {
	for part in c.constituents(t)! {
		pieces := if part.flags & type_flag_intersection != 0 {
			c.members_of(part)!
		} else {
			[part]
		}
		if !pieces.any(it.flags & flags != 0) {
			return false
		}
	}
	return true
}

// nuec_replace_value_with_enum ports the fixer of the `replaceValueWithEnum` suggestion: the right
// side becomes the key of the left side's enum with its static value or, failing that, the left
// side the key of the right side's enum.
fn (mut c Checker) nuec_replace_value_with_enum(comparison NuecComparison, left TypeResponse, right TypeResponse) ![]Fix {
	left_key := c.nuec_enum_key_for_literal(left, comparison.right)!
	if left_key != '' {
		return [fix_replace(comparison.right, left_key)]
	}
	right_key := c.nuec_enum_key_for_literal(right, comparison.left)!
	if right_key != '' {
		return [fix_replace(comparison.left, right_key)]
	}
	return []Fix{}
}

// nuec_enum_key_for_literal ports getEnumKeyForLiteral(getEnumLiterals(type), getStaticValue(node)?.value):
// the access to the first enum member of the type whose value is the static value of the node
// (evaluated without scope: no identifier is static), as `Enum.Member`, `Enum['member name']` or
// `Enum[computed]`; '' if none.
fn (mut c Checker) nuec_enum_key_for_literal(t TypeResponse, value_node C.TSNode) !string {
	static_value := c.get_static_value_unscoped(value_node)
	if !static_value.found {
		return ''
	}
	for part in c.constituents(t)! {
		if part.flags & nuec_enum_literal == 0 || !nuec_same_value(part, static_value.value) {
			continue
		}
		symbol := c.symbol_of(part)!
		if symbol.is_null() || symbol.value_declaration == '' {
			continue
		}
		tree := c.declaration_ast(handle_path(symbol.value_declaration))!
		member := handle_index(symbol.value_declaration)
		enum_name := tree.node_text(tree.node_child(tree.node_parent(member), 'name'))
		name := tree.node_child(member, 'name')
		match tree.node_kind(name) {
			syntax_kind_identifier {
				return '${enum_name}.${tree.node_text(name)}'
			}
			nuec_kind_string_literal {
				// The text of the literal, with its quotes escaped.
				raw := tree.node_source_text(name)
				content := if raw.len >= 2 { raw[1..raw.len - 1] } else { raw }
				text := cooked_string(content, false) or { content }
				escaped := text.replace("'", "\\'")
				return enum_name + "['" + escaped + "']"
			}
			syntax_kind_computed_property_name {
				return '${enum_name}[${tree.node_source_text(tree.node_child(name, 'expression'))}]'
			}
			else {}
		}
	}
	return ''
}

// nuec_same_value: `enumLiteral.value === literal`, the value of an enum literal type (a string or
// a number) and a static value.
fn nuec_same_value(t TypeResponse, value JsAny) bool {
	type_value := t.value
	if type_value is string {
		return value.kind == .string_ && stv_units_string(value.units) == type_value
	}
	if type_value is f64 {
		return value.kind == .number_ && value.number == type_value
	}
	return false
}
