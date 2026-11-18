module rules

import estree
import time

// Port of the `vue/no-ref-as-operand` rule of eslint-plugin-vue 10.12.1 (no options): a variable
// initialized with a ref of the composition API (or whose type is a ref) used as an operand
// without `.value`, with the fix that adds it; also the refs passed to `emit(…)`.

const vue_no_ref_as_operand_messages = {
	'requireDotValue':      'Must use `.value` to read or write the value wrapped by `{{method}}()`.'
	'requireDotValueOfRef': 'Must use `.value` to read or write the value of a ref.'
}

struct VnraoCandidate {
	node       int
	check_type bool
}

fn (mut c Checker) lint_vue_no_ref_as_operand(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	refs := c.vx6r_extract(root, t)
	mut candidates := []VnraoCandidate{}
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .identifier {
			continue
		}
		parent := t.nodes[node].parent
		if parent < 0 {
			continue
		}
		match t.typ(parent) {
			.if_statement, .switch_statement, .unary_expression, .update_expression,
			.binary_expression {
				candidates << VnraoCandidate{node, true}
			}
			.assignment_expression {
				if (t.string_of(parent, .operator) or { '' }) == '=' {
					if (t.node(parent, .left) or { -1 }) == node {
						candidates << VnraoCandidate{node, false}
					}
				} else {
					candidates << VnraoCandidate{node, true}
				}
			}
			.logical_expression {
				if (t.node(parent, .left) or { -1 }) != node {
					continue
				}
				data := refs.get(node) or { continue }
				if data.declaration < 0
					|| (t.string_of(data.declaration, .kind) or { '' }) != 'const' {
					continue
				}
				candidates << VnraoCandidate{node, true}
			}
			.conditional_expression {
				if (t.node(parent, .test) or { -1 }) == node {
					candidates << VnraoCandidate{node, true}
				}
			}
			.template_literal {
				grand := t.nodes[parent].parent
				if grand < 0 || t.typ(grand) != .tagged_template_expression {
					candidates << VnraoCandidate{node, true}
				}
			}
			.member_expression {
				if (t.node(parent, .object) or { -1 }) != node {
					continue
				}
				name := vue_static_property_name(t, parent) or { continue }
				if name in ['value', 'effect'] {
					continue
				}
				candidates << VnraoCandidate{node, true}
			}
			else {}
		}
	}
	candidates << c.vnrao_emit_candidates(root, t, s)
	// The types of the candidates that are not ref inits (isRefObjectType), asked at once.
	mut typed := []int{}
	for candidate in candidates {
		if candidate.check_type && !vnrao_is_ref_init(t, refs.get(candidate.node)) {
			typed << candidate.node
		}
	}
	has_types := c.vx6_resolve_types(t, typed, abs_path, mut stats)
	for candidate in candidates {
		stats.checked++
		node := candidate.node
		data := refs.get(node)
		fix := [fix_insert_at(t.nodes[node].end, '.value')]
		if vnrao_is_ref_init(t, data) {
			findings << c.with_fixes(Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'requireDotValue'
				data:       {
					'method': (data or { Vx6rRef{} }).method
				}
			}, fix)!
		} else if candidate.check_type && has_types && c.vx6_is_ref_object_type(t, node) {
			findings << c.with_fixes(Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'requireDotValueOfRef'
			}, fix)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnrao_is_ref_init is isRefInit: an identifier reference whose declarator's initializer is in
// its define chain.
fn vnrao_is_ref_init(t &estree.EsTree, data ?Vx6rRef) bool {
	d := data or { return false }
	if !d.is_id || d.declarator < 0 {
		return false
	}
	init := t.node(d.declarator, .init) or { return false }
	return init in d.define_chain
}

// vnrao_emit_candidates are the identifier arguments of the `emit('name', …)` calls of a setup
// context: the `emit` of defineEmits in `<script setup>`, and the `emit` (or the context's) of a
// Vue object's setup function.
fn (mut c Checker) vnrao_emit_candidates(root C.TSNode, t &estree.EsTree, s &VueScript) []VnraoCandidate {
	mut out := []VnraoCandidate{}
	// The setup contexts: by owner (-1 for the program), with the preorder index they start at.
	mut emit_ids := map[int]map[u64]bool{}
	mut context_ids := map[int]map[u64]bool{}
	mut start := map[int]int{}
	mut order := map[int]int{}
	mut next := 0
	for step in t.steps() {
		if !step.leave {
			order[step.node] = next
			next++
		}
	}
	for call in c.vue_macros_named(t, 'defineEmits') {
		parent := t.nodes[call].parent
		if parent < 0 || t.typ(parent) != .variable_declarator
			|| (t.node(parent, .init) or { -1 }) != call {
			continue
		}
		id := t.node(parent, .id) or { continue }
		if t.typ(id) != .identifier {
			continue
		}
		mut set := map[u64]bool{}
		c.vnrao_collect_references(root, t, id, mut set)
		emit_ids[-1] = set.clone()
		context_ids[-1] = map[u64]bool{}
		start[-1] = order[call]
	}
	for step in t.steps() {
		f := step.node
		if step.leave || s.vue_function_kind(t, f) != 'setup' {
			continue
		}
		params := t.list(f, .params) or { []int{} }
		if params.len < 2 {
			continue
		}
		mut param := params[1]
		if t.typ(param) == .assignment_pattern {
			param = t.node(param, .left) or { continue }
		}
		if t.typ(param) in [.rest_element, .array_pattern] {
			continue
		}
		mut emit_set := map[u64]bool{}
		mut context_set := map[u64]bool{}
		if t.typ(param) == .object_pattern {
			property := vue_find_assignment_property(t, param, 'emit')
			if property < 0 {
				continue
			}
			value := vue_property_value(t, property)
			if t.typ(value) != .identifier {
				continue
			}
			c.vnrao_collect_references(root, t, value, mut emit_set)
		} else {
			c.vnrao_collect_references(root, t, param, mut context_set)
		}
		owner := s.owner_of(f)
		emit_ids[owner] = emit_set.clone()
		context_ids[owner] = context_set.clone()
		start[owner] = order[f]
	}
	if start.len == 0 {
		return out
	}
	for step in t.steps() {
		call := step.node
		if step.leave || t.typ(call) != .call_expression {
			continue
		}
		args := t.list(call, .arguments) or { []int{} }
		// getNameParamNode: a string literal name first.
		if args.len == 0 || !vue_is_string_literal(t, args[0])
			|| (vue_string_literal_value(t, args[0], false) or { '\x00none' }) == '\x00none' {
			continue
		}
		mut keys := []int{}
		if s.in_script_setup(t, call) {
			keys << -1
		}
		owner := s.owner_of(call)
		if owner >= 0 {
			keys << owner
		}
		for key in keys {
			if key !in start || order[call] < start[key] {
				continue
			}
			callee := t.node(call, .callee) or { continue }
			mut matched := false
			if t.typ(callee) == .identifier {
				matched = vneaa_key(t, callee) in emit_ids[key]
			}
			if !matched {
				member := vue_skip_chain(t, callee)
				if t.typ(member) == .member_expression
					&& (vue_static_property_name(t, member) or { '' }) == 'emit' {
					object := t.node(member, .object) or { -1 }
					matched = object >= 0 && t.typ(object) == .identifier
						&& vneaa_key(t, object) in context_ids[key]
				}
			}
			if matched {
				for arg in args {
					if t.typ(arg) == .identifier {
						out << VnraoCandidate{arg, true}
					}
				}
			}
		}
	}
	return out
}

fn (mut c Checker) vnrao_collect_references(root C.TSNode, t &estree.EsTree, id int, mut out map[u64]bool) {
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return
	}
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		out[node_key(tree.references[r].identifier)] = true
	}
}
