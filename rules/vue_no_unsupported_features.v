module rules

import estree
import json2
import time

// Port of the `vue/no-unsupported-features` rule of eslint-plugin-vue 10.12.1 (options `version`
// and `ignores`): the syntaxes of lib/rules/syntaxes/*.ts a Vue.js version range (node-semver,
// rules/vue_semver.v) does not entirely support. slot-scope-attribute is reported without its
// fix (fixToUpgrade is only vue/no-deprecated-slot-scope-attribute's); v-slot,
// v-bind-prop-modifier-shorthand, v-bind-same-name-shorthand and define-options have fixes.

const vnuf_messages = {
	'forbiddenSlotScopeAttribute':         '`slot-scope` are not supported except Vue.js ">=2.5.0 <3.0.0".'
	'forbiddenDynamicDirectiveArguments':  'Dynamic arguments are not supported until Vue.js "2.6.0".'
	'forbiddenVSlot':                      '`v-slot` are not supported until Vue.js "2.6.0".'
	'forbiddenScriptSetup':                '`<script setup>` is not supported until Vue.js "2.7.0".'
	'forbiddenStyleCssVarsInjection':      'SFC CSS variable injection is not supported until Vue.js ">=3.0.3 || >=2.7.0 <3.0.0".'
	'forbiddenVModelArgument':             'Argument on `v-model` is not supported until Vue.js "3.0.0".'
	'forbiddenVModelCustomModifiers':      'Custom modifiers on `v-model` are not supported until Vue.js "3.0.0".'
	'forbiddenVIs':                        '`v-is` are not supported until Vue.js "3.0.0".'
	'forbiddenIsAttributeWithVuePrefix':   '`is="vue:"` are not supported until Vue.js "3.1.0".'
	'forbiddenVMemo':                      '`v-memo` are not supported until Vue.js "3.2.0".'
	'forbiddenVBindPropModifierShorthand': '`.prop` shorthand are not supported until Vue.js "3.2.0".'
	'forbiddenVBindAttrModifier':          '`.attr` modifiers on `v-bind` are not supported until Vue.js "3.2.0".'
	'forbiddenDefineOptions':              '`defineOptions()` macros are not supported until Vue.js "3.3.0".'
	'forbiddenDefineSlots':                '`defineSlots()` macros are not supported until Vue.js "3.3.0".'
	'forbiddenDefineModel':                '`defineModel()` macros are not supported until Vue.js "3.4.0".'
	'forbiddenVBindSameNameShorthand':     '`v-bind` same-name shorthand is not supported until Vue.js "3.4.0".'
}

// vnuf_features are FEATURES: each syntax and the versions that support it, in the order their
// listeners are composited.
const vnuf_features = [
	['slot-scope-attribute', '>=2.5.0 <3.0.0'],
	['dynamic-directive-arguments', '>=2.6.0'],
	['v-slot', '>=2.6.0'],
	['script-setup', '>=2.7.0'],
	['style-css-vars-injection', '>=3.0.3 || >=2.7.0 <3.0.0'],
	['v-model-argument', '>=3.0.0'],
	['v-model-custom-modifiers', '>=3.0.0'],
	['v-is', '>=3.0.0'],
	['is-attribute-with-vue-prefix', '>=3.1.0'],
	['v-memo', '>=3.2.0'],
	['v-bind-prop-modifier-shorthand', '>=3.2.0 || >=2.6.0-beta.1 <=2.6.0-beta.3'],
	['v-bind-attr-modifier', '>=3.2.0'],
	['define-options', '>=3.3.0'],
	['define-slots', '>=3.3.0'],
	['define-model', '>=3.4.0'],
	['v-bind-same-name-shorthand', '>=3.4.0'],
]

struct VnufOptions {
	version string
	ignores []string
}

fn vnuf_options(options []json2.Any) !VnufOptions {
	o := option_object(vue_no_unsupported_features, options, ['version', 'ignores'])!
	mut version := ''
	if value := o.values['version'] {
		if value !is string {
			return error('option `version` of `${vue_no_unsupported_features}` must be a text')
		}
		version = value as string
	}
	ignores := o.string_list('ignores')!
	feature_names := vnuf_features.map(it[0])
	for i, ignore in ignores {
		if ignore !in feature_names || ignore in ignores[..i] {
			return error('option `ignores` of `${vue_no_unsupported_features}` must be distinct syntax names')
		}
	}
	return VnufOptions{
		version: version
		ignores: ignores
	}
}

// vnuf_forbidden are the syntaxes the rule checks: those not ignored that the version range is
// not a subset of the supported range of. An error, as in the rule, when the version is not a
// valid range and a syntax is checked.
fn vnuf_forbidden(o VnufOptions) !map[string]bool {
	mut out := map[string]bool{}
	if o.version == '' {
		return out
	}
	r := vsem_re()!
	range := r.range(o.version) or { VsemRange{} }
	for feature in vnuf_features {
		if feature[0] in o.ignores {
			continue
		}
		if range.set.len == 0 {
			return error("Cannot read properties of null (reading 'set'): the version `${o.version}` of ${vue_no_unsupported_features} is not a valid range")
		}
		if !r.subset(range, r.range(feature[1])!)! {
			out[feature[0]] = true
		}
	}
	return out
}

fn (mut c Checker) lint_vue_no_unsupported_features(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	forbidden := vnuf_forbidden(vnuf_options(c.rule_options(vue_no_unsupported_features))!)!
	mut findings := []Finding{}
	if forbidden.len == 0 {
		return findings
	}
	none_data := map[string]string{}
	// The script's listeners: Program, then the macros of <script setup>.
	if s := c.vue_script(root, abs_path) {
		if forbidden['script-setup'] && s.has_setup {
			attr := c.vue_get_attribute(s.setup_element, 'setup', none)
			node := if attr >= 0 { attr } else { c.vue.doc.nodes[s.setup_element].start_tag }
			findings << c.vue_report_vnode(node, 'forbiddenScriptSetup', none_data)
		}
	}
	if forbidden['style-css-vars-injection'] {
		for style in c.vue.doc.top_elements('style') {
			for child in c.vue.doc.nodes[style].children {
				if c.vue.doc.nodes[child].typ == .v_expression_container {
					findings << c.vue_report_vnode(child, 'forbiddenStyleCssVarsInjection',
						none_data)
				}
			}
		}
	}
	if forbidden['define-options'] || forbidden['define-slots'] || forbidden['define-model'] {
		if t := c.es_tree(root, abs_path) {
			for macro in c.vue_macros(t) {
				if macro.name == 'defineOptions' && forbidden['define-options'] {
					f := Finding{
						stmt:       c.es_tree_position(t, macro.call)
						message_id: 'forbiddenDefineOptions'
					}
					findings << c.with_fixes(f, c.vnuf_define_options_fix(t, macro.call))!
				} else if macro.name == 'defineSlots' && forbidden['define-slots'] {
					findings << Finding{
						stmt:       c.es_tree_position(t, macro.call)
						message_id: 'forbiddenDefineSlots'
					}
				} else if macro.name == 'defineModel' && forbidden['define-model'] {
					findings << Finding{
						stmt:       c.es_tree_position(t, macro.call)
						message_id: 'forbiddenDefineModel'
					}
				}
			}
		}
	}
	if !c.vue_has_template() {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		stats.checked++
		if !node.directive {
			// VAttribute[directive=false][key.name='is']
			if forbidden['is-attribute-with-vue-prefix'] && c.vue.doc.nodes[node.key].name == 'is'
				&& node.value >= 0 && c.vue.doc.nodes[node.value].text.starts_with('vue:') {
				findings << c.vue_report_vnode(node.value, 'forbiddenIsAttributeWithVuePrefix',
					none_data)
			}
			continue
		}
		name := c.vue_directive_name(i)
		key := &c.vue.doc.nodes[node.key]
		// The VAttribute's listeners.
		if name == 'slot-scope' && forbidden['slot-scope-attribute'] {
			findings << c.vue_report_vnode(node.key, 'forbiddenSlotScopeAttribute', none_data)
		}
		if name == 'slot' && forbidden['v-slot'] {
			f := c.vue_report_vnode(node.key, 'forbiddenVSlot', none_data)
			findings << c.with_fixes(f, c.vnuf_v_slot_fix(i))!
		}
		if name == 'is' && forbidden['v-is'] {
			findings << c.vue_report_vnode(node.key, 'forbiddenVIs', none_data)
		}
		if name == 'memo' && forbidden['v-memo'] {
			findings << c.vue_report_vnode(node.key, 'forbiddenVMemo', none_data)
		}
		if name == 'bind' && forbidden['v-bind-attr-modifier'] {
			for m in key.modifiers {
				if c.vue.doc.nodes[m].name == 'attr' {
					findings << c.vue_report_vnode(m, 'forbiddenVBindAttrModifier', none_data)
					break
				}
			}
		}
		if name == 'bind' && forbidden['v-bind-same-name-shorthand']
			&& c.vue_is_vbind_same_name_shorthand(i) {
			// The Identifier vue-eslint-parser makes has the argument's name camelized.
			e := c.vue.doc.nodes[node.value].expression
			id_name := c.vue.doc.snippets[e.snippet].es.string_of(e.node, .name) or { '' }
			f := c.vue_report_vnode(i, 'forbiddenVBindSameNameShorthand', none_data)
			findings << c.with_fixes(f, [
				fix_insert_at(node.end, '="${id_name}"'),
			])!
		}
		// The VDirectiveKey's listeners.
		if name == 'model' && key.argument >= 0 && forbidden['v-model-argument'] {
			findings << c.vue_report_vnode(key.argument, 'forbiddenVModelArgument', none_data)
		}
		if name == 'model' && key.modifiers.len > 0 && forbidden['v-model-custom-modifiers'] {
			for m in key.modifiers {
				if c.vue.doc.nodes[m].name !in ['lazy', 'number', 'trim'] {
					findings << c.vue_report_vnode(m, 'forbiddenVModelCustomModifiers',
						none_data)
				}
			}
		}
		if name == 'bind' && key.dir_name >= 0 && c.vue.doc.nodes[key.dir_name].raw_name == '.'
			&& forbidden['v-bind-prop-modifier-shorthand'] {
			argument := if key.argument >= 0
				&& c.vue.doc.nodes[key.argument].typ == .v_identifier {
				c.vue.doc.nodes[key.argument].raw_name
			} else {
				'undefined'
			}
			f := c.vue_report_vnode(node.key, 'forbiddenVBindPropModifierShorthand', none_data)
			key_start, key_end := c.vue_vnode_range(node.key)
			findings << c.with_fixes(f, [
				fix_replace_range(key_start, key_end, ':${argument}.prop'),
			])!
		}
		// VAttribute[directive=true] > VDirectiveKey > VExpressionContainer
		if key.argument >= 0 && c.vue.doc.nodes[key.argument].typ == .v_expression_container
			&& forbidden['dynamic-directive-arguments'] {
			findings << c.vue_report_vnode(key.argument, 'forbiddenDynamicDirectiveArguments',
				none_data)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnuf_v_slot_fix is fixVSlotToSlot (on a `<template>` only): the `v-slot` made `slot` and
// `slot-scope` attributes.
fn (c &Checker) vnuf_v_slot_fix(attr int) []Fix {
	node := &c.vue.doc.nodes[attr]
	if c.vue.doc.nodes[c.vue_attribute_element(attr)].name != 'template' {
		return []
	}
	key := &c.vue.doc.nodes[node.key]
	if key.modifiers.len > 0 {
		return []
	}
	mut attrs := []string{}
	if key.argument >= 0 {
		argument := &c.vue.doc.nodes[key.argument]
		if argument.typ == .v_identifier {
			attrs << 'slot="${argument.raw_name}"'
		} else if argument.typ == .v_expression_container && !argument.expression.is_null() {
			start, end := c.vue_expr_range(argument.expression)
			attrs << ':slot="${c.vue_text(start, end)}"'
		} else {
			return []
		}
	}
	if node.value >= 0 {
		start, end := c.vue_vnode_range(node.value)
		attrs << 'slot-scope=${c.vue_text(start, end)}'
	}
	if attrs.len == 0 {
		attrs << 'slot'
	}
	start, end := c.vue_vnode_range(attr)
	return [fix_replace_range(start, end, attrs.join(' '))]
}

// vnuf_define_options_fix is define-options' fix: the options of the `defineOptions()` moved to
// a new `<script>` before `<script setup>`, when there is none, and its statement removed (with
// the white space before it on its line).
fn (c &Checker) vnuf_define_options_fix(t &estree.EsTree, call int) []Fix {
	args := t.list(call, .arguments) or { []int{} }
	if args.len == 0 || !c.vue_script_info.has_setup {
		return []
	}
	for script in c.vue.doc.top_elements('script') {
		if !c.vue_has_attribute(script, 'setup', none) {
			return []
		}
	}
	mut statement := call
	for t.nodes[statement].parent >= 0 && t.typ(t.nodes[statement].parent) != .program {
		statement = t.nodes[statement].parent
	}
	start := t.nodes[statement].start
	mut remove_start := start
	// The text of its line before it (lines broken by LF, as vue-eslint-parser counts them).
	line_start := c.src[..start].last_index_u8(`\n`) + 1
	if js_trim(c.src[line_start..start]) == '' {
		remove_start = line_start
	}
	options := c.src[t.nodes[args[0]].start..t.nodes[args[0]].end]
	return [
		fix_insert_at(c.vue_script_info.setup_start, '<script>\nexport default ${options}\n</script>\n'),
		fix_remove_range(remove_start, t.nodes[statement].end),
	]
}
