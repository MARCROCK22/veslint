module rules

import json2
import jsregexp
import time

// Ports of the `vue/no-restricted-v-bind` and `vue/no-restricted-v-on` rules of eslint-plugin-vue
// 10.12.1 (options: each an argument (a name or a regular expression as a string), null (no
// argument), or an object with `argument`, `modifiers` (all present), `element` and `message`):
// the key of a `v-bind` / `v-on` the first matching option restricts. no-restricted-v-bind
// restricts `:v-xxx` without options; no-restricted-v-on nothing.

const vnrvb_messages = {
	'restrictedVBind': '{{message}}'
}

const vnrvo_messages = {
	'restrictedVOn': '{{message}}'
}

struct VnrvOption {
	any_argument  bool // `argument: null`: the key has no argument
	argument      jsregexp.JsRegex
	has_modifiers bool
	modifiers     []string
	use_element   bool
	element       jsregexp.JsRegex
	message       string
}

fn vnrv_options(rule string, options []json2.Any) ![]VnrvOption {
	mut out := []VnrvOption{}
	for option in options {
		out << vnrv_option(rule, option)!
	}
	return out
}

// vnrv_option is parseOption.
fn vnrv_option(rule string, option json2.Any) !VnrvOption {
	if option is string {
		return VnrvOption{
			argument: vue_to_regexp(option, '', 'g')!
		}
	}
	if option is json2.Null {
		return VnrvOption{
			any_argument: true
		}
	}
	if option !is map[string]json2.Any {
		return error('an option of `${rule}` must be a string, null or an object')
	}
	o := option_object(rule, [option], ['argument', 'modifiers', 'element', 'message'])!
	argument := o.values['argument'] or { return error('an option of `${rule}` needs `argument`') }
	mut parsed := vnrv_option(rule, argument)!
	if 'modifiers' in o.values {
		parsed = VnrvOption{
			...parsed
			has_modifiers: true
			modifiers:     o.string_list('modifiers')!
		}
	}
	element := o.values['element'] or { json2.Any('') }
	if element is string && element != '' {
		parsed = VnrvOption{
			...parsed
			use_element: true
			element:     vue_to_regexp(element, '', 'g')!
		}
	}
	message := o.values['message'] or { json2.Any('') }
	return VnrvOption{
		...parsed
		message: if message is string { message } else { '' }
	}
}

fn vnrvb_options(options []json2.Any) ![]VnrvOption {
	return vnrv_options(vue_no_restricted_v_bind, options)
}

fn vnrvo_options(options []json2.Any) ![]VnrvOption {
	return vnrv_options(vue_no_restricted_v_on, options)
}

fn (c &Checker) vnrv_test(option &VnrvOption, attr int) bool {
	argument := c.vue_directive_argument(attr)
	if option.any_argument {
		if argument >= 0 {
			return false
		}
	} else if argument < 0 || c.vue.doc.nodes[argument].typ != .v_identifier
		|| !vue_regexp_test(option.argument, c.vue.doc.nodes[argument].raw_name) {
		return false
	}
	if option.has_modifiers {
		modifier_names := c.vue_directive_modifiers(attr).map(c.vue.doc.nodes[it].name)
		if !option.modifiers.all(it in modifier_names) {
			return false
		}
	}
	if option.use_element
		&& !vue_regexp_test(option.element, c.vue.doc.nodes[c.vue_attribute_element(attr)].raw_name) {
		return false
	}
	return true
}

// vnrv_lint reports the keys of the directives `directive` (bind or on).
fn (mut c Checker) vnrv_lint(directive string, options []VnrvOption, message_id string, mut stats Stats) []Finding {
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, directive) {
			continue
		}
		stats.checked++
		for option in options {
			if !c.vnrv_test(option, i) {
				continue
			}
			message := if option.message != '' {
				option.message
			} else if directive == 'bind' {
				c.vnrvb_default_message(i, option)
			} else {
				c.vnrvo_default_message(i, option)
			}
			findings << c.vue_report_vnode(c.vue.doc.nodes[i].key, message_id, {
				'message': message
			})
			break
		}
	}
	return findings
}

// vnrvb_default_message is no-restricted-v-bind's defaultMessage.
fn (c &Checker) vnrvb_default_message(attr int, option &VnrvOption) string {
	key := &c.vue.doc.nodes[c.vue.doc.nodes[attr].key]
	vbind := if c.vue.doc.nodes[key.dir_name].raw_name == ':' { '' } else { 'v-bind' }
	arg := if key.argument >= 0 && c.vue.doc.nodes[key.argument].typ == .v_identifier {
		':${c.vue.doc.nodes[key.argument].raw_name}'
	} else {
		''
	}
	mod := if option.modifiers.len > 0 { '.${option.modifiers.join('.')}' } else { '' }
	on := if option.use_element {
		' on `<${c.vue.doc.nodes[c.vue_attribute_element(attr)].raw_name}>`'
	} else {
		''
	}
	return 'Using `${vbind}${arg}${mod}`${on} is not allowed.'
}

// vnrvo_default_message is no-restricted-v-on's defaultMessage.
fn (c &Checker) vnrvo_default_message(attr int, option &VnrvOption) string {
	key := &c.vue.doc.nodes[c.vue.doc.nodes[attr].key]
	at := c.vue.doc.nodes[key.dir_name].raw_name == '@'
	von := if at { '' } else { 'v-on' }
	arg := if key.argument >= 0 && c.vue.doc.nodes[key.argument].typ == .v_identifier {
		'${if at { '@' } else { ':' }}${c.vue.doc.nodes[key.argument].raw_name}'
	} else {
		''
	}
	mod := if option.modifiers.len > 0 { '.${option.modifiers.join('.')}' } else { '' }
	element := if option.use_element {
		'<${c.vue.doc.nodes[c.vue_attribute_element(attr)].raw_name}>'
	} else {
		'element'
	}
	return 'Using `${von}${arg}${mod}` is not allowed on this ${element}.'
}

fn (mut c Checker) lint_vue_no_restricted_v_bind(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut options := vnrvb_options(c.rule_options(vue_no_restricted_v_bind))!
	if options.len == 0 {
		options = [
			VnrvOption{
				argument: vue_to_regexp('/^v-/', '', 'g')!
				message:  'Using `:v-xxx` is not allowed. Instead, remove `:` and use it as directive.'
			},
		]
	}
	findings := c.vnrv_lint('bind', options, 'restrictedVBind', mut stats)
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_no_restricted_v_on(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	options := vnrvo_options(c.rule_options(vue_no_restricted_v_on))!
	if options.len == 0 {
		return []
	}
	sw := time.new_stopwatch()
	findings := c.vnrv_lint('on', options, 'restrictedVOn', mut stats)
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
