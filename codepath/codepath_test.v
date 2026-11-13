module codepath

import estree
import treesitter

// The differential test (tools/run.sh of the code path work) checks the events against ESLint;
// these tests check the helpers rules use on top of them.

fn analyze_ts(src string) (estree.EsTree, Analysis) {
	p := treesitter.new_parser() or { panic(err) }
	tree := p.parse(src) or { panic(err) }
	t := estree.convert(treesitter.root_node(tree), src, false) or { panic(err) }
	return t, analyze(&t)
}

fn test_ids_and_final_segments() {
	t, an := analyze_ts('function f(a) { if (a) { return 1; } throw a; }')
	assert an.code_paths.len == 2
	assert an.code_path_id(1) == 's2'
	f := an.code_paths[1]
	assert f.origin == .function && f.upper == 0 && an.code_paths[0].child_code_paths == [1]
	assert an.segment_id(f.initial_segment) == 's2_1'
	assert f.returned_segments.map(an.segment_id(it)) == ['s2_2']
	assert f.thrown_segments.len == 1
	assert f.final_segments.len == 2
	assert t.typ(f.node) == .function_declaration
}

fn test_tracker_follows_segments() {
	t, an := analyze_ts('function f(a) { while (a) { a(); } return; }')
	mut tr := Tracker{}
	mut at_return := []int{}
	for ev in an.events {
		tr.apply(ev)
		if ev.kind == .enter_node && t.typ(ev.node) == .return_statement {
			at_return = tr.current().clone()
		}
	}
	// After the loop: the segment that follows it, reachable.
	assert at_return.len == 1
	assert an.segments[at_return[0]].reachable
	assert an.segments[at_return[0]].code_path == 1
}

struct Collected {
mut:
	segments []int
}

fn test_walker_skip_and_break() {
	_, an := analyze_ts('if (a) { b(); } else { c(); } d();')
	mut acc := &Collected{}
	an.traverse_segments(0, TraverseOptions{}, fn [mut acc] (seg int, mut w SegmentWalker) {
		acc.segments << seg
	})
	all := acc.segments.clone()
	assert all.len == 4
	// Skipping the consequent still visits the alternate and the join (one of its previous
	// segments was not skipped).
	mut w := an.walk_segments(0, TraverseOptions{})
	mut seen := []int{}
	for {
		seg := w.next() or { break }
		seen << seg
		if seen.len == 2 {
			w.skip()
		}
	}
	assert seen == all
	mut b := an.walk_segments(0, TraverseOptions{})
	first := b.next() or { -1 }
	b.stop()
	assert first == an.code_paths[0].initial_segment
	assert b.next() == none
}
