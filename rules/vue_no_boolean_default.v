module rules

import estree
import json2
import time

// Port of the `vue/no-boolean-default` rule of eslint-plugin-vue 10.12.1 (option "no-default",
// the default, or "default-false"): the default of a Boolean prop of a component's options or of
// defineProps (its `default`, the `withDefaults` one, or the props destructure's), or, with
// "default-false", a default that is not `false`.

const vue_no_boolean_default_messages = {
	'noBooleanDefault': 'Boolean prop should not set a default (Vue defaults it to false).'
	'defaultFalse':     'Boolean prop should only be defaulted to false.'
}

fn vue_no_boolean_default_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'no-default'
	}
	value := options[0]
	if value is string && value in ['default-false', 'no-default'] {
		return value
	}
	return error('the option of `${vue_no_boolean_default}` must be "default-false" or "no-default"')
}

fn (mut c Checker) lint_vue_no_boolean_default(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	style := vue_no_boolean_default_options(c.rule_options(vue_no_boolean_default))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_component_object_types) {
		for prop in vue_props_from_options(t, obj) {
			stats.checked++
			c.vnbd_process(root, t, prop, map[string][]int{}, style, abs_path, mut findings, mut
				stats)
		}
	}
	for call in c.vue_macros_named(t, 'defineProps') {
		with_defaults := c.vx6_with_defaults_expressions(root, t, call)
		destructure := vx6_destructure_defaults(t, call)
		mut others := map[string][]int{}
		for name, expression in with_defaults.props {
			if expression >= 0 {
				others[name] << expression
			}
		}
		for name, d in destructure {
			others[name] << d.expression
		}
		for prop in c.vue_define_props(root, t, call, abs_path, false, mut stats) {
			stats.checked++
			c.vnbd_process(root, t, prop, others, style, abs_path, mut findings, mut stats)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnbd_process is processProp; `others` are the other defaults of each prop (withDefaults first).
fn (mut c Checker) vnbd_process(root C.TSNode, t &estree.EsTree, prop VueProp, others map[string][]int, style string, abs_path string, mut findings []Finding, mut stats Stats) {
	if prop.kind == .object {
		value := prop.value
		is_boolean := vnbd_is_boolean_identifier(t, value) || (t.typ(value) == .object_expression
			&& vnbd_is_boolean_identifier(t, vx6_property_value_of(t, value, 'type')))
		if !is_boolean {
			return
		}
		if t.typ(value) == .object_expression {
			d := vue_find_property(t, value, 'default', none)
			if d >= 0 {
				c.vnbd_verify(t, vue_property_value(t, d), style, mut findings)
			}
		}
		if prop.has_name {
			for d in others[prop.name] or { []int{} } {
				c.vnbd_verify(t, d, style, mut findings)
			}
		}
	} else if prop.kind == .type_ {
		info := c.vx6_type_prop(root, t, prop.node, abs_path, mut stats)
		if info.types != ['Boolean'] {
			return
		}
		for d in others[prop.name] or { []int{} } {
			c.vnbd_verify(t, d, style, mut findings)
		}
	}
}

fn vnbd_is_boolean_identifier(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == 'Boolean'
}

// vnbd_verify is verifyDefaultExpression.
fn (mut c Checker) vnbd_verify(t &estree.EsTree, node int, style string, mut findings []Finding) {
	if node < 0 {
		return
	}
	if style == 'no-default' {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'noBooleanDefault'
		}
		return
	}
	value := t.get(node, .value)
	if t.typ(node) != .literal || !(value is bool && !value) {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'defaultFalse'
		}
	}
}
