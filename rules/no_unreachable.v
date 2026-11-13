module rules

import codepath
import estree
import time

// Port of the `no-unreachable` rule of ESLint 10.6.0 (it has no options), on the code path events
// of the codepath module.

const nunr_messages = {
	'unreachableCode': 'Unreachable code.'
}

// The statements reported when they cannot be reached (VariableDeclaration aside).
const nunr_statements = [estree.NodeType.block_statement, .break_statement, .class_declaration,
	.continue_statement, .debugger_statement, .do_while_statement, .expression_statement,
	.for_in_statement, .for_of_statement, .for_statement, .if_statement, .import_declaration,
	.labeled_statement, .return_statement, .switch_statement, .throw_statement, .try_statement,
	.while_statement, .with_statement, .export_named_declaration, .export_default_declaration,
	.export_all_declaration]

// NunrRange ports ConsecutiveRange: the first and the last node of a run of unreachable code
// (-1 when empty).
struct NunrRange {
mut:
	start_node int = -1
	end_node   int = -1
}

struct NunrConstructorInfo {
mut:
	has_super_call bool
}

fn (mut c Checker) lint_no_unreachable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut rng := NunrRange{}
	mut constructors := []NunrConstructorInfo{}
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
			.segment_start, .unreachable_segment_start {
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
			.enter_node {
				typ := t.typ(ev.node)
				if typ in nunr_statements {
					stats.checked++
					c.nunr_report_if_unreachable(t, an, current, ev.node, mut rng, mut findings)
				} else if typ == .variable_declaration {
					stats.checked++
					declarations := t.list(ev.node, .declarations) or { []int{} }
					if (t.string_of(ev.node, .kind) or { '' }) != 'var'
						|| declarations.any(t.node(it, .init) != none) {
						c.nunr_report_if_unreachable(t, an, current, ev.node, mut rng, mut
							findings)
					}
				} else if typ == .method_definition
					&& (t.string_of(ev.node, .kind) or { '' }) == 'constructor' {
					constructors << NunrConstructorInfo{}
				} else if typ == .super {
					// "CallExpression > Super.callee"
					parent := t.nodes[ev.node].parent
					if constructors.len > 0 && parent >= 0 && t.typ(parent) == .call_expression
						&& (t.node(parent, .callee) or { -1 }) == ev.node {
						constructors[constructors.len - 1].has_super_call = true
					}
				}
			}
			.leave_node {
				typ := t.typ(ev.node)
				if typ == .method_definition
					&& (t.string_of(ev.node, .kind) or { '' }) == 'constructor' {
					has_super_call := constructors.pop().has_super_call
					value := t.node(ev.node, .value) or { continue }
					if t.node(value, .body) == none {
						continue
					}
					class_definition := t.nodes[t.nodes[ev.node].parent].parent
					if t.node(class_definition, .super_class) != none && !has_super_call {
						class_body := t.node(class_definition, .body) or { continue }
						for element in t.list(class_body, .body) or { []int{} } {
							if t.typ(element) == .property_definition
								&& !(t.flag(element, .static_) or { false }) {
								c.nunr_report_if_unreachable(t, an, current, element, mut rng, mut
									findings)
							}
						}
					}
				} else if typ == .program {
					c.nunr_report_if_unreachable(t, an, current, -1, mut rng, mut findings)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nunr_report_if_unreachable ports reportIfUnreachable (`node` -1 at the end of the program).
fn (mut c Checker) nunr_report_if_unreachable(t &estree.EsTree, an &codepath.Analysis, current []int, node int, mut rng NunrRange, mut findings []Finding) {
	mut next_node := -1
	if node >= 0 && (t.typ(node) == .property_definition || !an.is_any_reachable(current)) {
		if rng.start_node < 0 || rng.end_node < 0 {
			rng.start_node = node
			rng.end_node = node
			return
		}
		if c.nunr_contains(t, rng, t.nodes[node].start, t.nodes[node].end) {
			return
		}
		// isConsecutive: the token before the node is in the range.
		tokens := c.source_tokens(t.nodes[t.root].ts)
		if before := tokens.before(t.nodes[node].start, false) {
			if c.nunr_contains(t, rng, before.start, before.end) {
				rng.end_node = node
				return
			}
		}
		next_node = node
	}
	if rng.start_node >= 0 && rng.end_node >= 0 {
		findings << Finding{
			stmt:       c.position_range(t.nodes[rng.start_node].start, t.nodes[rng.end_node].end)
			message_id: 'unreachableCode'
		}
	}
	rng.start_node = next_node
	rng.end_node = next_node
}

fn (c &Checker) nunr_contains(t &estree.EsTree, rng NunrRange, start int, end int) bool {
	return start >= t.nodes[rng.start_node].start && end <= t.nodes[rng.end_node].end
}
