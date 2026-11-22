module rules

import json2
import time

// Port of the `perfectionist/sort-exports` rule of eslint-plugin-perfectionist 5.13.0: the
// exports with a source (`export … from '…'`, `export * from '…'`) of a file sorted by their
// sources with the shared engine (perfectionist_utils*.v), with the `export` selector, the
// `value`/`type`, `named`/`wildcard` and `singleline`/`multiline` modifiers, all its options
// (with the comments above the groups), the `perfectionist` settings and the fixes.

const pfsx_messages = {
	'missedCommentAboveExport':    'Missed comment "{{missedCommentAbove}}" above "{{right}}".'
	'missedSpacingBetweenExports': 'Missed spacing between "{{left}}" and "{{right}}".'
	'extraSpacingBetweenExports':  'Extra spacing between "{{left}}" and "{{right}}".'
	'unexpectedExportsGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'unexpectedExportsOrder':      'Expected "{{right}}" to come before "{{left}}".'
}

const pfsx_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenExports'
	extra_spacing:          'extraSpacingBetweenExports'
	missed_comment_above:   'missedCommentAboveExport'
	unexpected_group_order: 'unexpectedExportsGroupOrder'
	unexpected_order:       'unexpectedExportsOrder'
}

const pfsx_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","partitionByComment":false,"newlinesBetween":"ignore","partitionByNewLine":false,"type":"alphabetical","customGroups":[],"ignoreCase":true,"locales":"en-US","alphabet":"","order":"asc","groups":[]}'

const pfsx_all_modifiers = ['value', 'type', 'named', 'wildcard', 'multiline', 'singleline']

fn (mut c Checker) lint_perfectionist_sort_exports(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_exports)
	ctx.pfsx_sort_exports()!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// pfsx_sort_exports ports the rule's `create`: the options, checked once for the file, the
// exports registered as the traversal enters them, and sortExportNodes at `Program:exit`.
fn (mut ctx PfContext) pfsx_sort_exports() ! {
	t := ctx.t
	settings := pf_get_settings(ctx.settings)!
	first_option := if ctx.options.len > 0 && ctx.options[0] is map[string]json2.Any {
		ctx.options[0].as_map()
	} else {
		map[string]json2.Any{}
	}
	options := pf_complete(first_option, pf_decode_defaults(pfsx_default_options), settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, ['export'], pfsx_all_modifiers)!
	pf_validate_newlines_and_partition_config(options)!
	mut formatted_members := [][]PfSortingNode{len: 1}
	for step in t.steps() {
		if step.leave || t.typ(step.node) !in [.export_named_declaration, .export_all_declaration] {
			continue
		}
		node := step.node
		// registerNode: only the exports with a source.
		source := t.node(node, .source) or { continue }
		kind := t.string_of(node, .export_kind) or { 'value' }
		modifiers := [
			if kind == 'type' { 'type' } else { 'value' },
			if t.typ(node) == .export_named_declaration { 'named' } else { 'wildcard' },
			if ctx.start_line(node) == ctx.end_line(node) { 'singleline' } else { 'multiline' },
		]
		name := pf_literal_string(t, source)
		group := pf_compute_group(options, pf_generate_predefined_groups(['export'], modifiers),
			PfElement{
				name:      name
				selectors: ['export']
				modifiers: modifiers
			})!
		mut last_node := ?int(none)
		last_part := formatted_members.last()
		if last_part.len > 0 {
			last_node = last_part.last().node
		}
		if ctx.pf_should_partition(options, last_node, node, '')! {
			formatted_members << []PfSortingNode{}
		}
		formatted_members[formatted_members.len - 1] << PfSortingNode{
			node:                             node
			name:                             name
			group:                            group
			size:                             ctx.pf_range_to_diff(node)
			is_eslint_disabled:               ctx.pf_is_node_eslint_disabled(node)
			add_safety_semicolon_when_inline: true
			partition_id:                     formatted_members.len
		}
	}
	// sortExportNodes.
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
	ctx.pf_report_all_errors(nodes, sorted, sorted_excluding_disabled, options, pfsx_message_ids)!
}
