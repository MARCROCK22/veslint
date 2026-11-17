module rules

import json2
import time

// Port of the `vue/valid-v-on` rule of eslint-plugin-vue 10.12.1 (option `modifiers`: more modifier
// names to accept): each modifier of a `v-on` that is not a known one, a number for parseInt, a
// single character or a key alias; and a `v-on` without an expression and without a verb modifier
// (stop, prevent), as a JavaScript keyword when its value is one word, else as a missing value.

const vvon_messages = {
	'unsupportedModifier': "'v-on' directives don't support the modifier '{{modifier}}'."
	'avoidKeyword':        'Avoid using JavaScript keyword as "v-on" value: {{value}}.'
	'expectedValueOrVerb': "'v-on' directives require a value or verb modifier (like 'stop' or 'prevent')."
}

const vvon_valid_modifiers = ['stop', 'prevent', 'capture', 'self', 'ctrl', 'shift', 'alt', 'meta',
	'native', 'once', 'left', 'right', 'middle', 'passive', 'esc', 'tab', 'enter', 'space', 'up',
	'down', 'delete', 'exact']

fn vvon_options(options []json2.Any) ![]string {
	o := option_object(vue_valid_v_on, options, ['modifiers'])!
	if 'modifiers' !in o.values {
		return []
	}
	return o.string_list('modifiers')!
}

// vvon_parse_int_is_safe is Number.isSafeInteger(Number.parseInt(text, 10)): the leading white
// space skipped, a sign, and at least one decimal digit, whose value is a safe integer.
fn vvon_parse_int_is_safe(text string) bool {
	runes := text.runes()
	mut i := 0
	for i < runes.len && is_js_space(runes[i]) {
		i++
	}
	if i < runes.len && (runes[i] == `+` || runes[i] == `-`) {
		i++
	}
	start := i
	for i < runes.len && runes[i] >= `0` && runes[i] <= `9` {
		i++
	}
	if i == start {
		return false
	}
	digits := runes[start..i].string().trim_left('0')
	// 2^53 - 1 = 9007199254740991 (16 digits).
	return digits.len < 16 || (digits.len == 16 && digits <= '9007199254740991')
}

// vvon_is_word is /^\w+$/.
fn vvon_is_word(text string) bool {
	if text == '' {
		return false
	}
	for b in text.bytes() {
		if !(b.is_letter() || b.is_digit() || b == `_`) {
			return false
		}
	}
	return true
}

fn (mut c Checker) lint_vue_valid_v_on(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	custom := vvon_options(c.rule_options(vue_valid_v_on))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'on') {
			continue
		}
		stats.checked++
		modifiers := c.vue_directive_modifiers(i)
		for m in modifiers {
			name := c.vue.doc.nodes[m].name
			if name in vvon_valid_modifiers || vvon_parse_int_is_safe(name) || name.runes().len == 1
				|| name in vue_key_aliases || name in custom {
				continue
			}
			findings << c.vue_report_vnode(m, 'unsupportedModifier', {
				'modifier': name
			})
		}
		value := c.vue.doc.nodes[i].value
		if (value >= 0 && !c.vue_container_expression(value).is_null())
			|| modifiers.any(c.vue.doc.nodes[it].name in ['stop', 'prevent']) {
			continue
		}
		if value >= 0 && !c.vue_is_empty_value_directive(i) {
			value_text := c.vue_vnode_text(value)
			quoted := value_text.len >= 1 && (value_text[0] == `"` || value_text[0] == `'`)
				&& value_text[0] == value_text[value_text.len - 1]
			inner := if quoted {
				if value_text.len >= 2 { value_text[1..value_text.len - 1] } else { '' }
			} else {
				value_text
			}
			if vvon_is_word(inner) {
				findings << c.vue_report_vnode(value, 'avoidKeyword', {
					'value': value_text
				})
			}
		} else {
			findings << c.vue_report_vnode(i, 'expectedValueOrVerb', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
