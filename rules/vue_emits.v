module rules

import estree
import tsgo

// The helpers of eslint-plugin-vue 10.12.1's emit rules (custom-event-name-casing,
// no-restricted-custom-event, no-unused-emit-declarations, prefer-single-event-payload,
// require-explicit-emits, no-shadow-native-events): the calls that emit an event (`this.$emit`,
// `$emit` of the template, the `emit` of a setup context or of `defineEmits`) and the name they
// emit. Each rule walks the script with t.steps() itself, as its listeners differ in small ways;
// a setup context (VueSetupContext) is a key of setupContexts: a Vue object, or the Program
// (vue_program_context) for `const emit = defineEmits()`.

// vue_program_context is the key of the Program in a map of setup contexts by Vue object.
const vue_program_context = -2

// VueSetupContext is a SetupContext of the emit rules: the identifiers (ESTree nodes) of the
// references to the setup's context parameter and to its `emit` (or defineEmits' variable).
struct VueSetupContext {
mut:
	context_ids map[int]bool
	emit_ids    map[int]bool
}

// vue_reference_ids are the identifiers of the references of the variable an Identifier names
// (findVariable(getScope(id), id).references; with `read_only`, those that read it), none when
// it names no variable.
fn (mut c Checker) vue_reference_ids(root C.vt_node, t &estree.EsTree, id int, read_only bool) ?map[int]bool {
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return none
	}
	tree := c.scope_tree(root)
	mut out := map[int]bool{}
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if read_only && !reference.read {
			continue
		}
		if i := c.es_index_of(t, reference.identifier) {
			out[i] = true
		}
	}
	return out
}

// vue_skip_default_param ports skipDefaultParamValue.
fn vue_skip_default_param(t &estree.EsTree, node int) int {
	mut n := node
	for n >= 0 && t.typ(n) == .assignment_pattern {
		n = t.node(n, .left) or { return n }
	}
	return n
}

// vue_find_assignment_property ports findAssignmentProperty: the first Property of the
// ObjectPattern with that static name, -1 for none.
fn vue_find_assignment_property(t &estree.EsTree, pattern int, name string) int {
	for p in t.list(pattern, .properties) or { []int{} } {
		if t.typ(p) == .property && (vue_static_property_name(t, p) or { continue }) == name {
			return p
		}
	}
	return -1
}

// vue_setup_context is the onSetupFunctionEnter of custom-event-name-casing and its siblings:
// the context of `setup(props, {emit})` (the references of `emit`, an Identifier) or of
// `setup(props, context)`; none when the setup has no second parameter, or one that cannot be
// checked (a rest element, an array pattern, `{emit: …}` that is not an Identifier, no variable).
fn (mut c Checker) vue_setup_context(root C.vt_node, t &estree.EsTree, setup int, emit_read_only bool) ?VueSetupContext {
	params := t.list(setup, .params) or { return none }
	if params.len < 2 {
		return none
	}
	param := vue_skip_default_param(t, params[1])
	if param < 0 || t.typ(param) in [.rest_element, .array_pattern] {
		return none
	}
	mut ctx := VueSetupContext{}
	if t.typ(param) == .object_pattern {
		property := vue_find_assignment_property(t, param, 'emit')
		if property < 0 {
			return none
		}
		value := t.node(property, .value) or { return none }
		if t.typ(value) != .identifier {
			return none
		}
		ctx.emit_ids = c.vue_reference_ids(root, t, value, emit_read_only)?
	} else {
		ctx.context_ids = c.vue_reference_ids(root, t, param, false)?
	}
	return ctx
}

// vue_define_emits_variable is the Identifier `emit` of `const emit = defineEmits(…)` (the
// declarator's id when the call is its init), -1 for another use of the call.
fn vue_define_emits_variable(t &estree.EsTree, call int) int {
	parent := t.nodes[call].parent
	if parent < 0 || t.typ(parent) != .variable_declarator
		|| (t.node(parent, .init) or { -1 }) != call {
		return -1
	}
	id := t.node(parent, .id) or { return -1 }
	return if t.typ(id) == .identifier { id } else { -1 }
}

// vue_callee_member ports the rules' getCalleeMemberNode: the static name of the callee (through
// chain expressions) when it is a member access, and that MemberExpression; none for another
// callee or an empty name.
fn vue_callee_member(t &estree.EsTree, call int) ?(string, int) {
	callee := vue_skip_chain(t, t.node(call, .callee) or { return none })
	if t.typ(callee) != .member_expression {
		return none
	}
	name := vue_static_property_name(t, callee) or { return none }
	if name == '' {
		return none
	}
	return name, callee
}

// vue_name_param ports getNameParamNode: the name a call's first argument gives (a string
// literal) and that argument.
fn vue_name_param(t &estree.EsTree, call int) ?(string, int) {
	args := t.list(call, .arguments) or { return none }
	if args.len == 0 || !vue_is_string_literal(t, args[0]) {
		return none
	}
	name := vue_string_literal_value(t, args[0], false) or { return none }
	return name, args[0]
}

// vue_identifier_name is the name of an Identifier, '' for another node.
fn vue_identifier_name(t &estree.EsTree, node int) string {
	if node < 0 || t.typ(node) != .identifier {
		return ''
	}
	return t.string_of(node, .name) or { '' }
}

// VueTemplateCall is a CallExpression of a template expression: its snippet and node.
struct VueTemplateCall {
	snippet int
	node    int
}

// vue_template_calls are the CallExpressions of the template's expressions, in the order of the
// traversal.
fn (mut c Checker) vue_template_calls() []VueTemplateCall {
	mut out := []VueTemplateCall{}
	for step in c.vue_template_steps() {
		n := step.node
		if step.leave || n.kind != .estree {
			continue
		}
		if c.vue.doc.snippets[n.snippet].es.typ(n.es) == .call_expression {
			out << VueTemplateCall{n.snippet, n.es}
		}
	}
	return out
}

// vue_emit_calls_of_script are the calls of the script that custom-event-name-casing and
// no-restricted-custom-event verify, in the order of their listeners (a call twice when two
// listeners take it): with `with_define_emits` (custom-event-name-casing's
// defineScriptSetupVisitor), a call of `<script setup>` through the variable of the last
// `const emit = defineEmits()` before it; in a Vue object, through the context of its setup
// function entered before it; and any `x.$emit(…)`. Also the name of the last defineEmits
// variable (emitParamName), which the template's calls use.
fn (mut c Checker) vue_emit_calls_of_script(root C.vt_node, t &estree.EsTree, s &VueScript, with_define_emits bool) ([]int, string) {
	mut out := []int{}
	mut emit_param_name := ''
	mut define_emits := map[int]bool{}
	if with_define_emits {
		for call in c.vue_macros_named(t, 'defineEmits') {
			define_emits[call] = true
		}
	}
	mut contexts := map[int]VueSetupContext{}
	for step in t.steps() {
		node := step.node
		if step.leave {
			if s.object_type(node) != .none_ {
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
		if node in define_emits {
			id := vue_define_emits_variable(t, node)
			if id >= 0 {
				emit_param_name = vue_identifier_name(t, id)
				if ids := c.vue_reference_ids(root, t, id, false) {
					contexts[vue_program_context] = VueSetupContext{
						emit_ids: ids
					}
				}
			}
		}
		if vue_name_param(t, node) == none {
			continue
		}
		if with_define_emits && s.in_script_setup(t, node) {
			if ctx := contexts[vue_program_context] {
				if vue_emit_call_of_context(t, node, ctx) {
					out << node
				}
			}
		}
		owner := s.owner_of(node)
		if owner >= 0 {
			if ctx := contexts[owner] {
				if vue_emit_call_of_context(t, node, ctx) {
					out << node
				}
			}
		}
		if name, _ := vue_callee_member(t, node) {
			if name == r'$emit' {
				out << node
			}
		}
	}
	return out, emit_param_name
}

// vue_emit_call_of_context: the call is `emit(…)` through the context's emit (its callee itself,
// not through chain expressions) or `context.emit(…)`.
fn vue_emit_call_of_context(t &estree.EsTree, call int, ctx VueSetupContext) bool {
	callee := t.node(call, .callee) or { return false }
	if t.typ(callee) == .identifier && callee in ctx.emit_ids {
		return true
	}
	name, member := vue_callee_member(t, call) or { return false }
	object := t.node(member, .object) or { return false }
	return name == 'emit' && t.typ(object) == .identifier && object in ctx.context_ids
}

// vue_symbol_flags_function_or_method are SymbolFlags.Function | SymbolFlags.Method.
const vue_symbol_flags_function_or_method = u32(16 | 8192)

// vue_emits_from_type_checker ports getComponentEmitsFromTypeDefineTypes (extractRuntimeEmits of
// ts-types.ts): for a function type, the string literal types of the first parameter of each call
// signature; for an object type, its property names; unknown otherwise.
fn (mut c Checker) vue_emits_from_type_checker(t &estree.EsTree, node int, abs_path string, mut stats Stats) []VueProp {
	unknown := VueProp{
		kind: .unknown
		node: node
	}
	typ := c.vue_type_of_type_node(t, node, abs_path, mut stats) or { return [unknown] }
	if typ.flags & (type_flag_any | type_flag_unknown | type_flag_never | type_flag_null) != 0 {
		return [unknown]
	}
	signatures := c.signatures_of(typ, 0) or { []tsgo.SignatureResponse{} }
	symbol := c.symbol_of(typ) or { tsgo.SymbolResponse{} }
	mut out := []VueProp{}
	if symbol.flags & vue_symbol_flags_function_or_method != 0 || signatures.len > 0 {
		for signature in signatures {
			params := c.signature_parameters(signature) or { []tsgo.ParameterResponse{} }
			if params.len == 0 {
				out << unknown
				continue
			}
			param_type := c.symbol_type(params[0].id) or {
				out << unknown
				continue
			}
			// iterateTypes: the members of a union that is not boolean.
			members := if param_type.flags & type_flag_union != 0
				&& param_type.flags & type_flag_boolean_like == 0 {
				c.members_of(param_type) or { [param_type] }
			} else {
				[param_type]
			}
			for member in members {
				value := member.value
				if member.flags & type_flag_string_literal != 0 && value is string {
					out << VueProp{
						kind:     .infer_type
						has_name: true
						name:     value
						node:     node
					}
				} else {
					out << unknown
				}
			}
		}
		return out
	}
	if typ.flags & type_flag_object != 0 {
		for property in c.properties(typ) or { []tsgo.SymbolResponse{} } {
			out << VueProp{
				kind:     .infer_type
				has_name: true
				name:     property.name
				node:     node
			}
		}
		return out
	}
	return [unknown]
}
