module rules

import estree
import json2
import time

// Port of the `vue/custom-event-name-casing` rule of eslint-plugin-vue 10.12.1 (options:
// "camelCase", the default, or "kebab-case"; ignores): in a .vue file, the string name of an
// emitted event (`this.$emit`/`x.$emit`, `emit` or `context.emit` of a setup's context, the
// variable of `const emit = defineEmits()`, `$emit` and that variable in the template) whose
// parts between `:` are not all in the case, unless an ignore matches it.

const vue_custom_event_name_casing_messages = {
	'unexpected': "Custom event name '{{name}}' must be {{caseType}}."
}

struct VcencOptions {
	case_type string = 'camelCase'
	ignores   VueRegexpGroup
}

fn vcenc_options(options []json2.Any) !VcencOptions {
	mut case_type := 'camelCase'
	if options.len > 0 {
		value := options[0]
		if value is string && value != '' {
			case_type = value
		}
	}
	o := option_object(vue_custom_event_name_casing, if options.len > 1 {
		options[1..].clone()
	} else {
		[]json2.Any{}
	}, ['ignores'])!
	return VcencOptions{
		case_type: case_type
		ignores:   vue_regexp_group(o.string_list('ignores')!)!
	}
}

fn (mut c Checker) lint_vue_custom_event_name_casing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	// defineTemplateBodyVisitor gives no listener, not even the script's, outside a .vue file.
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	o := vcenc_options(c.rule_options(vue_custom_event_name_casing))!
	mut findings := []Finding{}
	mut emit_param_name := ''
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		calls, name := c.vue_emit_calls_of_script(root, t, s, true)
		emit_param_name = name
		for call in calls {
			c.vcenc_verify(t, call, o, mut findings)
		}
	}
	for call in c.vue_template_calls() {
		es := &c.vue.doc.snippets[call.snippet].es
		callee := es.node(call.node, .callee) or { continue }
		name := vue_identifier_name(es, callee)
		if name != '' && (name == r'$emit' || name == emit_param_name) {
			c.vcenc_verify(es, call.node, o, mut findings)
		}
	}
	stats.checked += findings.len
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vcenc_verify is the rule's verify on the name a call emits.
fn (c &Checker) vcenc_verify(t &estree.EsTree, call int, o VcencOptions, mut findings []Finding) {
	name, node := vue_name_param(t, call) or { return }
	if name.split(':').all(vue_case_check(o.case_type, it)) || o.ignores.matches(name) {
		return
	}
	findings << c.vue_report(t.nodes[node].start, t.nodes[node].end, 'unexpected', {
		'name':     name
		'caseType': o.case_type
	})
}
