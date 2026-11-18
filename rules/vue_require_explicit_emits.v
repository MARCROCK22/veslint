module rules

import estree
import json2
import time

// Port of the `vue/require-explicit-emits` rule of eslint-plugin-vue 10.12.1 (options allowProps
// and ignoreMixins, default false): in a .vue file, an event emitted (`this.$emit`, `emit` or
// `context.emit` of a setup's context or of defineEmits' variable, `$emit` and that variable in
// the template, which takes the `<script setup>`'s defineEmits or the emits of the component the
// file exports) that the emits of its component do not declare, nor a defineModel (`update:x`),
// nor (allowProps) an `onX` prop; with suggestions that add it to the emits.

const vue_require_explicit_emits_messages = {
	'missing':              'The "{{name}}" event has been triggered but not declared on {{emitsKind}}.'
	'addOneOption':         'Add the "{{name}}" to {{emitsKind}}.'
	'addArrayEmitsOption':  'Add the {{emitsKind}} with array syntax and define "{{name}}" event.'
	'addObjectEmitsOption': 'Add the {{emitsKind}} with object syntax and define "{{name}}" event.'
}

struct VreeOptions {
	allow_props   bool
	ignore_mixins bool
}

fn vree_options(options []json2.Any) !VreeOptions {
	o := option_object(vue_require_explicit_emits, options, ['allowProps', 'ignoreMixins'])!
	return VreeOptions{
		allow_props:   o.bool_value('allowProps')!
		ignore_mixins: o.bool_value('ignoreMixins')!
	}
}

// vree_fix_emits_after_options are FIX_EMITS_AFTER_OPTIONS.
const vree_fix_emits_after_options = ['setup', 'data', 'computed', 'watch', 'methods', 'template',
	'render', 'renderError', 'beforeCreate', 'created', 'beforeMount', 'mounted', 'beforeUpdate',
	'updated', 'activated', 'deactivated', 'beforeUnmount', 'unmounted', 'beforeDestroy', 'destroyed',
	'renderTracked', 'renderTriggered', 'errorCaptured']

// VreeDefine is the emits and props of a component (an object, or the Program for
// `<script setup>`: vue_program_context), as the rule's maps keep them.
struct VreeDefine {
mut:
	key   int
	emits []VueProp
	props []VueProp
}

// VreeState is the rule's state as its listeners change it.
struct VreeState {
mut:
	emits        map[int][]VueProp
	props        map[int][]VueProp
	contexts     map[int]VueSetupContext
	model_events map[string]bool
	param_name   string
	// vueTemplateDefineData: `template_type` '' for null.
	template_type   string
	template_define VreeDefine
}

fn (mut c Checker) lint_vue_require_explicit_emits(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	o := vree_options(c.rule_options(vue_require_explicit_emits))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut st := VreeState{}
	if s.has_setup {
		st.template_type = 'setup'
		st.template_define = VreeDefine{
			key: vue_program_context
		}
	}
	mut macros := map[int]string{}
	for macro in c.vue_macros(t) {
		macros[macro.call] = macro.name
	}
	for step in t.steps() {
		node := step.node
		if step.leave {
			typ := s.object_type(node)
			if typ == .none_ {
				continue
			}
			// onVueObjectExit.
			if emits := st.emits[node] {
				if st.template_type !in ['export', 'setup'] && typ in [.mark, .export, .definition] {
					st.template_type = vue_object_type_name(typ)
					st.template_define = VreeDefine{
						key:   node
						emits: emits
						props: st.props[node] or { []VueProp{} }
					}
				}
			}
			st.contexts.delete(node)
			st.emits.delete(node)
			st.props.delete(node)
			continue
		}
		owner := s.owner_of(node)
		if owner == node {
			// onVueObjectEnter: emits declared in mixins are not visible.
			if !(o.ignore_mixins && vue_find_property(t, node, 'mixins', none) >= 0) {
				st.emits[node] = vue_emits_from_options(t, node)
				if o.allow_props {
					st.props[node] = vue_props_from_options(t, node)
				}
			}
		}
		if s.vue_function_kind(t, node) == 'setup' {
			if ctx := c.vree_setup_context(root, t, node) {
				st.contexts[owner] = ctx
			}
			continue
		}
		if t.typ(node) != .call_expression {
			continue
		}
		// defineScriptSetupVisitor's listeners, then defineVueVisitor's.
		match macros[node] or { '' } {
			'defineEmits' {
				emits := c.vue_define_emits(root, t, node, abs_path, true, mut stats)
				st.emits[vue_program_context] = emits
				if st.template_type == 'setup' {
					st.template_define.emits = emits
				}
				id := vue_define_emits_variable(t, node)
				if id >= 0 {
					st.param_name = vue_identifier_name(t, id)
					if ids := c.vue_reference_ids(root, t, id, true) {
						st.contexts[vue_program_context] = VueSetupContext{
							emit_ids: ids
						}
					}
				}
			}
			'defineModel' {
				st.model_events['update:${vue_define_model(t, node).name}'] = true
			}
			'defineProps' {
				if o.allow_props {
					props := c.vue_define_props(root, t, node, abs_path, true, mut stats)
					st.props[vue_program_context] = props
					if st.template_type == 'setup' {
						st.template_define.props = props
					}
				}
			}
			else {}
		}
		if s.in_script_setup(t, node) {
			c.vree_call(root, t, node, vue_program_context, o, st, mut findings)!
		}
		if owner >= 0 {
			c.vree_call(root, t, node, owner, o, st, mut findings)!
		}
	}
	if st.template_type != '' {
		for call in c.vue_template_calls() {
			es := &c.vue.doc.snippets[call.snippet].es
			name, literal := vue_name_param(es, call.node) or { continue }
			callee := vue_skip_chain(es, es.node(call.node, .callee) or { continue })
			callee_name := vue_identifier_name(es, callee)
			if callee_name != '' && (callee_name == r'$emit' || callee_name == st.param_name) {
				c.vree_verify(t, st.template_define, name, es.nodes[literal].start, es.nodes[literal].end,
					o, st, mut findings)!
			}
		}
	}
	stats.checked += findings.len
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vree_setup_context is the rule's onSetupFunctionEnter: the read references of the emit or the
// context (no default value skipped; another kind of parameter is a context that references
// nothing).
fn (mut c Checker) vree_setup_context(root C.TSNode, t &estree.EsTree, setup int) ?VueSetupContext {
	params := t.list(setup, .params) or { return none }
	if params.len < 2 || t.typ(params[1]) in [.rest_element, .array_pattern] {
		return none
	}
	param := params[1]
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
		ctx.emit_ids = c.vue_reference_ids(root, t, value, true)?
	} else if t.typ(param) == .identifier {
		ctx.context_ids = c.vue_reference_ids(root, t, param, true)?
	}
	return ctx
}

// vree_call is the rule's callVisitor on a call of the script, for the component `key`.
fn (mut c Checker) vree_call(root C.TSNode, t &estree.EsTree, call int, key int, o VreeOptions, st VreeState, mut findings []Finding) ! {
	name, literal := vue_name_param(t, call) or { return }
	emits := st.emits[key] or { return }
	define := VreeDefine{
		key:   key
		emits: emits
		props: st.props[key] or { []VueProp{} }
	}
	callee := vue_skip_chain(t, t.node(call, .callee) or { return })
	mut emit_name := ''
	if t.typ(callee) == .member_expression {
		member_name := vue_static_property_name(t, callee) or { '' }
		if member_name in ['emit', r'$emit'] {
			emit_name = member_name
		}
	}
	start, end := t.nodes[literal].start, t.nodes[literal].end
	if ctx := st.contexts[key] {
		if t.typ(callee) == .identifier && callee in ctx.emit_ids {
			c.vree_verify(t, define, name, start, end, o, st, mut findings)!
		} else if emit_name == 'emit' {
			object := vue_skip_chain(t, t.node(callee, .object) or { -1 })
			if object >= 0 && t.typ(object) == .identifier && object in ctx.context_ids {
				c.vree_verify(t, define, name, start, end, o, st, mut findings)!
			}
		}
	}
	if emit_name != r'$emit' {
		return
	}
	object := vue_skip_chain(t, t.node(callee, .object) or { -1 })
	if c.vue_is_this(root, t, object) {
		c.vree_verify(t, define, name, start, end, o, st, mut findings)!
	}
}

// vree_verify is verifyEmit: the report of a name [start, end) neither the emits, the models nor
// (allowProps) the props of the component declare.
fn (mut c Checker) vree_verify(t &estree.EsTree, define VreeDefine, name string, start int, end int, o VreeOptions, st VreeState, mut findings []Finding) ! {
	if name in st.model_events || define.emits.any(!it.has_name || it.name == name) {
		return
	}
	if o.allow_props {
		key := 'on${vue_capitalize(name)}'
		if define.props.any(!it.has_name || it.name == key) {
			return
		}
	}
	kind := if define.key == vue_program_context { '`defineEmits`' } else { '`emits` option' }
	mut suggestions := []Suggestion{}
	for suggestion in c.vree_suggest(t, define, name, kind) {
		ok, s := c.suggestion(suggestion.message_id, {
			'name':      name
			'emitsKind': kind
		}, [suggestion.fix])!
		if ok {
			suggestions << s
		}
	}
	findings << Finding{
		...c.vue_report(start, end, 'missing', {
			'name':      name
			'emitsKind': kind
		})
		suggestions: suggestions
	}
}

// VreeSuggestion is a suggestion of buildSuggest: its messageId and its one fix.
struct VreeSuggestion {
	message_id string
	fix        Fix
}

// vree_suggest is buildSuggest.
fn (mut c Checker) vree_suggest(t &estree.EsTree, define VreeDefine, name string, kind string) []VreeSuggestion {
	certain := define.emits.filter(it.kind in [.array, .object])
	if certain.len > 0 {
		last := certain.last()
		text := if last.kind == .array { ", '${name}'" } else { ", '${name}': null" }
		return [VreeSuggestion{'addOneOption', fix_insert_at(t.nodes[last.node].end, text)}]
	}
	if define.key == vue_program_context {
		// We don't know where to put defineEmits.
		return []
	}
	object := define.key
	all := t.list(object, .properties) or { []int{} }
	properties := all.filter(vue_is_property(t, it))
	mut emits_option := -1
	for p in properties {
		if (vue_static_property_name(t, p) or { '' }) == 'emits' {
			emits_option = p
			break
		}
	}
	if emits_option >= 0 {
		value := vue_property_value(t, emits_option)
		if t.typ(value) == .array_expression {
			comma := if (t.list(value, .elements) or { []int{} }).len > 0 { ',' } else { '' }
			return [
				VreeSuggestion{'addOneOption', fix_insert_at(t.nodes[value].start + 1, "'${name}'${comma}")},
			]
		}
		if t.typ(value) == .object_expression {
			comma := if (t.list(value, .properties) or { []int{} }).len > 0 { ',' } else { '' }
			return [
				VreeSuggestion{'addOneOption', fix_insert_at(t.nodes[value].start + 1, "'${name}': null${comma}")},
			]
		}
		return []
	}
	mut after_option := -1
	for p in properties {
		if (vue_static_property_name(t, p) or { '' }) in vree_fix_emits_after_options {
			after_option = p
			break
		}
	}
	tokens := c.un_tokens(t)
	mut out := []VreeSuggestion{}
	for i, value in ["['${name}']", "{'${name}': null}"] {
		message_id := if i == 0 { 'addArrayEmitsOption' } else { 'addObjectEmitsOption' }
		mut fix := Fix{}
		if after_option >= 0 {
			before := tokens.before(t.nodes[after_option].start, false) or { continue }
			fix = fix_insert_at(before.end, '\nemits: ${value},')
		} else if all.len > 0 {
			before := if properties.len > 0 { properties.last() } else { all.last() }
			fix = fix_insert_at(t.nodes[before].end, ',\nemits: ${value}')
		} else {
			left_line, _ := t.line_column(t.nodes[object].start)
			right_line, _ := t.line_column(t.nodes[object].end - 1)
			fix = fix_insert_at(t.nodes[object].start + 1, '\nemits: ${value}${if left_line < right_line {
				''
			} else {
				'\n'
			}}')
		}
		out << VreeSuggestion{message_id, fix}
	}
	return out
}
