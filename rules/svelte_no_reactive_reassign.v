module rules

import json2
import estree
import svelte

// Port of the `svelte/no-reactive-reassign` rule of eslint-plugin-svelte 3.24.1: a value computed by
// `$: x = …` must not be reassigned elsewhere (`x = …`, `x++`, `for (x of …)`, `bind:value={x}`,
// …), nor its properties with `props` (default true: `x.a = …`, `delete x.a`, `x.push(…)`). Its
// conditions leave runes mode out. It reads the document's scope manager.

const svnrr_messages = {
	'assignmentToReactiveValue':     "Assignment to reactive value '{{name}}'."
	'assignmentToReactiveValueProp': "Assignment to property of reactive value '{{name}}'."
}

fn svnrr_options(options []json2.Any) !bool {
	if options.len > 0 {
		if first := options[0] {
			if first is map[string]json2.Any {
				if props := first.as_map()['props'] {
					return props.json_str() != 'false'
				}
			}
		}
	}
	return true
}

// SvnrrReassign is what getReassignData gives: the node of the reassign and how many members are
// on the way to it.
struct SvnrrReassign {
	node  svelte.Ref
	depth int
}

// svnrr_reassign is getReassignData of an identifier of the document.
fn (c &Checker) svnrr_reassign(id int) ?SvnrrReassign {
	doc := c.svelte.doc
	es := &doc.es
	mut node := sv_es_ref(id)
	mut depth := 0
	mut last_member := -1
	mut members := []int{}
	for {
		parent := c.sv_parent(node) or { return none }
		if !parent.es {
			p := doc.nodes[parent.idx]
			if p.typ != .directive || p.kind != 'Binding' {
				return none
			}
			if p.shorthand || (p.expression.es == node.es && p.expression.idx == node.idx) {
				return SvnrrReassign{parent, depth}
			}
			return none
		}
		pi := parent.idx
		is_child := fn [es, node] (pi int, key estree.Key) bool {
			return node.es && (es.node(pi, key) or { -1 }) == node.idx
		}
		match es.typ(pi) {
			.update_expression {
				return SvnrrReassign{parent, depth}
			}
			.unary_expression {
				if (es.string_of(pi, .operator) or { '' }) == 'delete' {
					return SvnrrReassign{parent, depth}
				}
				return none
			}
			.assignment_expression, .for_in_statement, .for_of_statement {
				if is_child(pi, .left) {
					return SvnrrReassign{parent, depth}
				}
				return none
			}
			.call_expression {
				if depth > 0 && is_child(pi, .callee) {
					name := c.svsc_property_name(last_member) or { return none }
					if name in ['push', 'pop', 'shift', 'unshift', 'reverse', 'splice', 'sort',
						'copyWithin', 'fill'] {
						members.pop()
						return SvnrrReassign{parent, members.len}
					}
				}
				return none
			}
			.member_expression {
				if !is_child(pi, .object) {
					return none
				}
				members << pi
				last_member = pi
				depth = members.len
			}
			.chain_expression {}
			.conditional_expression {
				if is_child(pi, .test) {
					return none
				}
			}
			.property {
				outer := es.nodes[pi].parent
				if !is_child(pi, .value) || outer < 0 || es.typ(outer) != .object_pattern {
					return none
				}
				node = sv_es_ref(outer)
				continue
			}
			.array_pattern {
				if !node.es || node.idx !in (es.list(pi, .elements) or { []int{} }) {
					return none
				}
			}
			.rest_element {
				outer := es.nodes[pi].parent
				if !is_child(pi, .argument) || outer < 0 {
					return none
				}
				node = sv_es_ref(outer)
				continue
			}
			else {
				return none
			}
		}
		node = parent
	}
	return none
}

fn (mut c Checker) lint_svelte_no_reactive_reassign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	props := svnrr_options(c.rule_options(svelte_no_reactive_reassign))!
	if !c.svsc_runes_off(abs_path) {
		return []
	}
	doc := c.svelte.doc
	es := &doc.es
	info := &doc.scope
	toplevel := c.svsc_toplevel_scope()
	mut findings := []Finding{}
	for statement in c.svsc_reactive_statements() {
		body := es.node(statement, .body) or { continue }
		if es.typ(body) != .expression_statement {
			continue
		}
		assignment := es.node(body, .expression) or { continue }
		if es.typ(assignment) != .assignment_expression
			|| (es.string_of(assignment, .operator) or { '' }) != '=' {
			continue
		}
		left := es.node(assignment, .left) or { continue }
		for v in info.scopes[toplevel].variables {
			variable := info.variables[v]
			if !variable.defs.any(fn [c, assignment] (def svelte.SDef) bool {
				kind, node := c.svsc_def(def)
				return kind == .computed && node == assignment
			}) {
				continue
			}
			for r in variable.references {
				id := info.references[r].identifier
				if svsc_in_range(es, id, es.nodes[left].start, es.nodes[left].end) {
					continue
				}
				reassign := c.svnrr_reassign(id) or { continue }
				if !props && reassign.depth > 0 {
					continue
				}
				findings << c.sv_report_ref(reassign.node, if reassign.depth == 0 {
					'assignmentToReactiveValue'
				} else {
					'assignmentToReactiveValueProp'
				}, {
					'name': es.string_of(id, .name) or { '' }
				})
			}
		}
	}
	return findings
}
