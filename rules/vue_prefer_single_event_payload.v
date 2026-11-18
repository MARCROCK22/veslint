module rules

import estree
import time

// Port of the `vue/prefer-single-event-payload` rule of eslint-plugin-vue 10.12.1 (no options), in
// a .vue file: an emit call with more than one payload argument (reported from the second payload
// to the last argument), and an emit declared with more than one payload (the parameters of an
// `emits` validator, of a call signature or function type after the event, of a method signature,
// the elements of a tuple type).

const vue_prefer_single_event_payload_messages = {
	'preferSinglePayload':              'Pass a single payload object instead of multiple arguments when emitting the "{{name}}" event.'
	'preferSinglePayloadInDeclaration': 'Declare a single payload parameter instead of multiple parameters for the "{{name}}" event.'
}

fn (mut c Checker) lint_vue_prefer_single_event_payload(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
	for step in t.steps() {
		node := step.node
		if step.leave {
			// executeOnVue, then onVueObjectExit.
			if s.object_type(node) != .none_ {
				for emit in vue_emits_from_options(t, node) {
					c.vpsep_verify_declaration(t, emit, mut findings)
				}
				contexts.delete(node)
			}
			continue
		}
		if s.vue_function_kind(t, node) == 'setup' {
			if ctx := c.vue_setup_context(root, t, node, false) {
				contexts[s.owner_of(node)] = ctx
			}
			continue
		}
		if t.typ(node) != .call_expression {
			continue
		}
		callee := vue_skip_chain(t, t.node(node, .callee) or { continue })
		// defineScriptSetupVisitor.
		if node in define_emits {
			for emit in c.vue_define_emits_typed(root, t, node, abs_path, mut stats) {
				c.vpsep_verify_declaration(t, emit, mut findings)
			}
			id := vue_define_emits_variable(t, node)
			if id >= 0 {
				if ids := c.vue_reference_ids(root, t, id, true) {
					contexts[vue_program_context] = VueSetupContext{
						emit_ids: ids
					}
				}
			}
		}
		if s.in_script_setup(t, node) {
			if ctx := contexts[vue_program_context] {
				if t.typ(callee) == .identifier && callee in ctx.emit_ids {
					c.vpsep_verify_call(t, node, mut findings)
				}
			}
		}
		// defineVueVisitor.
		owner := s.owner_of(node)
		if owner >= 0 {
			if ctx := contexts[owner] {
				if t.typ(callee) == .identifier && callee in ctx.emit_ids {
					c.vpsep_verify_call(t, node, mut findings)
				} else if name, member := vue_callee_member(t, node) {
					object := t.node(member, .object) or { -1 }
					if name == 'emit' && object >= 0 && t.typ(object) == .identifier
						&& object in ctx.context_ids {
						c.vpsep_verify_call(t, node, mut findings)
					}
				}
			}
		}
		if name, _ := vue_callee_member(t, node) {
			if name == r'$emit' {
				c.vpsep_verify_call(t, node, mut findings)
			}
		}
	}
	// The template, at Program:exit: `$emit`, or the name of a read of defineEmits' variable.
	mut emit_names := map[string]bool{}
	if ctx := contexts[vue_program_context] {
		for id, _ in ctx.emit_ids {
			emit_names[vue_identifier_name(t, id)] = true
		}
	}
	for call in c.vue_template_calls() {
		es := &c.vue.doc.snippets[call.snippet].es
		callee := vue_skip_chain(es, es.node(call.node, .callee) or { continue })
		name := vue_identifier_name(es, callee)
		if name != '' && (name == r'$emit' || name in emit_names) {
			c.vpsep_verify_call(es, call.node, mut findings)
		}
	}
	stats.checked += findings.len
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vpsep_verify_call is verifyEmitCall.
fn (c &Checker) vpsep_verify_call(t &estree.EsTree, call int, mut findings []Finding) {
	args := t.list(call, .arguments) or { return }
	if args.len <= 2 {
		return
	}
	name := if vue_is_string_literal(t, args[0]) {
		vue_string_literal_value(t, args[0], false) or { 'unknown' }
	} else {
		'unknown'
	}
	findings << c.vue_report(t.nodes[args[2]].start, t.nodes[args.last()].end, 'preferSinglePayload',
		{
		'name': name
	})
}

// vpsep_verify_declaration is verifyEmitDeclaration.
fn (c &Checker) vpsep_verify_declaration(t &estree.EsTree, emit VueProp, mut findings []Finding) {
	mut parameters := []int{}
	mut first := 1
	if emit.kind == .object {
		if emit.value >= 0 && t.typ(emit.value) in [.arrow_function_expression, .function_expression] {
			parameters = t.list(emit.value, .params) or { []int{} }
		} else {
			return
		}
	} else if emit.kind == .type_ && emit.node >= 0 {
		match t.typ(emit.node) {
			.ts_call_signature_declaration, .ts_function_type {
				parameters = t.list(emit.node, .params) or { []int{} }
				first = 2
			}
			.ts_property_signature {
				annotation := t.node(emit.node, .type_annotation) or { return }
				tuple := t.node(annotation, .type_annotation) or { return }
				if t.typ(tuple) != .ts_tuple_type {
					return
				}
				parameters = t.list(tuple, .element_types) or { []int{} }
			}
			.ts_method_signature {
				parameters = t.list(emit.node, .params) or { []int{} }
			}
			else {
				return
			}
		}
	} else {
		return
	}
	if parameters.len < first + 1 {
		return
	}
	findings << c.vue_report(t.nodes[parameters[first]].start, t.nodes[parameters.last()].end,
		'preferSinglePayloadInDeclaration', {
		'name': if emit.has_name { emit.name } else { 'unknown' }
	})
}
