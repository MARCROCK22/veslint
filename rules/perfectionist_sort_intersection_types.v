module rules

import time

// Port of the `perfectionist/sort-intersection-types` rule of eslint-plugin-perfectionist 5.13.0:
// the types of an intersection sorted with the shared engine (perfectionist_utils*.v,
// perfectionist_sort_union_or_intersection_types.v), with all its options (ignoreCallableTypes,
// true by default, leaves an intersection with a callable type as it is), the `perfectionist`
// settings and the fixes.

const pfsit_messages = {
	'unexpectedIntersectionTypesOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedIntersectionTypesGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenIntersectionTypes':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenIntersectionTypes': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsit_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenIntersectionTypes'
	extra_spacing:          'extraSpacingBetweenIntersectionTypes'
	unexpected_group_order: 'unexpectedIntersectionTypesGroupOrder'
	unexpected_order:       'unexpectedIntersectionTypesOrder'
}

const pfsit_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","ignoreCallableTypes":true,"specialCharacters":"keep","newlinesBetween":"ignore","partitionByComment":false,"partitionByNewLine":false,"useConfigurationIf":{},"type":"alphabetical","ignoreCase":true,"locales":"en-US","customGroups":[],"alphabet":"","order":"asc","groups":[]}'

fn (mut c Checker) lint_perfectionist_sort_intersection_types(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_intersection_types)
	ctx.pf_sorters([.ts_intersection_type], fn (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfuo_sort(node, matched, pf_decode_defaults(pfsit_default_options), pfsit_message_ids,
			'&')!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}
