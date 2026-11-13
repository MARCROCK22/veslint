module rules

import codepath
import estree
import time

// Port of the `no-this-before-super` rule of ESLint 10.6.0 (it has no options), on the code path
// events of the codepath module.

const ntbs_messages = {
	'noBeforeSuper': "'{{kind}}' is not allowed before 'super()'."
}

struct NtbsSegmentInfo {
mut:
	super_called  bool
	invalid_nodes []int
}

struct NtbsFuncInfo {
	is_constructor bool
	has_extends    bool
	code_path      int
mut:
	current_segments []int // a Set: insertion order, no duplicates
}

fn (mut c Checker) lint_no_this_before_super(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut infos := map[int]NtbsSegmentInfo{}
	mut stack := []NtbsFuncInfo{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				node := ev.node
				if csup_is_constructor_function(t, node) {
					class_node := t.nodes[t.nodes[t.nodes[node].parent].parent].parent
					super_class := t.node(class_node, .super_class) or { -1 }
					stack << NtbsFuncInfo{
						is_constructor: true
						has_extends:    super_class >= 0
							&& !es_tree_is_null_or_undefined(t, super_class)
						code_path:      ev.code_path
					}
				} else {
					stack << NtbsFuncInfo{
						code_path: ev.code_path
					}
				}
			}
			.code_path_end {
				is_derived_class := stack.pop().has_extends
				if !is_derived_class {
					continue
				}
				stats.checked++
				mut reported := map[int]bool{}
				mut w := an.walk_segments(ev.code_path, codepath.TraverseOptions{})
				for {
					segment := w.next() or { break }
					info := infos[segment] or { NtbsSegmentInfo{} }
					for node in info.invalid_nodes {
						if node in reported {
							continue
						}
						reported[node] = true
						findings << Finding{
							stmt:       c.position_at(t.nodes[node].start)
							message_id: 'noBeforeSuper'
							data:       {
								'kind': if t.typ(node) == .super { 'super' } else { 'this' }
							}
						}
					}
					if info.super_called {
						w.skip()
					}
				}
			}
			.segment_start {
				top := stack.len - 1
				if ev.segment !in stack[top].current_segments {
					stack[top].current_segments << ev.segment
				}
				if !(stack[top].is_constructor && stack[top].has_extends) {
					continue
				}
				prevs := an.segments[ev.segment].prev_segments
				infos[ev.segment] = NtbsSegmentInfo{
					super_called: prevs.len > 0 && prevs.all(ntbs_is_called(an, infos, it))
				}
			}
			.unreachable_segment_start {
				top := stack.len - 1
				if ev.segment !in stack[top].current_segments {
					stack[top].current_segments << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				top := stack.len - 1
				k := stack[top].current_segments.index(ev.segment)
				if k >= 0 {
					stack[top].current_segments.delete(k)
				}
			}
			.segment_loop {
				info := stack[stack.len - 1]
				if !(info.is_constructor && info.has_extends) {
					continue
				}
				mut w := an.walk_segments(info.code_path, codepath.TraverseOptions{
					first: ev.to_segment
					last:  ev.segment
				})
				for {
					segment := w.next() or { break }
					mut seg_info := infos[segment] or { NtbsSegmentInfo{} }
					prevs := an.segments[segment].prev_segments
					if seg_info.super_called {
						w.skip()
					} else if prevs.len > 0 && prevs.all(ntbs_is_called(an, infos, it)) {
						seg_info.super_called = true
					}
					infos[segment] = seg_info
				}
			}
			.enter_node {
				typ := t.typ(ev.node)
				if typ == .this_expression || (typ == .super && !es_tree_is_callee(t, ev.node)) {
					stats.checked++
					top := stack.len - 1
					if ntbs_is_before_call_of_super(an, infos, stack[top]) {
						// setInvalid
						for segment in stack[top].current_segments {
							if an.segments[segment].reachable {
								infos[segment].invalid_nodes << ev.node
							}
						}
					}
				}
			}
			.leave_node {
				typ := t.typ(ev.node)
				if typ == .call_expression {
					callee := t.node(ev.node, .callee) or { continue }
					top := stack.len - 1
					if t.typ(callee) == .super
						&& ntbs_is_before_call_of_super(an, infos, stack[top]) {
						// setSuperCalled
						for segment in stack[top].current_segments {
							if an.segments[segment].reachable {
								infos[segment].super_called = true
							}
						}
					}
				} else if typ == .program {
					infos = map[int]NtbsSegmentInfo{}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ntbs_is_called ports isCalled: an unreachable segment, or one where `super()` was called.
fn ntbs_is_called(an &codepath.Analysis, infos map[int]NtbsSegmentInfo, segment int) bool {
	return !an.segments[segment].reachable || (infos[segment] or { return false }).super_called
}

// ntbs_is_before_call_of_super ports isBeforeCallOfSuper.
fn ntbs_is_before_call_of_super(an &codepath.Analysis, infos map[int]NtbsSegmentInfo, info NtbsFuncInfo) bool {
	return info.is_constructor && info.has_extends
		&& !info.current_segments.all(ntbs_is_called(an, infos, it))
}

// es_tree_is_callee ports isCallee: the node is the callee of a CallExpression.
fn es_tree_is_callee(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) == .call_expression
		&& (t.node(parent, .callee) or { -1 }) == node
}

// es_tree_is_null_literal ports isNullLiteral: the literal `null`.
fn es_tree_is_null_literal(t &estree.EsTree, node int) bool {
	return t.typ(node) == .literal && t.get(node, .value) is estree.Null
		&& t.prop(node, .regex) == none && t.prop(node, .bigint) == none
}

// es_tree_is_null_or_undefined ports isNullOrUndefined: `null`, `undefined` or a `void`
// expression.
fn es_tree_is_null_or_undefined(t &estree.EsTree, node int) bool {
	return es_tree_is_null_literal(t, node) || (t.typ(node) == .identifier
		&& (t.string_of(node, .name) or { '' }) == 'undefined')
		|| (t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == 'void')
}
