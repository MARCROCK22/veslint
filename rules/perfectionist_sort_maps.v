module rules

import time

// Port of the `perfectionist/sort-maps` rule of eslint-plugin-perfectionist 5.13.0 (with
// rules/sort-maps/): the entries of the array a `new Map(…)` is made from, sorted by their keys
// with the shared engine (perfectionist_utils*.v), in parts that holes and spread elements end,
// with all its options, the `perfectionist` settings and the fixes.

const pfsm_messages = {
	'unexpectedMapElementsOrder':             'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedMapElementsGroupOrder':        'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenMapElementsMembers':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenMapElementsMembers': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsm_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenMapElementsMembers'
	extra_spacing:          'extraSpacingBetweenMapElementsMembers'
	unexpected_group_order: 'unexpectedMapElementsGroupOrder'
	unexpected_order:       'unexpectedMapElementsOrder'
}

const pfsm_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","partitionByComment":false,"partitionByNewLine":false,"newlinesBetween":"ignore","useConfigurationIf":{},"type":"alphabetical","ignoreCase":true,"customGroups":[],"locales":"en-US","alphabet":"","order":"asc","groups":[]}'

fn (mut c Checker) lint_perfectionist_sort_maps(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_maps)
	ctx.pf_sorters([.new_expression], fn (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfsm_sort_potential_map(node, matched)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// pfsm_node_name ports computeNodeName of sort-maps: the text of the key of an entry (`raw` of a
// literal), `undefined` without one, or the text of what is not an array.
fn (ctx &PfContext) pfsm_node_name(element int) string {
	t := ctx.t
	if t.typ(element) != .array_expression {
		return ctx.text(element)
	}
	elements := t.list(element, .elements) or { []int{} }
	if elements.len == 0 || elements[0] < 0 {
		return 'undefined'
	}
	return ctx.text(elements[0])
}

// pfsm_sort_potential_map ports sortPotentialMap.
fn (mut ctx PfContext) pfsm_sort_potential_map(node int, matched_ast_selectors []string) ! {
	t := ctx.t
	callee := t.node(node, .callee) or { return }
	arguments := t.list(node, .arguments) or { []int{} }
	if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != 'Map'
		|| arguments.len == 0 || t.typ(arguments[0]) != .array_expression {
		return
	}
	elements := t.list(arguments[0], .elements) or { []int{} }
	if elements.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	mut node_names := []string{}
	for element in elements {
		if element >= 0 && t.typ(element) != .spread_element {
			node_names << ctx.pfsm_node_name(element)
		}
	}
	_, matched := ctx.pf_matched_context_options(node_names, matched_ast_selectors)!
	options := pf_complete(matched, pf_decode_defaults(pfsm_default_options), settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, [], [])!
	pf_validate_newlines_and_partition_config(options)!
	if !pf_can_report_errors(options, pf_default_comparator_computer, pfsm_message_ids) {
		return
	}
	// The parts the holes and the spread elements end.
	mut parts := [][]int{len: 1}
	for element in elements {
		if element < 0 || t.typ(element) == .spread_element {
			parts << []int{}
		} else {
			parts[parts.len - 1] << element
		}
	}
	for part in parts {
		mut formatted_members := [][]PfSortingNode{len: 1}
		for element in part {
			name := ctx.pfsm_node_name(element)
			mut last_node := ?int(none)
			last_part := formatted_members.last()
			if last_part.len > 0 {
				last_node = last_part.last().node
			}
			group := pf_compute_group(options, [], PfElement{
				name: name
			})!
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
		for nodes in formatted_members {
			sorted := pf_sort_nodes_by_groups(nodes, pf_default_comparator_computer, options,
				false)
			sorted_excluding_disabled := pf_sort_nodes_by_groups(nodes, pf_default_comparator_computer,
				options, true)
			ctx.pf_report_all_errors(nodes, sorted, sorted_excluding_disabled, options, pfsm_message_ids)!
		}
	}
}
