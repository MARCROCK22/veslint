module codepath

// code-path-segment.js and fork-context.js.

// new_segment is `new CodePathSegment(id, allPrevSegments, reachable)`, its id taken from the
// code path's IdGenerator.
fn (mut a Analyzer) new_segment(cp int, all_prev []int, reachable bool) int {
	a.an.code_paths[cp].segment_count++
	n := a.an.code_paths[cp].segment_count
	mut prev := []int{cap: all_prev.len}
	for p in all_prev {
		if a.an.segments[p].reachable {
			prev << p
		}
	}
	a.an.segments << Segment{
		code_path:         cp
		n:                 n
		reachable:         reachable
		prev_segments:     prev
		all_prev_segments: all_prev
	}
	return a.an.segments.len - 1
}

fn (a &Analyzer) any_reachable(segs []int) bool {
	for s in segs {
		if a.an.segments[s].reachable {
			return true
		}
	}
	return false
}

// new_next is CodePathSegment.newNext.
fn (mut a Analyzer) new_next(cp int, all_prev []int) int {
	reachable := a.any_reachable(all_prev)
	// The id is taken before the previous segments are flattened (which takes none).
	return a.new_segment(cp, a.flatten_unused_segments(all_prev), reachable)
}

// new_unreachable is CodePathSegment.newUnreachable.
fn (mut a Analyzer) new_unreachable(cp int, all_prev []int) int {
	seg := a.new_segment(cp, a.flatten_unused_segments(all_prev), false)
	a.mark_used(seg)
	return seg
}

// new_disconnected is CodePathSegment.newDisconnected.
fn (mut a Analyzer) new_disconnected(cp int, all_prev []int) int {
	return a.new_segment(cp, []int{}, a.any_reachable(all_prev))
}

// mark_used is CodePathSegment.markUsed.
fn (mut a Analyzer) mark_used(seg int) {
	if a.an.segments[seg].used {
		return
	}
	a.an.segments[seg].used = true
	prevs := a.an.segments[seg].all_prev_segments.clone()
	if a.an.segments[seg].reachable {
		for p in prevs {
			a.an.segments[p].all_next_segments << seg
			a.an.segments[p].next_segments << seg
		}
	} else {
		for p in prevs {
			a.an.segments[p].all_next_segments << seg
		}
	}
}

// flatten_unused_segments is CodePathSegment.flattenUnusedSegments: an unused segment is
// replaced by its previous segments; the order is that of a JavaScript Set.
fn (a &Analyzer) flatten_unused_segments(segs []int) []int {
	mut done := []int{cap: segs.len}
	mut seen := map[int]bool{}
	for s in segs {
		if seen[s] {
			continue
		}
		if !a.an.segments[s].used {
			for p in a.an.segments[s].all_prev_segments {
				if !seen[p] {
					seen[p] = true
					done << p
				}
			}
		} else {
			seen[s] = true
			done << s
		}
	}
	return done
}

// ForkContext is a fork context: a list of segment lists, each of `count` segments.
@[heap]
struct ForkContext {
	cp    int // the code path, whose IdGenerator names the segments
	upper &ForkContext = unsafe { nil }
	count int
mut:
	segments_list [][]int
}

fn (f &ForkContext) head() []int {
	if f.segments_list.len == 0 {
		return []int{}
	}
	return f.segments_list[f.segments_list.len - 1]
}

fn (f &ForkContext) empty() bool {
	return f.segments_list.len == 0
}

fn (a &Analyzer) fork_reachable(f &ForkContext) bool {
	h := f.head()
	return h.len > 0 && a.any_reachable(h)
}

enum SegmentMaker {
	next
	unreachable
	disconnected
}

// create_segments is createSegments of fork-context.js: `count` segments, the i-th of which
// follows the i-th segment of each list from `start` to `end` (negative: from the end).
fn (mut a Analyzer) create_segments(f &ForkContext, start int, end int, maker SegmentMaker) []int {
	list := f.segments_list
	b := if start >= 0 { start } else { list.len + start }
	e := if end >= 0 { end } else { list.len + end }
	mut out := []int{cap: f.count}
	for i in 0 .. f.count {
		mut prev := []int{}
		for j := b; j <= e; j++ {
			if j >= 0 && j < list.len && i < list[j].len {
				prev << list[j][i]
			}
		}
		out << match maker {
			.next { a.new_next(f.cp, prev) }
			.unreachable { a.new_unreachable(f.cp, prev) }
			.disconnected { a.new_disconnected(f.cp, prev) }
		}
	}
	return out
}

fn (mut a Analyzer) make_next(f &ForkContext, start int, end int) []int {
	return a.create_segments(f, start, end, .next)
}

fn (mut a Analyzer) make_unreachable(f &ForkContext, start int, end int) []int {
	return a.create_segments(f, start, end, .unreachable)
}

fn (mut a Analyzer) make_disconnected(f &ForkContext, start int, end int) []int {
	return a.create_segments(f, start, end, .disconnected)
}

// make_unreachable_without_range is `forkContext.makeUnreachable()` without arguments (in
// popTryContext): the indexes are NaN, so `count` unreachable segments without previous
// segments are made, and dropped; only their ids count.
fn (mut a Analyzer) make_unreachable_without_range(f &ForkContext) {
	for _ in 0 .. f.count {
		a.new_unreachable(f.cp, []int{})
	}
}

// merge_extra_segments is mergeExtraSegments of fork-context.js.
fn (mut a Analyzer) merge_extra_segments(f &ForkContext, segs []int) []int {
	if segs.len <= f.count {
		return segs
	}
	mut merged := []int{}
	half := segs.len / 2
	for i in 0 .. half {
		merged << a.new_next(f.cp, [segs[i], segs[i + half]])
	}
	return a.merge_extra_segments(f, merged)
}

fn (mut a Analyzer) fork_add(mut f ForkContext, segs []int) {
	merged := a.merge_extra_segments(f, segs)
	f.segments_list << merged
}

// fork_replace_head is ForkContext#replaceHead (`splice(-1, 1, …)`, which inserts into an empty
// list).
fn (mut a Analyzer) fork_replace_head(mut f ForkContext, segs []int) {
	merged := a.merge_extra_segments(f, segs)
	if f.segments_list.len == 0 {
		f.segments_list << merged
	} else {
		f.segments_list[f.segments_list.len - 1] = merged
	}
}

fn fork_add_all(mut f ForkContext, other &ForkContext) {
	n := other.segments_list.len
	for k in 0 .. n {
		f.segments_list << other.segments_list[k]
	}
}

fn fork_clear(mut f ForkContext) {
	f.segments_list = [][]int{}
}

fn new_empty_fork(parent &ForkContext, fork_leaving_path bool) &ForkContext {
	return &ForkContext{
		cp:    parent.cp
		upper: parent
		count: (if fork_leaving_path { 2 } else { 1 }) * parent.count
	}
}

fn (mut a Analyzer) new_root_fork(cp int) &ForkContext {
	mut f := &ForkContext{
		cp:    cp
		count: 1
	}
	root := a.new_segment(cp, []int{}, true)
	a.fork_add(mut f, [root])
	return f
}
