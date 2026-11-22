module rules

import json2
import time

// Port of the `vue/v-slot-style` rule of eslint-plugin-vue 10.12.1 (option "shorthand" or
// "longform" for every slot, or an object with `atComponent` ("v-slot" by default), `default` and
// `named` ("shorthand" by default)): a `v-slot` written in another style than the expected one for
// its place (the default slot on a component, the default slot on a <template>, a named slot),
// fixed.

const vvss_messages = {
	'expectedShorthand': "Expected '#{{argument}}' instead of '{{actual}}'."
	'expectedLongform':  "Expected 'v-slot:{{argument}}' instead of '{{actual}}'."
	'expectedVSlot':     "Expected 'v-slot' instead of '{{actual}}'."
}

struct VvssOptions {
	at_component string = 'v-slot'
	default_     string = 'shorthand'
	named        string = 'shorthand'
}

fn vvss_options(options []json2.Any) !VvssOptions {
	if options.len == 0 {
		return VvssOptions{}
	}
	value := options[0]
	if value is string {
		if value !in ['shorthand', 'longform'] {
			return error('the option of `${vue_v_slot_style}` must be "shorthand", "longform" or an object')
		}
		return VvssOptions{
			at_component: value
			default_:     value
			named:        value
		}
	}
	o := option_object(vue_v_slot_style, options, ['atComponent', 'default', 'named'])!
	at_component := o.string_value('atComponent', ['shorthand', 'longform', 'v-slot'])!
	default_ := o.string_value('default', ['shorthand', 'longform', 'v-slot'])!
	named := o.string_value('named', ['shorthand', 'longform'])!
	return VvssOptions{
		at_component: if at_component == '' { 'v-slot' } else { at_component }
		default_:     if default_ == '' { 'shorthand' } else { default_ }
		named:        if named == '' { 'shorthand' } else { named }
	}
}

fn (mut c Checker) lint_vue_v_slot_style(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vvss_options(c.rule_options(vue_v_slot_style))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'slot') {
			continue
		}
		stats.checked++
		key := &c.vue.doc.nodes[c.vue.doc.nodes[i].key]
		name := &c.vue.doc.nodes[key.dir_name]
		argument := key.argument
		// getExpectedStyle
		expected := if argument < 0 || (c.vue.doc.nodes[argument].typ == .v_identifier
			&& c.vue.doc.nodes[argument].name == 'default') {
			if c.vue.doc.nodes[c.vue_attribute_element(i)].name == 'template' {
				opts.default_
			} else {
				opts.at_component
			}
		} else {
			opts.named
		}
		// getActualStyle
		actual := if name.raw_name == '#' {
			'shorthand'
		} else if argument < 0 {
			'v-slot'
		} else {
			'longform'
		}
		if actual == expected {
			continue
		}
		end := if argument >= 0 { c.vue.doc.nodes[argument].end } else { name.end }
		argument_text := if argument >= 0 {
			c.vue_vnode_text(argument)
		} else {
			'default'
		}
		message_id, replacement := match expected {
			'shorthand' { 'expectedShorthand', '#${argument_text}' }
			'longform' { 'expectedLongform', 'v-slot:${argument_text}' }
			else { 'expectedVSlot', 'v-slot' }
		}
		findings << c.with_fixes(c.vue_report_vnode(i, message_id, {
			'actual':   c.vue_text(name.start, end)
			'argument': argument_text
		}), [fix_replace_range(name.start, end, replacement)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
