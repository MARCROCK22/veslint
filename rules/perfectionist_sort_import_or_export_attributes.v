module rules

import json2

// What sort-import-attributes and sort-export-attributes of eslint-plugin-perfectionist 5.13.0
// share (rules/sort-import-attributes/: sortImportOrExportAttributes, computeNodeName,
// computeMatchedContextOptions): the attributes of an import or an export (`with { … }`) sorted
// by their keys.

// The defaultOptions of both rules.
const pfie_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","partitionByComment":false,"partitionByNewLine":false,"newlinesBetween":"ignore","useConfigurationIf":{},"type":"alphabetical","ignoreCase":true,"customGroups":[],"locales":"en-US","alphabet":"","order":"asc","groups":[]}'

// pfie_node_name ports computeNodeName: the name of the key (an identifier) or its value (a
// string literal).
fn (ctx &PfContext) pfie_node_name(attribute int) string {
	t := ctx.t
	key := t.node(attribute, .key) or { return '' }
	if t.typ(key) == .identifier {
		return t.string_of(key, .name) or { '' }
	}
	return pf_literal_string(t, key)
}

// pfie_sort ports sortImportOrExportAttributes.
fn (mut ctx PfContext) pfie_sort(node int, matched_ast_selectors []string, defaults map[string]json2.Any, ids PfMessageIds) ! {
	t := ctx.t
	attributes := t.list(node, .attributes) or { []int{} }
	// isSortable: more than one.
	if attributes.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	node_names := attributes.map(ctx.pfie_node_name(it))
	_, matched := ctx.pf_matched_context_options(node_names, matched_ast_selectors)!
	options := pf_complete(matched, defaults, settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, [], [])!
	pf_validate_newlines_and_partition_config(options)!
	if !pf_can_report_errors(options, pf_default_comparator_computer, ids) {
		return
	}
	mut formatted_members := [][]PfSortingNode{len: 1}
	for attribute in attributes {
		name := ctx.pfie_node_name(attribute)
		group := pf_compute_group(options, [], PfElement{
			name: name
		})!
		mut last_node := ?int(none)
		last_part := formatted_members.last()
		if last_part.len > 0 {
			last_node = last_part.last().node
		}
		if ctx.pf_should_partition(options, last_node, attribute, '')! {
			formatted_members << []PfSortingNode{}
		}
		formatted_members[formatted_members.len - 1] << PfSortingNode{
			node:               attribute
			name:               name
			group:              group
			size:               ctx.pf_range_to_diff(attribute)
			is_eslint_disabled: ctx.pf_is_node_eslint_disabled(attribute)
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
