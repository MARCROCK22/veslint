module rules

import time

// Port of the `perfectionist/sort-named-imports` rule of eslint-plugin-perfectionist 5.13.0 (with
// rules/sort-named-imports/): the named specifiers of an import sorted by their names with the shared engine
// (perfectionist_utils*.v, perfectionist_sort_named_imports_or_exports.v), with all its options
// (ignoreAlias, the `import` selector and the `value` and `type` modifiers), the
// `perfectionist` settings and the fixes.

const pfsni_messages = {
	'unexpectedNamedImportsOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedNamedImportsGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenNamedImports':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenNamedImports': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfsni_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenNamedImports'
	extra_spacing:          'extraSpacingBetweenNamedImports'
	unexpected_group_order: 'unexpectedNamedImportsGroupOrder'
	unexpected_order:       'unexpectedNamedImportsOrder'
}

fn (mut c Checker) lint_perfectionist_sort_named_imports(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_named_imports)
	ctx.pf_sorters([.import_declaration], fn (mut ctx PfContext, node int, matched []string) ! {
		t := ctx.t
		specifiers := (t.list(node, .specifiers) or { []int{} }).filter(t.typ(it) == .import_specifier)
		ctx.pfne_sort(specifiers, matched, true, pfsni_message_ids)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}
