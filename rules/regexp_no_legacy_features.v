module rules

import json2
import time
import treesitter { position_of }

// Port of the `regexp/no-legacy-features` rule of eslint-plugin-regexp 3.3.3 with its options
// (staticProperties and prototypeMethods, all of them by default): the reads of the legacy static
// properties of the global RegExp (`RegExp.$1`, `RegExp.lastMatch`…, through ReferenceTracker), and
// `compile` of an object whose type (TypeScript's, from the program) is RegExp.

const regexp_no_legacy_features_messages = {
	'forbiddenStaticProperty':   "'{{name}}' static property is forbidden."
	'forbiddenPrototypeMethods': 'RegExp.prototype.{{name}} method is forbidden.'
}

const rxnlf_static_properties = ['input', '\$_', 'lastMatch', '\$&', 'lastParen', '\$+', 'leftContext',
	'\$`', 'rightContext', "\$'", '\$1', '\$2', '\$3', '\$4', '\$5', '\$6', '\$7', '\$8', '\$9']

// rxnlf_options are staticProperties and prototypeMethods.
fn rxnlf_options(options []json2.Any) !([]string, []string) {
	o := option_object(regexp_no_legacy_features, options, ['staticProperties', 'prototypeMethods'])!
	static_properties := if 'staticProperties' in o.values {
		o.string_list('staticProperties')!
	} else {
		rxnlf_static_properties
	}
	prototype_methods := if 'prototypeMethods' in o.values {
		o.string_list('prototypeMethods')!
	} else {
		['compile']
	}
	return static_properties, prototype_methods
}

fn (mut c Checker) lint_regexp_no_legacy_features(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	static_properties, prototype_methods := rxnlf_options(c.rule_options(regexp_no_legacy_features))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	if static_properties.len > 0 {
		mut children := map[string]EsTrace{}
		for sp in static_properties {
			children[sp] = EsTrace{
				read: true
			}
		}
		trace := {
			'RegExp': EsTrace{
				children: children
			}
		}
		for traced in c.es_global_references(root, trace) {
			stats.checked++
			position := if node := c.es_index_of(t, traced.node) {
				c.es_tree_position(t, node)
			} else {
				position_of(traced.node)
			}
			findings << Finding{
				stmt:       position
				message_id: 'forbiddenStaticProperty'
				data:       {
					'name': traced.path.join('.')
				}
			}
		}
	}
	if prototype_methods.len > 0 {
		for step in t.steps() {
			node := step.node
			if step.leave || t.typ(node) != .member_expression || (t.flag(node, .computed) or {
				false
			}) {
				continue
			}
			property := t.node(node, .property) or { continue }
			object := t.node(node, .object) or { continue }
			name := t.string_of(property, .name) or { '' }
			if t.typ(property) != .identifier || name !in prototype_methods || t.typ(object) == .super {
				continue
			}
			stats.checked++
			if c.rx_is_regexp(root, t, abs_path, object) {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'forbiddenPrototypeMethods'
					data:       {
						'name': name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
