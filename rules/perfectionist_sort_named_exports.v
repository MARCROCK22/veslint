module rules

import time

// Port of the `perfectionist/sort-named-exports` rule of eslint-plugin-perfectionist 5.13.0 (with
// rules/sort-named-exports/): the specifiers of an export sorted by their names with the shared engine
// (perfectionist_utils*.v, perfectionist_sort_named_imports_or_exports.v), with all its options
// (ignoreAlias, the `export` selector and the `value` and `type` modifiers), the
// `perfectionist` settings and the fixes.

const pfsne_messages = {
	'unexpectedNamedExportsOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedNamedExportsGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenNamedExports':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenNamedExports': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsne_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenNamedExports'
	extra_spacing:          'extraSpacingBetweenNamedExports'
	unexpected_group_order: 'unexpectedNamedExportsGroupOrder'
	unexpected_order:       'unexpectedNamedExportsOrder'
}

fn (mut c Checker) lint_perfectionist_sort_named_exports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_named_exports)
	ctx.pf_sorters([.export_named_declaration], fn (mut ctx PfContext, node int, matched []string) ! {
		t := ctx.t
		specifiers := t.list(node, .specifiers) or { []int{} }
		ctx.pfne_sort(specifiers, matched, false, pfsne_message_ids)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}
