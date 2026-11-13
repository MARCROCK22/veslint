module rules

import codepath
import estree
import time
import treesitter { node_end, node_kind, node_parent, node_start }

// Port of the `no-useless-assignment` rule of ESLint 10.6.0 (it has no options), on the code path
// events of the codepath module and on veslint's scope tree (rules/scope.v), which the
// identifiers of the ESTree reach through their tree-sitter nodes.

const nuas_messages = {
	'unnecessaryAssignment': "The value assigned to '{{name}}' is not used in subsequent statements."
}

// NuasSegmentInfo is the first and the last identifier seen in a segment (-1 for none).
struct NuasSegmentInfo {
mut:
	first int = -1
	last  int = -1
}

// NuasAssignment is a write of a variable: the identifier written, the node that writes it
// (declarator, assignment or update), the expression assigned (-1 for an update) and the
// segments current then.
struct NuasAssignment {
	variable   int
	identifier int
	node       int
	expression int
	segments   []int
}

struct NuasScopeInfo {
	code_path int
	scope     int
mut:
	segments             map[int]NuasSegmentInfo
	current_segments     []int // a Set: insertion order, no duplicates
	assignments          map[int][]NuasAssignment
	assignment_order     []int // the variables of `assignments`, in insertion order (a Map)
	try_statement_blocks []int
}

struct NuasSubsequent {
	segment    int
	assignment int // index in the list of assignments, -1 for none
}

fn (mut c Checker) lint_no_useless_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	scopes := c.scope_tree(root)
	// typescript-eslint's naming-convention runs collectUnusedVariables when it is created, before
	// the traversal, and that marks variables of the shared scope manager as used (eslintUsed):
	// with it on the file, this rule sees them so.
	marked := if '@typescript-eslint/naming-convention' in c.file_rules {
		c.unused_marked(root, scopes)
	} else {
		map[int]bool{}
	}
	mut code_path_start_scopes := map[int]bool{}
	mut stack := []NuasScopeInfo{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				scope := nuas_scope_of(scopes, t, ev.node)
				stack << NuasScopeInfo{
					code_path: ev.code_path
					scope:     scope
				}
				code_path_start_scopes[scope] = true
			}
			.code_path_end {
				target := stack.pop()
				c.nuas_verify(t, an, scopes, code_path_start_scopes, target, mut findings)
			}
			.segment_start {
				top := stack.len - 1
				stack[top].segments[ev.segment] = NuasSegmentInfo{}
				if ev.segment !in stack[top].current_segments {
					stack[top].current_segments << ev.segment
				}
			}
			.segment_end {
				top := stack.len - 1
				k := stack[top].current_segments.index(ev.segment)
				if k >= 0 {
					stack[top].current_segments.delete(k)
				}
			}
			.enter_node {
				typ := t.typ(ev.node)
				top := stack.len - 1
				if typ == .try_statement {
					stack[top].try_statement_blocks << t.node(ev.node, .block) or { -1 }
				} else if typ in [.identifier, .jsx_identifier] {
					for segment in stack[top].current_segments {
						mut info := stack[top].segments[segment] or { NuasSegmentInfo{} }
						if info.first < 0 {
							info.first = ev.node
						}
						info.last = ev.node
						stack[top].segments[segment] = info
					}
				}
			}
			.leave_node {
				typ := t.typ(ev.node)
				mut pattern := -1
				mut expression := -1
				if typ == .variable_declarator {
					expression = t.node(ev.node, .init) or { continue }
					pattern = t.node(ev.node, .id) or { continue }
				} else if typ == .assignment_expression {
					pattern = t.node(ev.node, .left) or { continue }
					expression = t.node(ev.node, .right) or { -1 }
				} else if typ == .update_expression {
					pattern = t.node(ev.node, .argument) or { continue }
				} else {
					continue
				}
				top := stack.len - 1
				if stack[top].current_segments.len == 0 {
					continue
				}
				stats.checked++
				for identifier in nuas_identifiers_of_pattern(t, pattern) {
					ts := t.ts_node(identifier) or { continue }
					name := t.string_of(identifier, .name) or { continue }
					variable := scopes.find_variable(scopes.get_scope(ts), name, t.nodes[identifier].start)
					if variable < 0 {
						continue
					}
					v := scopes.variables[variable]
					if scopes.scopes[v.scope].kind == .global && v.defs.len == 0 {
						continue
					}
					// Variables of an outer code path are not checked.
					if stack[top].scope != nuas_code_path_start_scope(scopes, code_path_start_scopes,
						v.scope) {
						continue
					}
					if v.eslint_used || variable in marked {
						continue
					}
					if scopes.scopes[v.scope].kind == .esmodule && nuas_is_exported(scopes, v) {
						continue
					}
					if variable !in stack[top].assignments {
						stack[top].assignments[variable] = []NuasAssignment{}
						stack[top].assignment_order << variable
					}
					stack[top].assignments[variable] << NuasAssignment{
						variable:   variable
						identifier: identifier
						node:       ev.node
						expression: expression
						segments:   stack[top].current_segments.clone()
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nuas_scope_of ports sourceCode.getScope(node) for the node that starts a code path: the scope of
// a function is the one it creates.
fn nuas_scope_of(scopes &ScopeTree, t &estree.EsTree, node int) int {
	if t.typ(node) == .program {
		return 0
	}
	ts := t.ts_node(node) or { return 0 }
	if t.typ(node) in [.function_declaration, .function_expression, .arrow_function_expression] {
		s := scopes.function_scope_of(ts)
		if s >= 0 {
			return s
		}
	}
	return scopes.get_scope(ts)
}

// nuas_code_path_start_scope ports getCodePathStartScope: the closest scope, from `scope` up, that
// starts a code path (-1 if none).
fn nuas_code_path_start_scope(scopes &ScopeTree, starts map[int]bool, scope int) int {
	mut target := scope
	for target >= 0 {
		if target in starts {
			return target
		}
		target = scopes.scopes[target].upper
	}
	return -1
}

// nuas_is_exported: a variable of a module that is exported, by its declaration or by an export
// specifier.
fn nuas_is_exported(scopes &ScopeTree, v ScopeVariable) bool {
	for def in v.defs {
		match def.kind {
			.variable {
				// def.parent.parent is an ExportNamedDeclaration
				declaration := node_parent(def.node) or { continue }
				if export := node_parent(declaration) {
					if node_kind(export) == 'export_statement' {
						return true
					}
				}
			}
			.function_name, .class_name {
				if parent := node_parent(def.node) {
					if node_kind(parent) == 'export_statement' {
						return true
					}
				}
			}
			else {}
		}
	}
	for r in v.references {
		if parent := node_parent(scopes.references[r].identifier) {
			if node_kind(parent) == 'export_specifier' {
				return true
			}
		}
	}
	return false
}

// nuas_identifiers_of_pattern ports extractIdentifiersFromPattern.
fn nuas_identifiers_of_pattern(t &estree.EsTree, pattern int) []int {
	mut out := []int{}
	nuas_collect_identifiers(t, pattern, mut out)
	return out
}

fn nuas_collect_identifiers(t &estree.EsTree, pattern int, mut out []int) {
	match t.typ(pattern) {
		.identifier {
			out << pattern
		}
		.object_pattern {
			for property in t.list(pattern, .properties) or { []int{} } {
				nuas_collect_identifiers(t, if t.typ(property) == .property {
					t.node(property, .value) or { continue }
				} else {
					property
				}, mut out)
			}
		}
		.array_pattern {
			for element in t.list(pattern, .elements) or { []int{} } {
				if element >= 0 {
					nuas_collect_identifiers(t, element, mut out)
				}
			}
		}
		.rest_element {
			nuas_collect_identifiers(t, t.node(pattern, .argument) or { return }, mut out)
		}
		.assignment_pattern {
			nuas_collect_identifiers(t, t.node(pattern, .left) or { return }, mut out)
		}
		else {}
	}
}

// nuas_evaluated_after ports isIdentifierEvaluatedAfterAssignment for an identifier at [start, end).
fn nuas_evaluated_after(t &estree.EsTree, a NuasAssignment, start int, end int) bool {
	if start < t.nodes[a.identifier].end {
		return false
	}
	if a.expression >= 0 && t.nodes[a.expression].start <= start && end <= t.nodes[a.expression].end {
		// The identifier is in the expression assigned (`x = x + 1`): it is read before the
		// assignment.
		return false
	}
	return true
}

// nuas_used_between ports isIdentifierUsedBetweenAssignedAndEqualSign.
fn nuas_used_between(t &estree.EsTree, a NuasAssignment, start int, end int) bool {
	if a.expression < 0 {
		return false
	}
	return t.nodes[a.identifier].end <= start && end <= t.nodes[a.expression].start
}

// nuas_verify ports verify(target): each assignment of the code path whose value is not read.
fn (mut c Checker) nuas_verify(t &estree.EsTree, an &codepath.Analysis, scopes &ScopeTree, starts map[int]bool, target NuasScopeInfo, mut findings []Finding) {
	for variable in target.assignment_order {
		mut assignments := target.assignments[variable] or { continue }
		positions := assignments.map(t.nodes[it.identifier].start)
		mut order := []int{len: assignments.len, init: index}
		order.sort_with_compare(fn [positions] (x &int, y &int) int {
			if positions[*x] != positions[*y] {
				return positions[*x] - positions[*y]
			}
			return *x - *y
		})
		assignments = order.map(assignments[it])
		for assignment in assignments {
			if c.nuas_is_unused(t, an, scopes, starts, target, assignment, assignments) {
				findings << Finding{
					stmt:       c.es_tree_position(t, assignment.identifier)
					message_id: 'unnecessaryAssignment'
					data:       {
						'name': t.string_of(assignment.identifier, .name) or { '' }
					}
				}
			}
		}
	}
}

// nuas_used_in_segment ports isIdentifierUsedInSegment.
fn nuas_used_in_segment(t &estree.EsTree, target NuasScopeInfo, segment int, start int, end int) bool {
	info := target.segments[segment] or { return false }
	return info.first >= 0 && info.last >= 0 && t.nodes[info.first].start <= start
		&& end <= t.nodes[info.last].end
}

// nuas_is_unused ports verifyAssignmentIsUsed: true where it reports.
fn (c &Checker) nuas_is_unused(t &estree.EsTree, an &codepath.Analysis, scopes &ScopeTree, starts map[int]bool, target NuasScopeInfo, a NuasAssignment, all []NuasAssignment) bool {
	id_start := t.nodes[a.identifier].start
	id_end := t.nodes[a.identifier].end
	if target.try_statement_blocks.any(it >= 0 && t.nodes[it].start <= id_start
		&& id_end <= t.nodes[it].end) {
		return false
	}
	v := scopes.variables[a.variable]
	reads := v.references.filter(scopes.references[it].read)
	if reads.len == 0 {
		// The variable is never read: no-unused-vars reports it.
		return false
	}
	// otherAssignmentAfterTargetAssignment
	mut other := -1
	for k, b in all {
		if b.identifier == a.identifier {
			continue
		}
		if b.segments.len > 0 && b.segments.all(it !in a.segments) {
			continue
		}
		if nuas_evaluated_after(t, a, t.nodes[b.identifier].start, t.nodes[b.identifier].end) {
			other = k
			break
		}
		if b.expression >= 0 && t.nodes[b.expression].start <= id_start
			&& id_end <= t.nodes[b.expression].end {
			// `a = a + 1` after the target assignment.
			other = k
			break
		}
	}
	mut subsequent := []NuasSubsequent{}
	mut subsequent_built := false
	for r in reads {
		reference := scopes.references[r]
		// A read in a function called later is not followed.
		if target.scope != nuas_code_path_start_scope(scopes, starts, reference.from) {
			return false
		}
		r_start := node_start(reference.identifier)
		r_end := node_end(reference.identifier)
		if nuas_evaluated_after(t, a, r_start, r_end) && (nuas_used_between(t, a, r_start, r_end)
			|| a.segments.any(nuas_used_in_segment(t, target, it, r_start, r_end))) {
			if other >= 0 && nuas_evaluated_after(t, all[other], r_start, r_end) {
				continue
			}
			return false
		}
		if other >= 0 {
			continue
		}
		if !subsequent_built {
			subsequent = nuas_subsequent_segments(t, an, a, all)
			subsequent_built = true
		}
		for s in subsequent {
			if nuas_used_in_segment(t, target, s.segment, r_start, r_end) {
				if s.assignment >= 0 && nuas_evaluated_after(t, all[s.assignment], r_start, r_end) {
					continue
				}
				return false
			}
		}
	}
	return true
}

// nuas_subsequent_segments ports getSubsequentSegments: the segments after the assignment, in
// breadth-first order, each with the other assignment of the variable it holds (that ends the
// path there).
fn nuas_subsequent_segments(t &estree.EsTree, an &codepath.Analysis, a NuasAssignment, all []NuasAssignment) []NuasSubsequent {
	mut results := []NuasSubsequent{}
	mut seen := map[int]bool{}
	mut queue := []int{}
	for segment in a.segments {
		queue << an.segments[segment].next_segments
	}
	mut head := 0
	id_start := t.nodes[a.identifier].start
	id_end := t.nodes[a.identifier].end
	for head < queue.len {
		next := queue[head]
		head++
		if next in seen {
			continue
		}
		seen[next] = true
		mut found := -1
		for k, b in all {
			if next in b.segments && !nuas_used_between(t, b, id_start, id_end) {
				found = k
				break
			}
		}
		if found < 0 {
			queue << an.segments[next].next_segments
		}
		results << NuasSubsequent{
			segment:    next
			assignment: found
		}
	}
	return results
}
