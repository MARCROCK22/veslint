module rules

import json2
import time

// Port of the `vue/v-bind-style` rule of eslint-plugin-vue 10.12.1 (options "shorthand", the
// default, or "longform", and `sameNameShorthand`: "always", "never" or "ignore", the default): a
// `v-bind` with an argument written the other way (`:x`, `.x` or `v-bind:x`), and one whose value is
// the argument's name (camel-cased when kebab-case) written with or without the same-name shorthand
// (`:foo` for `:foo="foo"`), each fixed.

const vvbs_messages = {
	'expectedLonghand':        "Expected 'v-bind' before ':'."
	'unexpectedLonghand':      "Unexpected 'v-bind' before ':'."
	'expectedLonghandForProp': "Expected 'v-bind:' instead of '.'."
	'expectedShorthand':       'Expected same-name shorthand.'
	'unexpectedShorthand':     'Unexpected same-name shorthand.'
}

struct VvbsOptions {
	prefer_shorthand    bool   = true
	same_name_shorthand string = 'ignore'
}

fn vvbs_options(options []json2.Any) !VvbsOptions {
	mut prefer := true
	if options.len > 0 {
		value := options[0]
		if value !is string || value as string !in ['shorthand', 'longform'] {
			return error('the first option of `${vue_v_bind_style}` must be "shorthand" or "longform"')
		}
		prefer = value as string != 'longform'
	}
	mut same_name := 'ignore'
	if options.len > 1 {
		o := option_object(vue_v_bind_style, options[1..], ['sameNameShorthand'])!
		value := o.string_value('sameNameShorthand', ['always', 'never', 'ignore'])!
		// `context.options[1]?.sameNameShorthand || 'ignore'`
		if value != '' {
			same_name = value
		}
	}
	return VvbsOptions{
		prefer_shorthand:    prefer
		same_name_shorthand: same_name
	}
}

// vvbs_kebab_to_camel is kebabCaseToCamelCase.
fn vvbs_kebab_to_camel(name string) string {
	return if vue_is_kebab_case(name) { vue_camel_case(name) } else { name }
}

// vvbs_is_same_name is isSameName: the argument (by its rawName) and the value (an Identifier)
// are the same name, kebab-case aside.
fn (c &Checker) vvbs_is_same_name(attr int) bool {
	argument := c.vue_directive_argument(attr)
	if argument < 0 || c.vue.doc.nodes[argument].typ != .v_identifier {
		return false
	}
	value := c.vue.doc.nodes[attr].value
	e := c.vue_container_expression(value)
	if c.vue_expr_type(e) != 'Identifier' {
		return false
	}
	name := c.vue.doc.snippets[e.snippet].es.string_of(e.node, .name) or { return false }
	return vvbs_kebab_to_camel(c.vue.doc.nodes[argument].raw_name) == vvbs_kebab_to_camel(name)
}

fn (mut c Checker) lint_vue_v_bind_style(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vvbs_options(c.rule_options(vue_v_bind_style))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'bind') || c.vue_directive_argument(i) < 0 {
			continue
		}
		stats.checked++
		node := c.vue.doc.nodes[i]
		key := c.vue.doc.nodes[node.key]
		// checkAttributeSameName
		if opts.same_name_shorthand != 'ignore' && c.vvbs_is_same_name(i) {
			prefer := opts.same_name_shorthand == 'always'
			if c.vue_is_vbind_same_name_shorthand(i) != prefer {
				report := c.vue_report_vnode(i, if prefer {
					'expectedShorthand'
				} else {
					'unexpectedShorthand'
				}, {})
				argument := c.vue.doc.nodes[key.argument]
				if prefer {
					// getCutStart: the end of the last modifier, or of the argument.
					cut := if key.modifiers.len > 0 {
						c.vue.doc.nodes[key.modifiers[key.modifiers.len - 1]].end
					} else {
						argument.end
					}
					findings << c.with_fixes(report, [fix_remove_range(cut, node.end)])!
				} else if argument.typ == .v_identifier {
					findings << c.with_fixes(report, [
						fix_insert_at(node.end, '="${vvbs_kebab_to_camel(argument.raw_name)}"'),
					])!
				} else {
					findings << report
				}
			}
		}
		// checkAttributeStyle
		raw := c.vue.doc.nodes[key.dir_name].raw_name
		is_shorthand_prop := raw == '.'
		is_shorthand := raw == ':' || is_shorthand_prop
		if is_shorthand == opts.prefer_shorthand {
			continue
		}
		message_id := if opts.prefer_shorthand {
			'unexpectedLonghand'
		} else if is_shorthand_prop {
			'expectedLonghandForProp'
		} else {
			'expectedLonghand'
		}
		report := c.vue_report_vnode(i, message_id, {})
		name := c.vue.doc.nodes[key.dir_name]
		mut fixes := []Fix{}
		if opts.prefer_shorthand {
			fixes << fix_remove_range(name.start, name.end)
		} else {
			fixes << fix_insert_at(node.start, 'v-bind')
			if is_shorthand_prop {
				fixes << fix_replace_range(name.start, name.end, ':')
				modifier := c.vue.doc.nodes[key.modifiers[0]]
				if modifier.name == 'prop' && modifier.raw_name == '' {
					fixes << fix_insert_at(modifier.start, '.prop')
				}
			}
		}
		findings << c.with_fixes(report, fixes)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
