module rules

import estree
import json2
import time

// Port of the `unicorn/prefer-switch` rule of eslint-plugin-unicorn 64.0.0, with its fix.

const ups_messages = {
	'prefer-switch': 'Use `switch` instead of multiple `else-if`.'
}

struct UpsOptions {
	minimum_cases      int
	empty_default_case string
}

fn ups_options(options []json2.Any) !UpsOptions {
	o := option_object(unicorn_prefer_switch, options, ['minimumCases', 'emptyDefaultCase'])!
	minimum := o.values['minimumCases'] or { json2.Any(3) }
	empty := o.values['emptyDefaultCase'] or { json2.Any('no-default-comment') }
	return UpsOptions{
		minimum_cases:      int(json_number(minimum))
		empty_default_case: empty.str()
	}
}

// UpsIf is an `if` of the chain with its `===` comparisons.
struct UpsIf {
	statement int
	compares  []int
}

// ups_is_same ports isSame: the same node, or isSameReference.
fn (mut c Checker) ups_is_same(t &estree.EsTree, a int, b int) bool {
	return a == b || c.un_is_same_reference(t, a, b)
}

// ups_equality_comparisons ports getEqualityComparisons: the `===` comparisons joined by `||`, in
// order; none if something else is joined.
fn ups_equality_comparisons(t &estree.EsTree, test int) []int {
	mut nodes := [test]
	mut out := []int{}
	for nodes.len > 0 {
		node := nodes.pop()
		operator := t.string_of(node, .operator) or { '' }
		if t.typ(node) == .logical_expression && operator == '||' {
			nodes << t.node(node, .right) or { return [] }
			nodes << t.node(node, .left) or { return [] }
			continue
		}
		if t.typ(node) != .binary_expression || operator != '===' {
			return []
		}
		out << node
	}
	return out
}

// ups_statements ports getStatements: the `if`s of the chain that compare a common reference with
// `===`, and that reference (-1 if none).
fn (mut c Checker) ups_statements(t &estree.EsTree, first int) ([]UpsIf, int) {
	mut candidates := ?[]int(none)
	mut ifs := []UpsIf{}
	mut statement := first
	for statement >= 0 && t.typ(statement) == .if_statement {
		compares := ups_equality_comparisons(t, t.node(statement, .test) or { break })
		if compares.len == 0 {
			break
		}
		if candidates == none {
			candidates = [t.node(compares[0], .left) or { break }, t.node(compares[0], .right) or {
				break
			}]
		}
		mut current := candidates or { []int{} }
		// getCommonReferences
		for compare in compares {
			left := t.node(compare, .left) or { -1 }
			right := t.node(compare, .right) or { -1 }
			current = current.filter(c.ups_is_same(t, it, left) || c.ups_is_same(t, it, right))
			if current.len == 0 {
				break
			}
		}
		if current.len == 0 {
			break
		}
		candidates = current
		ifs << UpsIf{statement, compares}
		statement = t.node(statement, .alternate) or { -1 }
	}
	list := candidates or { return ifs, -1 }
	return ifs, if list.len > 0 { list[0] } else { -1 }
}

const ups_breakable = [estree.NodeType.while_statement, .do_while_statement, .for_statement,
	.for_of_statement, .for_in_statement, .switch_statement]

// ups_break_target ports getBreakTarget: the closest loop or switch around the node (the node
// itself included), none at the top.
fn ups_break_target(t &estree.EsTree, node int) ?int {
	mut n := node
	for t.nodes[n].parent >= 0 {
		if t.typ(n) in ups_breakable {
			return n
		}
		n = t.nodes[n].parent
	}
	return none
}

fn ups_inside(t &estree.EsTree, inner int, outer int) bool {
	return t.nodes[inner].start >= t.nodes[outer].start && t.nodes[inner].end <= t.nodes[outer].end
}

// ups_has_break_inside ports hasBreakInside: a `break` in the node that would break out of the
// `switch` the fix makes.
fn ups_has_break_inside(t &estree.EsTree, breaks []int, node int) bool {
	for b in breaks {
		if !ups_inside(t, b, node) {
			continue
		}
		target := ups_break_target(t, b) or { return true }
		if ups_inside(t, node, target) {
			return true
		}
	}
	return false
}

// ups_block_last_node ports getBlockStatementLastNode.
fn ups_block_last_node(t &estree.EsTree, block int) ?int {
	body := t.list(block, .body) or { return none }
	for i := body.len - 1; i >= 0; i-- {
		node := body[i]
		if t.typ(node) in [.function_declaration, .empty_statement] {
			continue
		}
		if t.typ(node) == .block_statement {
			if last := ups_block_last_node(t, node) {
				return last
			}
			continue
		}
		return node
	}
	return none
}

// ups_should_insert_break ports shouldInsertBreakStatement.
fn ups_should_insert_break(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.return_statement, .throw_statement {
			return false
		}
		.if_statement {
			alternate := t.node(node, .alternate) or { return true }
			return ups_should_insert_break(t, t.node(node, .consequent) or { return true })
				|| ups_should_insert_break(t, alternate)
		}
		.block_statement {
			last := ups_block_last_node(t, node) or { return true }
			return ups_should_insert_break(t, last)
		}
		else {
			return true
		}
	}
}

fn (mut c Checker) lint_unicorn_prefer_switch(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	opts := ups_options(c.rule_options(unicorn_prefer_switch))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	order := un_enter_order(t)
	ifs_all := order.filter(t.typ(it) == .if_statement)
	breaks := order.filter(t.typ(it) == .break_statement && t.node(it, .label) == none)
	mut checked := map[int]bool{}
	for node in ifs_all {
		stats.checked++
		if node in checked {
			continue
		}
		ifs, discriminant := c.ups_statements(t, node)
		if discriminant < 0 || ifs.len < opts.minimum_cases {
			continue
		}
		for item in ifs {
			checked[item.statement] = true
		}
		consequent := t.node(node, .consequent) or { continue }
		mut finding := Finding{
			stmt:       c.position_range(t.nodes[node].start, t.nodes[consequent].start)
			message_id: 'prefer-switch'
		}
		if !un_has_side_effect(t, discriminant)
			&& !ifs.any(ups_has_break_inside(t, breaks, it.statement)) {
			has_fix, fix := c.merge_fixes(c.ups_fix(t, tokens, ifs, discriminant, opts))!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) ups_fix(t &estree.EsTree, tokens &SourceTokens, ifs []UpsIf, discriminant int, opts UpsOptions) []Fix {
	first := ifs[0].statement
	indent := c.un_indent_string(t, first)
	mut fixes := [fix_insert_at(t.nodes[first].start, 'switch (${c.un_text(t, discriminant)}) {')]
	last := ifs.last().statement
	if alternate := t.node(last, .alternate) {
		fixes << fix_insert_at(t.nodes[alternate].start, '\n${indent}default: ')
	} else {
		match opts.empty_default_case {
			'no-default-comment' {
				fixes << fix_insert_at(t.nodes[first].end, '\n${indent}// No default')
			}
			'do-nothing-comment' {
				fixes << fix_insert_at(t.nodes[first].end, '\n${indent}default:\n${indent}// Do nothing')
			}
			else {}
		}
	}
	fixes << fix_insert_at(t.nodes[first].end, '\n${indent}}')
	for item in ifs {
		statement := item.statement
		consequent := t.node(statement, .consequent) or { continue }
		if alternate := t.node(statement, .alternate) {
			fixes << fix_remove_range(t.nodes[consequent].end, t.nodes[alternate].start)
		}
		fixes << fix_remove_range(t.nodes[statement].start, t.nodes[consequent].start)
		for compare in item.compares {
			left := t.node(compare, .left) or { continue }
			right := t.node(compare, .right) or { continue }
			value := if c.ups_is_same(t, left, discriminant) { right } else { left }
			fixes << fix_insert_at(t.nodes[consequent].start, '\n${indent}case ${c.un_text(t,
				value)}: ')
		}
		if ups_should_insert_break(t, consequent) {
			if t.typ(consequent) == .block_statement {
				closing := un_last_token(t, tokens, consequent) or { continue }
				fixes << fix_insert_at(closing.start, '\n${indent}break;\n${indent}')
			} else {
				fixes << fix_insert_at(t.nodes[consequent].end, '\n${indent}break;')
				fixes << fix_insert_at(t.nodes[consequent].start, '{\n${indent}')
				fixes << fix_insert_at(t.nodes[consequent].end, '\n${indent}}')
			}
		}
	}
	return fixes
}
