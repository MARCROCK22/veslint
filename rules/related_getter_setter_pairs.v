module rules

import time
import treesitter { has_child_kind, named_children, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `related-getter-setter-pairs` rule of typescript-eslint 8.62.0 (it has no options).

const rgsp_messages = {
	'mismatch': '`get()` type should be assignable to its equivalent `set()` type.'
}

// RgspPair is a getter (with a return type) and a setter (with a single parameter) with the same
// name in a class body, an interface or a type literal.
struct RgspPair {
	getter    C.TSNode // the member, whose type is the getter's
	parameter C.TSNode // the ESTree node of the setter parameter
	report    C.TSNode // the return type of the getter
}

fn (mut c Checker) lint_related_getter_setter_pairs(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut pairs := []RgspPair{}
	mut spans := []Span{}
	// ClassBody, TSInterfaceBody and TSTypeLiteral, each with its own name → pair map.
	for body in c.nodes_of_kinds(root, ['class_body', 'interface_body', 'object_type'], []string{}) {
		mut getters := map[string]C.TSNode{}
		mut setters := map[string]C.TSNode{}
		mut order := []string{}
		for member in named_children(body) {
			kind := rgsp_accessor_kind(member)
			if kind == '' {
				continue
			}
			key := node_field(member, 'name') or { continue }
			name := c.rgsp_member_name(key)
			if kind == 'get' {
				// `:matches(MethodDefinition, TSMethodSignature)[kind=get]`, with a return type.
				if _ := node_field(member, 'return_type') {
					getters[name] = member
				} else {
					continue
				}
			} else {
				// `[kind=set]`, with a single parameter.
				parameters := node_field(member, 'parameters') or { continue }
				if named_children(parameters).len != 1 {
					continue
				}
				setters[name] = member
			}
			if name !in order {
				order << name
			}
		}
		for name in order {
			getter := getters[name] or { continue }
			setter := setters[name] or { continue }
			parameters := node_field(setter, 'parameters') or { continue }
			parameter := rgsp_estree_parameter(named_children(parameters)[0])
			annotation := node_field(getter, 'return_type') or { continue }
			report := unwrap_type_parens(first_named(annotation) or { continue })
			pairs << RgspPair{
				getter:    getter
				parameter: parameter
				report:    report
			}
			spans << member_span(getter)
			spans << node_span(parameter)
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for pair in pairs {
		get_type := c.node_type(pair.getter) or { continue }
		set_type := c.node_type(pair.parameter) or { continue }
		if !c.assignable(get_type.id, set_type.id)! {
			findings << Finding{
				stmt:       position_of(pair.report)
				message_id: 'mismatch'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += pairs.len
	return findings
}

// rgsp_accessor_kind is the ESTree `kind` ('get' or 'set') of a MethodDefinition (a class member
// that is not abstract: those are TSAbstractMethodDefinition) or a TSMethodSignature; '' for other
// members.
fn rgsp_accessor_kind(member C.TSNode) string {
	if node_kind(member) !in ['method_definition', 'method_signature']
		|| has_child_kind(member, 'abstract') {
		return ''
	}
	if has_child_kind(member, 'get') {
		return 'get'
	}
	if has_child_kind(member, 'set') {
		return 'set'
	}
	return ''
}

// rgsp_estree_parameter is the node TypeScript types for the ESTree parameter: the name (an
// identifier or a destructuring pattern), or the whole parameter if it is an AssignmentPattern or
// a RestElement.
fn rgsp_estree_parameter(parameter C.TSNode) C.TSNode {
	if _ := node_field(parameter, 'value') {
		return parameter
	}
	pattern := node_field(parameter, 'pattern') or { return parameter }
	if node_kind(pattern) == 'rest_pattern' {
		return parameter
	}
	return pattern
}

// rgsp_member_name ports getNameFromMember: the name of an identifier or a private name, a
// literal's String(value) (quoted when it is not a valid identifier, like requiresQuoting), or the
// source text of any other computed key.
fn (c &Checker) rgsp_member_name(key C.TSNode) string {
	mut node := key
	if node_kind(node) == 'computed_property_name' {
		node = unwrap_parens(first_named(node) or { return '' })
	}
	match node_kind(node) {
		'property_identifier', 'identifier' {
			return c.identifier_name(node)
		}
		'private_property_identifier' {
			return c.text(node)
		}
		'string', 'number', 'true', 'false', 'null', 'regex' {
			value := if node_kind(node) == 'regex' {
				c.text(node)
			} else {
				c.literal_name(node) or { c.text(node) }
			}
			return if requires_quoting(value) { '"${value}"' } else { value }
		}
		else {
			return c.text(node)
		}
	}
}
