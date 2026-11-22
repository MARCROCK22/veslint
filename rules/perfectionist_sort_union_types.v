module rules

import time

// Port of the `perfectionist/sort-union-types` rule of eslint-plugin-perfectionist 5.13.0: the
// types of a union sorted with the shared engine (perfectionist_utils*.v,
// perfectionist_sort_union_or_intersection_types.v), with all its options, the `perfectionist`
// settings and the fixes.

const pfsut_messages = {
	'unexpectedUnionTypesOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedUnionTypesGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenUnionTypes':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenUnionTypes': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsut_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenUnionTypes'
	extra_spacing:          'extraSpacingBetweenUnionTypes'
	unexpected_group_order: 'unexpectedUnionTypesGroupOrder'
	unexpected_order:       'unexpectedUnionTypesOrder'
}

// The rule's defaultOptions, with `ignoreCallableTypes: false` (what it gives the shared sort).
const pfsut_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","newlinesBetween":"ignore","partitionByNewLine":false,"partitionByComment":false,"useConfigurationIf":{},"type":"alphabetical","ignoreCase":true,"locales":"en-US","customGroups":[],"alphabet":"","order":"asc","groups":[],"ignoreCallableTypes":false}'

fn (mut c Checker) lint_perfectionist_sort_union_types(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_union_types)
	ctx.pf_sorters([.ts_union_type], fn (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfuo_sort(node, matched, pf_decode_defaults(pfsut_default_options), pfsut_message_ids,
			'|')!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}
