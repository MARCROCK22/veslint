module rules

import estree
import json2
import time

// Port of the `vue/new-line-between-multi-line-property` rule of eslint-plugin-vue 10.12.1
// (option `minLineOfMultilineProperty`, 2 by default): in an object of a Vue object that is not
// inside a call, a property of that many lines or more with no empty line after it before the
// next property, with the fix that adds one.

const vue_new_line_between_multi_line_property_messages = {
	'missingEmptyLine': 'Enforce new lines between multi-line properties in Vue components.'
}

fn vue_new_line_between_multi_line_property_options(options []json2.Any) !f64 {
	o := option_object(vue_new_line_between_multi_line_property, options, ['minLineOfMultilineProperty'])!
	value := o.values['minLineOfMultilineProperty'] or { return 2 }
	n := json_number(value)
	return if n != 0 { n } else { 2 }
}

fn (mut c Checker) lint_vue_new_line_between_multi_line_property(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	min_lines := vue_new_line_between_multi_line_property_options(c.rule_options(vue_new_line_between_multi_line_property))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .object_expression || s.owner_of(node) < 0 {
			continue
		}
		// The CallExpression listener pushes the calls inside a Vue object.
		mut in_call := false
		mut p := t.nodes[node].parent
		for p >= 0 {
			if t.typ(p) == .call_expression && s.owner_of(p) >= 0 {
				in_call = true
				break
			}
			p = t.nodes[p].parent
		}
		if in_call {
			continue
		}
		stats.checked++
		properties := t.list(node, .properties) or { []int{} }
		for i in 1 .. properties.len {
			cur := properties[i]
			pre := properties[i - 1]
			pre_start_line, _ := t.line_column(t.nodes[pre].start)
			pre_end_line, _ := t.line_column(t.nodes[pre].end)
			if f64(pre_end_line - pre_start_line + 1) < min_lines {
				continue
			}
			between := vnlbmlp_between_tokens(t, tokens, pre, cur)
			mut has_empty_line := false
			for k in 1 .. between.len {
				prev_end, _ := t.line_column(between[k - 1].end)
				start, _ := t.line_column(between[k].start)
				if start - prev_end >= 2 {
					has_empty_line = true
					break
				}
			}
			if has_empty_line {
				continue
			}
			mut fix := Fix{}
			mut found := false
			for k in 1 .. between.len {
				prev_end, _ := t.line_column(between[k - 1].end)
				start, _ := t.line_column(between[k].start)
				if prev_end < start {
					fix = fix_insert_at(between[k - 1].end, '\n')
					found = true
					break
				}
			}
			if !found {
				mut after := t.nodes[pre].end
				for token in tokens.tokens {
					if token.start >= t.nodes[pre].end && c.src[token.start..token.end] == ',' {
						after = token.end
						break
					}
				}
				fix = fix_insert_at(after, '\n\n')
			}
			findings << c.with_fixes(Finding{
				stmt:       c.position_range(t.nodes[pre].end, t.nodes[cur].start)
				message_id: 'missingEmptyLine'
			}, [fix])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnlbmlp_between_tokens is iterateBetweenTokens: the last token of `pre`, the tokens and
// comments between the two nodes, and the first token of `cur`.
fn vnlbmlp_between_tokens(t &estree.EsTree, tokens &SourceTokens, pre int, cur int) []SourceToken {
	mut out := []SourceToken{}
	if last := tokens.before(t.nodes[pre].end, false) {
		out << last
	}
	out << tokens.inside(t.nodes[pre].end, t.nodes[cur].start, true)
	if first := tokens.after(t.nodes[cur].start, false) {
		out << first
	}
	return out
}
