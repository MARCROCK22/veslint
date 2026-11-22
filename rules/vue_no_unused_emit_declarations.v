module rules

import estree
import time

// Port of the `vue/no-unused-emit-declarations` rule of eslint-plugin-vue 10.12.1 (no options):
// an event the `emits` of a Vue object or defineEmits declares that no call emits (`this.$emit`,
// `emit`/`context.emit` of a setup's context or of defineEmits' variable, `$emit` and that
// variable in the template; `update:x` of a defineModel kept in a variable). Passing the emit
// function or the context to a call forgets the declarations and calls found until then.

const vue_no_unused_emit_declarations_messages = {
	'unused': '`{{name}}` is defined as emit but never used.'
}

// VnuedState is the rule's state as its listeners change it.
struct VnuedState {
mut:
	declarations    map[string]VueProp
	calls           map[string]bool
	contexts        map[int]VueSetupContext
	emit_param_name string
}

fn (mut st VnuedState) clear() {
	st.declarations = map[string]VueProp{}
	st.calls = map[string]bool{}
}

fn (mut st VnuedState) declare(emits []VueProp) {
	for emit in emits {
		if emit.has_name && emit.name != '' {
			st.declarations[emit.name] = emit
		}
	}
}

fn (mut st VnuedState) add_call(t &estree.EsTree, call int) {
	if name, _ := vue_name_param(t, call) {
		st.calls[name] = true
	}
}

// Also in a TypeScript file: the rule composes its script listeners with defineTemplateBodyVisitor's
// (which gives none there) instead of handing them to it.
fn (mut c Checker) lint_vue_no_unused_emit_declarations(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut st := VnuedState{}
	mut define_emits := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineEmits') {
		define_emits[call] = true
	}
	mut define_models := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineModel') {
		define_models[call] = true
	}
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		owner := s.owner_of(node)
		// defineVueVisitor's listeners, then defineScriptSetupVisitor's.
		if owner == node {
			st.declare(vue_emits_from_options(t, node))
		}
		if s.vue_function_kind(t, node) == 'setup' {
			c.vnued_setup_function(root, t, node, owner, mut st)
		}
		if t.typ(node) != .call_expression {
			continue
		}
		if owner >= 0 {
			c.vnued_call(root, t, node, owner, true, mut st)
		}
		if node in define_emits {
			st.declare(c.vue_define_emits(root, t, node, abs_path, true, mut stats))
			id := vue_define_emits_variable(t, node)
			if id >= 0 {
				st.emit_param_name = vue_identifier_name(t, id)
				if ids := c.vue_reference_ids(root, t, id, false) {
					st.contexts[vue_program_context] = VueSetupContext{
						emit_ids: ids
					}
				}
			}
		} else if node in define_models {
			parent := t.nodes[node].parent
			if parent >= 0 && t.typ(parent) == .variable_declarator
				&& (t.node(parent, .init) or { -1 }) == node {
				st.calls['update:${vue_define_model(t, node).name}'] = true
			}
		}
		if s.in_script_setup(t, node) {
			c.vnued_call(root, t, node, vue_program_context, true, mut st)
		}
	}
	// The template, at Program:exit: its calls take the Program's context.
	for call in c.vue_template_calls() {
		c.vnued_call(root, &c.vue.doc.snippets[call.snippet].es, call.node, vue_program_context,
			false, mut st)
	}
	for name, emit in st.declarations {
		stats.checked++
		if name in st.calls || emit.node < 0 {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, emit.node)
			message_id: 'unused'
			data:       {
				'name': name
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnued_setup_function is the rule's onSetupFunctionEnter (it does not skip a default value of
// the context parameter: `ctx = …` is a context that references nothing).
fn (mut c Checker) vnued_setup_function(root C.vt_node, t &estree.EsTree, setup int, owner int, mut st VnuedState) {
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
		ctx.emit_ids = c.vue_reference_ids(root, t, value, false) or { return }
	} else if t.typ(param) == .identifier {
		ctx.context_ids = c.vue_reference_ids(root, t, param, false) or { map[int]bool{} }
	}
	st.contexts[owner] = ctx
}

// vnued_call is the rule's callVisitor on a call (of the script when `script`, else of the
// template) with the setup context of `key`.
fn (mut c Checker) vnued_call(root C.vt_node, t &estree.EsTree, call int, key int, script bool, mut st VnuedState) {
	raw_callee := t.node(call, .callee) or { return }
	callee := vue_skip_chain(t, raw_callee)
	mut emit_name := ''
	mut member := -1
	if t.typ(callee) == .member_expression {
		name := vue_static_property_name(t, callee) or { '' }
		if name in ['emit', r'$emit'] {
			emit_name = name
			member = callee
		}
	}
	if ctx := st.contexts[key] {
		// `callee.parent` is the call itself unless the callee is in a chain expression.
		if callee == raw_callee && vnued_has_arguments_references(t, call, ctx, mut st) {
			// The emit is passed as an argument.
			return
		}
		if t.typ(callee) == .identifier && callee in ctx.emit_ids {
			st.add_call(t, call)
		}
		if emit_name == 'emit' {
			object := vue_skip_chain(t, t.node(member, .object) or { -1 })
			if object >= 0 && t.typ(object) == .identifier && object in ctx.context_ids {
				st.add_call(t, call)
			}
		}
	}
	if emit_name == r'$emit' {
		object := vue_skip_chain(t, t.node(member, .object) or { -1 })
		is_this := if script {
			c.vue_is_this(root, t, object)
		} else {
			object >= 0 && t.typ(object) == .this_expression
		}
		if is_this {
			st.add_call(t, call)
		}
	}
	name := vue_identifier_name(t, callee)
	if name != '' && (name == r'$emit' || name == st.emit_param_name) {
		st.add_call(t, call)
	}
}

// vnued_has_reference_id is hasReferenceId.
fn vnued_has_reference_id(t &estree.EsTree, node int, ctx VueSetupContext) bool {
	return node >= 0 && t.typ(node) == .identifier && (node in ctx.emit_ids || node in ctx.context_ids)
}

// vnued_has_expression_reference is hasExpressionReference: the expression is the emit or the
// context, or a member of them (which forgets what was found).
fn vnued_has_expression_reference(t &estree.EsTree, expression int, ctx VueSetupContext, mut st VnuedState) bool {
	if t.typ(expression) == .member_expression {
		object := vue_skip_chain(t, t.node(expression, .object) or { -1 })
		if vnued_has_reference_id(t, object, ctx) {
			st.clear()
			return true
		}
	}
	if vnued_has_reference_id(t, expression, ctx) {
		st.clear()
		return true
	}
	return false
}

// vnued_has_arguments_references is hasArgumentsReferences of the call's arguments.
fn vnued_has_arguments_references(t &estree.EsTree, call int, ctx VueSetupContext, mut st VnuedState) bool {
	for argument in t.list(call, .arguments) or { []int{} } {
		if t.typ(argument) == .object_expression {
			for property in t.list(argument, .properties) or { []int{} } {
				if t.typ(property) == .property
					&& vnued_has_expression_reference(t, t.node(property, .value) or { continue }, ctx, mut
						st) {
					return true
				}
			}
		} else if t.typ(argument) == .array_expression {
			for element in t.list(argument, .elements) or { []int{} } {
				if element >= 0 && vnued_has_expression_reference(t, element, ctx, mut st) {
					return true
				}
			}
		}
		if vnued_has_expression_reference(t, argument, ctx, mut st) {
			return true
		}
	}
	return false
}
