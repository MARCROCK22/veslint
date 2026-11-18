module rules

import estree
import time

// Port of the `vue/no-setup-props-reactivity-loss` rule of eslint-plugin-vue 10.12.1 (no
// options): a destructuring of the props of `setup(props)` or of defineProps, or a value read from
// them in the root scope of `setup()` or `<script setup>` (in a call, a declarator or an
// assignment).

const vue_no_setup_props_reactivity_loss_messages = {
	'destructuring': 'Destructuring the `props` will cause the value to lose reactivity.'
	'getProperty':   'Getting a value from the `props` in root scope of `{{scopeName}}` will cause the value to lose reactivity.'
}

// VnsprlScope is a ScopePropsReferences: the read references (ESTree identifiers) of the props
// object (`props`) and of destructured props (`prop`), from the scope `scope_node` (-1: the
// Program), active after the preorder index `from`.
struct VnsprlScope {
mut:
	props      []int
	prop       []int
	scope_name string
	from       int
}

fn (mut c Checker) lint_vue_no_setup_props_reactivity_loss(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut order := []int{len: t.nodes.len, init: -1}
	mut next := 0
	for step in t.steps() {
		if !step.leave {
			order[step.node] = next
			next++
		}
	}
	mut scopes := map[int]VnsprlScope{}
	// onDefinePropsEnter
	for call in c.vue_macros_named(t, 'defineProps') {
		mut target := call
		if vue_has_with_defaults(t, target) {
			target = t.nodes[target].parent
		}
		parent := t.nodes[target].parent
		if parent < 0 {
			continue
		}
		mut id := -1
		if t.typ(parent) == .variable_declarator {
			if (t.node(parent, .init) or { -1 }) == target {
				id = t.node(parent, .id) or { -1 }
			}
		} else if t.typ(parent) == .assignment_expression {
			if (t.node(parent, .right) or { -1 }) == target {
				id = t.node(parent, .left) or { -1 }
			}
		}
		if id < 0 {
			continue
		}
		for prop_id in vnsprl_prop_ids(t, id) {
			c.vnsprl_process(root, t, prop_id, -1, '<script setup>', order[call], mut scopes, mut
				findings)
		}
	}
	// onSetupFunctionEnter
	for step in t.steps() {
		f := step.node
		if step.leave || s.vue_function_kind(t, f) != 'setup' {
			continue
		}
		params := t.list(f, .params) or { []int{} }
		if params.len == 0 {
			continue
		}
		mut param := params[0]
		if t.typ(param) == .assignment_pattern {
			param = t.node(param, .left) or { continue }
		}
		c.vnsprl_process(root, t, VnsprlPropId{param, false}, f, 'setup()', order[f], mut
			scopes, mut findings)
	}
	if scopes.len == 0 {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) !in [.call_expression, .variable_declarator,
			.assignment_expression] {
			continue
		}
		scope_node := vaa_innermost_function(t, node)
		scope := scopes[scope_node] or { continue }
		if order[node] <= scope.from {
			continue
		}
		stats.checked++
		match t.typ(node) {
			.call_expression {
				if vnsprl_is_props_member_accessed(t, node, scope) {
					findings << c.vnsprl_report(t, node, 'getProperty', scope.scope_name)
				}
			}
			.variable_declarator {
				c.vnsprl_verify(t, t.node(node, .id) or { -1 }, t.node(node, .init) or { -1 },
					scope, mut findings)
			}
			else {
				c.vnsprl_verify(t, t.node(node, .left) or { -1 }, t.node(node, .right) or { -1 },
					scope, mut findings)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

struct VnsprlPropId {
	node int
	prop bool // kind 'prop' (else 'props')
}

// vnsprl_prop_ids is iteratePropIds.
fn vnsprl_prop_ids(t &estree.EsTree, node int) []VnsprlPropId {
	mut out := []VnsprlPropId{}
	if t.typ(node) == .object_pattern {
		for p in t.list(node, .properties) or { []int{} } {
			if t.typ(p) == .property {
				out << VnsprlPropId{vnsprl_unwrap(t, t.node(p, .value) or { -1 }), true}
			} else {
				out << VnsprlPropId{vnsprl_unwrap(t, t.node(p, .argument) or { -1 }), false}
			}
		}
		return out
	}
	return [VnsprlPropId{vnsprl_unwrap(t, node), false}]
}

fn vnsprl_unwrap(t &estree.EsTree, node int) int {
	if node >= 0 && t.typ(node) == .assignment_pattern {
		return t.node(node, .left) or { -1 }
	}
	return node
}

// vnsprl_process is processPropId.
fn (mut c Checker) vnsprl_process(root C.TSNode, t &estree.EsTree, id VnsprlPropId, scope_node int, scope_name string, from int, mut scopes map[int]VnsprlScope, mut findings []Finding) {
	node := id.node
	if node < 0 || t.typ(node) in [.rest_element, .assignment_pattern, .member_expression] {
		return
	}
	if t.typ(node) in [.array_pattern, .object_pattern] {
		findings << c.vnsprl_report(t, node, 'destructuring', scope_name)
		return
	}
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return
	}
	if scope_node !in scopes {
		scopes[scope_node] = VnsprlScope{
			scope_name: scope_name
			from:       from
		}
	}
	tree := c.scope_tree(root)
	current := tree.variables[v].scope
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if reference.from != current || !reference.read {
			continue
		}
		es := c.es_index_of(t, reference.identifier) or { continue }
		if id.prop {
			scopes[scope_node].prop << es
		} else {
			scopes[scope_node].props << es
		}
	}
}

fn (c &Checker) vnsprl_report(t &estree.EsTree, node int, message_id string, scope_name string) Finding {
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: message_id
		data:       {
			'scopeName': scope_name
		}
	}
}

// vnsprl_is_props_member_accessed is isPropsMemberAccessed.
fn vnsprl_is_props_member_accessed(t &estree.EsTree, node int, scope VnsprlScope) bool {
	for id in scope.props {
		parent := t.nodes[id].parent
		if vx6_is_in_range(t, node, id) && parent >= 0 && t.typ(parent) == .member_expression
			&& (t.node(parent, .object) or { -1 }) == id {
			return true
		}
	}
	for id in scope.prop {
		if vx6_is_in_range(t, node, id) {
			return true
		}
	}
	return false
}

// vnsprl_verify is verify.
fn (mut c Checker) vnsprl_verify(t &estree.EsTree, left int, right int, scope VnsprlScope, mut findings []Finding) {
	if right < 0 || left < 0 {
		return
	}
	right_node := vue_skip_chain(t, right)
	if t.typ(right_node) in [.array_expression, .object_expression]
		&& vnsprl_is_props_member_accessed(t, right_node, scope) {
		findings << c.vnsprl_report(t, right_node, 'getProperty', scope.scope_name)
		return
	}
	mut expression := right_node
	for t.typ(expression) == .member_expression {
		expression = vue_skip_chain(t, t.node(expression, .object) or { break })
	}
	mut expressions := []int{}
	match t.typ(expression) {
		.template_literal {
			expressions << t.list(expression, .expressions) or { []int{} }
		}
		.conditional_expression {
			for key in [estree.Key.test, .consequent, .alternate] {
				expressions << t.node(expression, key) or { -1 }
			}
		}
		.identifier {
			expressions << expression
		}
		else {}
	}
	expressions = expressions.filter(it >= 0)
	if t.typ(left) in [.array_pattern, .object_pattern]
		&& expressions.any(t.typ(it) == .identifier && it in scope.props) {
		findings << c.vnsprl_report(t, left, 'getProperty', scope.scope_name)
		return
	}
	for e in expressions {
		if vnsprl_is_props_member_accessed(t, e, scope) {
			findings << c.vnsprl_report(t, e, 'getProperty', scope.scope_name)
			return
		}
	}
}
