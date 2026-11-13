module rules

import estree
import json2
import time

// Port of the `getter-return` rule of ESLint 10.6.0, on the code path events of the codepath
// module.

const gr_messages = {
	'expected':       'Expected to return a value in {{name}}.'
	'expectedAlways': 'Expected {{name}} to always return a value.'
}

fn gr_options(options []json2.Any) !bool {
	o := option_object(getter_return, options, ['allowImplicit'])!
	return o.bool_value('allowImplicit') or { false }
}

struct GrFuncInfo {
	should_check bool
	node         int
mut:
	has_return       bool
	current_segments []int // a Set: insertion order, no duplicates
}

fn (mut c Checker) lint_getter_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_implicit := gr_options(c.rule_options(getter_return))!
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	// The bottom entry is the rule's initial funcInfo (no code path).
	mut stack := [GrFuncInfo{
		node: -1
	}]
	for ev in an.events {
		top := stack.len - 1
		match ev.kind {
			.code_path_start {
				stack << GrFuncInfo{
					should_check: gr_is_getter(t, ev.node)
					node:         ev.node
				}
			}
			.code_path_end {
				stack.delete_last()
			}
			.segment_start, .unreachable_segment_start {
				if ev.segment !in stack[top].current_segments {
					stack[top].current_segments << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				k := stack[top].current_segments.index(ev.segment)
				if k >= 0 {
					stack[top].current_segments.delete(k)
				}
			}
			.enter_node {
				if t.typ(ev.node) == .return_statement && stack[top].should_check {
					stack[top].has_return = true
					stats.checked++
					if !allow_implicit && t.node(ev.node, .argument) == none {
						findings << Finding{
							stmt:       c.es_tree_position(t, ev.node)
							message_id: 'expected'
							data:       {
								'name': c.es_tree_function_name(t, stack[top].node)
							}
						}
					}
				}
			}
			.leave_node {
				// "FunctionExpression:exit" and "ArrowFunctionExpression:exit": checkLastSegment.
				if t.typ(ev.node) in [.function_expression, .arrow_function_expression] {
					info := stack[top]
					stats.checked++
					if info.should_check && an.is_any_reachable(info.current_segments) {
						findings << Finding{
							stmt:       c.es_tree_function_head(t, ev.node)
							message_id: if info.has_return { 'expectedAlways' } else { 'expected' }
							data:       {
								'name': c.es_tree_function_name(t, info.node)
							}
						}
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// gr_is_getter ports isGetter: a function with a block body that is a getter, or the `get` of a
// property descriptor given to Object.defineProperty, Reflect.defineProperty,
// Object.defineProperties or Object.create.
fn gr_is_getter(t &estree.EsTree, node int) bool {
	if t.typ(node) !in [.function_expression, .arrow_function_expression] {
		return false
	}
	body := t.node(node, .body) or { return false }
	if t.typ(body) != .block_statement {
		return false
	}
	parent := t.nodes[node].parent
	if (t.string_of(parent, .kind) or { '' }) == 'get' {
		return true
	}
	if t.typ(parent) != .property || (es_tree_static_property_name(t, parent) or { '' }) != 'get' {
		return false
	}
	object := t.nodes[parent].parent
	if t.typ(object) != .object_expression {
		return false
	}
	call := t.nodes[object].parent
	if t.typ(call) == .call_expression {
		callee := t.node(call, .callee) or { -1 }
		if es_tree_is_specific_member_access(t, callee, 'Object', 'defineProperty')
			|| es_tree_is_specific_member_access(t, callee, 'Reflect', 'defineProperty') {
			return true
		}
	}
	if t.typ(call) == .property {
		outer_object := t.nodes[call].parent
		if outer_object >= 0 && t.typ(outer_object) == .object_expression {
			outer := t.nodes[outer_object].parent
			if outer >= 0 && t.typ(outer) == .call_expression {
				callee := t.node(outer, .callee) or { -1 }
				return es_tree_is_specific_member_access(t, callee, 'Object', 'defineProperties')
					|| es_tree_is_specific_member_access(t, callee, 'Object', 'create')
			}
		}
	}
	return false
}
