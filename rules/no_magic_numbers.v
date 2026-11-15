module rules

import estree
import json2
import math
import time

// Port of the `@typescript-eslint/no-magic-numbers` rule of typescript-eslint 8.72.2, which extends
// the `no-magic-numbers` rule of ESLint 10.15.0 (ported here as nmag_core_literal, the base rule's
// Literal listener) with its options `ignoreEnums`, `ignoreNumericLiteralTypes`,
// `ignoreReadonlyClassProperties` and `ignoreTypeIndexes`.

const nmag_messages = {
	'useConst': "Number constants declarations must use 'const'."
	'noMagic':  'No magic number: {{raw}}.'
}

// NmagNumber is a number or a BigInt of JavaScript (`big` its decimal digits, with `-` when
// negative and never `-0`).
struct NmagNumber {
	is_bigint bool
	num       f64
	big       string
}

// nmag_same_value_zero is SameValueZero, what Set#has compares with.
fn nmag_same_value_zero(a NmagNumber, b NmagNumber) bool {
	if a.is_bigint != b.is_bigint {
		return false
	}
	if a.is_bigint {
		return a.big == b.big
	}
	if a.num != a.num {
		return b.num != b.num
	}
	return a.num == b.num
}

// nmag_bigint normalizes decimal digits with an optional sign.
fn nmag_bigint(text string) NmagNumber {
	mut digits := text
	mut negative := false
	if digits.starts_with('-') || digits.starts_with('+') {
		negative = digits[0] == `-`
		digits = digits[1..]
	}
	digits = digits.trim_left('0')
	if digits == '' {
		digits = '0'
	}
	return NmagNumber{
		is_bigint: true
		big:       if negative && digits != '0' { '-' + digits } else { digits }
	}
}

// nmag_negate is `-value`.
fn nmag_negate(v NmagNumber) NmagNumber {
	if v.is_bigint {
		return nmag_bigint(if v.big.starts_with('-') { v.big[1..] } else { '-' + v.big })
	}
	return NmagNumber{
		num: -v.num
	}
}

struct NmagOptions {
	detect_objects                    bool
	enforce_const                     bool
	ignore                            []NmagNumber
	ignore_array_indexes              bool
	ignore_default_values             bool
	ignore_class_field_initial_values bool
	ignore_enums                      bool
	ignore_numeric_literal_types      bool
	ignore_readonly_class_properties  bool
	ignore_type_indexes               bool
}

fn nmag_options(options []json2.Any) !NmagOptions {
	o := option_object(no_magic_numbers, options, ['detectObjects', 'enforceConst', 'ignore',
		'ignoreArrayIndexes', 'ignoreDefaultValues', 'ignoreClassFieldInitialValues', 'ignoreEnums',
		'ignoreNumericLiteralTypes', 'ignoreReadonlyClassProperties', 'ignoreTypeIndexes'])!
	mut ignore := []NmagNumber{}
	if raw := o.values['ignore'] {
		if raw !is []json2.Any {
			return error('option `ignore` of `${no_magic_numbers}` must be a list')
		}
		for item in raw.as_array() {
			match item {
				string {
					// pattern ^[+-]?(?:0|[1-9][0-9]*)n$
					body := item.trim_right('n')
					if !item.ends_with('n') || body.trim_left('+-').len == 0
						|| !body.trim_left('+-').bytes().all(it.is_digit()) {
						return error('option `ignore` of `${no_magic_numbers}`: `${item}` is not a BigInt')
					}
					ignore << nmag_bigint(item[..item.len - 1])
				}
				f64, f32, i64, int, i32, i16, i8, u64, u32, u16, u8 {
					ignore << NmagNumber{
						num: item.f64()
					}
				}
				else {
					return error('option `ignore` of `${no_magic_numbers}` must list numbers and BigInts')
				}
			}
		}
	}
	return NmagOptions{
		detect_objects:                    o.bool_value('detectObjects')!
		enforce_const:                     o.bool_value('enforceConst')!
		ignore:                            ignore
		ignore_array_indexes:              o.bool_value('ignoreArrayIndexes')!
		ignore_default_values:             o.bool_value('ignoreDefaultValues')!
		ignore_class_field_initial_values: o.bool_value('ignoreClassFieldInitialValues')!
		ignore_enums:                      o.bool_value('ignoreEnums')!
		ignore_numeric_literal_types:      o.bool_value('ignoreNumericLiteralTypes')!
		ignore_readonly_class_properties:  o.bool_value('ignoreReadonlyClassProperties')!
		ignore_type_indexes:               o.bool_value('ignoreTypeIndexes')!
	}
}

fn (o NmagOptions) is_ignored(v NmagNumber) bool {
	return o.ignore.any(nmag_same_value_zero(it, v))
}

// nmag_literal_value is the value of a numeric literal (a number or a BigInt), or none.
fn nmag_literal_value(t &estree.EsTree, node int) ?NmagNumber {
	if t.typ(node) != .literal {
		return none
	}
	value := t.get(node, .value)
	if value is f64 {
		return NmagNumber{
			num: value
		}
	}
	if value is estree.BigIntValue {
		return nmag_bigint(value.digits)
	}
	return none
}

fn (mut c Checker) lint_no_magic_numbers(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nmag_options(c.rule_options(no_magic_numbers))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		value := nmag_literal_value(t, node) or { continue }
		stats.checked++
		parent := t.nodes[node].parent
		parent_operator := if t.typ(parent) == .unary_expression {
			t.string_of(parent, .operator) or { '' }
		} else {
			''
		}
		// normalizeLiteralValue
		normalized := if parent_operator == '-' { nmag_negate(value) } else { value }
		mut is_allowed := 0 // 0 undefined, 1 true, 2 false
		if o.is_ignored(normalized) {
			is_allowed = 1
		} else if nmag_is_parent_ts_enum_declaration(t, node) {
			is_allowed = if o.ignore_enums { 1 } else { 2 }
		} else if nmag_is_ts_numeric_literal_type(t, node) {
			is_allowed = if o.ignore_numeric_literal_types { 1 } else { 2 }
		} else if nmag_is_ancestor_ts_indexed_access_type(t, node) {
			is_allowed = if o.ignore_type_indexes { 1 } else { 2 }
		} else if nmag_is_parent_ts_readonly_property_definition(t, node) {
			is_allowed = if o.ignore_readonly_class_properties { 1 } else { 2 }
		}
		if is_allowed == 1 {
			continue
		}
		raw := t.string_of(node, .raw) or { '' }
		if is_allowed == 2 {
			full := if parent_operator == '-' { parent } else { node }
			findings << Finding{
				stmt:       c.es_tree_position(t, full)
				message_id: 'noMagic'
				data:       {
					'raw': if parent_operator == '-' { '-' + raw } else { raw }
				}
			}
			continue
		}
		if finding := c.nmag_core_literal(t, node, value, raw, o) {
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nmag_core_literal is the Literal listener of ESLint's no-magic-numbers for a numeric literal.
fn (mut c Checker) nmag_core_literal(t &estree.EsTree, node int, node_value NmagNumber, node_raw string, o NmagOptions) ?Finding {
	mut full := node
	mut value := node_value
	mut raw := node_raw
	parent0 := t.nodes[node].parent
	if t.typ(parent0) == .unary_expression {
		operator := t.string_of(parent0, .operator) or { '' }
		if operator in ['-', '+'] {
			full = parent0
			value = if operator == '-' { nmag_negate(node_value) } else { node_value }
			raw = operator + node_raw
		}
	}
	parent := t.nodes[full].parent
	ptyp := t.typ(parent)
	if o.is_ignored(value)
		|| (o.ignore_default_values && ptyp == .assignment_pattern
		&& (t.node(parent, .right) or { -1 }) == full)
		|| (o.ignore_class_field_initial_values && ptyp == .property_definition
		&& (t.node(parent, .value) or { -1 }) == full)
		|| (o.ignore_enums && ptyp == .ts_enum_member)
		|| (o.ignore_numeric_literal_types && nmag_core_is_ts_numeric_literal_type(t, full))
		|| (o.ignore_type_indexes && nmag_core_is_ancestor_ts_indexed_access_type(t, full))
		|| (o.ignore_readonly_class_properties && ptyp == .property_definition
		&& (t.flag(parent, .readonly) or { false })) || nmag_is_parse_int_radix(t, full)
		|| ptyp.type_name().starts_with('JSX')
		|| (o.ignore_array_indexes && nmag_is_array_index(t, full, value)) {
		return none
	}
	if ptyp == .variable_declarator {
		declaration := t.nodes[parent].parent
		if o.enforce_const && (t.string_of(declaration, .kind) or { '' }) != 'const' {
			return Finding{
				stmt:       c.es_tree_position(t, full)
				message_id: 'useConst'
			}
		}
		return none
	}
	ok_type := !o.detect_objects && ptyp in [.object_expression, .property, .assignment_expression]
	assigns_identifier := ptyp == .assignment_expression
		&& t.typ(t.node(parent, .left) or { return none }) == .identifier
	if !ok_type || assigns_identifier {
		return Finding{
			stmt:       c.es_tree_position(t, full)
			message_id: 'noMagic'
			data:       {
				'raw': raw
			}
		}
	}
	return none
}

// nmag_is_parse_int_radix ports isParseIntRadix.
fn nmag_is_parse_int_radix(t &estree.EsTree, full int) bool {
	parent := t.nodes[full].parent
	if t.typ(parent) != .call_expression {
		return false
	}
	arguments := t.list(parent, .arguments) or { return false }
	if arguments.len < 2 || arguments[1] != full {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	return es_tree_is_specific_id(t, callee, 'parseInt')
		|| es_tree_is_specific_member_access(t, callee, 'Number', 'parseInt')
}

// nmag_is_array_index ports isArrayIndex.
fn nmag_is_array_index(t &estree.EsTree, full int, value NmagNumber) bool {
	parent := t.nodes[full].parent
	if t.typ(parent) != .member_expression || (t.node(parent, .property) or { -1 }) != full {
		return false
	}
	if value.is_bigint {
		if value.big.starts_with('-') {
			return false
		}
		// value < 2 ** 32 - 1
		return value.big.len < 10 || (value.big.len == 10 && value.big < '4294967295')
	}
	// Number.isInteger(value) && value >= 0 && value < MAX_ARRAY_LENGTH
	return value.num >= 0 && value.num < 4294967295.0 && value.num == math.floor(value.num)
}

// nmag_core_is_ts_numeric_literal_type ports the base rule's isTSNumericLiteralType.
fn nmag_core_is_ts_numeric_literal_type(t &estree.EsTree, node int) bool {
	mut ancestor := t.nodes[node].parent
	for t.nodes[ancestor].parent >= 0 && t.typ(t.nodes[ancestor].parent) == .ts_union_type {
		ancestor = t.nodes[ancestor].parent
	}
	return t.nodes[ancestor].parent >= 0
		&& t.typ(t.nodes[ancestor].parent) == .ts_type_alias_declaration
}

// nmag_core_is_ancestor_ts_indexed_access_type ports the base rule's
// isAncestorTSIndexedAccessType.
fn nmag_core_is_ancestor_ts_indexed_access_type(t &estree.EsTree, node int) bool {
	return nmag_indexed_access_from(t, t.nodes[node].parent)
}

// nmag_indexed_access_from climbs from `ancestor` through unions and intersections and tells
// whether an indexed access type is above.
fn nmag_indexed_access_from(t &estree.EsTree, start int) bool {
	mut ancestor := start
	for ancestor >= 0 && t.nodes[ancestor].parent >= 0
		&& t.typ(t.nodes[ancestor].parent) in [.ts_union_type, .ts_intersection_type] {
		ancestor = t.nodes[ancestor].parent
	}
	return ancestor >= 0 && t.nodes[ancestor].parent >= 0
		&& t.typ(t.nodes[ancestor].parent) == .ts_indexed_access_type
}

// nmag_literal_parent ports getLiteralParent: the parent, or the parent of the unary `-`/`+`.
fn nmag_literal_parent(t &estree.EsTree, node int) int {
	parent := t.nodes[node].parent
	if t.typ(parent) == .unary_expression
		&& (t.string_of(parent, .operator) or { '' }) in ['-', '+'] {
		return t.nodes[parent].parent
	}
	return parent
}

// nmag_is_parent_ts_enum_declaration ports isParentTSEnumDeclaration.
fn nmag_is_parent_ts_enum_declaration(t &estree.EsTree, node int) bool {
	parent := nmag_literal_parent(t, node)
	return parent >= 0 && t.typ(parent) == .ts_enum_member
}

// nmag_grand_parent_type is node.parent?.parent?.type, or none.
fn nmag_grand_parent_type(t &estree.EsTree, node int) ?estree.NodeType {
	parent := t.nodes[node].parent
	if parent < 0 || t.nodes[parent].parent < 0 {
		return none
	}
	return t.typ(t.nodes[parent].parent)
}

// nmag_is_ts_numeric_literal_type ports typescript-eslint's isTSNumericLiteralType.
fn nmag_is_ts_numeric_literal_type(t &estree.EsTree, from int) bool {
	mut node := from
	parent := t.nodes[node].parent
	if t.typ(parent) == .unary_expression && (t.string_of(parent, .operator) or { '' }) == '-' {
		node = parent
	}
	if t.nodes[node].parent < 0 || t.typ(t.nodes[node].parent) != .ts_literal_type {
		return false
	}
	grand := nmag_grand_parent_type(t, node) or { return false }
	if grand == .ts_type_alias_declaration {
		return true
	}
	if grand == .ts_union_type {
		return (nmag_grand_parent_type(t, t.nodes[node].parent) or { return false }) == .ts_type_alias_declaration
	}
	return false
}

// nmag_is_parent_ts_readonly_property_definition ports isParentTSReadonlyPropertyDefinition.
fn nmag_is_parent_ts_readonly_property_definition(t &estree.EsTree, node int) bool {
	parent := nmag_literal_parent(t, node)
	return parent >= 0 && t.typ(parent) == .property_definition
		&& (t.flag(parent, .readonly) or { false })
}

// nmag_is_ancestor_ts_indexed_access_type ports typescript-eslint's isAncestorTSIndexedAccessType.
fn nmag_is_ancestor_ts_indexed_access_type(t &estree.EsTree, node int) bool {
	return nmag_indexed_access_from(t, nmag_literal_parent(t, node))
}
