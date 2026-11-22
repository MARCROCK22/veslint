module rules

import estree
import json2
import time

// Port of the `promise/always-return` rule of eslint-plugin-promise 7.3.0, with its options, on
// the code path events of the codepath module.

const prm_always_return_messages = {
	'thenShouldReturnOrThrow': 'Each then() should return a value or throw'
}

struct PrmAlwaysReturn {
	ignore_last_callback       bool
	ignore_assignment_variable []string
}

fn prm_always_return_options(options []json2.Any) !PrmAlwaysReturn {
	o := option_object(promise_always_return, options, ['ignoreLastCallback', 'ignoreAssignmentVariable'])!
	// `options.ignoreAssignmentVariable || ['globalThis']`: an empty list stays empty.
	variables := if 'ignoreAssignmentVariable' in o.values {
		o.string_list('ignoreAssignmentVariable')!
	} else {
		['globalThis']
	}
	return PrmAlwaysReturn{
		ignore_last_callback:       o.bool_value('ignoreLastCallback')!
		ignore_assignment_variable: variables
	}
}

// prm_is_member_call_named ports isMemberCall: a call of the non-computed member `name`.
fn prm_is_member_call_named(t &estree.EsTree, name string, node int) bool {
	if !prm_is_member_call(t, node) {
		return false
	}
	callee := prm_child(t, node, .callee)
	property := prm_child(t, callee, .property)
	return !(t.flag(callee, .computed) or { false }) && t.typ(property) == .identifier
		&& prm_name(t, property) == name
}

// prm_is_inline_then_function_expression ports isInlineThenFunctionExpression: a function with a
// block body given as the first argument of a `.then()` call.
fn prm_is_inline_then_function_expression(t &estree.EsTree, node int) bool {
	with_block := match t.typ(node) {
		.function_expression { true }
		.arrow_function_expression { t.typ(prm_child(t, node, .body)) == .block_statement }
		else { false }
	}
	if !with_block {
		return false
	}
	parent := t.nodes[node].parent
	if !prm_is_member_call_named(t, 'then', parent) {
		return false
	}
	args := t.list(parent, .arguments) or { return false }
	return args.len > 0 && args[0] == node
}

// prm_is_last_callback ports isLastCallback: the `.then()` call is the last of its promise chain.
fn prm_is_last_callback(t &estree.EsTree, node int) bool {
	mut target := t.nodes[node].parent
	mut parent := t.nodes[target].parent
	for parent >= 0 {
		match t.typ(parent) {
			.expression_statement {
				return true
			}
			.unary_expression {
				return (t.string_of(parent, .operator) or { '' }) == 'void'
			}
			else {}
		}
		mut next_target := -1
		match t.typ(parent) {
			.sequence_expression {
				expressions := t.list(parent, .expressions) or { []int{} }
				if expressions.len == 0 || expressions.last() != target {
					return true
				}
				next_target = parent
			}
			.chain_expression, .await_expression {
				next_target = parent
			}
			.member_expression {
				grand := t.nodes[parent].parent
				if grand >= 0 && (prm_is_member_call_named(t, 'catch', grand)
					|| prm_is_member_call_named(t, 'finally', grand)) {
					next_target = grand
				}
			}
			else {}
		}
		if next_target < 0 {
			return false
		}
		target = next_target
		parent = t.nodes[target].parent
	}
	return false
}

// prm_root_object_name ports getRootObjectName ('' for undefined).
fn prm_root_object_name(t &estree.EsTree, node int) string {
	return match t.typ(node) {
		.identifier { prm_name(t, node) }
		.member_expression { prm_root_object_name(t, prm_child(t, node, .object)) }
		else { '' }
	}
}

// prm_is_ignored_assignment ports isIgnoredAssignment.
fn prm_is_ignored_assignment(t &estree.EsTree, node int, ignored []string) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	expression := prm_child(t, node, .expression)
	if t.typ(expression) != .assignment_expression {
		return false
	}
	name := prm_root_object_name(t, prm_child(t, expression, .left))
	return name != '' && name in ignored
}

// prm_is_process_exit_member: the MemberExpression of
// 'ExpressionStatement > CallExpression > MemberExpression[object.name="process"][property.name=…]'.
fn prm_is_process_exit_member(t &estree.EsTree, node int) bool {
	if t.typ(node) != .member_expression {
		return false
	}
	call := t.nodes[node].parent
	if call < 0 || t.typ(call) != .call_expression {
		return false
	}
	statement := t.nodes[call].parent
	if statement < 0 || t.typ(statement) != .expression_statement {
		return false
	}
	return prm_name(t, prm_child(t, node, .object)) == 'process'
		&& prm_name(t, prm_child(t, node, .property)) in ['exit', 'abort']
}

struct PrmBranch {
mut:
	good bool
	node int
}

struct PrmFuncInfo {
mut:
	branch_id_stack []int
	branch_info_map map[int]PrmBranch
}

fn (mut c Checker) lint_promise_always_return(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := prm_always_return_options(c.rule_options(promise_always_return))!
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut stack := []PrmFuncInfo{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				stack << PrmFuncInfo{}
			}
			.segment_start {
				top := stack.len - 1
				stack[top].branch_id_stack << ev.segment
				stack[top].branch_info_map[ev.segment] = PrmBranch{
					node: ev.node
				}
			}
			.segment_end {
				top := stack.len - 1
				if stack[top].branch_id_stack.len > 0 {
					stack[top].branch_id_stack.delete_last()
				}
			}
			.leave_node {
				// 'ReturnStatement:exit', 'ThrowStatement:exit' and the members of
				// `process.exit()` and `process.abort()`: markCurrentBranchAsGood.
				if t.typ(ev.node) in [.return_statement, .throw_statement]
					|| prm_is_process_exit_member(t, ev.node) {
					top := stack.len - 1
					if stack[top].branch_id_stack.len > 0 {
						current := stack[top].branch_id_stack.last()
						if current in stack[top].branch_info_map {
							stack[top].branch_info_map[current].good = true
						}
					}
				}
			}
			.code_path_end {
				info := stack.pop()
				node := ev.node
				stats.checked++
				if !prm_is_inline_then_function_expression(t, node) {
					continue
				}
				if o.ignore_last_callback && prm_is_last_callback(t, node) {
					continue
				}
				if o.ignore_assignment_variable.len > 0 && prm_is_last_callback(t, node) {
					body := prm_child(t, node, .body)
					if t.typ(body) == .block_statement {
						statements := t.list(body, .body) or { []int{} }
						if statements.any(prm_is_ignored_assignment(t, it, o.ignore_assignment_variable)) {
							continue
						}
					}
				}
				for segment in an.code_paths[ev.code_path].final_segments {
					// A final segment that did not start reachable has no branch: `branch.good`
					// throws, and ESLint stops linting the file.
					branch := info.branch_info_map[segment] or { return []Finding{} }
					if !branch.good {
						findings << Finding{
							stmt:       c.es_tree_position(t, branch.node)
							message_id: 'thenShouldReturnOrThrow'
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
