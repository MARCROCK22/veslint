module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-extend-native` rule of ESLint 10.6.0, with its option.

const nen_messages = {
	'unexpected': '{{builtin}} prototype is read only, properties should not be added.'
}

// nen_exceptions reads `exceptions`.
fn nen_exceptions(options []json2.Any) ![]string {
	o := option_object(no_extend_native, options, ['exceptions'])!
	value := o.values['exceptions'] or { json2.Any([]json2.Any{}) }
	return value.as_array().map(it.str())
}

fn (mut c Checker) lint_no_extend_native(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	exceptions := nen_exceptions(c.rule_options(no_extend_native))!
	mut findings := []Finding{}
	tree := c.scope_tree(root)
	// The globals of ECMAScript whose name starts with an upper case letter.
	for builtin in scope_es_globals {
		if builtin[0] < `A` || builtin[0] > `Z` || builtin in exceptions {
			continue
		}
		v := tree.own_variable(0, builtin)
		if v < 0 {
			continue
		}
		for r in tree.variables[v].references {
			id := tree.references[r].identifier
			stats.checked++
			// `X.prototype`, then a property of it assigned, or it given to Object.defineProperty.
			prototype := cti_estree_parent(id) or { continue }
			if node_kind(prototype) !in ['member_expression', 'subscript_expression'] {
				continue
			}
			object := node_field(prototype, 'object') or { continue }
			if node_key(unwrap_parens(object)) != node_key(id)
				|| (c.es_static_property_name(prototype) or { '' }) != 'prototype' {
				continue
			}
			parent := cti_estree_parent(prototype) or { continue }
			if node_kind(parent) in ['member_expression', 'subscript_expression'] {
				inner := node_field(parent, 'object') or { continue }
				if node_key(unwrap_parens(inner)) != node_key(prototype) {
					continue
				}
				assignment := cti_estree_parent(parent) or { continue }
				if node_kind(assignment) in ['assignment_expression', 'augmented_assignment_expression'] {
					left := node_field(assignment, 'left') or { continue }
					if node_key(unwrap_parens(left)) == node_key(parent) {
						findings << Finding{
							stmt:       position_of(assignment)
							message_id: 'unexpected'
							data:       {
								'builtin': builtin
							}
						}
					}
				}
				continue
			}
			if node_kind(parent) == 'arguments' {
				call := treesitter.node_parent(parent) or { continue }
				if node_kind(call) != 'call_expression' {
					continue
				}
				args := (call_arguments(call) or { continue }).filter(node_kind(it) != 'comment')
				if args.len == 0 || node_key(unwrap_parens(args[0])) != node_key(prototype) {
					continue
				}
				callee := node_field(call, 'function') or { continue }
				if c.es_is_specific_member_access(callee, 'Object', 'defineProperty')
					|| c.es_is_specific_member_access(callee, 'Object', 'defineProperties') {
					findings << Finding{
						stmt:       position_of(call)
						message_id: 'unexpected'
						data:       {
							'builtin': builtin
						}
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
