module rules

import json2
import time

// Port of the `vue/mustache-interpolation-spacing` rule of eslint-plugin-vue 10.12.1 (option
// "always", the default, or "never"): the space after `{{` and before `}}` of a mustache with an
// expression (the next and previous tokens, comments included), fixed.

const vmis_messages = {
	'expectedSpaceAfter':    "Expected 1 space after '{{', but not found."
	'expectedSpaceBefore':   "Expected 1 space before '}}', but not found."
	'unexpectedSpaceAfter':  "Expected no space after '{{', but found."
	'unexpectedSpaceBefore': "Expected no space before '}}', but found."
}

fn vmis_options(options []json2.Any) !bool {
	if options.len == 0 {
		return true
	}
	value := options[0]
	if value !is string || value as string !in ['always', 'never'] {
		return error('the option of `${vue_mustache_interpolation_spacing}` must be "always" or "never"')
	}
	return value as string == 'always'
}

fn (mut c Checker) lint_vue_mustache_interpolation_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	always := vmis_options(c.rule_options(vue_mustache_interpolation_spacing))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_expression_container || node.expression.is_null() {
			continue
		}
		stats.checked++
		open := c.vue_first_token_in(node.start, node.end) or { continue }
		close := c.vue_last_token_in(node.start, node.end) or { continue }
		if open.typ != 'VExpressionStart' || close.typ != 'VExpressionEnd' {
			continue
		}
		first := c.vue_token_after(open.end, true) or { continue }
		last := c.vue_token_before(close.start, true) or { continue }
		if always {
			if open.end == first.start {
				findings << c.with_fixes(c.vue_report(open.start, open.end, 'expectedSpaceAfter',
					{}), [fix_insert_at(open.end, ' ')])!
			}
			if close.start == last.end {
				findings << c.with_fixes(c.vue_report(close.start, close.end, 'expectedSpaceBefore',
					{}), [fix_insert_at(close.start, ' ')])!
			}
		} else {
			if open.end != first.start {
				findings << c.with_fixes(c.vue_report(open.start, first.start, 'unexpectedSpaceAfter',
					{}), [fix_remove_range(open.end, first.start)])!
			}
			if close.start != last.end {
				findings << c.with_fixes(c.vue_report(last.end, close.end, 'unexpectedSpaceBefore',
					{}), [fix_remove_range(last.end, close.start)])!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
