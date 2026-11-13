module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_start, position_of }

// Port of the `sort-vars` rule of ESLint 10.6.0.

const svars_messages = {
	'sortVars': 'Variables within the same declaration block should be sorted alphabetically.'
}

fn svars_options(options []json2.Any) !bool {
	o := option_object(sort_vars, options, ['ignoreCase'])!
	return o.bool_value('ignoreCase') or { false }
}

fn (mut c Checker) lint_sort_vars(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignore_case := svars_options(c.rule_options(sort_vars))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['variable_declaration', 'lexical_declaration'], []) {
		stats.checked++
		mut declarations := []C.TSNode{}
		mut sortable := [][]u16{}
		mut unfixable := false
		for declarator in named_children(node) {
			if node_kind(declarator) != 'variable_declarator' {
				continue
			}
			id := node_field(declarator, 'name') or { continue }
			if node_kind(id) !in ['identifier', 'undefined'] {
				continue
			}
			declarations << declarator
			units := utf16_units(c.identifier_name(id))
			sortable << if ignore_case { js_to_lower(units) } else { units }
			if init := node_field(declarator, 'value') {
				if node_kind(unwrap_parens(init)) !in literal_kinds {
					unfixable = true
				}
			}
		}
		if declarations.len < 2 {
			continue
		}
		mut fixed := false
		mut memo := 0
		for i in 1 .. declarations.len {
			if !units_less(sortable[i], sortable[memo]) {
				memo = i
				continue
			}
			has_fix := !unfixable && !fixed
			findings << Finding{
				stmt:       position_of(declarations[i])
				message_id: 'sortVars'
				has_fix:    has_fix
				fix:        if has_fix {
					c.svars_fix(declarations, sortable)
				} else {
					Fix{}
				}
			}
			fixed = true
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// svars_fix puts the declarators in order, each with the text that followed the one in its place.
fn (c &Checker) svars_fix(declarations []C.TSNode, sortable [][]u16) Fix {
	order := svars_sort(sortable)
	mut text := ''
	for index, i in order {
		text += c.text(declarations[i])
		if index < declarations.len - 1 {
			text += c.src[node_end(declarations[index])..node_start(declarations[index + 1])]
		}
	}
	return Fix{node_start(declarations[0]), node_end(declarations.last()), text}
}

// svars_sort is the order Array.prototype.sort of V8 gives with the comparator
// `(a, b) => a > b ? 1 : -1` (never 0): the first run, then a binary insertion of the others,
// which is all of TimSort for fewer than 64 elements.
fn svars_sort(sortable [][]u16) []int {
	compare := fn [sortable] (a int, b int) int {
		return if units_less(sortable[b], sortable[a]) { 1 } else { -1 }
	}
	mut order := []int{len: sortable.len, init: index}
	n := order.len
	if n < 2 {
		return order
	}
	// CountAndMakeRun
	mut run := 2
	descending := compare(order[1], order[0]) < 0
	for run < n {
		o := compare(order[run], order[run - 1])
		if (descending && o >= 0) || (!descending && o < 0) {
			break
		}
		run++
	}
	if descending {
		order[..run].reverse_in_place()
	}
	// BinaryInsertionSort
	for start in run .. n {
		pivot := order[start]
		mut left := 0
		mut right := start
		for left < right {
			mid := left + ((right - left) >> 1)
			if compare(pivot, order[mid]) < 0 {
				right = mid
			} else {
				left = mid + 1
			}
		}
		for p := start; p > left; p-- {
			order[p] = order[p - 1]
		}
		order[left] = pivot
	}
	return order
}

// units_less compares UTF-16 strings like JavaScript's `<`.
fn units_less(a []u16, b []u16) bool {
	for i in 0 .. if a.len < b.len { a.len } else { b.len } {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return a.len < b.len
}
