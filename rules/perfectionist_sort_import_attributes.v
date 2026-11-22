module rules

import time

// Port of the `perfectionist/sort-import-attributes` rule of eslint-plugin-perfectionist 5.13.0: the
// attributes of an ImportDeclaration (`with { … }`) sorted by their keys with the shared engine
// (perfectionist_utils*.v, perfectionist_sort_import_or_export_attributes.v), with all its
// options, the `perfectionist` settings and the fixes.

const pfsia_messages = {
	'unexpectedImportAttributesOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedImportAttributesGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenImportAttributes':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenImportAttributes': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsia_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenImportAttributes'
	extra_spacing:          'extraSpacingBetweenImportAttributes'
	unexpected_group_order: 'unexpectedImportAttributesGroupOrder'
	unexpected_order:       'unexpectedImportAttributesOrder'
}

fn (mut c Checker) lint_perfectionist_sort_import_attributes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_import_attributes)
	ctx.pf_sorters([.import_declaration], fn (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfie_sort(node, matched, pf_decode_defaults(pfie_default_options), pfsia_message_ids)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}
