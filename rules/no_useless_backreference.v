module rules

import regexpp
import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-useless-backreference` rule of ESLint 10.6.0 (it has no options).

const nub_messages = {
	'nested':                 "Backreference '{{ bref }}' will be ignored. It references group '{{ group }}'{{ otherGroups }} from within that group."
	'forward':                "Backreference '{{ bref }}' will be ignored. It references group '{{ group }}'{{ otherGroups }} which appears later in the pattern."
	'backward':               "Backreference '{{ bref }}' will be ignored. It references group '{{ group }}'{{ otherGroups }} which appears before in the same lookbehind."
	'disjunctive':            "Backreference '{{ bref }}' will be ignored. It references group '{{ group }}'{{ otherGroups }} which is in another alternative."
	'intoNegativeLookaround': "Backreference '{{ bref }}' will be ignored. It references group '{{ group }}'{{ otherGroups }} which is in a negative lookaround."
}

struct NubProblem {
	message_id string
	group      int
}

fn (mut c Checker) lint_no_useless_backreference(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['regex'], []) {
		stats.checked++
		pattern, flags := c.es_regex_literal(node) or { continue }
		nub_check(node, pattern, flags, mut findings)
	}
	// The calls and constructions of the global RegExp.
	trace := {
		'RegExp': EsTrace{
			call:      true
			construct: true
		}
	}
	for traced in c.es_global_references(root, trace) {
		stats.checked++
		mut args := []C.TSNode{}
		if arguments := node_field(traced.node, 'arguments') {
			if node_kind(arguments) == 'arguments' {
				args = named_children(arguments).filter(node_kind(it) != 'comment')
			}
		}
		if args.len == 0 {
			continue
		}
		pattern := c.string_if_constant(args[0]) or { continue }
		mut flags := ''
		if args.len > 1 {
			flags = c.string_if_constant(args[1]) or { '' }
		}
		nub_check(traced.node, utf16_units(pattern), flags, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn nub_path(ast &regexpp.Ast, node int) []int {
	mut path := []int{}
	mut current := node
	for current >= 0 {
		path << current
		current = ast.nodes[current].parent
	}
	return path
}

fn nub_is_lookaround(n regexpp.Node) bool {
	return n.kind == .assertion && n.assertion_kind in [.lookahead, .lookbehind]
}

// nub_check ports checkRegex.
fn nub_check(node C.TSNode, pattern []u16, flags string, mut findings []Finding) {
	ast := regexpp.parse_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags),
		regexpp.Options{}) or { return }
	for event in ast.visit_events() {
		if !event.enter || ast.nodes[event.node].kind != .backreference {
			continue
		}
		bref := ast.nodes[event.node]
		bref_path := nub_path(ast, event.node)
		mut problems := []?NubProblem{}
		for group in bref.resolved {
			problems << nub_problem(ast, bref, bref_path, group)
		}
		if problems.len == 0 || problems.any(it == none) {
			continue
		}
		all := problems.map(it or { NubProblem{} })
		same := all.filter(it.message_id != 'disjunctive')
		to_report := if same.len > 0 { same } else { all }
		other := to_report.len - 1
		findings << Finding{
			stmt:       position_of(node)
			message_id: to_report[0].message_id
			data:       {
				'bref':        ast.raw(event.node)
				'group':       ast.raw(to_report[0].group)
				'otherGroups': if other == 1 {
					' and another group'
				} else if other > 1 {
					' and other ${other} groups'
				} else {
					''
				}
			}
		}
	}
}

fn nub_problem(ast &regexpp.Ast, bref regexpp.Node, bref_path []int, group int) ?NubProblem {
	if group in bref_path {
		return NubProblem{'nested', group}
	}
	group_path := nub_path(ast, group)
	mut i := bref_path.len - 1
	mut j := group_path.len - 1
	for {
		i--
		j--
		a := if i >= 0 { bref_path[i] } else { -1 }
		b := if j >= 0 { group_path[j] } else { -1 }
		if a != b || (i < 0 && j < 0) {
			break
		}
	}
	lca := j + 1
	group_cut := group_path[..lca]
	common := group_path[lca..]
	mut backward := false
	for n in common {
		if nub_is_lookaround(ast.nodes[n]) {
			backward = ast.nodes[n].assertion_kind == .lookbehind
			break
		}
	}
	g := ast.nodes[group]
	if ast.nodes[group_cut.last()].kind == .alternative {
		return NubProblem{'disjunctive', group}
	}
	if !backward && bref.end <= g.start {
		return NubProblem{'forward', group}
	}
	if backward && g.end <= bref.start {
		return NubProblem{'backward', group}
	}
	if group_cut.any(nub_is_lookaround(ast.nodes[it]) && ast.nodes[it].negate) {
		return NubProblem{'intoNegativeLookaround', group}
	}
	return none
}
