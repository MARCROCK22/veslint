module rules

import estree
import json2
import jsregexp

// What sort-union-types and sort-intersection-types of eslint-plugin-perfectionist 5.13.0 share
// (rules/sort-union-or-intersection-types/: sortUnionOrIntersectionTypes, computeNodeName,
// computeMatchedContextOptions, typeContainsCallableType).

// pfuo_all_selectors are the selectors of the types (allSelectors of sort-union-types/types.ts).
const pfuo_all_selectors = ['intersection', 'conditional', 'function', 'operator', 'keyword', 'literal',
	'nullish', 'import', 'object', 'named', 'tuple', 'union']

const pfuo_re_leading_operator = jsregexp.js_regex_new('^\\s*[&|]\\s*', 'u') or { panic(err) }

// pfuo_node_name ports computeNodeName: the text of the type, without the `|` or `&` a union or
// an intersection starts with.
fn (ctx &PfContext) pfuo_node_name(typ int) string {
	name := ctx.text(typ)
	if ctx.t.typ(typ) !in [.ts_union_type, .ts_intersection_type] {
		return name
	}
	return stv_units_string(pf_regex_replace(pfuo_re_leading_operator, utf16_units(name),
		true, false, pf_remove_match))
}

// pfuo_selector is the selector of a type (the switch of sortUnionOrIntersectionTypes); '' for
// a type without one.
fn pfuo_selector(typ estree.NodeType) string {
	return match typ {
		.ts_template_literal_type, .ts_literal_type {
			'literal'
		}
		.ts_indexed_access_type, .ts_type_reference, .ts_qualified_name, .ts_array_type,
		.ts_infer_type {
			'named'
		}
		.ts_intersection_type {
			'intersection'
		}
		.ts_undefined_keyword, .ts_null_keyword, .ts_void_keyword {
			'nullish'
		}
		.ts_conditional_type {
			'conditional'
		}
		.ts_constructor_type, .ts_function_type {
			'function'
		}
		.ts_boolean_keyword, .ts_unknown_keyword, .ts_big_int_keyword, .ts_number_keyword,
		.ts_object_keyword, .ts_string_keyword, .ts_symbol_keyword, .ts_never_keyword,
		.ts_any_keyword, .ts_this_type {
			'keyword'
		}
		.ts_type_operator, .ts_type_query {
			'operator'
		}
		.ts_type_literal, .ts_mapped_type {
			'object'
		}
		.ts_import_type {
			'import'
		}
		.ts_tuple_type {
			'tuple'
		}
		.ts_union_type {
			'union'
		}
		else {
			''
		}
	}
}

// pfuo_type_contains_callable_type ports typeContainsCallableType: a function or constructor
// type, or an object type with a call signature, a method or a property of such a type.
fn pfuo_type_contains_callable_type(t &estree.EsTree, typ int) bool {
	match t.typ(typ) {
		.ts_constructor_type, .ts_function_type {
			return true
		}
		.ts_type_literal {
			for member in t.list(typ, .members) or { []int{} } {
				match t.typ(member) {
					.ts_call_signature_declaration, .ts_method_signature {
						return true
					}
					.ts_property_signature {
						annotation := t.node(member, .type_annotation) or { continue }
						inner := t.node(annotation, .type_annotation) or { continue }
						if pfuo_type_contains_callable_type(t, inner) {
							return true
						}
					}
					else {}
				}
			}
			return false
		}
		else {
			return false
		}
	}
}

// pfuo_sort ports sortUnionOrIntersectionTypes: the types of a union or an intersection sorted,
// in the partitions the partition options make.
fn (mut ctx PfContext) pfuo_sort(node int, matched_ast_selectors []string, defaults map[string]json2.Any, ids PfMessageIds, token_value_to_ignore_before string) ! {
	t := ctx.t
	types := t.list(node, .types) or { []int{} }
	settings := pf_get_settings(ctx.settings)!
	node_names := types.map(ctx.pfuo_node_name(it))
	_, matched := ctx.pf_matched_context_options(node_names, matched_ast_selectors)!
	options := pf_complete(matched, defaults, settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, pfuo_all_selectors, [])!
	pf_validate_newlines_and_partition_config(options)!
	if !pf_can_report_errors(options, pf_default_comparator_computer, ids) {
		return
	}
	if pf_opt_truthy(options, 'ignoreCallableTypes')
		&& types.any(pfuo_type_contains_callable_type(t, it)) {
		return
	}
	mut formatted_members := [][]PfSortingNode{len: 1}
	for typ in types {
		selector := pfuo_selector(t.typ(typ))
		selectors := if selector == '' { []string{} } else { [selector] }
		name := ctx.pfuo_node_name(typ)
		group := pf_compute_group(options, pf_generate_predefined_groups(selectors, []),
			PfElement{
				name:      name
				selectors: selectors
			})!
		mut last_node := ?int(none)
		last_group := formatted_members.last()
		if last_group.len > 0 {
			last_node = last_group.last().node
		}
		if ctx.pf_should_partition(options, last_node, typ, token_value_to_ignore_before)! {
			formatted_members << []PfSortingNode{}
		}
		formatted_members[formatted_members.len - 1] << PfSortingNode{
			node:               typ
			name:               name
			group:              group
			size:               ctx.pf_range_to_diff(typ)
			is_eslint_disabled: ctx.pf_is_node_eslint_disabled(typ)
			partition_id:       formatted_members.len
		}
	}
	for nodes in formatted_members {
		sorted := pf_sort_nodes_by_groups(nodes, pf_default_comparator_computer, options,
			false)
		sorted_excluding_disabled := pf_sort_nodes_by_groups(nodes, pf_default_comparator_computer,
			options, true)
		ctx.pf_report_all_errors(nodes, sorted, sorted_excluding_disabled, options, ids)!
	}
}
