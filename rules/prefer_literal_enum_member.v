module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/prefer-literal-enum-member` rule of typescript-eslint 8.72.2,
// with its option `allowBitwiseExpressions`.

const plem_messages = {
	'notLiteral':                    'Explicit enum value must only be a literal value (string or number).'
	'notLiteralOrBitwiseExpression': 'Explicit enum value must only be a literal value (string or number) or a bitwise expression.'
}

fn plem_options(options []json2.Any) !bool {
	o := option_object(prefer_literal_enum_member, options, ['allowBitwiseExpressions'])!
	return o.bool_value('allowBitwiseExpressions')!
}

fn (mut c Checker) lint_prefer_literal_enum_member(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_bitwise := plem_options(c.rule_options(prefer_literal_enum_member))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .ts_enum_member {
			continue
		}
		stats.checked++
		initializer := t.node(node, .initializer) or { continue }
		body := t.nodes[node].parent
		declaration := if body >= 0 { t.nodes[body].parent } else { -1 }
		if declaration < 0
			|| plem_is_allowed_initializer(t, declaration, initializer, false, allow_bitwise) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, t.node(node, .id) or { node })
			message_id: if allow_bitwise { 'notLiteralOrBitwiseExpression' } else { 'notLiteral' }
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// plem_is_identifier_with_name ports isIdentifierWithName.
fn plem_is_identifier_with_name(t &estree.EsTree, node int, name string) bool {
	return node >= 0 && t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == name
}

// plem_has_enum_member ports hasEnumMember.
fn plem_has_enum_member(t &estree.EsTree, declaration int, name string) bool {
	body := t.node(declaration, .body) or { return false }
	for member in t.list(body, .members) or { []int{} } {
		id := t.node(member, .id) or { continue }
		if plem_is_identifier_with_name(t, id, name) {
			return true
		}
		if t.typ(id) == .literal {
			if value := es_tree_static_string_value(t, id) {
				if value == name {
					return true
				}
			}
		}
	}
	return false
}

// plem_is_self_enum_member ports isSelfEnumMember.
fn plem_is_self_enum_member(t &estree.EsTree, declaration int, node int) bool {
	if t.typ(node) == .identifier {
		return plem_has_enum_member(t, declaration, t.string_of(node, .name) or { '' })
	}
	if t.typ(node) == .member_expression {
		decl_id := t.node(declaration, .id) or { return false }
		if !plem_is_identifier_with_name(t, t.node(node, .object) or { -1 }, t.string_of(decl_id,
			.name) or { '' }) {
			return false
		}
		property := t.node(node, .property) or { return false }
		if t.typ(property) == .identifier {
			return plem_has_enum_member(t, declaration, t.string_of(property, .name) or { '' })
		}
		if t.flag(node, .computed) or { false } {
			property_name := es_tree_static_string_value(t, property) or { '' }
			if property_name != '' {
				return plem_has_enum_member(t, declaration, property_name)
			}
		}
	}
	return false
}

// plem_is_allowed_initializer ports isAllowedInitializerExpressionRecursive.
fn plem_is_allowed_initializer(t &estree.EsTree, declaration int, node int, part_of_bitwise bool, allow_bitwise bool) bool {
	if part_of_bitwise && plem_is_self_enum_member(t, declaration, node) {
		return true
	}
	match t.typ(node) {
		.literal {
			return true
		}
		.template_literal {
			return (t.list(node, .expressions) or { []int{} }).len == 0
		}
		.unary_expression {
			operator := t.string_of(node, .operator) or { '' }
			argument := t.node(node, .argument) or { return false }
			if operator in ['-', '+'] {
				return plem_is_allowed_initializer(t, declaration, argument, part_of_bitwise,
					allow_bitwise)
			}
			if allow_bitwise {
				return operator == '~'
					&& plem_is_allowed_initializer(t, declaration, argument, true, allow_bitwise)
			}
			return false
		}
		.binary_expression {
			if allow_bitwise {
				operator := t.string_of(node, .operator) or { '' }
				left := t.node(node, .left) or { return false }
				right := t.node(node, .right) or { return false }
				return operator in ['&', '^', '<<', '>>', '>>>', '|']
					&& plem_is_allowed_initializer(t, declaration, left, true, allow_bitwise)
					&& plem_is_allowed_initializer(t, declaration, right, true, allow_bitwise)
			}
			return false
		}
		else {
			return false
		}
	}
}
