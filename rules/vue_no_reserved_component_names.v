module rules

import estree
import json2
import time

// Port of the `vue/no-reserved-component-names` rule of eslint-plugin-vue 10.12.1 (options
// `disallowVueBuiltInComponents`, `disallowVue3BuiltInComponents` and
// `htmlElementCaseSensitive`): a component name (`x.component('name', …)`, the `name` of a Vue
// object or of defineOptions, a key of `components`) that is an HTML or SVG element's (or, with
// the options, a built-in component's).

const vue_no_reserved_component_names_messages = {
	'reserved':       'Name "{{name}}" is reserved.'
	'reservedInHtml': 'Name "{{name}}" is reserved in HTML.'
	'reservedInVue':  'Name "{{name}}" is reserved in Vue.js.'
	'reservedInVue3': 'Name "{{name}}" is reserved in Vue.js 3.x.'
}

const vnrcn_kebab_case_elements = ['annotation-xml', 'color-profile', 'font-face', 'font-face-src',
	'font-face-uri', 'font-face-format', 'font-face-name', 'missing-glyph']

const vnrcn_vue2_builtin_components = ['template', 'slot', 'component', 'Component', 'transition',
	'Transition', 'transition-group', 'TransitionGroup', 'keep-alive', 'KeepAlive']

// The names of the rule's sets: RESERVED_NAMES_IN_OTHERS and the capitalized names.
struct VnrcnNames {
	others             map[string]bool
	capitalized_html   map[string]bool
	capitalized_others map[string]bool
}

const vnrcn_names = vnrcn_build_names()

fn vnrcn_build_names() VnrcnNames {
	mut others := map[string]bool{}
	mut capitalized_html := map[string]bool{}
	mut capitalized_others := map[string]bool{}
	for name, _ in vue_deprecated_html_element_names {
		others[name] = true
		capitalized_others[vue_capitalize(name)] = true
	}
	for name in vnrcn_kebab_case_elements {
		others[name] = true
		capitalized_others[vue_pascal_case(name)] = true
	}
	for name, _ in vue_svg_element_names {
		others[name] = true
		if name.bytes().all(it >= `a` && it <= `z`) {
			capitalized_others[vue_capitalize(name)] = true
		}
	}
	for name, _ in vue_html_element_names {
		capitalized_html[vue_capitalize(name)] = true
	}
	return VnrcnNames{
		others:             others
		capitalized_html:   capitalized_html
		capitalized_others: capitalized_others
	}
}

struct VnrcnOptions {
	vue2           bool
	vue3           bool
	case_sensitive bool
}

fn vue_no_reserved_component_names_options(options []json2.Any) !VnrcnOptions {
	o := option_object(vue_no_reserved_component_names, options, [
		'disallowVueBuiltInComponents',
		'disallowVue3BuiltInComponents',
		'htmlElementCaseSensitive',
	])!
	is_true := fn [o] (key string) bool {
		value := o.values[key] or { return false }
		return value is bool && value
	}
	return VnrcnOptions{
		vue2:           is_true('disallowVueBuiltInComponents')
		vue3:           is_true('disallowVue3BuiltInComponents')
		case_sensitive: is_true('htmlElementCaseSensitive')
	}
}

fn (o &VnrcnOptions) reserved_in_html(name string) bool {
	return name in vue_html_element_names
		|| (!o.case_sensitive && name in vnrcn_names.capitalized_html)
}

fn (o &VnrcnOptions) reserved(name string) bool {
	return o.reserved_in_html(name) || name in vnrcn_names.others
		|| (!o.case_sensitive && name in vnrcn_names.capitalized_others)
		|| (o.vue2 && name in vnrcn_vue2_builtin_components)
		|| (o.vue3 && name in vue_builtin_component_names)
}

fn (o &VnrcnOptions) message_id(name string) string {
	if o.reserved_in_html(name) {
		return 'reservedInHtml'
	}
	if name in vnrcn_vue2_builtin_components {
		return 'reservedInVue'
	}
	return if name in vue_builtin_component_names { 'reservedInVue3' } else { 'reserved' }
}

fn (mut c Checker) lint_vue_no_reserved_component_names(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_no_reserved_component_names_options(c.rule_options(vue_no_reserved_component_names))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut name_nodes := []int{}
	for call in vue_call_component_calls(t) {
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 2 && vue_is_string_literal(t, args[0]) {
			name_nodes << args[0]
		}
	}
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		components := vue_find_property(t, obj, 'components', fn [t] (p int) bool {
			return t.typ(vue_property_value(t, p)) == .object_expression
		})
		if components >= 0 {
			for p in t.list(vue_property_value(t, components), .properties) or { []int{} } {
				if !vue_is_property(t, p) {
					continue
				}
				name := vue_static_property_name(t, p) or { continue }
				if name != '' && o.reserved(name) {
					findings << c.vnrcn_report(t, p, name, o)
				}
			}
		}
		name := vue_find_property(t, obj, 'name', none)
		if name >= 0 && vue_is_string_literal(t, vue_property_value(t, name)) {
			name_nodes << vue_property_value(t, name)
		}
	}
	for call in c.vue_macros_named(t, 'defineOptions') {
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 0 || t.typ(args[0]) != .object_expression {
			continue
		}
		name := vue_find_property(t, args[0], 'name', none)
		if name >= 0 && vue_is_string_literal(t, vue_property_value(t, name)) {
			name_nodes << vue_property_value(t, name)
		}
	}
	for node in name_nodes {
		stats.checked++
		name := vue_string_literal_value(t, node, false) or { continue }
		if o.reserved(name) {
			findings << c.vnrcn_report(t, node, name, o)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vnrcn_report(t &estree.EsTree, node int, name string, o &VnrcnOptions) Finding {
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: o.message_id(name)
		data:       {
			'name': name
		}
	}
}
