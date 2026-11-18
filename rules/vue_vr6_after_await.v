module rules

import estree

// What the "…-after-await" rules of eslint-plugin-vue 10.12.1 share (no-lifecycle-after-await,
// no-watch-after-await, no-expose-after-await, no-restricted-call-after-await): a scope stack of
// the functions (`:function` / `:function:exit`), the `setup` functions of the Vue objects as
// setup scopes, and an `afterAwait` flag that the first AwaitExpression whose innermost function
// is the setup scope sets, for the CallExpressions entered after it.

// VaaScopes is the state of one traversal: the preorder index of each node and the preorder index
// of the first await of each function.
struct VaaScopes {
mut:
	order       []int
	first_await map[int]int // function (-1: Program) -> preorder index of its first AwaitExpression
	// The AwaitExpressions outside any function, in preorder.
	program_awaits []int
}

// vaa_scopes walks the tree once: the preorder of the nodes and the first await of each
// function (an AwaitExpression's innermost function; -1 for the Program).
fn vaa_scopes(t &estree.EsTree) VaaScopes {
	mut s := VaaScopes{
		order: []int{len: t.nodes.len, init: -1}
	}
	mut next := 0
	for step in t.steps() {
		if step.leave {
			continue
		}
		s.order[step.node] = next
		if t.typ(step.node) == .await_expression {
			f := vaa_innermost_function(t, step.node)
			if f !in s.first_await {
				s.first_await[f] = next
			}
			if f < 0 {
				s.program_awaits << step.node
			}
		}
		next++
	}
	return s
}

// vaa_innermost_function is the top of the scope stack when `node`'s listeners run: the
// innermost FunctionDeclaration, FunctionExpression or ArrowFunctionExpression that contains it,
// -1 for none (the Program).
fn vaa_innermost_function(t &estree.EsTree, node int) int {
	mut n := t.nodes[node].parent
	for n >= 0 {
		if t.typ(n) in [.function_declaration, .function_expression, .arrow_function_expression] {
			return n
		}
		n = t.nodes[n].parent
	}
	return -1
}

// after_await tells whether an AwaitExpression of the function `scope` (-1: the Program) inside
// [start, end] was entered before `node`.
fn (s &VaaScopes) after_await(t &estree.EsTree, scope int, start int, end int, node int) bool {
	first := s.first_await[scope] or { return false }
	if first >= s.order[node] {
		return false
	}
	if scope >= 0 {
		// The awaits of a function are inside its range.
		return true
	}
	for a in s.program_awaits {
		if s.order[a] >= s.order[node] {
			break
		}
		if start <= t.nodes[a].start && t.nodes[a].end <= end {
			return true
		}
	}
	return false
}

// vaa_setup_calls_after_await are the CallExpressions of the file whose innermost function is
// the `setup` function of a Vue object (onSetupFunctionEnter) and that come after an await of
// that function, in traversal order: what the CallExpression listener of the rules checks.
fn (mut c Checker) vaa_setup_calls_after_await(t &estree.EsTree, s &VueScript, scopes &VaaScopes) []int {
	mut out := []int{}
	if scopes.first_await.len == 0 {
		return out
	}
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .call_expression {
			continue
		}
		f := vaa_innermost_function(t, step.node)
		if f < 0 || s.vue_function_kind(t, f) != 'setup' {
			continue
		}
		if scopes.after_await(t, f, t.nodes[f].start, t.nodes[f].end, step.node) {
			out << step.node
		}
	}
	return out
}

// vaa_trace_map_calls are the CallExpressions of iterateReferencesTraceMap with the `names`
// called (ES modules of createCompositionApiTraceMap, then the globals).
fn (mut c Checker) vaa_trace_map_calls(root C.TSNode, t &estree.EsTree, names []string) []int {
	call_trace := EsTrace{
		call: true
	}
	mut children := map[string]EsTrace{}
	for name in names {
		children[name] = call_trace
	}
	esm := EsTrace{
		esm:      true
		children: children
	}
	mut esm_map := map[string]EsTrace{}
	for module in vue_composition_modules {
		esm_map[module] = esm
	}
	mut traced := c.es_esm_references(root, esm_map)
	traced << c.es_global_references(root, children)
	mut out := []int{}
	for r in traced {
		if r.kind != 'call' {
			continue
		}
		call := c.es_index_of(t, r.node) or { continue }
		if t.typ(call) == .call_expression && call !in out {
			out << call
		}
	}
	return out
}
