module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/explicit-function-return-type` rule of typescript-eslint 8.72.2,
// with all its options (util/explicitReturnTypeUtils.ts in rules/ts_explicit_return_type_utils.v).

const efrt_messages = {
	'missingReturnType': 'Missing return type on function.'
}

struct EfrtOptions {
	allow_concise_arrow_function_expressions_starting_with_void bool
	allow_functions_without_type_parameters                     bool
	allowed_names                                               []string
	allow_iifes                                                 bool
	ert                                                         ErtOptions
}

fn efrt_options(options []json2.Any) !EfrtOptions {
	o := option_object(explicit_function_return_type, options, [
		'allowConciseArrowFunctionExpressionsStartingWithVoid',
		'allowDirectConstAssertionInArrowFunctions', 'allowedNames', 'allowExpressions',
		'allowFunctionsWithoutTypeParameters', 'allowHigherOrderFunctions', 'allowIIFEs',
		'allowTypedFunctionExpressions'])!
	return EfrtOptions{
		allow_concise_arrow_function_expressions_starting_with_void: o.bool_value('allowConciseArrowFunctionExpressionsStartingWithVoid') or {
			false
		}
		allow_functions_without_type_parameters:                     o.bool_value('allowFunctionsWithoutTypeParameters') or {
			false
		}
		allowed_names:                                               o.string_list('allowedNames') or {
			[]string{}
		}
		allow_iifes:                                                 o.bool_value('allowIIFEs') or {
			false
		}
		ert:                                                         ErtOptions{
			allow_direct_const_assertion_in_arrow_functions: o.bool_value('allowDirectConstAssertionInArrowFunctions') or {
				true
			}
			allow_expressions:                               o.bool_value('allowExpressions') or {
				false
			}
			allow_higher_order_functions:                    o.bool_value('allowHigherOrderFunctions') or {
				true
			}
			allow_typed_function_expressions:                o.bool_value('allowTypedFunctionExpressions') or {
				true
			}
		}
	}
}

fn (mut c Checker) lint_explicit_function_return_type(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := efrt_options(c.rule_options(explicit_function_return_type))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	returns := ert_function_returns(t)
	for node in 0 .. t.nodes.len {
		if !ert_is_function(t, node) {
			continue
		}
		stats.checked++
		node_returns := returns[node] or { []int{} }
		if t.typ(node) == .function_declaration {
			if efrt_is_allowed_function(t, node, o) {
				continue
			}
			if o.ert.allow_typed_function_expressions && t.node(node, .return_type) != none {
				continue
			}
		} else {
			// exitFunctionExpression
			if o.allow_concise_arrow_function_expressions_starting_with_void
				&& t.typ(node) == .arrow_function_expression
				&& (t.flag(node, .expression) or { false }) {
				body := t.node(node, .body) or { -1 }
				if body >= 0 && t.typ(body) == .unary_expression
					&& (t.string_of(body, .operator) or { '' }) == 'void' {
					continue
				}
			}
			if efrt_is_allowed_function(t, node, o) {
				continue
			}
			if o.ert.allow_typed_function_expressions
				&& (ert_is_valid_function_expression_return_type(t, node, o.ert)
				|| ert_ancestor_has_return_type(t, node)) {
				continue
			}
		}
		if head := c.ert_check_function_return_type(t, node, node_returns, o.ert) {
			findings << Finding{
				stmt:       head
				message_id: 'missingReturnType'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// efrt_is_allowed_function ports isAllowedFunction.
fn efrt_is_allowed_function(t &estree.EsTree, node int, o EfrtOptions) bool {
	if o.allow_functions_without_type_parameters && t.node(node, .type_parameters) == none {
		return true
	}
	parent := t.nodes[node].parent
	// isIIFE
	if o.allow_iifes && t.typ(parent) == .call_expression {
		return true
	}
	if o.allowed_names.len == 0 {
		return false
	}
	id := t.node(node, .id) or { -1 }
	if t.typ(node) in [.arrow_function_expression, .function_expression] {
		mut func_name := ''
		id_name := if id >= 0 { t.string_of(id, .name) or { '' } } else { '' }
		if id_name != '' {
			func_name = id_name
		} else {
			match t.typ(parent) {
				.variable_declarator {
					pid := t.node(parent, .id) or { -1 }
					if pid >= 0 && t.typ(pid) == .identifier {
						func_name = t.string_of(pid, .name) or { '' }
					}
				}
				.method_definition, .property_definition, .property {
					key := t.node(parent, .key) or { -1 }
					if key >= 0 && t.typ(key) == .identifier
						&& !(t.flag(parent, .computed) or { false }) {
						func_name = t.string_of(key, .name) or { '' }
					}
				}
				else {}
			}
		}
		if func_name != '' && func_name in o.allowed_names {
			return true
		}
	}
	if t.typ(node) == .function_declaration && id >= 0
		&& (t.string_of(id, .name) or { '' }) in o.allowed_names {
		return true
	}
	return false
}
