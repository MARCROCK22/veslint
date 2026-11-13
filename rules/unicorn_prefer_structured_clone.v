module rules

import estree
import json2
import time

// Port of the `unicorn/prefer-structured-clone` rule of eslint-plugin-unicorn 64.0.0, with its
// suggestions.

const upsc_messages = {
	'prefer-structured-clone/error':      'Prefer `structuredClone(…)` over `{{description}}` to create a deep clone.'
	'prefer-structured-clone/suggestion': 'Switch to `structuredClone(…)`.'
}

fn upsc_options(options []json2.Any) ![]string {
	o := option_object(unicorn_prefer_structured_clone, options, ['functions'])!
	list := o.values['functions'] or { return []string{} }
	if list is []json2.Any {
		return list.map(it.str())
	}
	return []string{}
}

fn (mut c Checker) lint_unicorn_prefer_structured_clone(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut functions := upsc_options(c.rule_options(unicorn_prefer_structured_clone))!
	functions << ['_.cloneDeep', 'lodash.cloneDeep']
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		// `JSON.parse(JSON.stringify(…))`
		if un_is_method_call(t, node,
			objects:          ['JSON']
			methods:          ['parse']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) {
			stringify := (t.list(node, .arguments) or { []int{} })[0]
			if un_is_method_call(t, stringify,
				objects:          ['JSON']
				methods:          ['stringify']
				arguments_length: 1
				optional_call:    false
				optional_member:  false
			) {
				_, fix := c.merge_fixes(c.upsc_json_fix(t, tokens, node, stringify))!
				stringify_callee := t.node(stringify, .callee) or { continue }
				findings << Finding{
					stmt:        c.position_range(t.nodes[node].start, t.nodes[stringify_callee].end)
					message_id:  'prefer-structured-clone/error'
					data:        {
						'description': 'JSON.parse(JSON.stringify(…))'
					}
					suggestions: [
						Suggestion{
							message_id: 'prefer-structured-clone/suggestion'
							fix:        fix
						},
					]
				}
			}
		}
		// `_.cloneDeep(foo)`
		if !un_is_call(t, node, arguments_length: 1, optional: false) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		for function in functions {
			if !un_node_matches_name_or_path(t, callee, function) {
				continue
			}
			findings << Finding{
				stmt:        c.es_tree_position(t, callee)
				message_id:  'prefer-structured-clone/error'
				data:        {
					'description': '${function.trim_space()}(…)'
				}
				suggestions: [
					Suggestion{
						message_id: 'prefer-structured-clone/suggestion'
						fix:        fix_replace_range(t.nodes[callee].start, t.nodes[callee].end,
							'structuredClone')
					},
				]
			}
			break
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) upsc_json_fix(t &estree.EsTree, tokens &SourceTokens, parse int, stringify int) []Fix {
	parse_callee := t.node(parse, .callee) or { return [] }
	stringify_callee := t.node(stringify, .callee) or { return [] }
	mut fixes := [
		fix_replace_range(t.nodes[parse_callee].start, t.nodes[parse_callee].end, 'structuredClone'),
		fix_remove_range(t.nodes[stringify_callee].start, t.nodes[stringify_callee].end),
	]
	fixes << c.un_remove_parentheses(t, tokens, stringify_callee)
	call := c.un_call_tokens(t, tokens, stringify) or { return fixes }
	fixes << fix_remove_range(call.opening.start, call.opening.end)
	fixes << fix_remove_range(call.closing.start, call.closing.end)
	if trailing := call.trailing {
		fixes << fix_remove_range(trailing.start, trailing.end)
	}
	return fixes
}
