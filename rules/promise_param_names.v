module rules

import json2
import jsregexp
import time

// Port of the `promise/param-names` rule of eslint-plugin-promise 7.3.0, with its options.

const prm_param_names_messages = {
	'resolveParamNames': 'Promise constructor parameters must be named to match "{{ resolvePattern }}"'
	'rejectParamNames':  'Promise constructor parameters must be named to match "{{ rejectPattern }}"'
}

// prm_param_names_options are `new RegExp(options.resolvePattern || '^_?resolve$', 'u')` and the
// same for rejectPattern; a pattern that is not a regular expression makes the rule throw.
struct PrmParamNames {
	resolve        jsregexp.JsRegex
	resolve_source string
	reject         jsregexp.JsRegex
	reject_source  string
}

fn prm_param_names_options(options []json2.Any) !PrmParamNames {
	o := option_object(promise_param_names, options, ['resolvePattern', 'rejectPattern'])!
	mut resolve := o.values['resolvePattern'] or { json2.Any('') }.str()
	mut reject := o.values['rejectPattern'] or { json2.Any('') }.str()
	if resolve == '' {
		resolve = '^_?resolve$'
	}
	if reject == '' {
		reject = '^_?reject$'
	}
	resolve_re := jsregexp.js_regex_new(resolve, 'u')!
	reject_re := jsregexp.js_regex_new(reject, 'u')!
	resolve_value := jsregexp.regexp_new(utf16_units(resolve), 'u') or {
		return error('Invalid regular expression: /${resolve}/u')
	}
	reject_value := jsregexp.regexp_new(utf16_units(reject), 'u') or {
		return error('Invalid regular expression: /${reject}/u')
	}
	return PrmParamNames{
		resolve:        resolve_re
		resolve_source: stv_units_string(resolve_value.source)
		reject:         reject_re
		reject_source:  stv_units_string(reject_value.source)
	}
}

fn (mut c Checker) lint_promise_param_names(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := prm_param_names_options(c.rule_options(promise_param_names))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		if !prm_is_promise_constructor_with_inline_executor(t, node) {
			continue
		}
		args := t.list(node, .arguments) or { continue }
		params := t.list(args[0], .params) or { continue }
		if params.len == 0 {
			continue
		}
		resolve_name := prm_name(t, params[0])
		if resolve_name != '' && !o.resolve.test(utf16_units(resolve_name))! {
			findings << Finding{
				stmt:       c.es_tree_position(t, params[0])
				message_id: 'resolveParamNames'
				data:       {
					'resolvePattern': o.resolve_source
				}
			}
		}
		reject_name := if params.len > 1 { prm_name(t, params[1]) } else { '' }
		if reject_name != '' && !o.reject.test(utf16_units(reject_name))! {
			findings << Finding{
				stmt:       c.es_tree_position(t, params[1])
				message_id: 'rejectParamNames'
				data:       {
					'rejectPattern': o.reject_source
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
