module codepath

import estree

// A port of the code path analysis of ESLint 10.6.0 (lib/linter/code-path-analysis/) on the ESTree
// of the estree module. `analyze` runs it over a tree the way ESLint's SourceCode#traverse does
// and returns every event a rule listener would receive, in ESLint's order, with the code paths
// and segments they refer to.
//
// ESLint computes all the events of a file before it runs any rule, so a rule always sees the
// segments and code paths in their final state (all their next segments, all their final
// segments); the objects of an Analysis are that final state.

// Origin is CodePath#origin.
pub enum Origin as u8 {
	program
	function
	class_field_initializer
	class_static_block
}

// str is the value of CodePath#origin (`class-field-initializer`…).
pub fn (o Origin) str() string {
	return match o {
		.program { 'program' }
		.function { 'function' }
		.class_field_initializer { 'class-field-initializer' }
		.class_static_block { 'class-static-block' }
	}
}

// Segment is a CodePathSegment. Segments are referred to by their index in Analysis.segments.
pub struct Segment {
pub:
	code_path int // index of its code path in Analysis.code_paths
	n         int // its number in its code path: the id is `<code path id>_<n>`
	reachable bool
pub mut:
	next_segments     []int
	prev_segments     []int
	all_next_segments []int
	all_prev_segments []int
	// internal.used: the segment was attached to the code path.
	used bool
	// internal.loopedPrevSegments: the previous segments that come from the end of a loop.
	looped_prev_segments []int
}

// CodePath is a code path. Code paths are referred to by their index in Analysis.code_paths.
pub struct CodePath {
pub:
	n      int // the id is `s<n>`
	origin Origin
	upper  int // index of the enclosing code path, -1 for none
	node   int // the node that starts it (the Program, the function, the field's value…)
pub mut:
	child_code_paths  []int
	initial_segment   int
	final_segments    []int
	returned_segments []int
	thrown_segments   []int
	segment_count     int // the last number given to a segment (the IdGenerator of the code path)
}

// EventKind is the name of a listener: a node is entered (the node's selectors) or left
// (`:exit`), or one of the code path events.
pub enum EventKind as u8 {
	enter_node
	leave_node
	code_path_start           // onCodePathStart(codePath, node)
	code_path_end             // onCodePathEnd(codePath, node)
	segment_start             // onCodePathSegmentStart(segment, node)
	segment_end               // onCodePathSegmentEnd(segment, node)
	unreachable_segment_start // onUnreachableCodePathSegmentStart(segment, node)
	unreachable_segment_end   // onUnreachableCodePathSegmentEnd(segment, node)
	segment_loop              // onCodePathSegmentLoop(fromSegment, toSegment, node)
}

// listener_name is the name ESLint gives the event (`onCodePathStart`…; `enter` and `exit` for
// the node events).
pub fn (k EventKind) listener_name() string {
	return match k {
		.enter_node { 'enter' }
		.leave_node { 'exit' }
		.code_path_start { 'onCodePathStart' }
		.code_path_end { 'onCodePathEnd' }
		.segment_start { 'onCodePathSegmentStart' }
		.segment_end { 'onCodePathSegmentEnd' }
		.unreachable_segment_start { 'onUnreachableCodePathSegmentStart' }
		.unreachable_segment_end { 'onUnreachableCodePathSegmentEnd' }
		.segment_loop { 'onCodePathSegmentLoop' }
	}
}

// Event is one call of rule listeners. `node` is the node argument (the node entered or left
// for a node event). `code_path` is the code path of the event (for a segment event, the code
// path of the segment). `segment` is the segment of a segment event (`fromSegment` of a loop),
// `to_segment` the `toSegment` of a loop; both are -1 when the event has none.
pub struct Event {
pub:
	kind       EventKind
	node       int
	code_path  int = -1
	segment    int = -1
	to_segment int = -1
}

pub struct Analysis {
pub mut:
	segments   []Segment
	code_paths []CodePath
	events     []Event
}

// segment_id is CodePathSegment#id (`s1_2`).
pub fn (an &Analysis) segment_id(seg int) string {
	s := an.segments[seg]
	return 's${an.code_paths[s.code_path].n}_${s.n}'
}

// code_path_id is CodePath#id (`s1`).
pub fn (an &Analysis) code_path_id(cp int) string {
	return 's${an.code_paths[cp].n}'
}

// is_looped_prev_segment is CodePathSegment#isLoopedPrevSegment(prev).
pub fn (an &Analysis) is_looped_prev_segment(seg int, prev int) bool {
	return prev in an.segments[seg].looped_prev_segments
}

// is_any_reachable tells whether one of the segments is reachable (the isAnySegmentReachable
// helper of many rules).
pub fn (an &Analysis) is_any_reachable(segs []int) bool {
	for s in segs {
		if an.segments[s].reachable {
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------------------------
// CodePath#traverseSegments

// TraverseOptions are the options of traverseSegments: `first` (the initial segment when -1)
// and `last` (none when -1).
pub struct TraverseOptions {
pub:
	first int = -1
	last  int = -1
}

struct WalkRecord {
mut:
	segment int
	index   int
}

// SegmentWalker runs CodePath#traverseSegments step by step: each `next()` returns the segment
// the callback would be called with; `skip()` and `stop()` are the controller's skip() and
// break() for that segment.
//
//	mut w := an.walk_segments(cp, codepath.TraverseOptions{})
//	for {
//		seg := w.next() or { break }
//		if … { w.skip() }
//	}
pub struct SegmentWalker {
	an    &Analysis
	start int
	last  int
mut:
	stack   []WalkRecord
	visited map[int]bool
	skipped map[int]bool
	segment int = -1
	index   int
	pending bool // the last segment returned still has its post-callback steps to run
	broken  bool
	done    bool
}

// walk_segments starts a traversal of the segments of the code path `cp`.
pub fn (an &Analysis) walk_segments(cp int, opts TraverseOptions) SegmentWalker {
	start := if opts.first >= 0 { opts.first } else { an.code_paths[cp].initial_segment }
	return SegmentWalker{
		an:    an
		start: start
		last:  opts.last
		stack: [WalkRecord{start, 0}]
	}
}

// skip is controller.skip(): the segments after the current one are not visited unless another
// path leads to them.
pub fn (mut w SegmentWalker) skip() {
	w.skipped[w.segment] = true
}

// stop is controller.break(): the traversal ends.
pub fn (mut w SegmentWalker) stop() {
	w.broken = true
}

fn (w &SegmentWalker) is_visited(prev int) bool {
	return w.visited[prev] || w.an.is_looped_prev_segment(w.segment, prev)
}

fn (w &SegmentWalker) is_skipped(prev int) bool {
	return w.skipped[prev] || w.an.is_looped_prev_segment(w.segment, prev)
}

fn (mut w SegmentWalker) update_stack() {
	nexts := w.an.segments[w.segment].next_segments
	end := nexts.len - 1
	top := w.stack.len - 1
	if w.index < end {
		w.stack[top].index += 1
		w.stack << WalkRecord{nexts[w.index], 0}
	} else if w.index == end {
		w.stack[top] = WalkRecord{nexts[w.index], 0}
	} else {
		w.stack.delete_last()
	}
}

// next returns the next segment to visit, or none at the end of the traversal.
pub fn (mut w SegmentWalker) next() ?int {
	if w.done {
		return none
	}
	if w.pending {
		w.pending = false
		if w.segment == w.last {
			w.skip()
		}
		if w.broken {
			w.done = true
			return none
		}
		w.update_stack()
	}
	for w.stack.len > 0 {
		record := w.stack[w.stack.len - 1]
		w.segment = record.segment
		w.index = record.index
		if w.index == 0 {
			if w.visited[w.segment] {
				w.stack.delete_last()
				continue
			}
			prevs := w.an.segments[w.segment].prev_segments
			if w.segment != w.start && prevs.len > 0 && !prevs.all(w.is_visited(it)) {
				w.stack.delete_last()
				continue
			}
			w.visited[w.segment] = true
			should_skip := w.skipped.len > 0 && prevs.len > 0 && prevs.all(w.is_skipped(it))
			if !should_skip {
				w.pending = true
				return w.segment
			}
			w.skipped[w.segment] = true
		}
		w.update_stack()
	}
	w.done = true
	return none
}

// traverse_segments is CodePath#traverseSegments(options, callback) with a callback.
pub fn (an &Analysis) traverse_segments(cp int, opts TraverseOptions, callback fn (seg int, mut w SegmentWalker)) {
	mut w := an.walk_segments(cp, opts)
	for {
		seg := w.next() or { break }
		callback(seg, mut w)
	}
}

// ---------------------------------------------------------------------------------------------
// Current segments

// Tracker keeps the current segments of each code path being analyzed, the way rules do since
// ESLint 9 removed CodePath#currentSegments: a set per code path, in the order the segments
// started, updated with each event by `apply`. Call `apply` before handling an event; on
// `code_path_end` the code path's set is dropped after the event, at the next `apply`.
pub struct Tracker {
mut:
	stack    [][]int
	pop_next bool
}

// apply updates the current segments with an event.
pub fn (mut tr Tracker) apply(ev Event) {
	if tr.pop_next {
		tr.stack.delete_last()
		tr.pop_next = false
	}
	match ev.kind {
		.code_path_start {
			tr.stack << []int{}
		}
		.code_path_end {
			tr.pop_next = true
		}
		.segment_start, .unreachable_segment_start {
			tr.stack[tr.stack.len - 1] << ev.segment
		}
		.segment_end, .unreachable_segment_end {
			top := tr.stack.len - 1
			k := tr.stack[top].index(ev.segment)
			if k >= 0 {
				tr.stack[top].delete(k)
			}
		}
		else {}
	}
}

// current are the current segments of the innermost code path.
pub fn (tr &Tracker) current() []int {
	if tr.stack.len == 0 {
		return []int{}
	}
	return tr.stack[tr.stack.len - 1]
}

// analyze runs the code path analysis over the tree and returns its events.
pub fn analyze(t &estree.EsTree) Analysis {
	mut a := Analyzer{
		t: unsafe { t }
	}
	a.an.events = []Event{cap: t.nodes.len * 3}
	for step in t.steps() {
		if step.leave {
			a.leave_node(step.node)
		} else {
			a.enter_node(step.node)
		}
	}
	return a.an
}
