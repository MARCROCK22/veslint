module rules

import time

// Port of the `perfectionist/sort-export-attributes` rule of eslint-plugin-perfectionist 5.13.0: the
// attributes of an ExportNamedDeclaration (`with { … }`) sorted by their keys with the shared engine
// (perfectionist_utils*.v, perfectionist_sort_import_or_export_attributes.v), with all its
// options, the `perfectionist` settings and the fixes.

const pfsea_messages = {
	'unexpectedExportAttributesOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedExportAttributesGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenExportAttributes':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenExportAttributes': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsea_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenExportAttributes'
	extra_spacing:          'extraSpacingBetweenExportAttributes'
	unexpected_group_order: 'unexpectedExportAttributesGroupOrder'
	unexpected_order:       'unexpectedExportAttributesOrder'
}

fn (mut c Checker) lint_perfectionist_sort_export_attributes(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_export_attributes)
	ctx.pf_sorters([.export_named_declaration], fn (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfie_sort(node, matched, pf_decode_defaults(pfie_default_options), pfsea_message_ids)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}
