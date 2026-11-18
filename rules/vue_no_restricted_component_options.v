module rules

import estree
import json2
import jsregexp
import time

// Port of the `vue/no-restricted-component-options` rule of eslint-plugin-vue 10.12.1 (options:
// paths of option names, as a string, a list or `{name, message}`; `*` matches any property, a
// `/…/` name is a regular expression): a property of a Vue object or of defineOptions at the
// end of a restricted path.

const vue_no_restricted_component_options_messages = {
	'restrictedOption': '{{message}}'
}

// VrcoStep is a step of a path: any property (`*`) or the properties whose static name matches.
struct VrcoStep {
	wildcard bool
	regexp   jsregexp.JsRegex
}

struct VrcoOption {
	steps   []VrcoStep
	message string
}

fn vue_no_restricted_component_options_options(options []json2.Any) ![]VrcoOption {
	mut out := []VrcoOption{}
	for option in options {
		mut names := []string{}
		mut message := ''
		mut name_value := option
		if option is map[string]json2.Any {
			name_value = option['name'] or { json2.Any('') }
			if m := option['message'] {
				if m is string {
					message = m
				}
			}
		}
		if name_value is string {
			names << name_value
		} else if name_value is []json2.Any {
			for n in name_value {
				if n !is string {
					return error('a name of `${vue_no_restricted_component_options}` must be a string')
				}
				names << n as string
			}
		} else {
			return error('an option of `${vue_no_restricted_component_options}` must be a string, a list or an object')
		}
		mut steps := []VrcoStep{}
		for name in names {
			if name == '*' {
				steps << VrcoStep{
					wildcard: true
				}
			} else {
				steps << VrcoStep{
					regexp: vue_to_regexp(name, '', 'g')!
				}
			}
		}
		out << VrcoOption{
			steps:   steps
			message: message
		}
	}
	return out
}

fn (mut c Checker) lint_vue_no_restricted_component_options(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := vue_no_restricted_component_options_options(c.rule_options(vue_no_restricted_component_options))!
	mut findings := []Finding{}
	if options.len == 0 {
		return findings
	}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut objects := s.objects_of(vue_all_object_types)
	for call in c.vue_macros_named(t, 'defineOptions') {
		args := t.list(call, .arguments) or { []int{} }
		if args.len > 0 && t.typ(args[0]) == .object_expression {
			objects << args[0]
		}
	}
	for obj in objects {
		stats.checked++
		for option in options {
			if option.steps.len > 0 {
				c.vrco_verify(t, obj, option, 0, [], mut findings)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vrco_verify(t &estree.EsTree, object int, option &VrcoOption, index int, path []string, mut findings []Finding) {
	step := option.steps[index]
	for prop in t.list(object, .properties) or { []int{} } {
		mut key_name := '*'
		if !step.wildcard {
			if t.typ(prop) != .property {
				continue
			}
			name := vue_static_property_name(t, prop) or { continue }
			if name == '' || !vue_regexp_test(&step.regexp, name) {
				continue
			}
			key_name = name
		}
		mut next_path := path.clone()
		next_path << key_name
		if index + 1 < option.steps.len {
			if t.typ(prop) != .property {
				continue
			}
			value := vue_property_value(t, prop)
			if t.typ(value) != .object_expression {
				continue
			}
			c.vrco_verify(t, value, option, index + 1, next_path, mut findings)
			continue
		}
		node := if t.typ(prop) == .property { t.node(prop, .key) or { prop } } else { prop }
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'restrictedOption'
			data:       {
				'message': if option.message != '' {
					option.message
				} else {
					'Using `${next_path.join('.')}` is not allowed.'
				}
			}
		}
	}
}
