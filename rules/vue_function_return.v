module rules

import estree

// executeOnFunctionsWithoutReturn of eslint-plugin-vue 10.12.1's lib/utils/index.ts, on the code
// path events of the codepath module, with isExhaustiveSwitch of lib/utils/ts-utils/ts-types.ts
// (which reads the types when the parser has a program): the functions that do not always return
// a value.

struct VueFuncInfo {
	node int
mut:
	has_return       bool
	has_return_value bool
	current_segments []int
}

// vue_functions_without_return are the functions executeOnFunctionsWithoutReturn calls back
// with, in order: a function expression (an arrow function without an expression body) one of
// whose current segments is reachable at its exit (a segment that only the no-match edge of an
// exhaustive switch reaches counts as unreachable), or, with `treat_undefined`, whose last
// return has no value.
fn (mut c Checker) vue_functions_without_return(root C.vt_node, abs_path string, treat_undefined bool, mut stats Stats) []int {
	mut out := []int{}
	an := c.code_path_analysis(root, abs_path) or { return out }
	t := c.es_tree(root, abs_path) or { return out }
	// funcInfo is a linked list upstream: a function's code path pushes it, the end of any code
	// path (also a class field's or the program's) pops it.
	mut stack := []VueFuncInfo{}
	mut spurious := map[int]bool{}
	mut case_body := map[int]bool{}
	mut case_depth := 0
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				if t.typ(ev.node) in [.arrow_function_expression, .function_expression,
					.function_declaration] {
					stack << VueFuncInfo{
						node: ev.node
					}
				}
			}
			.code_path_end {
				if stack.len > 0 {
					stack.delete_last()
				}
			}
			.segment_start {
				if stack.len > 0 {
					stack[stack.len - 1].current_segments << ev.segment
				}
				prev := an.segments[ev.segment].prev_segments
				if prev.len > 0
					&& prev.all(!an.segments[it].reachable || spurious[it]) {
					spurious[ev.segment] = true
				}
				if case_depth > 0 {
					case_body[ev.segment] = true
				}
			}
			.segment_end {
				if stack.len > 0 && stack.last().current_segments.len > 0 {
					stack[stack.len - 1].current_segments.delete_last()
				}
			}
			.enter_node {
				match t.typ(ev.node) {
					.return_statement {
						if stack.len > 0 {
							stack[stack.len - 1].has_return = true
							stack[stack.len - 1].has_return_value = t.node(ev.node, .argument) != none
						}
					}
					.switch_case {
						case_depth++
					}
					else {}
				}
			}
			.leave_node {
				match t.typ(ev.node) {
					.switch_case {
						case_depth--
					}
					.switch_statement {
						if stack.len == 0 {
							continue
						}
						cases := t.list(ev.node, .cases) or { []int{} }
						if cases.any(t.node(it, .test) == none)
							|| !c.vue_is_exhaustive_switch(t, ev.node, abs_path, mut stats) {
							continue
						}
						info := stack.last()
						from_case_body := info.current_segments.any(an.segments[it].prev_segments.any(an.segments[it].reachable && !spurious[it] && case_body[it]))
						if from_case_body {
							continue
						}
						for segment in info.current_segments {
							spurious[segment] = true
						}
					}
					.arrow_function_expression, .function_expression {
						if stack.len == 0 {
							continue
						}
						info := stack.last()
						if t.typ(ev.node) == .arrow_function_expression
							&& (t.flag(ev.node, .expression) or { false }) {
							continue
						}
						valid := info.current_segments.all(!an.segments[it].reachable
							|| spurious[it]) && (!treat_undefined || info.has_return_value)
						if !valid {
							out << info.node
						}
					}
					else {}
				}
			}
			else {}
		}
	}
	return out
}

// vue_is_exhaustive_switch ports isExhaustiveSwitch: with a program, every member of the
// discriminant's type (its base constraint) has a literal part a case covers.
fn (mut c Checker) vue_is_exhaustive_switch(t &estree.EsTree, switch_node int, abs_path string, mut stats Stats) bool {
	if !c.scope_setup.type_information {
		return false
	}
	discriminant := t.node(switch_node, .discriminant) or { return false }
	discriminant_type := c.unb_type_of(t, discriminant, abs_path, mut stats) or { return false }
	constrained := c.constrained(discriminant_type) or { return false }
	mut case_types := []int{}
	mut has_undefined_case := false
	for case_node in t.list(switch_node, .cases) or { []int{} } {
		test := t.node(case_node, .test) or { return true }
		case_type := c.unb_type_of(t, test, abs_path, mut stats) or { return false }
		ct := c.constrained(case_type) or { return false }
		case_types << ct.id
		if ct.flags & type_flag_undefined != 0 {
			has_undefined_case = true
		}
	}
	literal_like := u32(1024 | 2048 | 4096 | 8192) | type_flag_undefined | type_flag_null | u32(16384)
	members := c.constituents(constrained) or { return false }
	for member in members {
		parts := if member.flags & type_flag_intersection != 0 {
			c.members_of(member) or { return false }
		} else {
			[member]
		}
		covered := parts.any(it.flags & literal_like != 0 && (it.id in case_types
			|| (has_undefined_case && it.flags & type_flag_undefined != 0)))
		if !covered {
			return false
		}
	}
	return true
}
