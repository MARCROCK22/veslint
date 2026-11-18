module rules

import estree
import json2
import time

// Port of the `vue/no-required-prop-with-default` rule of eslint-plugin-vue 10.12.1 (option
// `autofix`): a required prop with a default (its `default`, the `withDefaults` one or the props
// destructure's), with a suggestion (with `autofix`, a fix) to make it optional.

const vue_no_required_prop_with_default_messages = {
	'requireOptional': 'Prop "{{ key }}" should be optional.'
	'fixRequiredProp': 'Change this prop to be optional.'
}

fn vue_no_required_prop_with_default_options(options []json2.Any) !bool {
	o := option_object(vue_no_required_prop_with_default, options, ['autofix'])!
	value := o.values['autofix'] or { return false }
	return value is bool && value
}

fn (mut c Checker) lint_vue_no_required_prop_with_default(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	autofix := vue_no_required_prop_with_default_options(c.rule_options(vue_no_required_prop_with_default))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	// onVueObjectEnter: in the order the objects are entered.
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .object_expression
			|| s.object_type(step.node) == .none_ {
			continue
		}
		for prop in vue_props_from_options(t, step.node) {
			stats.checked++
			c.vnrpwd_handle(root, t, prop, map[string]bool{}, autofix, abs_path, mut findings, mut stats)!
		}
	}
	for call in c.vx6_define_props_calls(t) {
		mut defaults := map[string]bool{}
		for name, _ in c.vx6_with_defaults_expressions(root, t, call).props {
			defaults[name] = true
		}
		for name, _ in vx6_destructure_defaults(t, call) {
			defaults[name] = true
		}
		for prop in c.vue_define_props(root, t, call, abs_path, false, mut stats) {
			stats.checked++
			c.vnrpwd_handle(root, t, prop, defaults, autofix, abs_path, mut findings, mut stats)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnrpwd_handle is handleObjectProp.
fn (mut c Checker) vnrpwd_handle(root C.TSNode, t &estree.EsTree, prop VueProp, defaults map[string]bool, autofix bool, abs_path string, mut findings []Finding, mut stats Stats) ! {
	// `defaultProps?.has(prop.propName)`: the options have no other defaults.
	in_defaults := prop.has_name && prop.name in defaults
	if prop.kind == .object && prop.has_name && t.typ(prop.value) == .object_expression
		&& (vue_find_property(t, prop.value, 'default', none) >= 0 || in_defaults) {
		required := vue_find_property(t, prop.value, 'required', none)
		if required < 0 {
			return
		}
		node := vue_property_value(t, required)
		if node >= 0 && t.typ(node) == .literal && vue_literal_truthy(t, node) {
			findings << c.vnrpwd_report(t, prop, fix_replace_range(t.nodes[node].start,
				t.nodes[node].end, 'false'), autofix)!
		}
	} else if prop.kind == .type_ && in_defaults {
		info := c.vx6_type_prop(root, t, prop.node, abs_path, mut stats)
		if !info.required {
			return
		}
		kind := t.string_of(prop.node, .kind) or { '' }
		if (t.typ(prop.node) == .ts_method_signature && kind in ['get', 'set'])
			|| (t.flag(prop.node, .computed) or { false }) {
			return
		}
		findings << c.vnrpwd_report(t, prop, fix_insert_at(t.nodes[prop.key].end, '?'),
			autofix)!
	}
}

fn (mut c Checker) vnrpwd_report(t &estree.EsTree, prop VueProp, fix Fix, autofix bool) !Finding {
	finding := Finding{
		stmt:       c.es_tree_position(t, prop.node)
		message_id: 'requireOptional'
		data:       {
			'key': prop.name
		}
	}
	if autofix {
		return c.with_fixes(finding, [fix])!
	}
	ok, suggestion := c.suggestion('fixRequiredProp', {}, [fix])!
	return Finding{
		...finding
		suggestions: if ok { [suggestion] } else { []Suggestion{} }
	}
}
