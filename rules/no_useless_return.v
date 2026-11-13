module rules

import codepath
import estree
import time

// Port of the `no-useless-return` rule of ESLint 10.6.0 (it has no options), with its fix, on the
// code path events of the codepath module.

const nuret_messages = {
	'unnecessaryReturn': 'Unnecessary return statement.'
}

// The statements that use the returns before them (markReturnStatementsOnCurrentSegmentsAsUsed).
const nuret_using_statements = [estree.NodeType.class_declaration, .continue_statement,
	.debugger_statement, .do_while_statement, .empty_statement, .expression_statement,
	.for_in_statement, .for_of_statement, .for_statement, .if_statement, .import_declaration,
	.labeled_statement, .switch_statement, .throw_statement, .try_statement, .variable_declaration,
	.while_statement, .with_statement, .export_named_declaration, .export_default_declaration,
	.export_all_declaration]

// NuretSegmentInfo is what the rule keeps of a reachable segment.
struct NuretSegmentInfo {
mut:
	useless_returns []int
	returned        bool
}

struct NuretScopeInfo {
mut:
	useless_returns                []int
	traversed_try_block_statements []int
	current_segments               []int // a Set: insertion order, no duplicates
}

struct NuretState {
mut:
	infos map[int]NuretSegmentInfo
	scope NuretScopeInfo
}

fn (mut c Checker) lint_no_useless_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut st := NuretState{}
	mut uppers := []NuretScopeInfo{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				uppers << st.scope
				st.scope = NuretScopeInfo{}
			}
			.code_path_end {
				for node in st.scope.useless_returns {
					findings << c.nuret_report(t, node)
				}
				st.scope = uppers.pop()
			}
			.segment_start {
				if ev.segment !in st.scope.current_segments {
					st.scope.current_segments << ev.segment
				}
				mut traversed := map[int]bool{}
				st.infos[ev.segment] = NuretSegmentInfo{
					useless_returns: st.useless_returns_of(an, an.segments[ev.segment].all_prev_segments, mut
						traversed)
				}
			}
			.unreachable_segment_start {
				if ev.segment !in st.scope.current_segments {
					st.scope.current_segments << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				k := st.scope.current_segments.index(ev.segment)
				if k >= 0 {
					st.scope.current_segments.delete(k)
				}
			}
			.enter_node {
				typ := t.typ(ev.node)
				if typ == .return_statement {
					stats.checked++
					has_argument := t.node(ev.node, .argument) != none
					if has_argument {
						st.mark_current_segments_as_used(an, t)
					}
					if has_argument || nuret_is_in_loop(t, ev.node) || nuret_is_in_finally(t, ev.node)
						|| !an.is_any_reachable(st.scope.current_segments) {
						continue
					}
					for segment in st.scope.current_segments {
						if segment in st.infos {
							st.infos[segment].useless_returns << ev.node
							st.infos[segment].returned = true
						}
					}
					st.scope.useless_returns << ev.node
				} else if typ in nuret_using_statements {
					st.mark_current_segments_as_used(an, t)
				}
			}
			.leave_node {
				typ := t.typ(ev.node)
				if typ == .block_statement {
					// "TryStatement > BlockStatement.block:exit"
					parent := t.nodes[ev.node].parent
					if parent >= 0 && t.typ(parent) == .try_statement
						&& (t.node(parent, .block) or { -1 }) == ev.node {
						st.scope.traversed_try_block_statements << ev.node
					}
				} else if typ == .try_statement {
					if st.scope.traversed_try_block_statements.len > 0 {
						st.scope.traversed_try_block_statements.delete_last()
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// is_returned ports isReturned: a segment without info (unreachable), or one that returned.
fn (st &NuretState) is_returned(segment int) bool {
	info := st.infos[segment] or { return true }
	return info.returned
}

// useless_returns_of ports getUselessReturns.
fn (st &NuretState) useless_returns_of(an &codepath.Analysis, prev_segments []int, mut traversed map[int]bool) []int {
	mut out := []int{}
	for segment in prev_segments {
		if !an.segments[segment].reachable {
			if segment !in traversed {
				traversed[segment] = true
				prevs := an.segments[segment].all_prev_segments.filter(st.is_returned(it))
				out << st.useless_returns_of(an, prevs, mut traversed)
			}
			continue
		}
		if info := st.infos[segment] {
			out << info.useless_returns
		}
	}
	return out
}

// mark_current_segments_as_used ports markReturnStatementsOnCurrentSegmentsAsUsed.
fn (mut st NuretState) mark_current_segments_as_used(an &codepath.Analysis, t &estree.EsTree) {
	for segment in st.scope.current_segments.clone() {
		mut used := map[int]bool{}
		st.mark_segment_as_used(an, t, segment, mut used)
	}
}

// mark_segment_as_used ports markReturnStatementsOnSegmentAsUsed.
fn (mut st NuretState) mark_segment_as_used(an &codepath.Analysis, t &estree.EsTree, segment int, mut used map[int]bool) {
	if !an.segments[segment].reachable {
		used[segment] = true
		prevs := an.segments[segment].all_prev_segments.filter(st.is_returned(it)
			&& it !in used)
		for prev in prevs {
			st.mark_segment_as_used(an, t, prev, mut used)
		}
		return
	}
	info := st.infos[segment] or { return }
	mut kept := []int{}
	for node in info.useless_returns {
		if st.scope.traversed_try_block_statements.len > 0 {
			start := t.nodes[node].start
			end := t.nodes[node].end
			if st.scope.traversed_try_block_statements.any(start >= t.nodes[it].start
				&& end <= t.nodes[it].end) {
				kept << node
				continue
			}
		}
		k := st.scope.useless_returns.index(node)
		if k >= 0 {
			st.scope.useless_returns.delete(k)
		}
	}
	st.infos[segment].useless_returns = kept
}

// nuret_report reports a useless return, with the fix that removes it (FixTracker: the text of the
// enclosing function, or of the program, is replaced) when it is in a list of statements and
// has no comment inside.
fn (mut c Checker) nuret_report(t &estree.EsTree, node int) Finding {
	start := t.nodes[node].start
	end := t.nodes[node].end
	parent := t.nodes[node].parent
	mut finding := Finding{
		stmt:       c.position_at(start)
		message_id: 'unnecessaryReturn'
	}
	if t.typ(parent) !in [.program, .block_statement, .static_block, .switch_case] {
		return finding
	}
	tokens := c.source_tokens(t.nodes[t.root].ts)
	if tokens.inside(start, end, true).any(it.is_comment()) {
		return finding
	}
	mut function := t.root
	for n := node; n >= 0; n = t.nodes[n].parent {
		if t.typ(n) in [.function_declaration, .function_expression, .arrow_function_expression] {
			function = n
			break
		}
	}
	retain_start := t.nodes[function].start
	retain_end := t.nodes[function].end
	return Finding{
		...finding
		has_fix: true
		fix:     Fix{retain_start, retain_end, c.src[retain_start..start] + c.src[end..retain_end]}
	}
}

// nuret_is_in_loop ports isInLoop: a loop between the node and its function.
fn nuret_is_in_loop(t &estree.EsTree, node int) bool {
	for n := node; n >= 0
		&& t.typ(n) !in [.function_declaration, .function_expression, .arrow_function_expression]; n = t.nodes[n].parent {
		if t.typ(n) in [.do_while_statement, .for_statement, .for_in_statement, .for_of_statement,
			.while_statement] {
			return true
		}
	}
	return false
}

// nuret_is_in_finally ports isInFinally: the node is in the `finally` block of a try statement of
// its function.
fn nuret_is_in_finally(t &estree.EsTree, node int) bool {
	for n := node; n >= 0 && t.nodes[n].parent >= 0
		&& t.typ(n) !in [.function_declaration, .function_expression, .arrow_function_expression]; n = t.nodes[n].parent {
		parent := t.nodes[n].parent
		if t.typ(parent) == .try_statement && (t.node(parent, .finalizer) or { -1 }) == n {
			return true
		}
	}
	return false
}
