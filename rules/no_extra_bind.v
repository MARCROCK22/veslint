module rules

import time
import treesitter { node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-extra-bind` rule of ESLint 10.15.0, with its fix (it has no options).

const neb_messages = {
	'unexpected': 'The function binding is unnecessary.'
}

// The nodes whose `this` is their own: the functions that are not arrows and the static blocks.
const neb_this_scope_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'method_definition', 'class_static_block']

// neb_in_field_initializer: between the node and `top`, the node is in the value of a class field
// (a PropertyDefinition, not an AccessorProperty).
fn neb_in_field_initializer(n C.vt_node, top C.vt_node) bool {
	mut child := n
	for node_key(child) != node_key(top) {
		parent := node_parent(child) or { return false }
		if node_kind(parent) == 'public_field_definition' && !es_is_accessor_field(parent) {
			if value := node_field(parent, 'value') {
				if node_key(value) == node_key(child) {
					return true
				}
			}
		}
		child = parent
	}
	return false
}

fn (mut c Checker) lint_no_extra_bind(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	kinds := ['function_expression', 'generator_function', 'arrow_function']
	for node in c.nodes_of_kinds(root, kinds, []) {
		member, call := c.neb_bind_call(node) or { continue }
		stats.checked++
		// A function that uses no `this` of its own (an arrow never has one).
		if node_kind(node) != 'arrow_function' {
			body := node_field(node, 'body') or { continue }
			// Class field initializers and static blocks have their own `this` (a field's key
			// is in the function's).
			mut uses_this := false
			for this_node in c.nodes_of_kinds(body, ['this'], neb_this_scope_kinds) {
				if !neb_in_field_initializer(this_node, body) {
					uses_this = true
					break
				}
			}
			if uses_this {
				continue
			}
		}
		// The property: a name, or the key in the brackets of a computed one.
		property := unwrap_parens(node_field(member, if node_kind(member) == 'subscript_expression' {
			'index'
		} else {
			'property'
		}) or { continue })
		has_fix, fix := c.neb_fix(root, member, call)
		findings << Finding{
			stmt:       position_of(property)
			message_id: 'unexpected'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// neb_bind_call ports isCalleeOfBindMethod: the function is the object of `.bind(x)`, called with
// one argument that is not a spread.
fn (c &Checker) neb_bind_call(f C.vt_node) ?(C.vt_node, C.vt_node) {
	member := cti_estree_parent(f)?
	if !c.es_is_specific_member_access(member, '', 'bind') {
		return none
	}
	object := node_field(member, 'object')?
	if node_key(unwrap_parens(object)) != node_key(f) {
		return none
	}
	call := es_callee_of(member)?
	if node_kind(call) != 'call_expression' {
		return none
	}
	args := (call_arguments(call)?).filter(node_kind(it) != 'comment')
	if args.len != 1 || node_kind(args[0]) == 'spread_element' {
		return none
	}
	return member, call
}

// neb_fix removes `.bind` and its arguments, when the argument has no side effects.
fn (mut c Checker) neb_fix(root C.vt_node, member C.vt_node, call C.vt_node) (bool, Fix) {
	args := (call_arguments(call) or { return false, Fix{} }).filter(node_kind(it) != 'comment')
	argument := unwrap_parens(args[0])
	if node_kind(argument) !in ['string', 'number', 'true', 'false', 'null', 'regex', 'identifier',
		'undefined', 'this', 'function_expression', 'generator_function'] {
		return false, Fix{}
	}
	tokens := c.source_tokens(root)
	object := unwrap_parens(node_field(member, 'object') or { return false, Fix{} })
	mut first := tokens.after(c.es_end(object), false) or { return false, Fix{} }
	for c.src[first.start..first.end] == ')' {
		first = tokens.after(first.end, false) or { return false, Fix{} }
	}
	member_last := tokens.before(c.es_end(member), false) or { return false, Fix{} }
	mut second := tokens.after(c.es_end(member), false) or { return false, Fix{} }
	for c.src[second.start..second.end] == ')' {
		second = tokens.after(second.end, false) or { return false, Fix{} }
	}
	call_last := tokens.before(c.es_end(call), false) or { return false, Fix{} }
	if tokens.comments_exist_between(first.start, call_last.end) {
		return false, Fix{}
	}
	has_fix, fix := c.merge_fixes([fix_remove_range(first.start, member_last.end),
		fix_remove_range(second.start, call_last.end)]) or { return false, Fix{} }
	return has_fix, fix
}
