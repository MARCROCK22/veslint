module rules

import json2
import time

// Port of the `vue/v-on-style` rule of eslint-plugin-vue 10.12.1 (option "shorthand", the default,
// or "longform"): a `v-on` with an argument written the other way, fixed by replacing its first 5
// characters (`v-on:`) with `@`, or its first one (`@`) with `v-on:`.

const vvos_messages = {
	'expectedShorthand': "Expected '@' instead of 'v-on:'."
	'expectedLonghand':  "Expected 'v-on:' instead of '@'."
}

fn vvos_options(options []json2.Any) !bool {
	if options.len == 0 {
		return true
	}
	value := options[0]
	if value !is string || value as string !in ['shorthand', 'longform'] {
		return error('the option of `${vue_v_on_style}` must be "shorthand" or "longform"')
	}
	return value as string != 'longform'
}

fn (mut c Checker) lint_vue_v_on_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	prefer_shorthand := vvos_options(c.rule_options(vue_v_on_style))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'on') || c.vue_directive_argument(i) < 0 {
			continue
		}
		stats.checked++
		key := &c.vue.doc.nodes[c.vue.doc.nodes[i].key]
		is_shorthand := c.vue.doc.nodes[key.dir_name].raw_name == '@'
		if is_shorthand == prefer_shorthand {
			continue
		}
		pos := c.vue.doc.nodes[i].start
		report := c.vue_report_vnode(i, if prefer_shorthand {
			'expectedShorthand'
		} else {
			'expectedLonghand'
		}, {})
		// replaceTextRange([pos, pos + 5]): five UTF-16 units, which `v-on:` is.
		fix := if prefer_shorthand {
			fix_replace_range(pos, pos + 5, '@')
		} else {
			fix_replace_range(pos, pos + 1, 'v-on:')
		}
		findings << c.with_fixes(report, [fix])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
