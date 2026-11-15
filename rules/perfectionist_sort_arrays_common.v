module rules

import estree
import json2
import jsregexp

// What the rules of eslint-plugin-perfectionist 5.13.0 that sort the elements of an array share
// (rules/sort-arrays/: sortArray, computeArrayElements, computeNodeName,
// computeMatchedContextOptions): sort-array-includes and sort-sets (and sort-arrays).

// pfsa_all_selectors are the selectors of the elements (allSelectors of sort-arrays/types.ts).
const pfsa_all_selectors = ['literal']

// pfsa_array_elements ports computeArrayElements: the elements of an array (-1 for a hole), or
// the arguments of `new Array(…)`; none for another `new`.
fn pfsa_array_elements(t &estree.EsTree, node int) ?[]int {
	if t.typ(node) == .array_expression {
		return t.list(node, .elements) or { []int{} }
	}
	callee := t.node(node, .callee) or { return none }
	if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != 'Array' {
		return none
	}
	return t.list(node, .arguments) or { []int{} }
}

// pfsa_node_name ports computeNodeName of sort-arrays: String(value) of a literal, or the text of
// the element.
fn (ctx &PfContext) pfsa_node_name(element int) string {
	if ctx.t.typ(element) == .literal {
		return pf_literal_string(ctx.t, element)
	}
	return ctx.text(element)
}

// pf_literal_string is `String(node.value)` of a Literal.
fn pf_literal_string(t &estree.EsTree, node int) string {
	value := t.get(node, .value)
	return match value {
		string {
			value
		}
		f64 {
			js_number_to_string(value)
		}
		bool {
			if value { 'true' } else { 'false' }
		}
		estree.BigIntValue {
			t.string_of(node, .bigint) or { value.digits }
		}
		estree.RegExpValue {
			info := t.get(node, .regex)
			if info is estree.RegexInfo {
				re := jsregexp.regexp_new(utf16_units(info.pattern), info.flags) or {
					return 'null'
				}
				'/${stv_units_string(re.source)}/${re.flags}'
			} else {
				'null'
			}
		}
		else {
			'null'
		}
	}
}

// pfsa_sort_array ports sortArray: the elements of the array (or of `new Array(…)`) sorted, in
// partitions that its spread elements and the partition options make.
fn (mut ctx PfContext) pfsa_sort_array(node int, matched_ast_selectors []string, defaults map[string]json2.Any, ids PfMessageIds, must_have_matched_context_options bool) ! {
	t := ctx.t
	elements := pfsa_array_elements(t, node) or { return }
	if elements.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	mut node_names := []string{}
	for element in elements {
		if element >= 0 {
			node_names << ctx.pfsa_node_name(element)
		}
	}
	has_matched, matched := ctx.pf_matched_context_options(node_names, matched_ast_selectors)!
	if must_have_matched_context_options && !has_matched {
		return
	}
	options := pf_complete(matched, defaults, settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, pfsa_all_selectors, [])!
	pf_validate_newlines_and_partition_config(options)!
	if !pf_can_report_errors(options, pf_default_comparator_computer, ids) {
		return
	}
	predefined_groups := pf_generate_predefined_groups(['literal'], [])
	mut formatted_members := [][]PfSortingNode{len: 1}
	for element in elements {
		if element < 0 {
			continue
		}
		if t.typ(element) == .spread_element {
			formatted_members << []PfSortingNode{}
			continue
		}
		name := ctx.pfsa_node_name(element)
		group := pf_compute_group(options, predefined_groups, PfElement{
			name:      name
			selectors: ['literal']
		})!
		mut last_node := ?int(none)
		last_part := formatted_members.last()
		if last_part.len > 0 {
			last_node = last_part.last().node
		}
		if ctx.pf_should_partition(options, last_node, element, '')! {
			formatted_members << []PfSortingNode{}
		}
		formatted_members[formatted_members.len - 1] << PfSortingNode{
			node:               element
			name:               name
			group:              group
			size:               ctx.pf_range_to_diff(element)
			is_eslint_disabled: ctx.pf_is_node_eslint_disabled(element)
			partition_id:       formatted_members.len
		}
	}
	mut sorted := []PfSortingNode{}
	mut sorted_excluding_disabled := []PfSortingNode{}
	mut nodes := []PfSortingNode{}
	for part in formatted_members {
		sorted << pf_sort_nodes_by_groups(part, pf_default_comparator_computer, options,
			false)
		sorted_excluding_disabled << pf_sort_nodes_by_groups(part, pf_default_comparator_computer,
			options, true)
		nodes << part
	}
	ctx.pf_report_all_errors(nodes, sorted, sorted_excluding_disabled, options, ids)!
}

// pf_sorters runs `sorter` on each node of those types when ESLint's traversal leaves it (the
// `${nodeType}:exit` listeners of buildAstListeners), with the selectors of
// `useConfigurationIf.matchesAstSelector` it matched.
fn (mut ctx PfContext) pf_sorters(node_types []estree.NodeType, sorter fn (mut ctx PfContext, node int, matched []string) !) ! {
	matched := ctx.pf_matched_ast_selectors(node_types)!
	for step in ctx.t.steps() {
		if !step.leave || ctx.t.typ(step.node) !in node_types {
			continue
		}
		sorter(mut ctx, step.node, matched[step.node] or { []string{} })!
	}
}

// pf_decode_defaults decodes the default options of a rule (its `defaultOptions` as JSON).
fn pf_decode_defaults(text string) map[string]json2.Any {
	decoded := json2.decode[json2.Any](text) or { return map[string]json2.Any{} }
	return decoded.as_map()
}
