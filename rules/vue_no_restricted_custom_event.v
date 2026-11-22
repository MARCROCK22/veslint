module rules

import estree
import jsregexp
import json2
import time

// Port of the `vue/no-restricted-custom-event` rule of eslint-plugin-vue 10.12.1 (options: event
// names or /regexps/, or {event, message, suggest}): in a .vue file, an emitted event (the calls
// of vue_emit_calls_of_script without defineEmits, and `$emit` of the template) whose string name
// the first matching option restricts, with its message and a suggestion of its `suggest` name.

const vue_no_restricted_custom_event_messages = {
	'restrictedEvent': '{{message}}'
	'instead':         'Instead, change to `{{suggest}}`.'
}

struct VnrceOption {
	test        jsregexp.JsRegex
	message     string
	suggest     string
	has_suggest bool
}

fn vnrce_options(options []json2.Any) ![]VnrceOption {
	mut out := []VnrceOption{}
	for option in options {
		if option is string {
			out << VnrceOption{
				test: vue_to_regexp(option, '', 'g')!
			}
			continue
		}
		o := option_object(vue_no_restricted_custom_event, [option], ['event', 'message', 'suggest'])!
		event := o.values['event'] or { return error('`${vue_no_restricted_custom_event}` needs an event') }
		if event !is string {
			return error('the event of `${vue_no_restricted_custom_event}` must be a text')
		}
		suggest := o.values['suggest'] or { json2.Any(json2.null) }
		out << VnrceOption{
			test:        vue_to_regexp(event as string, '', 'g')!
			message:     if m := o.values['message'] { m.str() } else { '' }
			suggest:     if suggest is string { suggest } else { '' }
			has_suggest: suggest is string && suggest != ''
		}
	}
	return out
}

fn (mut c Checker) lint_vue_no_restricted_custom_event(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	// defineTemplateBodyVisitor gives no listener, not even the script's, outside a .vue file.
	if !c.is_vue() {
		return []
	}
	options := vnrce_options(c.rule_options(vue_no_restricted_custom_event))!
	if options.len == 0 {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		calls, _ := c.vue_emit_calls_of_script(root, t, s, false)
		for call in calls {
			c.vnrce_verify(t, call, options, mut findings)!
		}
	}
	for call in c.vue_template_calls() {
		es := &c.vue.doc.snippets[call.snippet].es
		callee := es.node(call.node, .callee) or { continue }
		if vue_identifier_name(es, callee) == r'$emit' {
			c.vnrce_verify(es, call.node, options, mut findings)!
		}
	}
	stats.checked += findings.len
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnrce_verify is the rule's verify on the name a call emits: the report of the first option
// that matches it.
fn (c &Checker) vnrce_verify(t &estree.EsTree, call int, options []VnrceOption, mut findings []Finding) ! {
	name, node := vue_name_param(t, call) or { return }
	for option in options {
		if !vue_regexp_test(&option.test, name) {
			continue
		}
		start := t.nodes[node].start
		end := t.nodes[node].end
		mut finding := c.vue_report(start, end, 'restrictedEvent', {
			'message': if option.message != '' {
				option.message
			} else {
				'Using `${name}` event is not allowed.'
			}
		})
		if option.has_suggest {
			quoted := js_json_quote(option.suggest)
			text := c.src[start..start + 1] + quoted[1..quoted.len - 1].replace("'", "\\'") +
				c.src[end - 1..end]
			ok, suggestion := c.suggestion('instead', {
				'suggest': option.suggest
			}, [fix_replace_range(start, end, text)])!
			if ok {
				finding = Finding{
					...finding
					suggestions: [suggestion]
				}
			}
		}
		findings << finding
		return
	}
}
