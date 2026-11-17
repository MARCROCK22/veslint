module rules

import time

// Port of the `vue/no-deprecated-v-on-number-modifiers` rule of eslint-plugin-vue 10.12.1 (no
// options): the first modifier of a `v-on` that is a safe integer for Number() (`.13`, `.0x0d`),
// unless it is 0 to 9, fixed to the name of its key (keycode-to-key.ts) when it has one.

const vndvonum_messages = {
	'numberModifierIsDeprecated': "'KeyboardEvent.keyCode' modifier on 'v-on' directive is deprecated. Using 'KeyboardEvent.key' instead."
}

// vndvonum_safe_integer is Number.isSafeInteger(Number(text)).
fn vndvonum_safe_integer(text string) ?i64 {
	n := js_string_to_number(text)
	if n != n || n > 9007199254740991.0 || n < -9007199254740991.0 || n != f64(i64(n)) {
		return none
	}
	return i64(n)
}

fn (mut c Checker) lint_vue_no_deprecated_v_on_number_modifiers(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VAttribute[directive=true][key.name.name='on'] > VDirectiveKey`
		if !c.vue_is_directive(i, 'on') {
			continue
		}
		stats.checked++
		mut modifier := -1
		mut code := i64(0)
		for m in c.vue_directive_modifiers(i) {
			if n := vndvonum_safe_integer(c.vue.doc.nodes[m].name) {
				modifier = m
				code = n
				break
			}
		}
		if modifier < 0 || (code <= 9 && code >= 0) {
			continue
		}
		report := c.vue_report_vnode(modifier, 'numberModifierIsDeprecated', {})
		// keycode-to-key.ts has small codes only (and no 48 to 57: no fix for the digits).
		if code >= 1000 || int(code) !in vue_keycode_keys {
			findings << report
			continue
		}
		key := vue_keycode_keys[int(code)]
		m := &c.vue.doc.nodes[modifier]
		findings << c.with_fixes(report, [fix_replace_range(m.start, m.end, key)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
