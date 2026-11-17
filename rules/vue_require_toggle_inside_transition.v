module rules

import json2
import time

// Port of the `vue/require-toggle-inside-transition` rule of eslint-plugin-vue 10.12.1 (option
// `additionalDirectives`: directive names besides `if` and `show`): the start tag of the first
// child element of a <transition> without `appear` (or a `:appear` not `false`) that is not a
// custom component, not a <slot>, and has none of those directives nor a `:key`.

const vrtit_messages = {
	'expected': 'The element inside `<transition>` is expected to have a {{allowedDirectives}} directive.'
}

fn vrtit_options(options []json2.Any) ![]string {
	o := option_object(vue_require_toggle_inside_transition, options, ['additionalDirectives'])!
	mut out := ['if', 'show']
	out << o.string_list('additionalDirectives')!
	return out
}

// vrtit_directive_list is createDirectiveList: "`v-a`, `v-b` or `v-c`".
fn vrtit_directive_list(directives []string) string {
	mut s := ''
	for index, directive in directives {
		if index == 0 {
			s += '`v-${directive}`'
		} else if index < directives.len - 1 {
			s += ', `v-${directive}`'
		} else {
			s += ' or `v-${directive}`'
		}
	}
	return s
}

fn (mut c Checker) lint_vue_require_toggle_inside_transition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allowed := vrtit_options(c.rule_options(vue_require_toggle_inside_transition))!
	allowed_text := vrtit_directive_list(allowed)
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.parent < 0 {
			continue
		}
		parent := &c.vue.doc.nodes[node.parent]
		if parent.typ != .v_element || parent.name != 'transition' {
			continue
		}
		stats.checked++
		// Only the first child element.
		if parent.children.filter(c.vue.doc.nodes[it].typ == .v_element)[0] != i {
			continue
		}
		if c.vue_is_custom_component(i, false) {
			continue
		}
		if c.vue_has_attribute(node.parent, 'appear', none) {
			continue
		}
		appear := c.vue_get_directive(node.parent, 'bind', 'appear')
		if appear >= 0 && c.vrtit_is_valid_bind_appear(appear) {
			continue
		}
		if node.name != 'slot' && allowed.all(!c.vue_has_directive(i, it, none))
			&& !c.vue_has_directive(i, 'bind', 'key') {
			findings << c.vue_report_vnode(node.start_tag, 'expected', {
				'allowedDirectives': allowed_text
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vrtit_is_valid_bind_appear is isValidBindAppear: a `:appear` without an expression or whose
// expression is not the literal `false`.
fn (c &Checker) vrtit_is_valid_bind_appear(directive int) bool {
	e := c.vue_container_expression(c.vue.doc.nodes[directive].value)
	if e.is_null() || c.vue_expr_type(e) != 'Literal' {
		return true
	}
	value := c.vue_expr_es(e).get(e.node, .value)
	return !(value is bool && !value)
}
