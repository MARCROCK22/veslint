module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `restrict-plus-operands` rule of typescript-eslint 8.62.0, with all its options.

const rpo_messages = {
	'bigintAndNumber': "Numeric '+' operations must either be both bigints or both numbers. Got `{{left}}` + `{{right}}`."
	'invalid':         "Invalid operand for a '+' operation. Operands must each be a number or {{stringLike}}. Got `{{type}}`."
	'mismatched':      "Operands of '+' operations must be a number or {{stringLike}}. Got `{{left}}` + `{{right}}`."
}

struct RpoOptions {
	allow_any                 bool
	allow_boolean             bool
	allow_nullish             bool
	allow_number_and_string   bool
	allow_regexp              bool
	skip_compound_assignments bool
}

fn rpo_options(options []json2.Any) !RpoOptions {
	o := option_object(restrict_plus_operands, options, ['allowAny', 'allowBoolean', 'allowNullish',
		'allowNumberAndString', 'allowRegExp', 'skipCompoundAssignments'])!
	return RpoOptions{
		allow_any:                 o.bool_value('allowAny')!
		allow_boolean:             o.bool_value('allowBoolean')!
		allow_nullish:             o.bool_value('allowNullish')!
		allow_number_and_string:   o.bool_value('allowNumberAndString')!
		allow_regexp:              o.bool_value('allowRegExp')!
		skip_compound_assignments: o.bool_value('skipCompoundAssignments')!
	}
}

// rpo_string_like is the `stringLike` text of the messages for the options.
fn rpo_string_like(o RpoOptions) string {
	mut likes := []string{}
	if o.allow_any {
		likes << '`any`'
	}
	if o.allow_boolean {
		likes << '`boolean`'
	}
	if o.allow_nullish {
		likes << '`null`'
	}
	if o.allow_regexp {
		likes << '`RegExp`'
	}
	if o.allow_nullish {
		likes << '`undefined`'
	}
	return match likes.len {
		0 { 'string' }
		1 { 'string, allowing a string + ${likes[0]}' }
		else { 'string, allowing a string + any of: ${likes.join(', ')}' }
	}
}

// RpoAddition is a `+` (BinaryExpression) or a `+=` (AssignmentExpression) with its ESTree operands.
struct RpoAddition {
	node  C.TSNode
	left  C.TSNode
	right C.TSNode
}

fn (mut c Checker) lint_restrict_plus_operands(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := rpo_options(c.rule_options(restrict_plus_operands))!
	mut additions := []RpoAddition{}
	for node in c.nodes_of_kinds(root, ['binary_expression', 'augmented_assignment_expression'],
		[]string{}) {
		wanted := if node_kind(node) == 'binary_expression' { '+' } else { '+=' }
		if operator_of(node) != wanted || (wanted == '+=' && o.skip_compound_assignments) {
			continue
		}
		left := node_field(node, 'left') or { continue }
		right := node_field(node, 'right') or { continue }
		additions << RpoAddition{
			node:  node
			left:  unwrap_parens(left)
			right: unwrap_parens(right)
		}
	}
	mut spans := []Span{}
	for a in additions {
		spans << node_span(a.left)
		spans << node_span(a.right)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	string_like := rpo_string_like(o)
	mut base_types := map[int]TypeResponse{}
	mut findings := []Finding{}
	for a in additions {
		left_type := c.node_type(a.left) or { continue }
		right_type := c.node_type(a.right) or { continue }
		left := c.rpo_base_type(left_type, mut base_types)!
		right := c.rpo_base_type(right_type, mut base_types)!
		c.rpo_check(a, left, right, o, string_like, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += additions.len
	return findings
}

// rpo_base_type ports getTypeConstrained: getBaseTypeOfLiteralType of the constrained type.
fn (mut c Checker) rpo_base_type(t TypeResponse, mut cache map[int]TypeResponse) !TypeResponse {
	constrained := c.constrained(t)!
	if constrained.id !in cache {
		mut base := c.client.base_type_of_literal(c.snapshot, c.project, constrained.id)!
		if base.is_null() {
			base = constrained
		}
		cache[constrained.id] = base
	}
	return cache[constrained.id]
}

// rpo_in_union ports isTypeFlagSetInUnion: some union part has the flag (its own flags).
fn (mut c Checker) rpo_in_union(t TypeResponse, flags u32) !bool {
	for part in c.constituents(t)! {
		if part.flags & flags != 0 {
			return true
		}
	}
	return false
}

// rpo_deeply_object ports isDeeplyObjectType: every part of the intersection (or of the union) is an
// object.
fn (mut c Checker) rpo_deeply_object(t TypeResponse) !bool {
	parts := if t.flags & type_flag_intersection != 0 {
		c.members_of(t)!
	} else {
		c.constituents(t)!
	}
	return parts.all(it.flags & type_flag_object != 0)
}

// rpo_check ports checkPlusOperands.
fn (mut c Checker) rpo_check(a RpoAddition, left TypeResponse, right TypeResponse, o RpoOptions, string_like string, mut findings []Finding) ! {
	if left.id == right.id
		&& left.flags & (type_flag_bigint_like | type_flag_number_like | type_flag_string_like) != 0 {
		return
	}
	mut complained := false
	for side in [0, 1] {
		base_node := if side == 0 { a.left } else { a.right }
		base_type := if side == 0 { left } else { right }
		other_type := if side == 0 { right } else { left }
		if c.rpo_in_union(base_type, type_flag_es_symbol_like | type_flag_never | type_flag_unknown)!
			|| (!o.allow_any && c.rpo_in_union(base_type, type_flag_any)!)
			|| (!o.allow_boolean && c.rpo_in_union(base_type, type_flag_boolean_like)!)
			|| (!o.allow_nullish
				&& c.type_flags(base_type)! & (type_flag_null | type_flag_undefined) != 0) {
			findings << Finding{
				stmt:       position_of(base_node)
				message_id: 'invalid'
				data:       {
					'type':       c.type_string(base_type)!
					'stringLike': string_like
				}
			}
			complained = true
			continue
		}
		// RegExps also contain ts.TypeFlags.Any & ts.TypeFlags.Object.
		for part in c.constituents(base_type)! {
			invalid := if c.type_name(part, 0)! == 'RegExp' {
				!o.allow_regexp || other_type.flags & type_flag_number_like != 0
			} else {
				(!o.allow_any && part.flags & type_flag_any != 0) || c.rpo_deeply_object(part)!
			}
			if invalid {
				findings << Finding{
					stmt:       position_of(base_node)
					message_id: 'invalid'
					data:       {
						'type':       c.type_string(part)!
						'stringLike': string_like
					}
				}
				complained = true
			}
		}
	}
	if complained {
		return
	}
	for side in [0, 1] {
		base_type := if side == 0 { left } else { right }
		other_type := if side == 0 { right } else { left }
		if !o.allow_number_and_string && c.rpo_in_union(base_type, type_flag_string_like)!
			&& c.rpo_in_union(other_type, type_flag_number_like | type_flag_bigint_like)! {
			findings << Finding{
				stmt:       position_of(a.node)
				message_id: 'mismatched'
				data:       {
					'left':       c.type_string(left)!
					'right':      c.type_string(right)!
					'stringLike': string_like
				}
			}
			return
		}
		if c.rpo_in_union(base_type, type_flag_number_like)!
			&& c.rpo_in_union(other_type, type_flag_bigint_like)! {
			findings << Finding{
				stmt:       position_of(a.node)
				message_id: 'bigintAndNumber'
				data:       {
					'left':  c.type_string(left)!
					'right': c.type_string(right)!
				}
			}
			return
		}
	}
}
