module rules

import json2
import time
import treesitter { Ident }

// Port of the `perfectionist/sort-switch-case` rule of eslint-plugin-perfectionist 5.13.0 (with
// rules/sort-switch-case/): in a switch without conditions, the tests of the cases that fall
// through to the same code sorted, the default case last of those, and the blocks of cases that
// end with a break or a return sorted (the default one last), with the shared engine
// (perfectionist_utils*.v), all its options, the `perfectionist` settings and the fixes.

const pfsw_messages = {
	'unexpectedSwitchCaseOrder': 'Expected "{{right}}" to come before "{{left}}".'
}

const pfsw_order_error_id = 'unexpectedSwitchCaseOrder'

const pfsw_default_options = '{"fallbackSort":{"type":"unsorted"},"specialCharacters":"keep","type":"alphabetical","ignoreCase":true,"locales":"en-US","alphabet":"","order":"asc"}'

fn (mut c Checker) lint_perfectionist_sort_switch_case(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_switch_case)
	// The `SwitchStatement` listener: when the traversal enters the node.
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .switch_statement {
			continue
		}
		ctx.pfsw_sort_switch(step.node)!
	}
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// pfsw_is_condition_expression ports isConditionExpression: a logical or binary expression, a
// `!`, or a boolean literal.
fn (ctx &PfContext) pfsw_is_condition_expression(node int) bool {
	t := ctx.t
	return match t.typ(node) {
		.logical_expression, .binary_expression {
			true
		}
		.unary_expression {
			(t.string_of(node, .operator) or { '' }) == '!'
		}
		.literal {
			t.get(node, .value) is bool
		}
		else {
			false
		}
	}
}

// pfsw_case_name ports getCaseName: String(value) of a literal test, `default` without a test,
// or the text of the test.
fn (ctx &PfContext) pfsw_case_name(case_node int) string {
	t := ctx.t
	test := t.node(case_node, .test) or { return 'default' }
	if t.typ(test) == .literal {
		return pf_literal_string(t, test)
	}
	return ctx.text(test)
}

// pfsw_case_has_break_or_return ports caseHasBreakOrReturn: a break or a return among the
// statements of the case (or of the block it starts with).
fn (ctx &PfContext) pfsw_case_has_break_or_return(case_node int) bool {
	t := ctx.t
	consequent := t.list(case_node, .consequent) or { []int{} }
	statements := if consequent.len > 0 && t.typ(consequent[0]) == .block_statement {
		t.list(consequent[0], .body) or { []int{} }
	} else {
		consequent
	}
	return statements.any(t.typ(it) in [.break_statement, .return_statement])
}

// pfsw_reduce_case_sorting_nodes ports reduceCaseSortingNodes: the cases in blocks, a block ending
// with a case for which `ends_block` holds (but the last case).
fn pfsw_reduce_case_sorting_nodes(case_nodes []PfSortingNode, ends_block []bool) [][]PfSortingNode {
	mut out := [][]PfSortingNode{len: 1}
	for index, case_node in case_nodes {
		out[out.len - 1] << case_node
		if ends_block[index] && index != case_nodes.len - 1 {
			out << []PfSortingNode{}
		}
	}
	return out
}

// pfsw_report reports `unexpectedSwitchCaseOrder` on a node, with the names as they are (or as
// toSingleLine gives them, for reportErrors) and the fix.
fn (mut ctx PfContext) pfsw_report(node int, left string, right string, has_fix bool, fix Fix) {
	ctx.findings << Finding{
		stmt:       Ident{
			start_byte: ctx.t.nodes[node].start
			end_byte:   ctx.t.nodes[node].end
		}
		message_id: pfsw_order_error_id
		data:       {
			'left':  left
			'right': right
		}
		has_fix:    has_fix
		fix:        fix
	}
}

// pfsw_sort_switch ports the `SwitchStatement` listener.
fn (mut ctx PfContext) pfsw_sort_switch(switch_node int) ! {
	t := ctx.t
	cases := t.list(switch_node, .cases) or { []int{} }
	// isSortable: more than one.
	if cases.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	first_option := if ctx.options.len > 0 && ctx.options[0] is map[string]json2.Any {
		ctx.options[0].as_map()
	} else {
		map[string]json2.Any{}
	}
	options := pf_complete(first_option, pf_decode_defaults(pfsw_default_options), settings)!
	pf_validate_custom_sort_config(options)!
	discriminant := t.node(switch_node, .discriminant) or { -1 }
	if discriminant >= 0 && ctx.pfsw_is_condition_expression(discriminant) {
		return
	}
	for case_node in cases {
		if test := t.node(case_node, .test) {
			if ctx.pfsw_is_condition_expression(test) {
				return
			}
		}
	}
	// The tests of the cases that fall through to the same code.
	mut case_name_groups := [][]PfSortingNode{len: 1}
	for index, case_node in cases {
		if test := t.node(case_node, .test) {
			case_name_groups[case_name_groups.len - 1] << PfSortingNode{
				node:         test
				name:         ctx.pfsw_case_name(case_node)
				group:        'unknown'
				size:         ctx.pf_range_to_diff(test)
				partition_id: case_name_groups.len
			}
		}
		consequent := t.list(case_node, .consequent) or { []int{} }
		if consequent.len > 0 && index != cases.len - 1 {
			case_name_groups << []PfSortingNode{}
		}
	}
	no_options := map[string]json2.Any{}
	mut has_unsorted_nodes := false
	for group in case_name_groups {
		sorted := pf_sort_nodes(group, pf_default_comparator_computer, options, false, [])
		for index, node in sorted {
			if node.node != group[index].node {
				has_unsorted_nodes = true
			}
		}
		mut index_of := map[int]int{}
		for index, node in sorted {
			index_of[node.node] = index
		}
		mut fix_done := false
		mut has_fix := false
		mut fix := Fix{}
		for i := 1; i < group.len; i++ {
			left := group[i - 1]
			right := group[i]
			if index_of[left.node] < index_of[right.node] {
				continue
			}
			if !fix_done {
				has_fix, fix = ctx.pf_merge_fixes(ctx.pf_make_fixes(group, sorted, no_options, false,
					false))!
				fix_done = true
			}
			ctx.pfsw_report(right.node, pf_to_single_line(left.name), pf_to_single_line(right.name),
				has_fix, fix)
		}
	}
	sorting_nodes := cases.map(PfSortingNode{
		node:                             it
		name:                             ctx.pfsw_case_name(it)
		group:                            'unknown'
		size:                             if test := t.node(it, .test) {
			ctx.pf_range_to_diff(test)
		} else {
			'default'.len
		}
		add_safety_semicolon_when_inline: true
	})
	is_default := cases.map((t.node(it, .test) or { -1 }) < 0)
	// The default case last of the cases that fall through to the same code.
	has_consequent := cases.map((t.list(it, .consequent) or { []int{} }).len > 0)
	mut offset := 0
	for group in pfsw_reduce_case_sorting_nodes(sorting_nodes, has_consequent) {
		group_start := offset
		offset += group.len
		default_index := is_default[group_start..offset].index(true)
		if default_index < 0 {
			continue
		}
		if !is_default[offset - 1] {
			default_case := group[default_index]
			last_case := group.last()
			last_test := t.node(last_case.node, .test) or { break }
			punctuator := ctx.tokens.after(t.nodes[last_test].end, false) or { break }
			last_start := t.nodes[last_case.node].start
			default_start := t.nodes[default_case.node].start
			default_end := t.nodes[default_case.node].end
			mut fixes := [
				fix_replace_range(default_start, default_end, ctx.src[last_start..punctuator.end]),
				fix_replace_range(last_start, punctuator.end, ctx.text(default_case.node)),
			]
			fixes << ctx.pf_make_single_node_comment_after_fixes(default_start, default_end,
				punctuator.end)
			fixes << ctx.pf_make_single_node_comment_after_fixes(punctuator.start, punctuator.end,
				default_end)
			has_fix, fix := ctx.pf_merge_fixes(fixes)!
			ctx.pfsw_report(default_case.node, default_case.name, last_case.name, has_fix,
				fix)
		}
		// find: the first group with the default case.
		break
	}
	// The blocks of cases that end with a break or a return.
	ends_with_break := cases.map(ctx.pfsw_case_has_break_or_return(it))
	case_blocks := pfsw_reduce_case_sorting_nodes(sorting_nodes, ends_with_break)
	mut blocks := []PfSortingNode{}
	mut default_blocks := map[int]bool{}
	offset = 0
	for block in case_blocks {
		if is_default[offset..offset + block.len].any(it) {
			default_blocks[block[0].node] = true
		}
		offset += block.len
		blocks << block[0]
	}
	last_block := case_blocks.last()
	last_block_to_keep_in_place := if ctx.pfsw_case_has_break_or_return(last_block.last().node) {
		-1
	} else {
		last_block[0].node
	}
	// buildCaseBlockComparatorByOptionsComputer: the block to keep in place last, then the
	// block of the default case, the others by the comparator of the options (without their
	// fallbackSort: the computer ignores the options it is given).
	main := pf_default_comparator_computer(options)
	comparator := PfComparator{
		cmp: fn [last_block_to_keep_in_place, default_blocks, main] (a &PfSortingNode, b &PfSortingNode) int {
			if a.node == last_block_to_keep_in_place {
				return 1
			}
			if b.node == last_block_to_keep_in_place {
				return -1
			}
			if a.node in default_blocks {
				return 1
			}
			if b.node in default_blocks {
				return -1
			}
			if main.unsorted {
				return 0
			}
			return main.cmp(a, b)
		}
	}
	sorted_blocks := pf_stable_sort(blocks, [comparator])
	mut block_index := map[int]int{}
	for index, block in sorted_blocks {
		block_index[block.node] = index
	}
	mut cases_of_block := map[int][]PfSortingNode{}
	for block in case_blocks {
		cases_of_block[block[0].node] = block
	}
	mut sorted_cases := []PfSortingNode{}
	for block in sorted_blocks {
		sorted_cases << cases_of_block[block.node]
	}
	mut fix_done := false
	mut has_fix := false
	mut fix := Fix{}
	for i := 1; i < case_blocks.len; i++ {
		left_block := case_blocks[i - 1]
		right_block := case_blocks[i]
		if block_index[left_block[0].node] < block_index[right_block[0].node] {
			continue
		}
		left := left_block.last()
		right := right_block[0]
		// Raise errors but only sort on second iteration.
		if !has_unsorted_nodes && !fix_done {
			has_fix, fix = ctx.pf_merge_fixes(ctx.pf_make_fixes(sorting_nodes, sorted_cases,
				no_options, false, false))!
			fix_done = true
		}
		ctx.pfsw_report(right.node, left.name, right.name, has_fix, fix)
	}
}
