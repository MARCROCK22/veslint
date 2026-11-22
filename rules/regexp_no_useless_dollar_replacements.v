module rules

import time

// Port of the `regexp/no-useless-dollar-replacements` rule of eslint-plugin-regexp 3.3.3 (it has no
// options): a `$n` or `$<name>` of the replacement string literal of `replace` or `replaceAll` (of a
// string, by TypeScript's type of the object) that refers to a capturing group the regular
// expression (a literal or a static RegExp) does not have.

const regexp_no_useless_dollar_replacements_messages = {
	'numberRef':                      "'\${{ refText }}' replacement will insert '\${{ refText }}' because there are less than {{ num }} capturing groups. Use '\$\$' if you want to escape '\$'."
	'numberRefCapturingNotFound':     "'\${{ refText }}' replacement will insert '\${{ refText }}' because capturing group is not found. Use '\$\$' if you want to escape '\$'."
	'namedRef':                       "'\$<{{ refText }}>' replacement will be ignored because the named capturing group is not found. Use '\$\$' if you want to escape '\$'."
	'namedRefNamedCapturingNotFound': "'\$<{{ refText }}>' replacement will insert '\$<{{ refText }}>' because named capturing group is not found. Use '\$\$' if you want to escape '\$'."
}

fn (mut c Checker) lint_regexp_no_useless_dollar_replacements(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	methods := {
		'replace':    2
		'replaceAll': 2
	}
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .call_expression || !rx_is_known_method_call(t, node, methods) {
			continue
		}
		stats.checked++
		args := t.list(node, .arguments) or { continue }
		replacement := args[1]
		if !rx_is_string_literal(t, replacement) {
			continue
		}
		pattern := c.rx_regexp_node_from_expression(root, t, args[0]) or { continue }
		object := t.node(t.node(node, .callee) or { continue }, .object) or { continue }
		if !c.rx_is_string(root, t, abs_path, object) {
			continue
		}
		count := rx_capturing_groups(&pattern).len
		group_names := rx_capturing_group_names(&pattern)
		for element in c.rx_parse_replacements(t, replacement) {
			if element.kind != .reference {
				continue
			}
			mut message_id := ''
			mut data := map[string]string{}
			if element.ref_is_num {
				if count >= element.ref_num {
					continue
				}
				message_id = if count > 0 { 'numberRef' } else { 'numberRefCapturingNotFound' }
				data = {
					'refText': element.ref_text
					'num':     '${element.ref_num}'
				}
			} else {
				if element.ref_name in group_names {
					continue
				}
				message_id = if group_names.len > 0 {
					'namedRef'
				} else {
					'namedRefNamedCapturingNotFound'
				}
				data = {
					'refText': element.ref_text
				}
			}
			findings << Finding{
				stmt:       c.position_range(element.start, element.end)
				message_id: message_id
				data:       data
				text_loc:   true
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
