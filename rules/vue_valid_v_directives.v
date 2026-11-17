module rules

import time

// Ports of the `vue/valid-v-*` rules of eslint-plugin-vue 10.12.1 for the directives whose checks
// are the same few ones (none has options): valid-v-bind, valid-v-cloak, valid-v-html,
// valid-v-once, valid-v-pre, valid-v-text, valid-v-show, valid-v-if, valid-v-else-if, valid-v-else
// and valid-v-is. Each runs on every directive of its name, in the template's order, and makes its
// reports in the order of the original's checks.

const vvbind_messages = {
	'unsupportedModifier': "'v-bind' directives don't support the modifier '{{name}}'."
	'expectedValue':       "'v-bind' directives require an attribute value."
}

const vvcloak_messages = {
	'unexpectedArgument': "'v-cloak' directives require no argument."
	'unexpectedModifier': "'v-cloak' directives require no modifier."
	'unexpectedValue':    "'v-cloak' directives require no attribute value."
}

const vvhtml_messages = {
	'unexpectedArgument': "'v-html' directives require no argument."
	'unexpectedModifier': "'v-html' directives require no modifier."
	'expectedValue':      "'v-html' directives require that attribute value."
}

const vvonce_messages = {
	'unexpectedArgument': "'v-once' directives require no argument."
	'unexpectedModifier': "'v-once' directives require no modifier."
	'unexpectedValue':    "'v-once' directives require no attribute value."
}

const vvpre_messages = {
	'unexpectedArgument': "'v-pre' directives require no argument."
	'unexpectedModifier': "'v-pre' directives require no modifier."
	'unexpectedValue':    "'v-pre' directives require no attribute value."
}

const vvtext_messages = {
	'unexpectedArgument': "'v-text' directives require no argument."
	'unexpectedModifier': "'v-text' directives require no modifier."
	'expectedValue':      "'v-text' directives require that attribute value."
}

const vvshow_messages = {
	'unexpectedArgument': "'v-show' directives require no argument."
	'unexpectedModifier': "'v-show' directives require no modifier."
	'expectedValue':      "'v-show' directives require that attribute value."
	'unexpectedTemplate': "'v-show' directives cannot be put on <template> tags."
}

const vvif_messages = {
	'withVElse':          "'v-if' and 'v-else' directives can't exist on the same element. You may want 'v-else-if' directives."
	'withVElseIf':        "'v-if' and 'v-else-if' directives can't exist on the same element."
	'unexpectedArgument': "'v-if' directives require no argument."
	'unexpectedModifier': "'v-if' directives require no modifier."
	'expectedValue':      "'v-if' directives require that attribute value."
}

const vvelseif_messages = {
	'missingVIf':         "'v-else-if' directives require being preceded by the element which has a 'v-if' or 'v-else-if' directive."
	'withVIf':            "'v-else-if' and 'v-if' directives can't exist on the same element."
	'withVElse':          "'v-else-if' and 'v-else' directives can't exist on the same element."
	'unexpectedArgument': "'v-else-if' directives require no argument."
	'unexpectedModifier': "'v-else-if' directives require no modifier."
	'expectedValue':      "'v-else-if' directives require that attribute value."
}

const vvelse_messages = {
	'missingVIf':         "'v-else' directives require being preceded by the element which has a 'v-if' or 'v-else-if' directive."
	'withVIf':            "'v-else' and 'v-if' directives can't exist on the same element. You may want 'v-else-if' directives."
	'withVElseIf':        "'v-else' and 'v-else-if' directives can't exist on the same element."
	'unexpectedArgument': "'v-else' directives require no argument."
	'unexpectedModifier': "'v-else' directives require no modifier."
	'unexpectedValue':    "'v-else' directives require no attribute value."
}

const vvis_messages = {
	'unexpectedArgument':     "'v-is' directives require no argument."
	'unexpectedModifier':     "'v-is' directives require no modifier."
	'expectedValue':          "'v-is' directives require that attribute value."
	'ownerMustBeHTMLElement': "'v-is' directive must be owned by a native HTML element, but '{{name}}' is not."
}

// vvd_argument reports the argument of the directive (unexpectedArgument).
fn (c &Checker) vvd_argument(attr int, mut findings []Finding) {
	argument := c.vue_directive_argument(attr)
	if argument >= 0 {
		findings << c.vue_report_vnode(argument, 'unexpectedArgument', {})
	}
}

// vvd_modifiers reports the modifiers of the directive, from the start of the first to the end of
// the last (unexpectedModifier).
fn (c &Checker) vvd_modifiers(attr int, mut findings []Finding) {
	modifiers := c.vue_directive_modifiers(attr)
	if modifiers.len == 0 {
		return
	}
	start, _ := c.vue_vnode_range(modifiers[0])
	_, end := c.vue_vnode_range(modifiers[modifiers.len - 1])
	findings << c.vue_report(start, end, 'unexpectedModifier', {})
}

// vvd_no_value reports the value of the directive (unexpectedValue).
fn (c &Checker) vvd_no_value(attr int, mut findings []Finding) {
	value := c.vue.doc.nodes[attr].value
	if value >= 0 {
		findings << c.vue_report_vnode(value, 'unexpectedValue', {})
	}
}

// vvd_expected_value reports the directive when it has no value or an empty one (expectedValue).
fn (c &Checker) vvd_expected_value(attr int, mut findings []Finding) {
	if c.vue.doc.nodes[attr].value < 0 || c.vue_is_empty_value_directive(attr) {
		findings << c.vue_report_vnode(attr, 'expectedValue', {})
	}
}

// vvd_directives are the directives of the template named `name`.
fn (mut c Checker) vvd_directives(name string) []int {
	return c.vue_template_vnodes().filter(c.vue_is_directive(it, name))
}

fn (mut c Checker) lint_vue_valid_v_bind(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives('bind') {
		stats.checked++
		for m in c.vue_directive_modifiers(i) {
			name := c.vue.doc.nodes[m].name
			if name !in ['prop', 'camel', 'sync', 'attr'] {
				findings << c.vue_report_vnode(m, 'unsupportedModifier', {
					'name': name
				})
			}
		}
		c.vvd_expected_value(i, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vvd_simple is valid-v-cloak, valid-v-once and valid-v-pre (no argument, no modifier, no value)
// and valid-v-html and valid-v-text (no argument, no modifier, a value).
fn (mut c Checker) vvd_simple(name string, needs_value bool, mut stats Stats) []Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives(name) {
		stats.checked++
		c.vvd_argument(i, mut findings)
		c.vvd_modifiers(i, mut findings)
		if needs_value {
			c.vvd_expected_value(i, mut findings)
		} else {
			c.vvd_no_value(i, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_valid_v_cloak(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return if c.vue_has_template() { c.vvd_simple('cloak', false, mut stats) } else { [] }
}

fn (mut c Checker) lint_vue_valid_v_once(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return if c.vue_has_template() { c.vvd_simple('once', false, mut stats) } else { [] }
}

fn (mut c Checker) lint_vue_valid_v_pre(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return if c.vue_has_template() { c.vvd_simple('pre', false, mut stats) } else { [] }
}

fn (mut c Checker) lint_vue_valid_v_html(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return if c.vue_has_template() { c.vvd_simple('html', true, mut stats) } else { [] }
}

fn (mut c Checker) lint_vue_valid_v_text(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return if c.vue_has_template() { c.vvd_simple('text', true, mut stats) } else { [] }
}

fn (mut c Checker) lint_vue_valid_v_show(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives('show') {
		stats.checked++
		c.vvd_argument(i, mut findings)
		c.vvd_modifiers(i, mut findings)
		c.vvd_expected_value(i, mut findings)
		if c.vue.doc.nodes[c.vue_attribute_element(i)].name == 'template' {
			findings << c.vue_report_vnode(i, 'unexpectedTemplate', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_valid_v_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives('if') {
		stats.checked++
		element := c.vue_attribute_element(i)
		if c.vue_has_directive(element, 'else', none) {
			findings << c.vue_report_vnode(i, 'withVElse', {})
		}
		if c.vue_has_directive(element, 'else-if', none) {
			findings << c.vue_report_vnode(i, 'withVElseIf', {})
		}
		c.vvd_argument(i, mut findings)
		c.vvd_modifiers(i, mut findings)
		c.vvd_expected_value(i, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_valid_v_else_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives('else-if') {
		stats.checked++
		element := c.vue_attribute_element(i)
		if !c.vue_prev_element_has_if(element) {
			findings << c.vue_report_vnode(i, 'missingVIf', {})
		}
		if c.vue_has_directive(element, 'if', none) {
			findings << c.vue_report_vnode(i, 'withVIf', {})
		}
		if c.vue_has_directive(element, 'else', none) {
			findings << c.vue_report_vnode(i, 'withVElse', {})
		}
		c.vvd_argument(i, mut findings)
		c.vvd_modifiers(i, mut findings)
		c.vvd_expected_value(i, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_valid_v_else(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives('else') {
		stats.checked++
		element := c.vue_attribute_element(i)
		if !c.vue_prev_element_has_if(element) {
			findings << c.vue_report_vnode(i, 'missingVIf', {})
		}
		if c.vue_has_directive(element, 'if', none) {
			findings << c.vue_report_vnode(i, 'withVIf', {})
		}
		if c.vue_has_directive(element, 'else-if', none) {
			findings << c.vue_report_vnode(i, 'withVElseIf', {})
		}
		c.vvd_argument(i, mut findings)
		c.vvd_modifiers(i, mut findings)
		c.vvd_no_value(i, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_valid_v_is(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vvd_directives('is') {
		stats.checked++
		c.vvd_argument(i, mut findings)
		c.vvd_modifiers(i, mut findings)
		c.vvd_expected_value(i, mut findings)
		element := c.vue_attribute_element(i)
		// isValidElement: not an HTML element, or a well-known HTML element name.
		if !c.vue_is_html_element_node(element)
			|| vue_is_html_well_known_element_name(c.vue.doc.nodes[element].raw_name) {
			continue
		}
		findings << c.vue_report_vnode(i, 'ownerMustBeHTMLElement', {
			'name': c.vue.doc.nodes[element].name
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
