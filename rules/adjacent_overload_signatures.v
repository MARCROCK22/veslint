module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start }

// Port of the `adjacent-overload-signatures` rule of typescript-eslint 8.62.0 (it has no options).

const aos_messages = {
	'adjacentSignature': 'All {{name}} signatures should be adjacent.'
}

// MemberNameType of typescript-eslint's util/misc.
enum AosNameType {
	private_    = 1
	quoted      = 2
	normal      = 3
	expression_ = 4
}

// AosStatic is the `static` of a Method: undefined for a function or a call or construct
// signature, which `===` tells from false.
enum AosStatic {
	undefined_
	false_
	true_
}

// AosMethod is the Method of the rule: what tells two overloads of the same member.
struct AosMethod {
	name           string
	type           AosNameType
	call_signature bool
	static         AosStatic
}

fn (mut c Checker) lint_adjacent_overload_signatures(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// BlockStatement, ClassBody, Program, TSInterfaceBody, TSModuleBlock and TSTypeLiteral. The body
	// of a static block is no BlockStatement in ESTree.
	for node in c.nodes_of_kinds(root, ['program', 'statement_block', 'class_body', 'interface_body',
		'object_type'], []) {
		members := match node_kind(node) {
			'class_body' {
				cm_members(node)
			}
			'statement_block' {
				parent := node_parent(node) or { continue }
				if node_kind(parent) == 'class_static_block' {
					continue
				}
				named_children(node)
			}
			else {
				named_children(node).filter(node_kind(it) != 'hash_bang_line')
			}
		}
		checked++
		c.aos_check_body(members, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// aos_check_body ports checkBodyForOverloadMethods.
fn (mut c Checker) aos_check_body(members []C.TSNode, mut findings []Finding) {
	mut last_method := ?AosMethod(none)
	mut seen_methods := []AosMethod{}
	for member in members {
		method := c.aos_member_method(member) or {
			last_method = none
			continue
		}
		mut index := -1
		for i, seen in seen_methods {
			if seen == method {
				index = i
				break
			}
		}
		if index > -1 && !aos_same(method, last_method) {
			start := if node_kind(node_parent(member) or { member }) == 'class_body' {
				cm_start(member)
			} else {
				node_start(member)
			}
			findings << Finding{
				stmt:       c.position_at(start)
				message_id: 'adjacentSignature'
				data:       {
					'name': if method.static == .true_ {
						'static ${method.name}'
					} else {
						method.name
					}
				}
			}
		} else if index == -1 {
			seen_methods << method
		}
		last_method = method
	}
}

fn aos_same(method AosMethod, other ?AosMethod) bool {
	o := other or { return false }
	return method == o
}

// aos_member_method ports getMemberMethod: none for a member that is not relevant to the rule.
fn (mut c Checker) aos_member_method(member C.TSNode) ?AosMethod {
	match node_kind(member) {
		'export_statement' {
			// `export { a }`, `export default a` and `export = a` have no declaration.
			return c.aos_member_method(node_field(member, 'declaration')?)
		}
		'ambient_declaration' {
			// `declare function f()` is a TSDeclareFunction.
			for child in named_children(member) {
				if node_kind(child) == 'function_signature' {
					return c.aos_member_method(child)
				}
			}
			return none
		}
		'function_declaration', 'generator_function_declaration', 'function_signature' {
			name := node_field(member, 'name')?
			return AosMethod{
				name: c.identifier_name(name)
				type: .normal
			}
		}
		'method_definition', 'method_signature' {
			// A MethodDefinition in a class, a TSMethodSignature in a type.
			name, type := c.aos_name_from_member(node_field(member, 'name')?)
			return AosMethod{
				name:   name
				type:   type
				static: if cm_is_static(member) { .true_ } else { .false_ }
			}
		}
		'call_signature' {
			return AosMethod{
				name:           'call'
				type:           .normal
				call_signature: true
			}
		}
		'construct_signature' {
			return AosMethod{
				name: 'new'
				type: .normal
			}
		}
		else {
			return none
		}
	}
}

// aos_name_from_member ports getNameFromMember for a key: an Identifier (computed or not), a
// private name (with its `#`), String(value) of a Literal (quoted when it requires quoting), or the
// text of any other expression of a computed key.
fn (c &Checker) aos_name_from_member(key C.TSNode) (string, AosNameType) {
	mut node := key
	if node_kind(node) == 'computed_property_name' {
		node = unwrap_parens(first_named(node) or { return c.text(key), AosNameType.expression_ })
	}
	match node_kind(node) {
		'property_identifier', 'identifier', 'undefined' {
			return c.identifier_name(node), AosNameType.normal
		}
		'private_property_identifier' {
			return c.identifier_name(node), AosNameType.private_
		}
		'string', 'number', 'true', 'false', 'null', 'regex' {
			name := c.literal_name(node) or { c.text(node) }
			if requires_quoting(name) {
				return '"${name}"', AosNameType.quoted
			}
			return name, AosNameType.normal
		}
		else {
			return c.text(node), AosNameType.expression_
		}
	}
}
