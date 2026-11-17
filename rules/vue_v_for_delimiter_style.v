module rules

import json2
import vue
import time

// Port of the `vue/v-for-delimiter-style` rule of eslint-plugin-vue 10.12.1 (option "in", the
// default, or "of"): a VForExpression whose delimiter (the first token after its last alias that is
// not a punctuator) is the other one, fixed by replacing it.

const vvfds_messages = {
	'expected': "Expected '{{preferredDelimiter}}' instead of '{{usedDelimiter}}' in 'v-for'."
}

fn vvfds_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'in'
	}
	value := options[0]
	if value !is string || value as string !in ['in', 'of'] {
		return error('the option of `${vue_v_for_delimiter_style}` must be "in" or "of"')
	}
	return value as string
}

fn (mut c Checker) lint_vue_v_for_delimiter_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	preferred := vvfds_options(c.rule_options(vue_v_for_delimiter_style))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_for_expression {
			continue
		}
		stats.checked++
		// getTokenAfter(node.left.at(-1) ?? getFirstToken(node), not a Punctuator)
		mut after := -1
		if node.exprs.len > 0 && !node.exprs[node.exprs.len - 1].is_null() {
			_, after = c.vue_expr_range(node.exprs[node.exprs.len - 1])
		} else {
			start, end := c.vue_vnode_range(i)
			first := c.vue_first_token_in(start, end) or { continue }
			after = first.end
		}
		delimiter := c.vue_token_after_where(after, fn (t vue.Token) bool {
			return t.typ != 'Punctuator'
		}) or { continue }
		if delimiter.value == preferred {
			continue
		}
		findings << c.with_fixes(c.vue_report_vnode(i, 'expected', {
			'preferredDelimiter': preferred
			'usedDelimiter':      delimiter.value
		}), [fix_replace_range(delimiter.start, delimiter.end, preferred)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
