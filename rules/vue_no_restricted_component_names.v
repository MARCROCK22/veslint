module rules

import estree
import json2
import jsregexp
import time

// Port of the `vue/no-restricted-component-names` rule of eslint-plugin-vue 10.12.1 (options:
// names, as strings or `{name, message, suggest}`; a name is a regular expression `/…/` or a
// name matched in PascalCase and kebab-case): the `name` of a Vue object or of defineOptions
// that a restriction matches, with a suggestion to the `suggest` name.

const vue_no_restricted_component_names_messages = {
	'disallow': '{{message}}'
	'suggest':  'Instead, change to `{{suggest}}`.'
}

struct VrcnOption {
	is_regexp bool
	regexp    jsregexp.JsRegex
	name      string
	message   string
	suggest   string
}

fn vue_no_restricted_component_names_options(options []json2.Any) ![]VrcnOption {
	mut out := []VrcnOption{}
	for option in options {
		mut name := ''
		mut message := ''
		mut suggest := ''
		if option is string {
			name = option
		} else if option is map[string]json2.Any {
			n := option['name'] or { json2.Any('') }
			if n !is string {
				return error('`name` of `${vue_no_restricted_component_names}` must be a string')
			}
			name = n as string
			if m := option['message'] {
				if m is string {
					message = m
				}
			}
			if s := option['suggest'] {
				if s is string {
					suggest = s
				}
			}
		} else {
			return error('an option of `${vue_no_restricted_component_names}` must be a string or an object')
		}
		is_regexp := vue_is_regexp(name)
		out << VrcnOption{
			is_regexp: is_regexp
			regexp:    if is_regexp { vue_to_regexp(name, '', 'g')! } else { jsregexp.JsRegex{} }
			name:      name
			message:   message
			suggest:   suggest
		}
	}
	return out
}

fn (o &VrcnOption) test(name string) bool {
	if o.is_regexp {
		return vue_regexp_test(&o.regexp, name)
	}
	return name == vue_pascal_case(o.name) || name == vue_kebab_case(o.name)
}

fn (mut c Checker) lint_vue_no_restricted_component_names(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := vue_no_restricted_component_names_options(c.rule_options(vue_no_restricted_component_names))!
	mut findings := []Finding{}
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
		c.vrcn_verify(t, obj, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vrcn_verify(t &estree.EsTree, object int, options []VrcnOption, mut findings []Finding) {
	property := vue_find_property(t, object, 'name', none)
	if property < 0 {
		return
	}
	value := vue_property_value(t, property)
	if (vue_static_property_name(t, property) or { '' }) != 'name' || t.typ(value) != .literal {
		return
	}
	// `property.value.value?.toString()`: nothing for null.
	if t.get(value, .value) is estree.Null {
		return
	}
	name := vue_literal_string(t, value)
	if name == '' {
		return
	}
	for option in options {
		if !option.test(name) {
			continue
		}
		mut suggestions := []Suggestion{}
		if option.suggest != '' {
			suggestions << Suggestion{
				message_id: 'suggest'
				data:       {
					'suggest': option.suggest
				}
				fix:        fix_replace_range(t.nodes[value].start, t.nodes[value].end,
					js_json_stringify(json2.Any(option.suggest)))
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, value)
			message_id:  'disallow'
			data:        {
				'message': if option.message != '' {
					option.message
				} else {
					'Using component name `${name}` is not allowed.'
				}
			}
			suggestions: suggestions
		}
	}
}
