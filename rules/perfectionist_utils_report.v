module rules

import json2
import jsregexp
import treesitter { Ident }

// reportAllErrors and makeFixes of eslint-plugin-perfectionist 5.13.0 with what
// pf_report_all_errors and pf_make_fixes (perfectionist_utils.v) leave out: the dependencies
// (unexpectedDependencyOrder), a newlinesBetweenValueGetter (the overload signatures), the
// comments above groups (getCommentAboveThatShouldExist, makeCommentAboveFixes) and
// ignoreFirstNodeHighestBlockComment; and sortNodesByGroups with isNodeIgnored and
// isNodeIgnoredForGroup.

// PfNewlinesGetter ports NewlinesBetweenValueGetter: the lines between two nodes, from the ones the
// options give (pf_ignore for 'ignore').
type PfNewlinesGetter = fn (computed f64, left PfSortingNode, right PfSortingNode) f64

// PfReportExtras are the parameters of reportAllErrors that pf_report_all_errors does not take.
struct PfReportExtras {
	dependencies                            PfDependencies
	newlines_getter                         PfNewlinesGetter = unsafe { nil }
	ignore_first_node_highest_block_comment bool
}

// pf_report_all_errors_full ports reportAllErrors: `sorted` and `sorted_excluding_disabled` are
// what sortNodesExcludingEslintDisabled gives with false and with true.
fn (mut ctx PfContext) pf_report_all_errors_full(nodes []PfSortingNode, sorted []PfSortingNode, sorted_excluding_disabled []PfSortingNode, options map[string]json2.Any, ids PfMessageIds, extras PfReportExtras) ! {
	groups := pf_opt_list(options, 'groups')
	mut index_of := map[int]int{}
	for index, node in sorted {
		index_of[node.node] = index
	}
	circular := if ids.unexpected_dependency_order != '' {
		extras.dependencies.pf_nodes_in_circular_dependencies(nodes)
	} else {
		map[int]bool{}
	}
	sorted_excluding_disabled_nodes := sorted_excluding_disabled.map(it.node)
	// The fixes, made once for each value of hasCommentAboveMissing (createFixProvider).
	mut fix_done := [false, false]
	mut has_fix := [false, false]
	mut fixes := [Fix{}, Fix{}]
	for i, right in nodes {
		mut message_ids := []string{}
		right_group_index := pf_get_group_index(groups, right.group)
		right_index := index_of[right.node] or { 0 }
		index_of_right_excluding_disabled := sorted_excluding_disabled_nodes.index(right.node)
		mut first_unordered := ?PfSortingNode(none)
		if ids.unexpected_dependency_order != '' {
			first_unordered = extras.dependencies.pf_first_unordered_node_dependent_on(right,
				nodes, circular)
		}
		mut left_group_index := ?int(none)
		if i > 0 {
			left := nodes[i - 1]
			current_left_group_index := pf_get_group_index(groups, left.group)
			left_group_index = current_left_group_index
			left_index := index_of[left.node] or { 0 }
			if first_unordered != none || left_index > right_index
				|| (left.is_eslint_disabled && left_index >= index_of_right_excluding_disabled) {
				if first_unordered != none {
					message_ids << ids.unexpected_dependency_order
				} else {
					message_ids << if current_left_group_index == right_group_index
						|| ids.unexpected_group_order == '' {
						ids.unexpected_order
					} else {
						ids.unexpected_group_order
					}
				}
			}
			if ids.missed_spacing != '' && ids.extra_spacing != '' {
				message_ids << ctx.pf_newlines_between_errors_with_getter(options, left, right,
					current_left_group_index, right_group_index, ids, extras.newlines_getter)
			}
		}
		mut comment_above_missing := ?string(none)
		if ids.missed_comment_above != '' {
			if comment_above := ctx.pf_comment_above_that_should_exist(options, left_group_index,
				right_group_index, right.node)
			{
				if !comment_above.exists {
					comment_above_missing = comment_above.comment
					message_ids << ids.missed_comment_above
				}
			}
		}
		if message_ids.len == 0 {
			continue
		}
		has_comment_above_missing := comment_above_missing != none
		cache := if has_comment_above_missing { 1 } else { 0 }
		if !fix_done[cache] {
			has_fix[cache], fixes[cache] = ctx.pf_merge_fixes(ctx.pf_make_fixes_full(nodes,
				sorted_excluding_disabled, options, extras, has_comment_above_missing))!
			fix_done[cache] = true
		}
		for message_id in message_ids {
			mut data := {
				'left':       if i > 0 { pf_to_single_line(nodes[i - 1].name) } else { '' }
				'right':      pf_to_single_line(right.name)
				'rightGroup': right.group
			}
			if i > 0 {
				data['leftGroup'] = nodes[i - 1].group
			}
			if dependent := first_unordered {
				data['nodeDependentOnRight'] = dependent.name
			}
			if comment := comment_above_missing {
				data['missedCommentAbove'] = comment
			}
			ctx.findings << Finding{
				stmt:       Ident{
					start_byte: ctx.t.nodes[right.node].start
					end_byte:   ctx.t.nodes[right.node].end
				}
				message_id: message_id
				data:       data
				has_fix:    has_fix[cache]
				fix:        fixes[cache]
			}
		}
	}
}

// pf_newlines_between_errors_with_getter ports getNewlinesBetweenErrors with a
// newlinesBetweenValueGetter.
fn (ctx &PfContext) pf_newlines_between_errors_with_getter(options map[string]json2.Any, left PfSortingNode, right PfSortingNode, left_group_index int, right_group_index int, ids PfMessageIds, getter PfNewlinesGetter) []string {
	if left_group_index > right_group_index || left.partition_id != right.partition_id {
		return []string{}
	}
	mut newlines_between := pf_get_newlines_between_option(options, left_group_index,
		right_group_index)
	if getter != unsafe { nil } {
		newlines_between = getter(newlines_between, left, right)
	}
	if newlines_between == pf_ignore {
		return []string{}
	}
	lines := f64(ctx.pf_lines_between(left.node, right.node))
	if lines < newlines_between {
		return [ids.missed_spacing]
	}
	if lines > newlines_between {
		return [ids.extra_spacing]
	}
	return []string{}
}

// pf_make_fixes_full ports makeFixes.
fn (ctx &PfContext) pf_make_fixes_full(nodes []PfSortingNode, sorted []PfSortingNode, options map[string]json2.Any, extras PfReportExtras, has_comment_above_missing bool) []Fix {
	order_fixes := ctx.pf_make_order_fixes(nodes, sorted, options, extras.ignore_first_node_highest_block_comment)
	comment_after_fixes := ctx.pf_make_comment_after_fixes(nodes, sorted)
	if comment_after_fixes.len > 0 {
		mut out := order_fixes.clone()
		out << comment_after_fixes
		return out
	}
	if 'groups' in options {
		newlines_fixes := ctx.pf_make_newlines_between_fixes_with_getter(nodes, sorted, options,
			extras.newlines_getter)
		if newlines_fixes.len > 0 {
			mut out := order_fixes.clone()
			out << newlines_fixes
			return out
		}
	}
	if order_fixes.len > 0 {
		return order_fixes
	}
	if !has_comment_above_missing || 'groups' !in options {
		return []Fix{}
	}
	return ctx.pf_make_comment_above_fixes(sorted, options)
}

// pf_make_newlines_between_fixes_with_getter ports makeNewlinesBetweenFixes with a
// newlinesBetweenValueGetter.
fn (ctx &PfContext) pf_make_newlines_between_fixes_with_getter(nodes []PfSortingNode, sorted []PfSortingNode, options map[string]json2.Any, getter PfNewlinesGetter) []Fix {
	mut fixes := []Fix{}
	groups := pf_opt_list(options, 'groups')
	for i := 0; i < sorted.len - 1; i++ {
		sorting_node := nodes[i]
		next_sorting_node := nodes[i + 1]
		sorted_sorting_node := sorted[i]
		next_sorted_sorting_node := sorted[i + 1]
		if sorted_sorting_node.partition_id != next_sorted_sorting_node.partition_id {
			continue
		}
		node_group_index := pf_get_group_index(groups, sorted_sorting_node.group)
		next_node_group_index := pf_get_group_index(groups, next_sorted_sorting_node.group)
		if node_group_index > next_node_group_index {
			continue
		}
		mut newlines_between := pf_get_newlines_between_option(options, node_group_index,
			next_node_group_index)
		if getter != unsafe { nil } {
			newlines_between = getter(newlines_between, sorted_sorting_node, next_sorted_sorting_node)
		}
		if newlines_between == pf_ignore {
			continue
		}
		_, current_end := ctx.pf_get_node_range(sorting_node.node, map[string]json2.Any{},
			false, PfSortingNode{ node: -1 })
		next_start, _ := ctx.pf_get_node_range(next_sorting_node.node, map[string]json2.Any{},
			false, PfSortingNode{ node: -1 })
		lines_between := ctx.pf_lines_between(sorting_node.node, next_sorting_node.node)
		if f64(lines_between) == newlines_between {
			continue
		}
		text_between := ctx.src[current_end..next_start]
		is_on_same_line := ctx.end_line(sorting_node.node) == ctx.start_line(next_sorting_node.node)
		fixes << fix_replace_range(current_end, next_start, pf_range_replacement(text_between,
			newlines_between, is_on_same_line))
	}
	return fixes
}

// --- Comments above groups ---------------------------------------------------------------------

// PfCommentAbove ports the result of getCommentAboveThatShouldExist.
struct PfCommentAbove {
	comment string
	exists  bool
}

// pf_comment_above_that_should_exist ports getCommentAboveThatShouldExist: the `commentAbove` of
// the group of the node when the node starts that group (`left_group_index` is none for the
// first node), and whether a comment above the node has it.
fn (ctx &PfContext) pf_comment_above_that_should_exist(options map[string]json2.Any, left_group_index ?int, right_group_index int, node int) ?PfCommentAbove {
	if left := left_group_index {
		if left >= right_group_index {
			return none
		}
	}
	groups := pf_opt_list(options, 'groups')
	if right_group_index < 0 || right_group_index >= groups.len {
		return none
	}
	right_group := groups[right_group_index]
	if !pf_is_group_with_overrides_option(right_group) {
		return none
	}
	comment_above := right_group.as_map()['commentAbove'] or { return none }
	if !pf_truthy(comment_above) {
		return none
	}
	expected := comment_above.str()
	mut exists := false
	for comment in ctx.pf_get_comments_before(node, '') {
		if pf_comment_matches(ctx.pf_comment_value(comment), expected) {
			exists = true
			break
		}
	}
	return PfCommentAbove{
		comment: expected
		exists:  exists
	}
}

// pf_comment_matches ports commentMatches: the comment has the expected text, ignoring case.
fn pf_comment_matches(comment string, expected string) bool {
	lower_comment := stv_units_string(jsregexp.js_to_lower(utf16_units(comment)))
	lower_expected := js_trim(stv_units_string(jsregexp.js_to_lower(utf16_units(expected))))
	return lower_comment.contains(lower_expected)
}

// pf_make_comment_above_fixes ports makeCommentAboveFixes.
fn (ctx &PfContext) pf_make_comment_above_fixes(sorted []PfSortingNode, options map[string]json2.Any) []Fix {
	mut all_auto_added_comments := []string{}
	for group in pf_opt_list(options, 'groups') {
		if !pf_is_group_with_overrides_option(group) {
			continue
		}
		if comment := group.as_map()['commentAbove'] {
			if comment is string {
				all_auto_added_comments << comment
			}
		}
	}
	mut fixes := []Fix{}
	if sorted.len == 0 {
		return fixes
	}
	fixes << ctx.pf_make_comment_above_fix(none, sorted[0], all_auto_added_comments, options)
	for i := 0; i < sorted.len - 1; i++ {
		fixes << ctx.pf_make_comment_above_fix(sorted[i], sorted[i + 1], all_auto_added_comments,
			options)
	}
	return fixes
}

fn (ctx &PfContext) pf_make_comment_above_fix(sorted_sorting_node ?PfSortingNode, next_sorted_sorting_node PfSortingNode, all_auto_added_comments []string, options map[string]json2.Any) []Fix {
	groups := pf_opt_list(options, 'groups')
	left_group_index := if node := sorted_sorting_node {
		pf_get_group_index(groups, node.group)
	} else {
		-1
	}
	right_group_index := pf_get_group_index(groups, next_sorted_sorting_node.group)
	comment_above := ctx.pf_comment_above_that_should_exist(options, left_group_index,
		right_group_index, next_sorted_sorting_node.node)
	comments_before := ctx.pf_get_comments_before(next_sorted_sorting_node.node, '')
	mut fixes := []Fix{}
	for comment in comments_before {
		value := pf_slice_first_unit(ctx.pf_comment_value(comment))
		if expected := comment_above {
			if expected.comment != '' && value == expected.comment {
				continue
			}
		}
		if comment.kind != .line_comment || value !in all_auto_added_comments {
			continue
		}
		next_token := ctx.tokens.after(comment.end, false) or { continue }
		fixes << fix_replace_range(comment.start, next_token.start, '')
	}
	if expected := comment_above {
		if !expected.exists {
			node := next_sorted_sorting_node.node
			is_first_token := ctx.tokens.before(ctx.t.nodes[node].start, false) == none
			start := if is_first_token || comments_before.len == 0 {
				ctx.t.nodes[node].start
			} else {
				comments_before[0].start
			}
			fixes << fix_replace_range(start, start, '// ${expected.comment}\n')
		}
	}
	return fixes
}

// pf_slice_first_unit is `value.slice(1)`.
fn pf_slice_first_unit(value string) string {
	units := utf16_units(value)
	if units.len == 0 {
		return ''
	}
	return stv_units_string(units[1..])
}

// --- Sort by groups ----------------------------------------------------------------------------

// PfNodeIgnored ports the isNodeIgnored of sortNodesByGroups; PfNodeIgnoredForGroup its
// isNodeIgnoredForGroup.
type PfNodeIgnored = fn (node PfSortingNode) bool

type PfNodeIgnoredForGroup = fn (group_options map[string]json2.Any, group_index int, node PfSortingNode) bool

// pf_sort_nodes_by_groups_with ports sortNodesByGroups with isNodeIgnored and
// isNodeIgnoredForGroup (nil when not given).
fn pf_sort_nodes_by_groups_with(nodes []PfSortingNode, computer PfComparatorComputer, options map[string]json2.Any, ignore_eslint_disabled bool, is_node_ignored PfNodeIgnored, is_node_ignored_for_group PfNodeIgnoredForGroup) []PfSortingNode {
	groups := pf_opt_list(options, 'groups')
	mut by_group := map[int][]PfSortingNode{}
	mut ignored_indices := []int{}
	for index, node in nodes {
		if (ignore_eslint_disabled && node.is_eslint_disabled)
			|| (is_node_ignored != unsafe { nil } && is_node_ignored(node)) {
			ignored_indices << index
			continue
		}
		group_index := pf_get_group_index(groups, node.group)
		by_group[group_index] << node
	}
	mut indexes := by_group.keys()
	indexes.sort()
	mut sorted := []PfSortingNode{}
	for group_index in indexes {
		group_options := pf_overridden_options_by_group_index(options, group_index)
		nodes_to_push := by_group[group_index]
		mut group_ignored := []int{}
		if is_node_ignored_for_group != unsafe { nil } {
			for node in nodes_to_push {
				if is_node_ignored_for_group(group_options, group_index, node) {
					group_ignored << node.node
				}
			}
		}
		sorted << pf_sort_nodes(nodes_to_push, computer, group_options, false, group_ignored)
	}
	for index in ignored_indices {
		sorted.insert(if index <= sorted.len { index } else { sorted.len }, nodes[index])
	}
	return sorted
}
