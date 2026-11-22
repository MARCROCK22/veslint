module rules

import estree
import json2
import time

// Port of the `promise/spec-only` rule of eslint-plugin-promise 7.3.0, with its options.

const prm_spec_only_messages = {
	'avoidNonStandard': "Avoid using non-standard 'Promise.{{ name }}'"
}

const prm_promise_instance_methods = ['then', 'catch', 'finally']

fn prm_spec_only_options(options []json2.Any) ![]string {
	o := option_object(promise_spec_only, options, ['allowedMethods'])!
	return o.string_list('allowedMethods')!
}

// prm_is_permitted_property ports isPermittedProperty.
fn prm_is_permitted_property(t &estree.EsTree, expression int, standard []string, allowed []string) bool {
	if t.typ(expression) != .member_expression {
		return false
	}
	property := prm_child(t, expression, .property)
	if t.typ(property) == .literal {
		value := t.get(property, .value)
		return value is string && (value in standard || value in allowed)
	}
	if t.typ(property) == .identifier {
		name := prm_name(t, property)
		return (t.flag(expression, .computed) or { false }) || name in standard || name in allowed
	}
	return false
}

fn (mut c Checker) lint_promise_spec_only(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allowed := prm_spec_only_options(c.rule_options(promise_spec_only))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .member_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		object := prm_child(t, node, .object)
		if t.typ(object) != .identifier || prm_name(t, object) != 'Promise' {
			continue
		}
		property := prm_child(t, node, .property)
		name := prm_name(t, property)
		parent := t.nodes[node].parent
		if (name != 'prototype' && !prm_is_permitted_property(t, node, prm_promise_statics, allowed))
			|| (name == 'prototype' && parent >= 0 && t.typ(parent) == .member_expression
				&& !prm_is_permitted_property(t, parent, prm_promise_instance_methods, allowed)) {
			// `node.property.name ?? node.property.value`
			shown := t.string_of(property, .name) or {
				if t.typ(property) == .literal {
					tsm_literal_string(t, property)
				} else {
					'undefined'
				}
			}
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'avoidNonStandard'
				data:       {
					'name': shown
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
