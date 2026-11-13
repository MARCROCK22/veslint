module rules

import estree
import json2
import time

// Port of the `no-unreachable-loop` rule of ESLint 10.6.0, on the code path events of the
// codepath module.

const nurl_messages = {
	'invalid': 'Invalid loop. Its body allows only one iteration.'
}

const nurl_loop_types = ['WhileStatement', 'DoWhileStatement', 'ForStatement', 'ForInStatement',
	'ForOfStatement']

fn nurl_options(options []json2.Any) ![]string {
	o := option_object(no_unreachable_loop, options, ['ignore'])!
	return o.string_list('ignore')!
}

fn (mut c Checker) lint_no_unreachable_loop(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignored := nurl_options(c.rule_options(no_unreachable_loop))!
	checked := nurl_loop_types.filter(it !in ignored)
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut loops_by_target_segments := map[int]int{}
	mut loops_to_report := []int{} // a Set: insertion order
	mut code_path_segments := [][]int{}
	mut current := []int{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				code_path_segments << current
				current = []int{}
			}
			.code_path_end {
				current = code_path_segments.pop()
			}
			.unreachable_segment_start {
				if ev.segment !in current {
					current << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				k := current.index(ev.segment)
				if k >= 0 {
					current.delete(k)
				}
			}
			.segment_start {
				if ev.segment !in current {
					current << ev.segment
				}
				if nurl_is_looping_target(t, ev.node) {
					loops_by_target_segments[ev.segment] = t.nodes[ev.node].parent
				}
			}
			.segment_loop {
				if loop := loops_by_target_segments[ev.to_segment] {
					if ev.node == loop || t.typ(ev.node) == .continue_statement {
						k := loops_to_report.index(loop)
						if k >= 0 {
							loops_to_report.delete(k)
						}
					}
				}
			}
			.enter_node {
				if t.typ(ev.node).type_name() in checked {
					stats.checked++
					if an.is_any_reachable(current) && ev.node !in loops_to_report {
						loops_to_report << ev.node
					}
				}
			}
			else {}
		}
	}
	for loop in loops_to_report {
		findings << Finding{
			stmt:       c.position_at(t.nodes[loop].start)
			message_id: 'invalid'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nurl_is_looping_target ports isLoopingTarget: the node a loop goes back to at the end of an
// iteration (the test of a while, the body of a do-while, the update, test or body of a for, the
// left side of a for-in or for-of).
fn nurl_is_looping_target(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.while_statement {
			node == t.node(parent, .test) or { -1 }
		}
		.do_while_statement {
			node == t.node(parent, .body) or { -1 }
		}
		.for_statement {
			node == t.node(parent, .update) or {
				t.node(parent, .test) or { t.node(parent, .body) or { -1 } }
			}
		}
		.for_in_statement, .for_of_statement {
			node == t.node(parent, .left) or { -1 }
		}
		else {
			false
		}
	}
}
