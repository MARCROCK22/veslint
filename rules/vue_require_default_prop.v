module rules

import estree
import time

// Port of the `vue/require-default-prop` rule of eslint-plugin-vue 10.12.1 (no options): a prop
// that is not required, not Boolean and has no default, in the options of a Vue object or in
// defineProps (where a type prop counts only with withDefaults or a props destructure).

const vue_require_default_prop_messages = {
	'missingDefault': "Prop '{{propName}}' requires default value to be set."
}

const vrdp_native_types = ['String', 'Number', 'Boolean', 'Function', 'Object', 'Array', 'Symbol']

// vrdp_object_prototype are the names `{}[name]` finds on Object.prototype.
const vrdp_object_prototype = ['constructor', 'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable',
	'toLocaleString', 'toString', 'valueOf', '__proto__', '__defineGetter__', '__defineSetter__',
	'__lookupGetter__', '__lookupSetter__']

fn (mut c Checker) lint_vue_require_default_prop(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineProps') {
		has_with_defaults := vue_has_with_defaults(t, call)
		with_defaults := c.vx6_with_defaults_expressions(root, t, call)
		destructure := vue_is_using_props_destructure(t, call)
		destructure_defaults := vx6_destructure_defaults(t, call)
		should_ignore := fn [has_with_defaults, with_defaults, destructure, destructure_defaults] (prop VueProp) bool {
			if prop.kind == .type_ && ((!has_with_defaults && !destructure)
				|| with_defaults.has_unknown || (with_defaults.props[prop.name] or { -1 }) >= 0
				|| prop.name in vrdp_object_prototype) {
				return true
			}
			return destructure && (!prop.has_name || prop.name in destructure_defaults)
		}
		for prop in c.vue_define_props(root, t, call, abs_path, false, mut stats) {
			stats.checked++
			c.vrdp_process(root, t, prop, should_ignore, abs_path, mut findings, mut stats)
		}
	}
	for obj in s.objects_of(vue_all_object_types) {
		for prop in vue_props_from_options(t, obj) {
			stats.checked++
			c.vrdp_process(root, t, prop, fn (prop VueProp) bool {
				return false
			}, abs_path, mut findings, mut stats)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vrdp_process is processProps for one prop.
fn (mut c Checker) vrdp_process(root C.vt_node, t &estree.EsTree, prop VueProp, should_ignore fn (VueProp) bool, abs_path string, mut findings []Finding, mut stats Stats) {
	if prop.kind == .object {
		if (t.flag(prop.node, .shorthand) or { false }) || !vrdp_is_without_default(t, prop.value)
			|| vrdp_is_boolean_prop(t, prop.value) || should_ignore(prop) {
			return
		}
		name := if prop.has_name {
			prop.name
		} else {
			key := t.node(prop.node, .key) or { -1 }
			'[${if key >= 0 { c.vx6_raw(t, key) } else { '' }}]'
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, prop.node)
			message_id: 'missingDefault'
			data:       {
				'propName': name
			}
		}
	} else if prop.kind == .type_ {
		info := c.vx6_type_prop(root, t, prop.node, abs_path, mut stats)
		if info.required || info.types == ['Boolean'] || should_ignore(prop) {
			return
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, prop.node)
			message_id: 'missingDefault'
			data:       {
				'propName': prop.name
			}
		}
	}
}

// vrdp_is_without_default is isWithoutDefaultValue.
fn vrdp_is_without_default(t &estree.EsTree, value int) bool {
	return match t.typ(value) {
		.object_expression {
			!vrdp_has_property(t, value, 'required', true) && !vrdp_has_property(t, value,
				'default', false)
		}
		.identifier {
			(t.string_of(value, .name) or { '' }) in vrdp_native_types
		}
		.call_expression, .member_expression {
			false
		}
		else {
			true
		}
	}
}

// vrdp_has_property: a Property with that static name (and, with `literal_true`, the value
// `true`).
fn vrdp_has_property(t &estree.EsTree, object int, name string, literal_true bool) bool {
	for p in t.list(object, .properties) or { []int{} } {
		if t.typ(p) != .property || (vue_static_property_name(t, p) or { continue }) != name {
			continue
		}
		if !literal_true {
			return true
		}
		v := vue_property_value(t, p)
		value := t.get(v, .value)
		if t.typ(v) == .literal && value is bool && value {
			return true
		}
	}
	return false
}

fn vrdp_is_boolean_type_value(t &estree.EsTree, value int) bool {
	if value < 0 {
		return false
	}
	if t.typ(value) == .identifier {
		return (t.string_of(value, .name) or { '' }) == 'Boolean'
	}
	if t.typ(value) == .array_expression {
		elements := (t.list(value, .elements) or { []int{} }).filter(it >= 0)
		return elements.len == 1 && t.typ(elements[0]) == .identifier
			&& (t.string_of(elements[0], .name) or { '' }) == 'Boolean'
	}
	return false
}

// vrdp_is_boolean_prop is isBooleanProp.
fn vrdp_is_boolean_prop(t &estree.EsTree, value int) bool {
	if vrdp_is_boolean_type_value(t, value) {
		return true
	}
	if t.typ(value) != .object_expression {
		return false
	}
	for p in t.list(value, .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		key := t.node(p, .key) or { continue }
		if t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == 'type'
			&& vrdp_is_boolean_type_value(t, vue_property_value(t, p)) {
			return true
		}
	}
	return false
}
