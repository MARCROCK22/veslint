module rules

import estree
import json2
import time

// Port of the `require-atomic-updates` rule of ESLint 10.15.0, with its option `allowProperties`,
// on the code path events of the codepath module and on veslint's scope tree (rules/scope.v).

const rau_messages = {
	'nonAtomicUpdate':       'Possible race condition: `{{value}}` might be reassigned based on an outdated value of `{{value}}`.'
	'nonAtomicObjectUpdate': 'Possible race condition: `{{value}}` might be assigned based on an outdated state of `{{object}}`.'
}

fn rau_options(options []json2.Any) !bool {
	o := option_object(require_atomic_updates, options, ['allowProperties'])!
	return o.bool_value('allowProperties') or { false }
}

// RauSegmentInfo is what SegmentInfo keeps for a segment: the variables read in it (fresh) and
// those read before an `await` or `yield` (outdated).
struct RauSegmentInfo {
mut:
	outdated map[int]bool
	fresh    map[int]bool
}

// RauFrame is an entry of the rule's stack: one per code path.
struct RauFrame {
	verify bool
	// reference_map is createReferenceMap of a resumable function: the reference of each
	// identifier (by node key), the last one when an identifier has several.
	reference_map map[u64]int
mut:
	current_segments []int // a Set
}

// RauAssignment is a reference whose write expression is the right side of an assignment, with
// its identifier in the ESTree.
struct RauAssignment {
	reference  int
	identifier int
}

fn (mut c Checker) lint_require_atomic_updates(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_properties := rau_options(c.rule_options(require_atomic_updates))!
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	mut infos := map[int]RauSegmentInfo{}
	mut assignments := map[int][]RauAssignment{}
	mut stack := []RauFrame{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				scope := rau_scope_of(tree, t, ev.node)
				verify := scope >= 0 && tree.scopes[scope].kind == .function
					&& ((t.flag(ev.node, .async) or { false })
						|| (t.flag(ev.node, .generator) or { false }))
				mut reference_map := map[u64]int{}
				if verify {
					rau_reference_map(tree, scope, mut reference_map)
				}
				stack << RauFrame{
					verify:        verify
					reference_map: reference_map
				}
			}
			.code_path_end {
				stack.delete_last()
			}
			.segment_start {
				// SegmentInfo#initialize
				mut info := RauSegmentInfo{}
				for prev in an.segments[ev.segment].prev_segments {
					if p := infos[prev] {
						for v, _ in p.outdated {
							info.outdated[v] = true
						}
						for v, _ in p.fresh {
							info.fresh[v] = true
						}
					}
				}
				infos[ev.segment] = info
				rau_add(mut stack[stack.len - 1].current_segments, ev.segment)
			}
			.unreachable_segment_start {
				rau_add(mut stack[stack.len - 1].current_segments, ev.segment)
			}
			.segment_end, .unreachable_segment_end {
				k := stack[stack.len - 1].current_segments.index(ev.segment)
				if k >= 0 {
					stack[stack.len - 1].current_segments.delete(k)
				}
			}
			.enter_node {
				frame := stack[stack.len - 1]
				if t.typ(ev.node) != .identifier || !frame.verify {
					continue
				}
				id := t.ts_node(ev.node) or { continue }
				r := frame.reference_map[node_key(id)] or { continue }
				stats.checked++
				reference := tree.references[r]
				variable := reference.resolved
				write_expr := rau_write_expr(t, ev.node, reference.write)
				parent := t.nodes[ev.node].parent
				is_member_access := parent >= 0 && t.typ(parent) == .member_expression
				// Add a fresh read variable.
				if reference.read && !(write_expr >= 0
					&& (t.string_of(t.nodes[write_expr].parent, .operator) or { '' }) == '=') {
					// SegmentInfo#markAsRead
					for segment in frame.current_segments {
						if segment in infos {
							infos[segment].fresh[variable] = true
							infos[segment].outdated.delete(variable)
						}
					}
				}
				// If the reference is in an assignment's right side (not a declarator's
				// initializer) and the variable is not a local one that does not escape, it is
				// verified when that side is left.
				if write_expr >= 0
					&& (t.node(t.nodes[write_expr].parent, .right) or { -1 }) == write_expr
					&& !rau_is_local_without_escape(tree, variable, is_member_access) {
					assignments[write_expr] << RauAssignment{
						reference:  r
						identifier: ev.node
					}
				}
			}
			.leave_node {
				// ":expression:exit"
				frame := stack[stack.len - 1]
				if !frame.verify || !rau_is_expression(t, ev.node) {
					continue
				}
				// Mark the read variables on this code path as outdated.
				if t.typ(ev.node) in [.await_expression, .yield_expression] {
					// SegmentInfo#makeOutdated
					for segment in frame.current_segments {
						if segment in infos {
							for v, _ in infos[segment].fresh {
								infos[segment].outdated[v] = true
							}
							infos[segment].fresh = map[int]bool{}
						}
					}
				}
				references := assignments[ev.node] or { continue }
				assignments.delete(ev.node)
				parent := t.nodes[ev.node].parent
				for a in references {
					variable := tree.references[a.reference].resolved
					// SegmentInfo#isOutdated
					if !frame.current_segments.any(it in infos && variable in infos[it].outdated) {
						continue
					}
					left := t.node(parent, .left) or { -1 }
					if left == a.identifier {
						findings << Finding{
							stmt:       c.es_tree_position(t, parent)
							message_id: 'nonAtomicUpdate'
							data:       {
								'value': tree.variables[variable].name
							}
						}
					} else if !allow_properties && left >= 0 {
						findings << Finding{
							stmt:       c.es_tree_position(t, parent)
							message_id: 'nonAtomicObjectUpdate'
							data:       {
								'value':  c.src[t.nodes[left].start..t.nodes[left].end]
								'object': tree.variables[variable].name
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

fn rau_add(mut set []int, segment int) {
	if segment !in set {
		set << segment
	}
}

// rau_scope_of ports sourceCode.getScope of the node a code path starts at: the global scope for
// the Program, the function scope of a function, the innermost scope of another node.
fn rau_scope_of(tree &ScopeTree, t &estree.EsTree, node int) int {
	if t.typ(node) == .program {
		return tree.global_scope()
	}
	ts := t.ts_node(node) or { return -1 }
	if t.typ(node) in [.function_declaration, .function_expression, .arrow_function_expression] {
		s := tree.function_scope_of(ts)
		if s >= 0 {
			return s
		}
	}
	return tree.get_scope(ts)
}

// rau_reference_map ports createReferenceMap: the resolved references of a scope and of its child
// scopes that are not functions, by identifier.
fn rau_reference_map(tree &ScopeTree, scope int, mut out map[u64]int) {
	for r in tree.scopes[scope].references {
		if tree.references[r].resolved < 0 {
			continue
		}
		out[node_key(tree.references[r].identifier)] = r
	}
	for child in tree.scopes[scope].children {
		if tree.scopes[child].kind != .function {
			rau_reference_map(tree, child, mut out)
		}
	}
}

// rau_is_local_without_escape ports isLocalVariableWithoutEscape: every reference of the variable
// is in the function that declares it (a parameter whose property is accessed is not local).
fn rau_is_local_without_escape(tree &ScopeTree, variable int, is_member_access bool) bool {
	v := tree.variables[variable]
	if is_member_access && v.defs.any(it.kind == .parameter) {
		return false
	}
	function_scope := tree.scopes[v.scope].variable_scope
	return v.references.all(tree.scopes[tree.references[it].from].variable_scope == function_scope)
}

// rau_is_expression ports esquery's `:expression` class (matchesSelectorClass of ESLint's
// JavaScript language).
fn rau_is_expression(t &estree.EsTree, node int) bool {
	typ := t.typ(node).type_name()
	if typ.ends_with('Expression') || typ.ends_with('Literal') || typ == 'MetaProperty' {
		return true
	}
	if typ == 'Identifier' {
		parent := t.nodes[node].parent
		return parent < 0 || t.typ(parent) != .meta_property
	}
	return false
}

// rau_write_expr ports getWriteExpr: the writeExpr the scope manager gives the reference of the
// identifier (the last one when it has several), or else the right side of the assignment the
// identifier is the target of, through member accesses; -1 for none.
fn rau_write_expr(t &estree.EsTree, id int, write bool) int {
	if write {
		expr := rau_reference_write_expr(t, id)
		if expr >= 0 {
			return expr
		}
	}
	mut node := id
	for {
		parent := t.nodes[node].parent
		if parent < 0 {
			break
		}
		typ := t.typ(parent)
		if typ == .assignment_expression && (t.node(parent, .left) or { -1 }) == node {
			return t.node(parent, .right) or { -1 }
		}
		if typ == .member_expression && (t.node(parent, .object) or { -1 }) == node {
			node = parent
			continue
		}
		break
	}
	return -1
}

// rau_reference_write_expr is the writeExpr of the last write reference typescript-eslint's
// Referencer makes for an identifier that is written: the right side of an `=` assignment (or of a
// compound one to an identifier), of a for-in/of head and the initializer of a declarator, which
// come after those of the default values of the patterns around the identifier; without them, the
// innermost default value.
fn rau_reference_write_expr(t &estree.EsTree, id int) int {
	mut current := id
	mut innermost_default := -1
	for {
		parent := t.nodes[current].parent
		if parent < 0 {
			return innermost_default
		}
		match t.typ(parent) {
			.object_pattern, .array_pattern, .rest_element {
				current = parent
			}
			.property {
				grand := t.nodes[parent].parent
				if grand < 0 || t.typ(grand) != .object_pattern
					|| (t.node(parent, .value) or { -1 }) != current {
					return innermost_default
				}
				current = parent
			}
			.assignment_pattern {
				if (t.node(parent, .left) or { -1 }) != current {
					return innermost_default
				}
				if innermost_default < 0 {
					innermost_default = t.node(parent, .right) or { -1 }
				}
				current = parent
			}
			.assignment_expression {
				if (t.node(parent, .left) or { -1 }) != current {
					return innermost_default
				}
				return t.node(parent, .right) or { -1 }
			}
			.for_in_statement, .for_of_statement {
				if (t.node(parent, .left) or { -1 }) != current {
					return innermost_default
				}
				return t.node(parent, .right) or { -1 }
			}
			.variable_declarator {
				if (t.node(parent, .id) or { -1 }) != current {
					return innermost_default
				}
				// A declaration that is the left of a for-in/of: the iterated value.
				declaration := t.nodes[parent].parent
				head := if declaration >= 0 { t.nodes[declaration].parent } else { -1 }
				if head >= 0 && t.typ(head) in [.for_in_statement, .for_of_statement]
					&& (t.node(head, .left) or { -1 }) == declaration {
					return t.node(head, .right) or { -1 }
				}
				return t.node(parent, .init) or { innermost_default }
			}
			else {
				return innermost_default
			}
		}
	}
	return innermost_default
}
