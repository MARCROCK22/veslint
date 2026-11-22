module rules

import estree
import time

// Port of the `vue/prefer-use-template-ref` rule of eslint-plugin-vue 10.12.1 (no options): a
// `ref="name"` of the template whose name is a variable of the script initialized with `ref(…)` or
// `shallowRef(…)` (the first declarator of a declaration in the body of `<script setup>`'s Program
// or of a component's `setup` function), reported at that call.

const vue_prefer_use_template_ref_messages = {
	'preferUseTemplateRef': "Replace '{{name}}' with 'useTemplateRef'."
}

fn (mut c Checker) lint_vue_prefer_use_template_ref(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut template_refs := []string{}
	for v in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[v]
		if node.typ != .v_attribute || node.directive || c.vue.doc.nodes[node.key].name != 'ref'
			|| node.value < 0 {
			continue
		}
		value := c.vue.doc.nodes[node.value].text
		if value != '' && value !in template_refs {
			template_refs << value
		}
	}
	if template_refs.len == 0 {
		return findings
	}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	// The pairs in the order they are pushed: the Program of `<script setup>` (its listener runs
	// first), then the setup functions as the traversal enters them; a later pair of a name wins.
	mut script_refs := map[string]int{}
	if s.has_setup && t.root >= 0 {
		vpurt_script_refs(t, t.list(t.root, .body) or { []int{} }, mut script_refs)
	}
	for step in t.steps() {
		node := step.node
		if step.leave || s.vue_function_kind(t, node) != 'setup' {
			continue
		}
		if t.typ(node) == .arrow_function_expression && (t.flag(node, .expression) or { false }) {
			continue
		}
		body := t.node(node, .body) or { continue }
		vpurt_script_refs(t, t.list(body, .body) or { []int{} }, mut script_refs)
	}
	for name in template_refs {
		stats.checked++
		call := script_refs[name] or { continue }
		callee := t.node(call, .callee) or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, call)
			message_id: 'preferUseTemplateRef'
			data:       {
				'name': t.string_of(callee, .name) or { '' }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vpurt_script_refs is getScriptRefsFromSetupFunction: the variable declarations of the body whose
// first declarator is an Identifier initialized with `ref(…)` or `shallowRef(…)`.
fn vpurt_script_refs(t &estree.EsTree, body []int, mut out map[string]int) {
	for child in body {
		if t.typ(child) != .variable_declaration {
			continue
		}
		declarations := t.list(child, .declarations) or { continue }
		if declarations.len == 0 {
			continue
		}
		declarator := declarations[0]
		init := t.node(declarator, .init) or { continue }
		id := t.node(declarator, .id) or { continue }
		if t.typ(init) != .call_expression || t.typ(id) != .identifier {
			continue
		}
		if vue_callee_name(t, init) in ['ref', 'shallowRef'] {
			out[t.string_of(id, .name) or { continue }] = init
		}
	}
}
