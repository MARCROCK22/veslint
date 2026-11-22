module rules

import time

// Port of the `perfectionist/sort-heritage-clauses` rule of eslint-plugin-perfectionist 5.13.0
// (with rules/sort-heritage-clauses/): the types of the `extends` of an interface and of the
// `implements` of a class declaration sorted by their names with the shared engine
// (perfectionist_utils*.v), with all its options, the `perfectionist` settings and the fixes.

const pfhc_messages = {
	'unexpectedHeritageClausesOrder':      'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedHeritageClausesGroupOrder': 'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenHeritageClauses':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenHeritageClauses': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfhc_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenHeritageClauses'
	extra_spacing:          'extraSpacingBetweenHeritageClauses'
	unexpected_group_order: 'unexpectedHeritageClausesGroupOrder'
	unexpected_order:       'unexpectedHeritageClausesOrder'
}

const pfhc_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","newlinesBetween":"ignore","partitionByNewLine":false,"partitionByComment":false,"useConfigurationIf":{},"type":"alphabetical","ignoreCase":true,"customGroups":[],"locales":"en-US","alphabet":"","order":"asc","groups":[]}'

fn (mut c Checker) lint_perfectionist_sort_heritage_clauses(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_heritage_clauses)
	ctx.pf_sorters([.ts_interface_declaration, .class_declaration], fn (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfhc_sort_heritage_clause(node, matched)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// pfhc_node_name ports computeNodeName of sort-heritage-clauses: the name of the innermost
// property of the expression of a clause (`B` of `A.B`).
fn (ctx &PfContext) pfhc_node_name(clause int) string {
	t := ctx.t
	mut current := t.node(clause, .expression) or { return '' }
	for current >= 0 && t.typ(current) == .member_expression {
		current = t.node(current, .property) or { break }
	}
	if current >= 0 && t.typ(current) == .identifier {
		return t.string_of(current, .name) or { '' }
	}
	return ctx.text(current)
}

// pfhc_sort_heritage_clause ports sortHeritageClause.
fn (mut ctx PfContext) pfhc_sort_heritage_clause(node int, matched_ast_selectors []string) ! {
	t := ctx.t
	heritage_clauses := if t.typ(node) == .ts_interface_declaration {
		t.list(node, .extends_) or { []int{} }
	} else {
		t.list(node, .implements_) or { []int{} }
	}
	// isSortable: more than one.
	if heritage_clauses.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	node_names := heritage_clauses.map(ctx.pfhc_node_name(it))
	_, matched := ctx.pf_matched_context_options(node_names, matched_ast_selectors)!
	options := pf_complete(matched, pf_decode_defaults(pfhc_default_options), settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, [], [])!
	pf_validate_newlines_and_partition_config(options)!
	if !pf_can_report_errors(options, pf_default_comparator_computer, pfhc_message_ids) {
		return
	}
	mut formatted_members := [][]PfSortingNode{len: 1}
	for clause in heritage_clauses {
		name := ctx.pfhc_node_name(clause)
		group := pf_compute_group(options, [], PfElement{
			name: name
		})!
		mut last_node := ?int(none)
		last_part := formatted_members.last()
		if last_part.len > 0 {
			last_node = last_part.last().node
		}
		if ctx.pf_should_partition(options, last_node, clause, '')! {
			formatted_members << []PfSortingNode{}
		}
		formatted_members[formatted_members.len - 1] << PfSortingNode{
			node:               clause
			name:               name
			group:              group
			size:               ctx.pf_range_to_diff(clause)
			is_eslint_disabled: ctx.pf_is_node_eslint_disabled(clause)
			partition_id:       0
		}
	}
	for nodes in formatted_members {
		sorted := pf_sort_nodes_by_groups(nodes, pf_default_comparator_computer, options,
			false)
		sorted_excluding_disabled := pf_sort_nodes_by_groups(nodes, pf_default_comparator_computer,
			options, true)
		ctx.pf_report_all_errors(nodes, sorted, sorted_excluding_disabled, options, pfhc_message_ids)!
	}
}
