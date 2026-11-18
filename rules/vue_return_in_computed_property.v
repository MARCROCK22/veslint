module rules

import json2
import time

// Port of the `vue/return-in-computed-property` rule of eslint-plugin-vue 10.12.1 (option
// `treatUndefinedAsUnspecified`, true by default): a getter of a computed property of a Vue
// object, or of a `computed(…)` of the composition API (imported from `vue` and its kin, or the
// global), that does not always return a value (executeOnFunctionsWithoutReturn, which reads the
// types for an exhaustive switch).

const vue_return_in_computed_property_messages = {
	'expectedReturnInFunction': 'Expected to return a value in computed function.'
	'expectedReturnInProperty': 'Expected to return a value in "{{name}}" computed property.'
}

fn vue_return_in_computed_property_options(options []json2.Any) !bool {
	o := option_object(vue_return_in_computed_property, options, ['treatUndefinedAsUnspecified'])!
	if 'treatUndefinedAsUnspecified' !in o.values {
		return true
	}
	// `options.treatUndefinedAsUnspecified !== false`
	return o.bool_value('treatUndefinedAsUnspecified')!
}

fn (mut c Checker) lint_vue_return_in_computed_property(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	treat_undefined := vue_return_in_computed_property_options(c.rule_options(vue_return_in_computed_property))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	// Program: the getters of `computed(…)` (iterateReferencesTraceMap: ES modules, then globals).
	call_trace := EsTrace{
		call: true
	}
	esm := EsTrace{
		esm:      true
		children: {
			'computed': call_trace
		}
	}
	mut esm_map := map[string]EsTrace{}
	for module in vue_composition_modules {
		esm_map[module] = esm
	}
	mut traced := c.es_esm_references(root, esm_map)
	traced << c.es_global_references(root, {
		'computed': call_trace
	})
	mut functions := []int{}
	for r in traced {
		call := c.es_index_of(t, r.node) or { continue }
		if t.typ(call) != .call_expression {
			continue
		}
		getter := vue_getter_body_from_computed_function(t, call)
		if getter >= 0 {
			functions << getter
		}
	}
	// onVueObjectEnter: the computed properties of every Vue object, in the order they are entered.
	mut computed := []VueComputedProperty{}
	for step in t.steps() {
		if !step.leave && t.typ(step.node) == .object_expression
			&& s.object_type(step.node) != .none_ {
			computed << vue_computed_properties(t, step.node)
		}
	}
	if functions.len == 0 && computed.len == 0 {
		return findings
	}
	for f in c.vue_functions_without_return(root, abs_path, treat_undefined, mut stats) {
		stats.checked++
		for cp in computed {
			if cp.value >= 0 && t.nodes[cp.value].parent == f {
				findings << Finding{
					stmt:       c.es_tree_position(t, f)
					message_id: 'expectedReturnInProperty'
					data:       {
						'name': if cp.has_key && cp.key != '' { cp.key } else { 'Unknown' }
					}
				}
			}
		}
		for getter in functions {
			if getter == f {
				findings << Finding{
					stmt:       c.es_tree_position(t, f)
					message_id: 'expectedReturnInFunction'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
