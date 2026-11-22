module rules

import estree
import time

// Port of the `vue/no-shadow-native-events` rule of eslint-plugin-vue 10.12.1 (no options), in a
// .vue file: an event name that is a native DOM event (in lower case), declared by the `emits` of a
// Vue object or by defineEmits, or emitted (`this.$emit`, `emit`/`context.emit` of a setup's
// context or of defineEmits' variable, `$emit` and that variable in the template).

const vue_no_shadow_native_events_messages = {
	'violation': 'Avoid shadowing the native event "{{ name }}".'
}

fn (mut c Checker) lint_vue_no_shadow_native_events(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut define_emits := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineEmits') {
		define_emits[call] = true
	}
	mut contexts := map[int]VueSetupContext{}
	// The variable of the last defineEmits of `<script setup>` (vueTemplateDefineData.defineEmits).
	mut template_emit_name := ''
	for step in t.steps() {
		node := step.node
		if step.leave {
			if s.object_type(node) != .none_ {
				contexts.delete(node)
			}
			continue
		}
		if s.owner_of(node) == node {
			c.vnsne_verify_declarations(t, vue_emits_from_options(t, node), mut findings)
		}
		if s.vue_function_kind(t, node) == 'setup' {
			c.vnsne_setup_function(root, t, node, s.owner_of(node), mut contexts)
			continue
		}
		if t.typ(node) != .call_expression {
			continue
		}
		// defineScriptSetupVisitor's listeners, then defineVueVisitor's.
		if node in define_emits {
			c.vnsne_verify_declarations(t, c.vue_define_emits(root, t, node, abs_path, true, mut stats), mut findings)
			parent := t.nodes[node].parent
			template_emit_name = ''
			if parent >= 0 && t.typ(parent) == .variable_declarator {
				template_emit_name = vue_identifier_name(t, t.node(parent, .id) or { -1 })
				if (t.node(parent, .init) or { -1 }) == node && template_emit_name != '' {
					id := t.node(parent, .id) or { -1 }
					if ids := c.vue_reference_ids(root, t, id, true) {
						contexts[vue_program_context] = VueSetupContext{
							emit_ids: ids
						}
					}
				}
			}
		}
		if s.in_script_setup(t, node) {
			c.vnsne_call(root, t, node, contexts[vue_program_context] or { VueSetupContext{} },
				vue_program_context in contexts, mut findings)
		}
		owner := s.owner_of(node)
		if owner >= 0 {
			c.vnsne_call(root, t, node, contexts[owner] or { VueSetupContext{} }, owner in contexts, mut
				findings)
		}
	}
	for call in c.vue_template_calls() {
		es := &c.vue.doc.snippets[call.snippet].es
		callee := vue_skip_chain(es, es.node(call.node, .callee) or { continue })
		name := vue_identifier_name(es, callee)
		if name != '' && (name == r'$emit' || (s.has_setup && name == template_emit_name)) {
			c.vnsne_verify_emit(es, call.node, mut findings)
		}
	}
	stats.checked += findings.len
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnsne_setup_function is the rule's onSetupFunctionEnter: the read references of the emit or the
// context (no default value skipped; another kind of parameter is a context that references
// nothing).
fn (mut c Checker) vnsne_setup_function(root C.vt_node, t &estree.EsTree, setup int, owner int, mut contexts map[int]VueSetupContext) {
	params := t.list(setup, .params) or { return }
	if params.len < 2 || t.typ(params[1]) in [.rest_element, .array_pattern] {
		return
	}
	param := params[1]
	mut ctx := VueSetupContext{}
	if t.typ(param) == .object_pattern {
		property := vue_find_assignment_property(t, param, 'emit')
		if property < 0 {
			return
		}
		value := t.node(property, .value) or { return }
		if t.typ(value) != .identifier {
			return
		}
		ctx.emit_ids = c.vue_reference_ids(root, t, value, true) or { return }
	} else if t.typ(param) == .identifier {
		ctx.context_ids = c.vue_reference_ids(root, t, param, true) or { return }
	}
	contexts[owner] = ctx
}

// vnsne_call is the rule's callVisitor with the setup context of the call's Vue object or of the
// Program (`has_ctx` false when there is none).
fn (mut c Checker) vnsne_call(root C.vt_node, t &estree.EsTree, call int, ctx VueSetupContext, has_ctx bool, mut findings []Finding) {
	if vue_name_param(t, call) == none {
		return
	}
	callee := vue_skip_chain(t, t.node(call, .callee) or { return })
	mut emit_name := ''
	if t.typ(callee) == .member_expression {
		name := vue_static_property_name(t, callee) or { '' }
		if name in ['emit', r'$emit'] {
			emit_name = name
		}
	}
	if has_ctx {
		if t.typ(callee) == .identifier && callee in ctx.emit_ids {
			c.vnsne_verify_emit(t, call, mut findings)
		} else if emit_name == 'emit' {
			object := vue_skip_chain(t, t.node(callee, .object) or { -1 })
			if object >= 0 && t.typ(object) == .identifier && object in ctx.context_ids {
				c.vnsne_verify_emit(t, call, mut findings)
			}
		}
	}
	if emit_name == r'$emit' {
		object := vue_skip_chain(t, t.node(callee, .object) or { -1 })
		if c.vue_is_this(root, t, object) {
			c.vnsne_verify_emit(t, call, mut findings)
		}
	}
}

// vnsne_verify_emit is verifyEmit on the name a call emits.
fn (c &Checker) vnsne_verify_emit(t &estree.EsTree, call int, mut findings []Finding) {
	name, node := vue_name_param(t, call) or { return }
	if vue_js_to_lower(name) !in vue_dom_events {
		return
	}
	findings << c.vue_report(t.nodes[node].start, t.nodes[node].end, 'violation', {
		'name': name
	})
}

// vnsne_verify_declarations is verifyEmitDeclaration.
fn (c &Checker) vnsne_verify_declarations(t &estree.EsTree, emits []VueProp, mut findings []Finding) {
	for emit in emits {
		if emit.node < 0 || !emit.has_name || emit.name == ''
			|| vue_js_to_lower(emit.name) !in vue_dom_events {
			continue
		}
		findings << c.vue_report(t.nodes[emit.node].start, t.nodes[emit.node].end, 'violation',
			{
				'name': emit.name
			})
	}
}
