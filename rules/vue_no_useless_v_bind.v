module rules

import estree
import json2
import time

// Port of the `vue/no-useless-v-bind` rule of eslint-plugin-vue 10.12.1 (options
// `ignoreIncludesComment` and `ignoreStringEscape`): a `v-bind` with an argument, no modifiers and
// a string literal (or a template literal without expressions) as its value, fixed into a plain
// attribute unless the value has a comment or a useful escape.

const vnuvb_messages = {
	'unexpected': 'Unexpected `v-bind` with a string literal value.'
}

struct VnuvbOptions {
	ignore_comment bool
	ignore_escape  bool
}

fn vnuvb_options(options []json2.Any) !VnuvbOptions {
	o := option_object(vue_no_useless_v_bind, options, ['ignoreIncludesComment', 'ignoreStringEscape'])!
	return VnuvbOptions{
		ignore_comment: o.bool_value('ignoreIncludesComment')!
		ignore_escape:  o.bool_value('ignoreStringEscape')!
	}
}

// vnuvb_has_escape is the check of escapes of the raw value: a backslash before one of `nrvtbfux`
// or at the end.
fn vnuvb_has_escape(raw string) bool {
	chars := raw.runes()
	mut i := 0
	for i < chars.len {
		if chars[i] == `\\` {
			i++
			if i >= chars.len || chars[i] in [`n`, `r`, `v`, `t`, `b`, `f`, `u`, `x`] {
				return true
			}
		}
		i++
	}
	return false
}

fn (mut c Checker) lint_vue_no_useless_v_bind(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnuvb_options(c.rule_options(vue_no_useless_v_bind))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'bind') || c.vue_directive_argument(i) < 0 {
			continue
		}
		stats.checked++
		node := &c.vue.doc.nodes[i]
		key := &c.vue.doc.nodes[node.key]
		if node.value < 0 || key.modifiers.len > 0 {
			continue
		}
		e := c.vue_container_expression(node.value)
		if e.kind != .estree {
			continue
		}
		es := c.vue_expr_es(e)
		if !vue_tpl_is_string_literal(es, e.node) {
			continue
		}
		str_value := vue_tpl_string_literal_value(es, e.node, false) or { continue }
		expression := es.nodes[e.node]
		raw_value := if expression.typ == .literal {
			text := c.vue_text(expression.start, expression.end)
			if text.len >= 2 { text[1..text.len - 1] } else { '' }
		} else {
			quasis := es.list(e.node, .quasis) or { []int{} }
			v := if quasis.len > 0 {
				es.get(quasis[0], .value)
			} else {
				estree.Value(estree.Undefined{})
			}
			if v is estree.TemplateValue { v.raw } else { '' }
		}
		value := &c.vue.doc.nodes[node.value]
		has_comment := c.vue_tokens_with_comments_in(value.start, value.end).any(it.typ in [
			'Block',
			'Line',
		])
		if opts.ignore_comment && has_comment {
			continue
		}
		has_escape := raw_value != str_value && vnuvb_has_escape(raw_value)
		if opts.ignore_escape && has_escape {
			continue
		}
		report := c.vue_report_vnode(i, 'unexpected', {})
		if has_comment || has_escape {
			findings << report
			continue
		}
		text := c.vue_text(value.start, value.end)
		quote := if text.len > 0 { text[0] } else { u8(0) }
		name := &c.vue.doc.nodes[key.dir_name]
		is_shorthand := name.raw_name == ':'
		attr_value := match quote {
			`"` { '"' + str_value.replace('"', '&quot;') + '"' }
			`'` { "'" + str_value.replace("'", '&apos;') + "'" }
			else { str_value.replace('"', '&quot;').replace("'", '&apos;') }
		}
		findings << c.with_fixes(report, [
			fix_remove_range(name.start, name.end + if is_shorthand { 0 } else { 1 }),
			fix_replace_range(value.start, value.end, attr_value),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
