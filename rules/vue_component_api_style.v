module rules

import estree
import json2
import time

// Port of the `vue/component-api-style` rule of eslint-plugin-vue 10.12.1 (option: the allowed
// styles among "script-setup", "composition", "composition-vue2" and "options", by default
// ["script-setup", "composition"]): `<script setup>` when it is not allowed, and the options of a
// Vue object that belong to an API that is not allowed.

const vue_component_api_style_messages = {
	'disallowScriptSetup':                      '`<script setup>` is not allowed in your project. Use {{allowedApis}} instead.'
	'disallowComponentOption':                  '{{disallowedApi}} is not allowed in your project. {{optionPhrase}} is part of the {{disallowedApi}}. Use {{allowedApis}} instead.'
	'disallowComponentOptionPreferScriptSetup': '{{disallowedApi}} is not allowed in your project. Use `<script setup>` instead.'
}

struct VcasAllows {
mut:
	script_setup     bool
	composition      bool
	composition_vue2 bool
	options          bool
}

struct VcasOptions {
mut:
	sfc   VcasAllows
	other VcasAllows
}

fn vue_component_api_style_options(options []json2.Any) !VcasOptions {
	mut o := VcasOptions{}
	mut prefer := ['script-setup', 'composition']
	if options.len > 0 {
		value := options[0]
		if value !is []json2.Any {
			return error('the option of `${vue_component_api_style}` must be a list')
		}
		prefer = []
		for item in value as []json2.Any {
			if item is string {
				prefer << item
			}
		}
	}
	for p in prefer {
		match p {
			'script-setup' {
				o.sfc.script_setup = true
			}
			'composition' {
				o.sfc.composition = true
				o.other.composition = true
			}
			'composition-vue2' {
				o.sfc.composition_vue2 = true
				o.other.composition_vue2 = true
			}
			'options' {
				o.sfc.options = true
				o.other.options = true
			}
			else {}
		}
	}
	if !o.other.composition && !o.other.composition_vue2 && !o.other.options {
		o.other.composition = true
		o.other.composition_vue2 = true
		o.other.options = true
	}
	return o
}

const vcas_options_api = ['mixins', 'extends', 'data', 'computed', 'methods', 'watch', 'provide',
	'inject', 'beforeCreate', 'created', 'beforeMount', 'mounted', 'beforeUpdate', 'updated',
	'activated', 'deactivated', 'beforeDestroy', 'beforeUnmount', 'destroyed', 'unmounted', 'render',
	'renderTracked', 'renderTriggered', 'errorCaptured', 'expose']
const vcas_composition_api = ['setup']
const vcas_composition_api_vue2 = ['setup', 'render', 'renderTracked', 'renderTriggered']
const vcas_lifecycle_hooks = ['beforeCreate', 'created', 'beforeMount', 'mounted', 'beforeUpdate',
	'updated', 'activated', 'deactivated', 'beforeDestroy', 'beforeUnmount', 'destroyed', 'unmounted',
	'renderTracked', 'renderTriggered', 'errorCaptured']

fn vcas_allowed_phrase(a VcasAllows) string {
	mut phrases := []string{}
	if a.script_setup {
		phrases << '`<script setup>`'
	}
	if a.composition {
		phrases << 'Composition API'
	}
	if a.composition_vue2 {
		phrases << 'Composition API (Vue 2)'
	}
	if a.options {
		phrases << 'Options API'
	}
	return if phrases.len > 2 {
		'${phrases[..phrases.len - 1].join(', ')} or ${phrases.last()}'
	} else {
		phrases.join(' or ')
	}
}

fn vcas_option_phrase(name string) string {
	if name in vcas_lifecycle_hooks {
		return '`${name}` lifecycle hook'
	}
	return if name == 'setup' || name == 'render' {
		'`${name}` function'
	} else {
		'`${name}` option'
	}
}

fn (mut c Checker) lint_vue_component_api_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_component_api_style_options(c.rule_options(vue_component_api_style))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if !o.sfc.script_setup && s.has_setup {
		findings << c.vue_report_vnode(c.vue.doc.nodes[s.setup_element].start_tag, 'disallowScriptSetup',
			{
				'allowedApis': vcas_allowed_phrase(o.sfc)
			})
	}
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		allows := if c.vcas_is_sfc_object(root, t, s, obj) { o.sfc } else { o.other }
		if (allows.composition || allows.composition_vue2) && allows.options {
			continue
		}
		apis := [
			VcasApi{allows.composition, vcas_composition_api, 'Composition API'},
			VcasApi{allows.options, vcas_options_api, 'Options API'},
			VcasApi{allows.composition_vue2, vcas_composition_api_vue2, 'Composition API (Vue 2)'},
		]
		prefer_script_setup := allows.script_setup && !allows.composition
			&& !allows.composition_vue2 && !allows.options
		for prop in t.list(obj, .properties) or { []int{} } {
			if t.typ(prop) != .property {
				continue
			}
			name := vue_static_property_name(t, prop) or { continue }
			if name == '' || apis.any(it.allow && name in it.options) {
				continue
			}
			mut disallowed := ''
			for api in apis {
				if !api.allow && name in api.options {
					disallowed = api.name
					break
				}
			}
			if disallowed == '' {
				continue
			}
			key := t.node(prop, .key) or { continue }
			findings << Finding{
				stmt:       c.es_tree_position(t, key)
				message_id: if prefer_script_setup {
					'disallowComponentOptionPreferScriptSetup'
				} else {
					'disallowComponentOption'
				}
				data:       {
					'disallowedApi': disallowed
					'optionPhrase':  vcas_option_phrase(name)
					'allowedApis':   vcas_allowed_phrase(allows)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

struct VcasApi {
	allow   bool
	options []string
	name    string
}

// vcas_is_sfc_object ports isSFCObject: in a .vue file (or one without extension), the object
// `export default` (outside `<script setup>`), `defineComponent`, `defineNuxtComponent` or
// `Vue.extend` give, or a `const` that one of them is given.
fn (mut c Checker) vcas_is_sfc_object(root C.TSNode, t &estree.EsTree, s &VueScript, node int) bool {
	ext := vmcfn_extname(s.filename.all_after_last('/'))
	if ext != '.vue' && ext != '' {
		return false
	}
	return c.vcas_is_sfc(root, t, s, node, 0)
}

fn (mut c Checker) vcas_is_sfc(root C.TSNode, t &estree.EsTree, s &VueScript, node int, depth int) bool {
	if depth > 100 {
		return false
	}
	parent := vue_get_parent(t, node)
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.export_default_declaration {
			if vue_skip_ts_as(t, t.node(parent, .declaration) or { -1 }) != node {
				return false
			}
			return !s.has_setup || s.setup_start > t.nodes[parent].start
				|| t.nodes[parent].end > s.setup_end
		}
		.call_expression {
			args := t.list(parent, .arguments) or { []int{} }
			if args.all(vue_skip_ts_as(t, it) != node) {
				return false
			}
			callee := t.node(parent, .callee) or { return false }
			mut ok := false
			if t.typ(callee) == .identifier {
				name := t.string_of(callee, .name) or { '' }
				ok = name == 'defineComponent' || name == 'defineNuxtComponent'
			} else if t.typ(callee) == .member_expression {
				object := t.node(callee, .object) or { -1 }
				property := t.node(callee, .property) or { -1 }
				ok = object >= 0 && t.typ(object) == .identifier
					&& (t.string_of(object, .name) or { '' }) == 'Vue' && property >= 0
					&& t.typ(property) == .identifier
					&& (t.string_of(property, .name) or { '' }) == 'extend'
			}
			return ok && c.vcas_is_sfc(root, t, s, parent, depth + 1)
		}
		.variable_declarator {
			id := t.node(parent, .id) or { return false }
			if vue_skip_ts_as(t, t.node(parent, .init) or { -1 }) != node || t.typ(id) != .identifier {
				return false
			}
			v := c.unb_find_variable(root, t, id)
			if v < 0 {
				return false
			}
			tree := c.scope_tree(root)
			for r in tree.variables[v].references {
				identifier := c.es_index_of(t, tree.references[r].identifier) or { continue }
				if c.vcas_is_sfc(root, t, s, identifier, depth + 1) {
					return true
				}
			}
			return false
		}
		else {
			return false
		}
	}
}
