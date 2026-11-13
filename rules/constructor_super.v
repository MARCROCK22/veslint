module rules

import codepath
import estree
import time

// Port of the `constructor-super` rule of ESLint 10.6.0 (it has no options), on the code path
// events of the codepath module.

const csup_messages = {
	'missingSome': "Lacked a call of 'super()' in some code paths."
	'missingAll':  "Expected to call 'super()'."
	'duplicate':   "Unexpected duplicate 'super()'."
	'badSuper':    "Unexpected 'super()' because 'super' is not a constructor."
}

struct CsupSegmentInfo {
mut:
	called_in_every_paths bool
	called_in_some_paths  bool
	valid_nodes           []int
}

struct CsupFuncInfo {
	is_constructor       bool
	has_extends          bool
	super_is_constructor bool
	code_path            int
mut:
	current_segments []int // a Set: insertion order, no duplicates
}

fn (mut c Checker) lint_constructor_super(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut infos := map[int]CsupSegmentInfo{}
	mut stack := []CsupFuncInfo{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				node := ev.node
				if csup_is_constructor_function(t, node) {
					class_node := t.nodes[t.nodes[t.nodes[node].parent].parent].parent
					super_class := t.node(class_node, .super_class) or { -1 }
					stack << CsupFuncInfo{
						is_constructor:       true
						has_extends:          super_class >= 0
						super_is_constructor: csup_is_possible_constructor(t, super_class)
						code_path:            ev.code_path
					}
				} else {
					stack << CsupFuncInfo{
						code_path: ev.code_path
					}
				}
			}
			.code_path_end {
				has_extends := stack.pop().has_extends
				if !has_extends {
					continue
				}
				stats.checked++
				returned := an.code_paths[ev.code_path].returned_segments
				called_in_every_paths := returned.all(csup_is_called_in_every_path(an, infos,
					it))
				called_in_some_paths := returned.any(csup_is_called_in_some_path(an, infos,
					it))
				if !called_in_every_paths {
					findings << Finding{
						stmt:       c.es_tree_position(t, t.nodes[ev.node].parent)
						message_id: if called_in_some_paths { 'missingSome' } else { 'missingAll' }
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
				mut seg_info := CsupSegmentInfo{}
				seen := an.segments[ev.segment].prev_segments.filter(it in infos)
				if seen.len > 0 {
					seg_info.called_in_some_paths = seen.any(csup_is_called_in_some_path(an,
						infos, it))
					seg_info.called_in_every_paths = seen.all(csup_is_called_in_every_path(an,
						infos, it))
				}
				// When the segment is the update of a for loop, it is reached only after the
				// body, so the call is checked against the body's paths (at the loop).
				parent := t.nodes[ev.node].parent
				if parent >= 0 && t.typ(parent) == .for_statement
					&& (t.node(parent, .update) or { -1 }) == ev.node {
					seg_info.called_in_every_paths = true
				}
				infos[ev.segment] = seg_info
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
					if segment !in infos {
						w.skip()
						continue
					}
					seen := an.segments[segment].prev_segments.filter(it in infos)
					called_in_some := seen.any(csup_is_called_in_some_path(an, infos, it))
					called_in_every := seen.all(csup_is_called_in_every_path(an, infos, it))
					infos[segment].called_in_some_paths = infos[segment].called_in_some_paths
						|| called_in_some
					infos[segment].called_in_every_paths = infos[segment].called_in_every_paths
						|| called_in_every
					if called_in_some {
						nodes := infos[segment].valid_nodes
						infos[segment].valid_nodes = []int{}
						for node in nodes {
							findings << Finding{
								stmt:       c.es_tree_position(t, node)
								message_id: 'duplicate'
							}
						}
					}
				}
			}
			.leave_node {
				// "CallExpression:exit"
				if t.typ(ev.node) != .call_expression {
					continue
				}
				info := stack[stack.len - 1]
				if !(info.is_constructor && info.has_extends) {
					continue
				}
				callee := t.node(ev.node, .callee) or { continue }
				if t.typ(callee) != .super {
					continue
				}
				stats.checked++
				mut duplicate := false
				mut last := -1
				for segment in info.current_segments {
					if an.segments[segment].reachable {
						last = segment
						duplicate = duplicate || infos[segment].called_in_some_paths
						infos[segment].called_in_some_paths = true
						infos[segment].called_in_every_paths = true
					}
				}
				if last >= 0 {
					if duplicate {
						findings << Finding{
							stmt:       c.es_tree_position(t, ev.node)
							message_id: 'duplicate'
						}
					} else if !info.super_is_constructor {
						findings << Finding{
							stmt:       c.es_tree_position(t, ev.node)
							message_id: 'badSuper'
						}
					} else {
						infos[last].valid_nodes << ev.node
					}
				}
			}
			.enter_node {
				// ReturnStatement
				if t.typ(ev.node) != .return_statement {
					continue
				}
				info := stack[stack.len - 1]
				if !(info.is_constructor && info.has_extends) {
					continue
				}
				if t.node(ev.node, .argument) == none {
					continue
				}
				for segment in info.current_segments {
					if an.segments[segment].reachable {
						infos[segment].called_in_some_paths = true
						infos[segment].called_in_every_paths = true
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn csup_is_called_in_some_path(an &codepath.Analysis, infos map[int]CsupSegmentInfo, segment int) bool {
	return an.segments[segment].reachable && (infos[segment] or { return false }).called_in_some_paths
}

fn csup_is_called_in_every_path(an &codepath.Analysis, infos map[int]CsupSegmentInfo, segment int) bool {
	return an.segments[segment].reachable && (infos[segment] or { return false }).called_in_every_paths
}

// csup_is_constructor_function ports isConstructorFunction: the FunctionExpression of a
// `constructor` method.
fn csup_is_constructor_function(t &estree.EsTree, node int) bool {
	if t.typ(node) != .function_expression {
		return false
	}
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) == .method_definition
		&& (t.string_of(parent, .kind) or { '' }) == 'constructor'
}

// csup_is_possible_constructor ports isPossibleConstructor: whether the expression may be a
// constructor.
fn csup_is_possible_constructor(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	return match t.typ(node) {
		.class_expression, .function_expression, .this_expression, .member_expression,
		.call_expression, .new_expression, .chain_expression, .yield_expression,
		.tagged_template_expression, .meta_property {
			true
		}
		.identifier {
			(t.string_of(node, .name) or { '' }) != 'undefined'
		}
		.assignment_expression {
			operator := t.string_of(node, .operator) or { '' }
			if operator in ['=', '&&='] {
				csup_is_possible_constructor(t, t.node(node, .right) or { -1 })
			} else if operator in ['||=', '??='] {
				csup_is_possible_constructor(t, t.node(node, .left) or { -1 })
					|| csup_is_possible_constructor(t, t.node(node, .right) or { -1 })
			} else {
				false
			}
		}
		.logical_expression {
			// `a && b`: if `a` is false, it is not a constructor.
			if (t.string_of(node, .operator) or { '' }) == '&&' {
				csup_is_possible_constructor(t, t.node(node, .right) or { -1 })
			} else {
				csup_is_possible_constructor(t, t.node(node, .left) or { -1 })
					|| csup_is_possible_constructor(t, t.node(node, .right) or { -1 })
			}
		}
		.conditional_expression {
			csup_is_possible_constructor(t, t.node(node, .alternate) or { -1 })
				|| csup_is_possible_constructor(t, t.node(node, .consequent) or { -1 })
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { []int{} }
			expressions.len > 0 && csup_is_possible_constructor(t, expressions.last())
		}
		else {
			false
		}
	}
}
