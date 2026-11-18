module rules

import estree
import svelte
import treesitter { node_kind }

// Port of the `svelte/no-top-level-browser-globals` rule of eslint-plugin-svelte 3.24.1: a browser
// global (`window`, `document` and the browser globals of `globals` that Node.js does not have)
// read at the top level of a component or a `.svelte.[js|ts]` module (outside functions and
// snippets, and outside type annotations) is reported, unless a guard makes the place
// browser-only: `browser` of `$app/environment` (or `$app/env`) or `BROWSER` of `esm-env`,
// `!import.meta.env.SSR`, `typeof window !== 'undefined'`, `globalThis.x !== undefined`, an
// optional access `globalThis.x?.y`, in an `if`, a `{#if}`, a `?:` or a `&&` (a guard on
// `window` or `document` makes every global available). The globals and modules are found by
// ReferenceTracker on the lint code; the rest reads the document.

const svntlbg_messages = {
	'unexpectedGlobal': 'Unexpected top-level browser global variable "{{name}}".'
}

// SvntlbgChecker is the function a guard gives: a node is available in one of the ranges, or is
// the node itself (`exact`).
struct SvntlbgChecker {
	ranges [][]int
	exact  int = -1
}

struct SvntlbgGuard {
	checker SvntlbgChecker
	browser bool   // browserEnvironment
	name    string // reference?.name ('' for none)
}

struct SvntlbgState {
mut:
	functions [][]int // ranges of the top-level functions and snippets
	types     [][]int // ranges of the outermost type annotations
	guards    []SvntlbgGuard
}

fn svntlbg_contains(ranges [][]int, start int, end int) bool {
	return ranges.any(it[0] <= start && end <= it[1])
}

fn (c &Checker) svntlbg_range(e &SvscEs, r svelte.Ref) []int {
	if r.es {
		return [e.t.nodes[r.idx].start, e.t.nodes[r.idx].end]
	}
	n := c.svelte.doc.nodes[r.idx]
	return [n.start, n.end]
}

// svntlbg_is_jump is isJumpStatement.
fn svntlbg_is_jump(t &estree.EsTree, s int) bool {
	return t.typ(s) in [.return_statement, .continue_statement, .break_statement]
}

// svntlbg_jumps_in_all_paths is hasJumpStatementInAllPath.
fn svntlbg_jumps_in_all_paths(t &estree.EsTree, s int) bool {
	if svntlbg_is_jump(t, s) {
		return true
	}
	if t.typ(s) == .block_statement {
		return (t.list(s, .body) or { []int{} }).any(svntlbg_jumps_in_all_paths(t, it))
	}
	if t.typ(s) == .if_statement {
		alternate := t.node(s, .alternate) or { return false }
		consequent := t.node(s, .consequent) or { return false }
		return svntlbg_jumps_in_all_paths(t, alternate) && svntlbg_jumps_in_all_paths(t, consequent)
	}
	return false
}

// svntlbg_guard_checker is getGuardChecker: where the guard `node` (or its negation) holds.
fn (c &Checker) svntlbg_guard_checker(e &SvscEs, node svelte.Ref, not bool) ?SvntlbgChecker {
	t := e.t
	parent := c.svsc_parent_ref(e, node.idx)?
	if !parent.es {
		p := c.svelte.doc.nodes[parent.idx]
		if p.typ != .if_block || p.expression.es != node.es || p.expression.idx != node.idx {
			return none
		}
		if !not {
			if p.children.len == 0 {
				return none
			}
			first := c.svelte.doc.nodes[p.children[0]]
			last := c.svelte.doc.nodes[p.children.last()]
			return SvntlbgChecker{
				ranges: [[first.start, last.end]]
			}
		}
		if p.else_ >= 0 {
			block := c.svelte.doc.nodes[p.else_]
			return SvntlbgChecker{
				ranges: [[block.start, block.end]]
			}
		}
		return none
	}
	pi := parent.idx
	child_is := fn [t, node, pi] (key estree.Key) bool {
		return node.es && (t.node(pi, key) or { -1 }) == node.idx
	}
	range_of := fn [t] (i int) SvntlbgChecker {
		return SvntlbgChecker{
			ranges: [[t.nodes[i].start, t.nodes[i].end]]
		}
	}
	match t.typ(pi) {
		.conditional_expression {
			return range_of(t.node(pi, if not { .alternate } else { .consequent })?)
		}
		.unary_expression {
			if (t.string_of(pi, .operator) or { '' }) == '!' {
				return c.svntlbg_guard_checker(e, parent, !not)
			}
		}
		.if_statement {
			if !child_is(.test) {
				return none
			}
			if !not {
				return range_of(t.node(pi, .consequent)?)
			}
			if alternate := t.node(pi, .alternate) {
				return range_of(alternate)
			}
			if !svntlbg_jumps_in_all_paths(t, t.node(pi, .consequent)?) {
				return none
			}
			outer := c.svsc_parent_ref(e, pi)?
			if !outer.es || t.typ(outer.idx) !in [.block_statement, .program] {
				return none
			}
			return SvntlbgChecker{
				ranges: [[t.nodes[pi].end, t.nodes[outer.idx].end]]
			}
		}
		.logical_expression {
			operator := t.string_of(pi, .operator) or { '' }
			if !not && operator == '&&' {
				parent_checker := c.svntlbg_guard_checker(e, parent, not)
				if child_is(.left) {
					right := t.node(pi, .right)?
					mut ranges := [][]int{}
					mut exact := -1
					if pc := parent_checker {
						ranges << pc.ranges
						exact = pc.exact
					}
					ranges << [t.nodes[right].start, t.nodes[right].end]
					return SvntlbgChecker{
						ranges: ranges
						exact:  exact
					}
				}
				return parent_checker
			}
			if not && operator == '||' {
				return c.svntlbg_guard_checker(e, parent, not)
			}
		}
		else {}
	}
	return none
}

// svntlbg_static is getStaticValue of a node of the view (through its lint code node).
fn (mut c Checker) svntlbg_static(b &SvscBridge, i int) ?JsAny {
	lint := b.lint_of(i)?
	ts := b.lint.ts_node(lint)?
	value := c.get_static_value(ts)
	return if value.found { value.value } else { none }
}

// svntlbg_reference_checker is getGuardCheckerFromReference.
fn (mut c Checker) svntlbg_reference_checker(e &SvscEs, b &SvscBridge, node int) ?SvntlbgChecker {
	t := e.t
	parent := c.svsc_parent(e, node)
	if parent < 0 {
		return none
	}
	member := t.typ(node) == .member_expression
	match t.typ(parent) {
		.binary_expression {
			operator := t.string_of(parent, .operator) or { '' }
			left := t.node(parent, .left) or { -1 }
			right := t.node(parent, .right) or { -1 }
			if operator == 'instanceof' && left == node && member {
				return c.svntlbg_guard_checker(e, sv_es_ref(parent), false)
			}
			operand := if left == node {
				right
			} else if right == node {
				left
			} else {
				return none
			}
			value := c.svntlbg_static(b, operand)?
			if value.kind == .undefined_ && member {
				if operator in ['!==', '!='] {
					return c.svntlbg_guard_checker(e, sv_es_ref(parent), false)
				} else if operator in ['===', '=='] {
					return c.svntlbg_guard_checker(e, sv_es_ref(parent), true)
				}
			} else if value.kind == .null_ && member {
				if operator == '!=' {
					return c.svntlbg_guard_checker(e, sv_es_ref(parent), false)
				} else if operator == '==' {
					return c.svntlbg_guard_checker(e, sv_es_ref(parent), true)
				}
			}
			return none
		}
		.unary_expression {
			if (t.string_of(parent, .operator) or { '' }) == 'typeof'
				&& (t.node(parent, .argument) or { -1 }) == node {
				pp := c.svsc_parent(e, parent)
				if pp < 0 || t.typ(pp) != .binary_expression {
					return none
				}
				other := if (t.node(pp, .left) or { -1 }) == parent {
					t.node(pp, .right) or { return none }
				} else {
					t.node(pp, .left) or { return none }
				}
				value := c.svntlbg_static(b, other)?
				text := if value.kind == .string_ { stv_units_string(value.units) } else { '' }
				if value.kind != .string_ || text !in ['undefined', 'object'] {
					return none
				}
				operator := t.string_of(pp, .operator) or { '' }
				if operator in ['!==', '!='] {
					return c.svntlbg_guard_checker(e, sv_es_ref(pp), text != 'undefined')
				} else if operator in ['===', '=='] {
					return c.svntlbg_guard_checker(e, sv_es_ref(pp), text == 'undefined')
				}
				return none
			}
		}
		else {}
	}
	if member {
		optional := t.flag(parent, .optional) or { false }
		if optional && ((t.typ(parent) == .call_expression
			&& (t.node(parent, .callee) or { -1 }) == node)
			|| (t.typ(parent) == .member_expression && (t.node(parent, .object) or { -1 }) == node)) {
			return SvntlbgChecker{
				exact: node
			}
		}
		return c.svntlbg_guard_checker(e, sv_es_ref(node), false)
	}
	return none
}

fn (st &SvntlbgState) top_level(t &estree.EsTree, i int) bool {
	return !svntlbg_contains(st.functions, t.nodes[i].start, t.nodes[i].end)
}

fn (mut c Checker) lint_svelte_no_top_level_browser_globals(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if sv_file_type(c.sv_file_path(abs_path)) == .none {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	b := c.svsc_bridge(root, &e, abs_path) or { return [] }
	t := e.t
	mut st := SvntlbgState{}
	// The traversal: functions and snippets at the top level, type annotations, import.meta.
	mut entered := []svelte.Ref{}
	if e.svelte {
		for step in c.sv_steps() {
			if !step.leave {
				entered << step.node
			}
		}
	} else {
		for i in e.entered() {
			entered << sv_es_ref(i)
		}
	}
	for ref in entered {
		if !ref.es {
			n := c.svelte.doc.nodes[ref.idx]
			if n.typ == .snippet_block && !svntlbg_contains(st.functions, n.start, n.end) {
				st.functions << [n.start, n.end]
			}
			continue
		}
		i := ref.idx
		n := t.nodes[i]
		if t.typ(i) in [.function_declaration, .function_expression, .arrow_function_expression]
			&& !svntlbg_contains(st.functions, n.start, n.end) {
			st.functions << [n.start, n.end]
		}
		parent := c.svsc_parent(&e, i)
		if parent >= 0 && ((t.node(parent, .type_annotation) or { -1 }) == i
			|| (t.node(parent, .type_arguments) or { -1 }) == i)
			&& !svntlbg_contains(st.types, n.start, n.end) {
			st.types << [n.start, n.end]
		}
		if t.typ(i) == .meta_property {
			meta := t.node(i, .meta) or { continue }
			property := t.node(i, .property) or { continue }
			if (t.string_of(meta, .name) or { '' }) != 'import'
				|| (t.string_of(property, .name) or { '' }) != 'meta' {
				continue
			}
			lint := b.lint_of(i) or { continue }
			ts := b.lint.ts_node(lint) or { continue }
			mut stack := []int{}
			mut out := []EsTraced{}
			c.es_trace_properties(root, ts, []string{}, EsTrace{
				children: {
					'env': EsTrace{
						children: {
							'SSR': EsTrace{
								read: true
							}
						}
					}
				}
			}, mut stack, mut out)
			for traced in out {
				lint_node := c.es_index_of(b.lint, traced.node) or { continue }
				node := b.view_of(lint_node) or { continue }
				if t.typ(node) !in [.identifier, .member_expression] {
					continue
				}
				if checker := c.svntlbg_guard_checker(&e, sv_es_ref(node), true) {
					st.guards << SvntlbgGuard{
						checker: checker
						browser: true
					}
				}
			}
		}
	}
	// Program:exit. The modules that tell the browser environment apart.
	tree := c.scope_tree(root)
	environment := EsTrace{
		esm:      true
		children: {
			'browser': EsTrace{
				read: true
			}
		}
	}
	for traced in c.es_esm_references(root, {
		'esm-env':           EsTrace{
			esm:      true
			children: {
				'BROWSER': EsTrace{
					read: true
				}
			}
		}
		'\$app/environment': environment
		'\$app/env':         environment
	}) {
		mut nodes := []int{}
		// An ImportSpecifier (whose tree-sitter node its names share): its variable's reads.
		specifier := node_kind(traced.node) == 'import_specifier'
		if !specifier {
			lint_node := c.es_index_of(b.lint, traced.node) or { continue }
			if b.lint.typ(lint_node) in [.identifier, .member_expression] {
				nodes << b.view_of(lint_node) or { continue }
			}
		} else {
			v := c.svsc_import_variable(root, traced.node)
			if v < 0 {
				continue
			}
			for r in tree.variables[v].references {
				reference := tree.references[r]
				if !reference.read {
					continue
				}
				lint_node := c.es_index_of(b.lint, reference.identifier) or { continue }
				if b.lint.typ(lint_node) == .identifier {
					nodes << b.view_of(lint_node) or { continue }
				}
			}
		}
		for node in nodes {
			if !st.top_level(t, node) {
				continue
			}
			if checker := c.svntlbg_guard_checker(&e, sv_es_ref(node), false) {
				st.guards << SvntlbgGuard{
					checker: checker
					browser: true
				}
			}
		}
	}
	// The references to the browser globals.
	mut trace := map[string]EsTrace{}
	for name in svsc_browser_globals {
		trace[name] = EsTrace{
			read: true
		}
	}
	mut candidates := []EsTraced{}
	mut candidate_nodes := []int{}
	for traced in c.svsc_global_references(root, trace, ['globalThis']) {
		lint_node := c.es_index_of(b.lint, traced.node) or { continue }
		node := b.view_of(lint_node) or { continue }
		n := t.nodes[node]
		if !st.top_level(t, node) || svntlbg_contains(st.types, n.start, n.end) {
			continue
		}
		if checker := c.svntlbg_reference_checker(&e, &b, node) {
			name := traced.path.join('.')
			st.guards << SvntlbgGuard{
				checker: checker
				browser: name in ['window', 'document']
				name:    name
			}
		} else {
			candidates << traced
			candidate_nodes << node
		}
	}
	mut findings := []Finding{}
	for k, traced in candidates {
		node := candidate_nodes[k]
		name := traced.path.join('.')
		n := t.nodes[node]
		if st.guards.any((it.checker.exact == node
			|| svntlbg_contains(it.checker.ranges, n.start, n.end))
			&& (it.browser || it.name == name)) {
			continue
		}
		findings << c.svsc_report(&e, node, 'unexpectedGlobal', {
			'name': name
		})
	}
	return findings
}
