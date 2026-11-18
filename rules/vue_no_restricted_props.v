module rules

import estree
import json2
import jsregexp
import time

// Port of the `vue/no-restricted-props` rule of eslint-plugin-vue 10.12.1 (options: prop names
// or `{name, message, suggest}`; a `/…/` name is a regular expression): a restricted prop of the
// options or of defineProps, with a suggestion to rename it (and its withDefaults and destructure
// keys) when `suggest` is given.

const vue_no_restricted_props_messages = {
	'restrictedProp': '{{message}}'
	'instead':        'Instead, change to `{{suggest}}`.'
}

struct VnrpOption {
	regexp      jsregexp.JsRegex
	message     string
	suggest     string
	has_suggest bool
}

fn vue_no_restricted_props_options(options []json2.Any) ![]VnrpOption {
	mut out := []VnrpOption{}
	for option in options {
		if option is string {
			out << VnrpOption{
				regexp: vue_to_regexp(option, '', 'g')!
			}
			continue
		}
		if option !is map[string]json2.Any {
			return error('an option of `${vue_no_restricted_props}` must be a string or an object')
		}
		o := option as map[string]json2.Any
		for key, _ in o {
			if key !in ['name', 'message', 'suggest'] {
				return error('unknown property `${key}` in an option of `${vue_no_restricted_props}`')
			}
		}
		name := o['name'] or { return error('an option of `${vue_no_restricted_props}` must have `name`') }
		if name !is string {
			return error('`name` of `${vue_no_restricted_props}` must be a string')
		}
		mut parsed := VnrpOption{
			regexp: vue_to_regexp(name as string, '', 'g')!
		}
		if m := o['message'] {
			if m !is string || (m as string) == '' {
				return error('`message` of `${vue_no_restricted_props}` must be a non-empty string')
			}
			parsed = VnrpOption{
				...parsed
				message: m as string
			}
		}
		if sg := o['suggest'] {
			if sg !is string {
				return error('`suggest` of `${vue_no_restricted_props}` must be a string')
			}
			parsed = VnrpOption{
				...parsed
				suggest:     sg as string
				has_suggest: true
			}
		}
		out << parsed
	}
	return out
}

fn (mut c Checker) lint_vue_no_restricted_props(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := vue_no_restricted_props_options(c.rule_options(vue_no_restricted_props))!
	mut findings := []Finding{}
	if options.len == 0 {
		return findings
	}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for call in c.vue_macros_named(t, 'defineProps') {
		props := c.vue_define_props(root, t, call, abs_path, true, mut stats)
		c.vnrp_process(t, props, call, options, mut findings, mut stats)!
	}
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .object_expression
			|| s.object_type(step.node) == .none_ {
			continue
		}
		c.vnrp_process(t, vue_props_from_options(t, step.node), -1, options, mut findings, mut
			stats)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnrp_process is processProps; `call` is the defineProps call (-1 for the options), whose
// withDefaults and destructure keys the suggestion renames too.
fn (mut c Checker) vnrp_process(t &estree.EsTree, props []VueProp, call int, options []VnrpOption, mut findings []Finding, mut stats Stats) ! {
	for prop in props {
		stats.checked++
		if !prop.has_name || prop.name == '' {
			continue
		}
		mut option := VnrpOption{}
		mut found := false
		for o in options {
			if vue_regexp_test(&o.regexp, prop.name) {
				option = o
				found = true
				break
			}
		}
		if !found {
			continue
		}
		message := if option.message != '' {
			option.message
		} else {
			'Using `${prop.name}` props is not allowed.'
		}
		report_node := if prop.kind == .infer_type { prop.node } else { prop.key }
		mut suggestions := []Suggestion{}
		if prop.kind != .infer_type && option.has_suggest && option.suggest != '' {
			key := prop.key
			mut replace := ''
			if t.typ(key) in [.literal, .template_literal] {
				replace = js_json_stringify(json2.Any(option.suggest))
			} else if t.typ(key) == .identifier {
				replace = if vnrp_is_simple_name(option.suggest) {
					option.suggest
				} else {
					js_json_stringify(json2.Any(option.suggest))
				}
			}
			if replace != '' {
				mut fixes := [fix_replace_range(t.nodes[key].start, t.nodes[key].end, replace)]
				if call >= 0 {
					mut nodes := []int{}
					if p := vx6_with_defaults_props(t, call)[prop.name] {
						nodes << p
					}
					if p := vx6_props_destructure(t, call)[prop.name] {
						nodes << p
					}
					for p in nodes {
						if t.flag(p, .shorthand) or { false } {
							value := t.node(p, .value) or { continue }
							fixes << fix_insert_at(t.nodes[value].start, '${replace}:')
						} else {
							k := t.node(p, .key) or { continue }
							fixes << fix_replace_range(t.nodes[k].start, t.nodes[k].end, replace)
						}
					}
				}
				fixes.sort(a.start < b.start)
				ok, suggestion := c.suggestion('instead', {
					'suggest': option.suggest
				}, fixes)!
				if ok {
					suggestions << suggestion
				}
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, report_node)
			message_id:  'restrictedProp'
			data:        {
				'message': message
			}
			suggestions: suggestions
		}
	}
}

// vnrp_is_simple_name is /^[a-z]\w*$/iu.
fn vnrp_is_simple_name(s string) bool {
	if s == '' || !s[0].is_letter() {
		return false
	}
	for b in s.bytes() {
		if !(b.is_letter() || b.is_digit() || b == `_`) {
			return false
		}
	}
	return true
}
