module codepath

import math
import estree

// code-path-analyzer.js, driven as SourceCode#traverse drives it: for each node entered,
// preprocess, processCodePathToEnter, then the node's own event; for each node left,
// processCodePathToExit, the node's `:exit` event, then postprocess.

struct Analyzer {
	t &estree.EsTree
mut:
	an       Analysis
	cp       int = -1 // the current code path
	states   []&State
	cur_node int = -1
}

fn (mut a Analyzer) emit(kind EventKind, cp int, seg int, to int, node int) {
	a.an.events << Event{
		kind:       kind
		node:       node
		code_path:  cp
		segment:    seg
		to_segment: to
	}
}

fn (mut a Analyzer) emit_segment(kind EventKind, seg int, node int) {
	a.emit(kind, a.an.segments[seg].code_path, seg, -1, node)
}

// on_looped is CodePathAnalyzer#onLooped.
fn (mut a Analyzer) on_looped(from int, to int) {
	if a.an.segments[from].reachable && a.an.segments[to].reachable {
		a.emit(.segment_loop, a.an.segments[from].code_path, from, to, a.cur_node)
	}
}

fn (mut a Analyzer) enter_node(node int) {
	a.cur_node = node
	if a.t.nodes[node].parent >= 0 {
		a.preprocess(node)
	}
	a.process_code_path_to_enter(node)
	a.emit(.enter_node, a.cp, -1, -1, node)
	a.cur_node = -1
}

fn (mut a Analyzer) leave_node(node int) {
	a.cur_node = node
	a.process_code_path_to_exit(node)
	a.emit(.leave_node, a.cp, -1, -1, node)
	a.postprocess(node)
	a.cur_node = -1
}

// ---------------------------------------------------------------------------------------------
// Helpers of code-path-analyzer.js

fn (a &Analyzer) child(node int, key estree.Key) int {
	return a.t.node(node, key) or { -1 }
}

fn (a &Analyzer) operator(node int) string {
	return a.t.string_of(node, .operator) or { '' }
}

fn (a &Analyzer) is_optional(node int) bool {
	return a.t.flag(node, .optional) or { false }
}

fn is_handled_logical_operator(op string) bool {
	return op in ['&&', '||', '??']
}

fn is_logical_assignment_operator(op string) bool {
	return op in ['&&=', '||=', '??=']
}

// is_property_definition_value is isPropertyDefinitionValue.
fn (a &Analyzer) is_property_definition_value(node int) bool {
	parent := a.t.nodes[node].parent
	return parent >= 0 && a.t.typ(parent) == .property_definition
		&& a.child(parent, .value) == node
}

// get_label is getLabel ('' for null).
fn (a &Analyzer) get_label(node int) string {
	parent := a.t.nodes[node].parent
	if parent >= 0 && a.t.typ(parent) == .labeled_statement {
		label := a.child(parent, .label)
		return a.t.string_of(label, .name) or { '' }
	}
	return ''
}

// label_name is `node.label && node.label.name` ('' for none).
fn (a &Analyzer) label_name(node int) string {
	label := a.child(node, .label)
	if label < 0 {
		return ''
	}
	return a.t.string_of(label, .name) or { '' }
}

// is_breakable_type is breakableTypePattern of ast-utils.
fn is_breakable_type(typ estree.NodeType) bool {
	return typ in [.while_statement, .do_while_statement, .for_statement, .for_in_statement,
		.for_of_statement, .switch_statement]
}

// is_forking_by_true_or_false is isForkingByTrueOrFalse.
fn (a &Analyzer) is_forking_by_true_or_false(node int) bool {
	parent := a.t.nodes[node].parent
	return match a.t.typ(parent) {
		.conditional_expression, .if_statement, .while_statement, .do_while_statement,
		.for_statement {
			a.child(parent, .test) == node
		}
		.logical_expression {
			is_handled_logical_operator(a.operator(parent))
		}
		.assignment_expression {
			is_logical_assignment_operator(a.operator(parent))
		}
		else {
			false
		}
	}
}

// get_boolean_value_if_simple_constant is getBooleanValueIfSimpleConstant: `Boolean(value)`
// of a Literal, none (undefined) for another node.
fn (a &Analyzer) get_boolean_value_if_simple_constant(node int) ?bool {
	if a.t.typ(node) != .literal {
		return none
	}
	v := a.t.get(node, .value)
	return match v {
		estree.Undefined, estree.Null { false }
		bool { v }
		f64 { v != 0 && !math.is_nan(v) }
		string { v.len > 0 }
		estree.BigIntValue { v.digits.trim_left('-') != '0' }
		else { true }
	}
}

// is_identifier_reference is isIdentifierReference.
fn (a &Analyzer) is_identifier_reference(node int) bool {
	parent := a.t.nodes[node].parent
	if parent < 0 {
		return true
	}
	return match a.t.typ(parent) {
		.labeled_statement, .break_statement, .continue_statement, .array_pattern, .rest_element,
		.import_specifier, .import_default_specifier, .import_namespace_specifier, .catch_clause {
			false
		}
		.function_declaration, .function_expression, .arrow_function_expression,
		.class_declaration, .class_expression, .variable_declarator {
			a.child(parent, .id) != node
		}
		.property, .property_definition, .method_definition {
			a.child(parent, .key) != node || (a.t.flag(parent, .computed) or { false })
				|| (a.t.flag(parent, .shorthand) or { false })
		}
		.assignment_pattern {
			a.child(parent, .key) != node
		}
		else {
			true
		}
	}
}

// forward_current_to_head is forwardCurrentToHead.
fn (mut a Analyzer) forward_current_to_head(node int) {
	mut st := a.st()
	current_segments := st.current_segments
	head_segments := st.fork.head()
	end := if current_segments.len > head_segments.len {
		current_segments.len
	} else {
		head_segments.len
	}
	for i in 0 .. end {
		current := if i < current_segments.len { current_segments[i] } else { -1 }
		head := if i < head_segments.len { head_segments[i] } else { -1 }
		if current != head && current >= 0 {
			kind := if a.an.segments[current].reachable {
				EventKind.segment_end
			} else {
				EventKind.unreachable_segment_end
			}
			a.emit_segment(kind, current, node)
		}
	}
	st.current_segments = head_segments
	for i in 0 .. end {
		current := if i < current_segments.len { current_segments[i] } else { -1 }
		head := if i < head_segments.len { head_segments[i] } else { -1 }
		if current != head && head >= 0 {
			kind := if a.an.segments[head].reachable {
				EventKind.segment_start
			} else {
				EventKind.unreachable_segment_start
			}
			a.mark_used(head)
			a.emit_segment(kind, head, node)
		}
	}
}

// leave_from_current_segment is leaveFromCurrentSegment.
fn (mut a Analyzer) leave_from_current_segment(node int) {
	mut st := a.st()
	for seg in st.current_segments {
		kind := if a.an.segments[seg].reachable {
			EventKind.segment_end
		} else {
			EventKind.unreachable_segment_end
		}
		a.emit_segment(kind, seg, node)
	}
	st.current_segments = []int{}
}

// preprocess updates the code path before a node is entered, for the parts of its parent that
// fork (the consequent of an if, the right side of a logical expression…).
fn (mut a Analyzer) preprocess(node int) {
	parent := a.t.nodes[node].parent
	match a.t.typ(parent) {
		.call_expression {
			if a.is_optional(parent) {
				args := a.t.list(parent, .arguments) or { []int{} }
				if args.len >= 1 && args[0] == node {
					a.make_optional_right()
				}
			}
		}
		.member_expression {
			if a.is_optional(parent) && a.child(parent, .property) == node {
				a.make_optional_right()
			}
		}
		.logical_expression {
			if a.child(parent, .right) == node && is_handled_logical_operator(a.operator(parent)) {
				a.make_logical_right()
			}
		}
		.assignment_expression {
			if a.child(parent, .right) == node
				&& is_logical_assignment_operator(a.operator(parent)) {
				a.make_logical_right()
			}
		}
		.conditional_expression, .if_statement {
			if a.child(parent, .consequent) == node {
				a.make_if_consequent()
			} else if a.child(parent, .alternate) == node {
				a.make_if_alternate()
			}
		}
		.switch_case {
			consequent := a.t.list(parent, .consequent) or { []int{} }
			if consequent.len > 0 && consequent[0] == node {
				a.make_switch_case_body(false, a.child(parent, .test) < 0)
			}
		}
		.try_statement {
			if a.child(parent, .handler) == node {
				a.make_catch_block()
			} else if a.child(parent, .finalizer) == node {
				a.make_finally_block()
			}
		}
		.while_statement {
			if a.child(parent, .test) == node {
				a.make_while_test(a.get_boolean_value_if_simple_constant(node))
			} else {
				a.make_while_body()
			}
		}
		.do_while_statement {
			if a.child(parent, .body) == node {
				a.make_do_while_body()
			} else {
				a.make_do_while_test(a.get_boolean_value_if_simple_constant(node))
			}
		}
		.for_statement {
			if a.child(parent, .test) == node {
				a.make_for_test(a.get_boolean_value_if_simple_constant(node))
			} else if a.child(parent, .update) == node {
				a.make_for_update()
			} else if a.child(parent, .body) == node {
				a.make_for_body()
			}
		}
		.for_in_statement, .for_of_statement {
			if a.child(parent, .left) == node {
				a.make_for_in_of_left()
			} else if a.child(parent, .right) == node {
				a.make_for_in_of_right()
			} else {
				a.make_for_in_of_body()
			}
		}
		.assignment_pattern {
			// The right side of a default value forks: it is evaluated or not.
			if a.child(parent, .right) == node {
				a.push_fork_context(false)
				a.fork_bypass_path()
				a.fork_path()
			}
		}
		else {}
	}
}

fn (mut a Analyzer) start_code_path(origin Origin, node int) {
	upper := a.cp
	if upper >= 0 {
		a.forward_current_to_head(node)
	}
	cp := a.an.code_paths.len
	a.an.code_paths << CodePath{
		n:      cp + 1
		origin: origin
		upper:  upper
		node:   node
	}
	if upper >= 0 {
		a.an.code_paths[upper].child_code_paths << cp
	}
	a.cp = cp
	a.states << a.new_state(cp)
	a.emit(.code_path_start, cp, -1, -1, node)
}

// process_code_path_to_enter is processCodePathToEnter.
fn (mut a Analyzer) process_code_path_to_enter(node int) {
	parent := a.t.nodes[node].parent
	if a.is_property_definition_value(node) {
		a.start_code_path(.class_field_initializer, node)
	}
	typ := a.t.typ(node)
	match typ {
		.program {
			a.start_code_path(.program, node)
		}
		.function_declaration, .function_expression, .arrow_function_expression {
			a.start_code_path(.function, node)
		}
		.static_block {
			a.start_code_path(.class_static_block, node)
		}
		.chain_expression {
			a.push_chain_context()
		}
		.call_expression, .member_expression {
			if a.is_optional(node) {
				a.make_optional_node()
			}
		}
		.logical_expression {
			op := a.operator(node)
			if is_handled_logical_operator(op) {
				a.push_choice_context(op, a.is_forking_by_true_or_false(node))
			}
		}
		.assignment_expression {
			op := a.operator(node)
			if is_logical_assignment_operator(op) {
				a.push_choice_context(op[..op.len - 1], a.is_forking_by_true_or_false(node))
			}
		}
		.conditional_expression, .if_statement {
			a.push_choice_context('test', false)
		}
		.switch_statement {
			cases := a.t.list(node, .cases) or { []int{} }
			has_case := cases.any(a.child(it, .test) >= 0)
			a.push_switch_context(has_case, a.get_label(node))
		}
		.try_statement {
			a.push_try_context(a.child(node, .finalizer) >= 0)
		}
		.switch_case {
			// Fork if this node is after the second case.
			cases := a.t.list(parent, .cases) or { []int{} }
			if a.child(parent, .discriminant) != node && (cases.len == 0 || cases[0] != node) {
				a.fork_path()
			}
		}
		.while_statement, .do_while_statement, .for_statement, .for_in_statement,
		.for_of_statement {
			a.push_loop_context(typ, a.get_label(node))
		}
		.labeled_statement {
			body := a.child(node, .body)
			if !is_breakable_type(a.t.typ(body)) {
				a.push_break_context(false, a.label_name(node))
			}
		}
		else {}
	}
	a.forward_current_to_head(node)
}

// process_code_path_to_exit is processCodePathToExit.
fn (mut a Analyzer) process_code_path_to_exit(node int) {
	mut dont_forward := false
	match a.t.typ(node) {
		.chain_expression {
			a.pop_chain_context()
		}
		.if_statement, .conditional_expression {
			a.pop_choice_context()
		}
		.logical_expression {
			if is_handled_logical_operator(a.operator(node)) {
				a.pop_choice_context()
			}
		}
		.assignment_expression {
			if is_logical_assignment_operator(a.operator(node)) {
				a.pop_choice_context()
			}
		}
		.switch_statement {
			a.pop_switch_context()
		}
		.switch_case {
			// An empty case (`case 0: case 1: …`) is a body of its own here.
			consequent := a.t.list(node, .consequent) or { []int{} }
			if consequent.len == 0 {
				a.make_switch_case_body(true, a.child(node, .test) < 0)
			}
			if a.fork_reachable(a.st().fork) {
				dont_forward = true
			}
		}
		.try_statement {
			a.pop_try_context()
		}
		.break_statement {
			a.forward_current_to_head(node)
			a.make_break(a.label_name(node))
			dont_forward = true
		}
		.continue_statement {
			a.forward_current_to_head(node)
			a.make_continue(a.label_name(node))
			dont_forward = true
		}
		.return_statement {
			a.forward_current_to_head(node)
			a.make_return()
			dont_forward = true
		}
		.throw_statement {
			a.forward_current_to_head(node)
			a.make_throw()
			dont_forward = true
		}
		.identifier {
			if a.is_identifier_reference(node) {
				a.make_first_throwable_path_in_try_or_catch_block()
				dont_forward = true
			}
		}
		.call_expression, .import_expression, .member_expression, .new_expression {
			a.make_first_throwable_path_in_try_or_catch_block()
		}
		.yield_expression {
			a.make_yield()
		}
		.while_statement, .do_while_statement, .for_statement, .for_in_statement,
		.for_of_statement {
			a.pop_loop_context()
		}
		.assignment_pattern {
			a.pop_fork_context()
		}
		.labeled_statement {
			body := a.child(node, .body)
			if !is_breakable_type(a.t.typ(body)) {
				a.pop_break_context()
			}
		}
		else {}
	}
	if !dont_forward {
		a.forward_current_to_head(node)
	}
}

fn (mut a Analyzer) end_code_path(node int) {
	a.make_final()
	a.leave_from_current_segment(node)
	a.emit(.code_path_end, a.cp, -1, -1, node)
	a.cp = a.an.code_paths[a.cp].upper
}

// postprocess is postprocess of code-path-analyzer.js: after a node's `:exit` event.
fn (mut a Analyzer) postprocess(node int) {
	match a.t.typ(node) {
		.program, .function_declaration, .function_expression, .arrow_function_expression,
		.static_block {
			a.end_code_path(node)
		}
		.call_expression {
			// `a?.()`: the optional call has no argument to make its right side.
			args := a.t.list(node, .arguments) or { []int{} }
			if a.is_optional(node) && args.len == 0 {
				a.make_optional_right()
			}
		}
		else {}
	}
	if a.is_property_definition_value(node) {
		a.end_code_path(node)
	}
}
