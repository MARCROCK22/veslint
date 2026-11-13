module rules

import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-setter-return` rule of ESLint 10.6.0 (it has no options).

const nsr_messages = {
	'returnsValue': 'Setter cannot return a value.'
}

const nsr_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition']

fn (mut c Checker) lint_no_setter_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['method_definition', 'function_expression', 'generator_function',
		'arrow_function'], []) {
		stats.checked++
		if !c.nsr_is_setter(root, node) {
			continue
		}
		body := node_field(node, 'body') or { continue }
		if node_kind(node) == 'arrow_function' && node_kind(body) != 'statement_block' {
			findings << Finding{
				stmt:       position_of(unwrap_parens(body))
				message_id: 'returnsValue'
			}
			continue
		}
		for statement in c.nodes_of_kinds(body, ['return_statement'], nsr_function_kinds) {
			if _ := first_named(statement) {
				findings << Finding{
					stmt:       position_of(statement)
					message_id: 'returnsValue'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nsr_is_setter ports isSetter: a `set` accessor, or the function of a property `set` of a
// property descriptor.
fn (mut c Checker) nsr_is_setter(root C.TSNode, f C.TSNode) bool {
	if node_kind(f) == 'method_definition' {
		if es_accessor_kind(f) == 'set' {
			return true
		}
		// `{ set(v) {} }`: a Property with a method as its value.
		parent := node_parent(f) or { return false }
		name := c.es_static_key_name(f) or { return false }
		return node_kind(parent) == 'object' && name == 'set'
			&& c.nsr_is_property_descriptor(root, parent)
	}
	pair := cti_estree_parent(f) or { return false }
	if node_kind(pair) != 'pair' {
		return false
	}
	value := node_field(pair, 'value') or { return false }
	if node_key(unwrap_parens(value)) != node_key(f) {
		return false
	}
	object := node_parent(pair) or { return false }
	name := c.es_static_key_name(pair) or { return false }
	return node_kind(object) == 'object' && name == 'set'
		&& c.nsr_is_property_descriptor(root, object)
}

// nsr_is_property_descriptor ports isPropertyDescriptor: the third argument of
// Object.defineProperty or Reflect.defineProperty, or a value of the second argument of
// Object.create or Object.defineProperties.
fn (mut c Checker) nsr_is_property_descriptor(root C.TSNode, object C.TSNode) bool {
	if c.nsr_is_argument_of(root, object, 'Object', 'defineProperty', 2)
		|| c.nsr_is_argument_of(root, object, 'Reflect', 'defineProperty', 2) {
		return true
	}
	pair := cti_estree_parent(object) or { return false }
	if node_kind(pair) != 'pair' {
		return false
	}
	value := node_field(pair, 'value') or { return false }
	if node_key(unwrap_parens(value)) != node_key(object) {
		return false
	}
	outer := node_parent(pair) or { return false }
	return node_kind(outer) == 'object'
		&& (c.nsr_is_argument_of(root, outer, 'Object', 'create', 1)
			|| c.nsr_is_argument_of(root, outer, 'Object', 'defineProperties', 1))
}

// nsr_is_argument_of ports isArgumentOfGlobalMethodCall: the node is the argument at `index` of
// a call of `object.method` where `object` is the global one.
fn (mut c Checker) nsr_is_argument_of(root C.TSNode, n C.TSNode, object string, method string, index int) bool {
	args_node := cti_estree_parent(n) or { return false }
	if node_kind(args_node) != 'arguments' {
		return false
	}
	call := node_parent(args_node) or { return false }
	if node_kind(call) != 'call_expression' {
		return false
	}
	args := call_arguments(call) or { return false }
	list := args.filter(node_kind(it) != 'comment')
	if index >= list.len || node_key(unwrap_parens(list[index])) != node_key(n) {
		return false
	}
	callee := unwrap_parens(node_field(call, 'function') or { return false })
	if !c.es_is_specific_member_access(callee, object, method) {
		return false
	}
	target := unwrap_parens(node_field(callee, 'object') or { return false })
	return c.es_is_global_reference(root, target)
}
