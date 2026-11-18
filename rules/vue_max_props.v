module rules

import estree
import json2
import time

// Port of the `vue/max-props` rule of eslint-plugin-vue 10.12.1 (option `maxProps`): a component
// with more distinct prop names than the maximum (an unnamed prop counts as one name), reported
// at its `props` property or at its `defineProps`.

const vue_max_props_messages = {
	'tooManyProps': 'Component has too many props ({{propCount}}). Maximum allowed is {{limit}}.'
}

fn vue_max_props_options(options []json2.Any) !f64 {
	o := option_object(vue_max_props, options, ['maxProps'])!
	value := o.values['maxProps'] or { return -1 }
	if value !is f64 && value !is int && value !is i64 {
		return error('option `maxProps` of `${vue_max_props}` must be an integer')
	}
	return value.f64()
}

fn (mut c Checker) lint_vue_max_props(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	max_props := vue_max_props_options(c.rule_options(vue_max_props))!
	mut findings := []Finding{}
	if max_props < 0 {
		return findings
	}
	limit := max_props
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		props_node := vue_find_property(t, obj, 'props', none)
		if props_node >= 0 {
			c.vue_check_max_props(t, vue_props_from_options(t, obj), props_node, limit, mut
				findings, mut stats)
		}
	}
	for call in c.vue_macros_named(t, 'defineProps') {
		props := c.vue_define_props(root, t, call, abs_path, true, mut stats)
		c.vue_check_max_props(t, props, call, limit, mut findings, mut stats)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vue_check_max_props(t &estree.EsTree, props []VueProp, node int, limit f64, mut findings []Finding, mut stats Stats) {
	stats.checked++
	mut distinct := map[string]bool{}
	for prop in props {
		// `new Set(props.map((prop) => prop.propName))`: null is one more name.
		distinct[if prop.has_name { 's' + prop.name } else { 'null' }] = true
	}
	count := distinct.len
	if f64(count) > limit && props.len > 0 && props[0].node >= 0 {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'tooManyProps'
			data:       {
				'propCount': count.str()
				'limit':     js_number_to_string(limit)
			}
		}
	}
}
