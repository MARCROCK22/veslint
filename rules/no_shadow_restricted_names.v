module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-shadow-restricted-names` rule of ESLint 10.6.0, with its option.

const nsrn_messages = {
	'shadowingRestrictedName': "Shadowing of global property '{{name}}'."
}

// nsrn_report_global_this reads reportGlobalThis.
fn nsrn_report_global_this(options []json2.Any) !bool {
	o := option_object(no_shadow_restricted_names, options, ['reportGlobalThis'])!
	return o.bool_value('reportGlobalThis')!
}

fn (mut c Checker) lint_no_shadow_restricted_names(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut restricted := ['undefined', 'NaN', 'Infinity', 'arguments', 'eval']
	if nsrn_report_global_this(c.rule_options(no_shadow_restricted_names))! {
		restricted << 'globalThis'
	}
	mut findings := []Finding{}
	mut reported := map[u64]bool{}
	kinds := ['lexical_declaration', 'variable_declaration', 'function_declaration',
		'function_expression', 'generator_function', 'generator_function_declaration', 'arrow_function',
		'method_definition', 'catch_clause', 'import_statement', 'class_declaration',
		'abstract_class_declaration', 'class']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		tree := c.scope_tree(root)
		for v in c.es_declared_variables(root, node) {
			variable := tree.variables[v]
			if variable.defs.len == 0 || variable.name !in restricted
				|| c.nsrn_safely_shadows_undefined(tree, v) {
				continue
			}
			for def in variable.defs {
				key := node_key(def.name)
				if key in reported {
					continue
				}
				reported[key] = true
				findings << Finding{
					stmt:       position_of(def.name)
					message_id: 'shadowingRestrictedName'
					data:       {
						'name': variable.name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nsrn_safely_shadows_undefined: `var undefined;` never written.
fn (c &Checker) nsrn_safely_shadows_undefined(tree &ScopeTree, v int) bool {
	variable := tree.variables[v]
	if variable.name != 'undefined' || variable.references.any(tree.references[it].write) {
		return false
	}
	for def in variable.defs {
		if node_kind(def.node) != 'variable_declarator' {
			return false
		}
		if _ := node_field(def.node, 'value') {
			return false
		}
	}
	return true
}
