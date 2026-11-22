module rules

import json2
import jsregexp
import time

// Ports of the `vue/attribute-hyphenation` and `vue/v-on-event-hyphenation` rules of
// eslint-plugin-vue 10.12.1 (first option "always", the default, or "never"; then `ignore`, names
// that may appear anywhere in the name to leave it, and `ignoreTags`, names or regular expressions
// as strings of elements to leave).
//
// attribute-hyphenation: on a custom component or a <slot>, a plain attribute, or the argument of
// a `v-bind` or `v-model`, not hyphenated ("always") or hyphenated ("never"); `data-`, `aria-`,
// `slot-scope` and the SVG attributes that are not kebab-case are always left. Fixed by the name
// in the other case (getExactConverter) but for names with `_`, a `.sync` key or a name that
// starts with a capital letter.
//
// v-on-event-hyphenation: the argument of a `v-on` on a custom component, not hyphenated or
// hyphenated; fixed (getConverter) only with `autofix`, but for names with `_`.

const vah_messages = {
	'mustBeHyphenated':   "Attribute '{{text}}' must be hyphenated."
	'cannotBeHyphenated': "Attribute '{{text}}' can't be hyphenated."
}

const voeh_messages = {
	'mustBeHyphenated':   "v-on event '{{text}}' must be hyphenated."
	'cannotBeHyphenated': "v-on event '{{text}}' can't be hyphenated."
}

struct VueHyphenationOptions {
	hyphenated  bool = true
	ignore      []string
	ignore_tags VueRegexpGroup
	autofix     bool
}

fn vue_hyphenation_options(rule string, options []json2.Any, keys []string) !VueHyphenationOptions {
	mut hyphenated := true
	if options.len > 0 {
		value := options[0]
		if value !is string || value as string !in ['always', 'never'] {
			return error('the first option of `${rule}` must be "always" or "never"')
		}
		hyphenated = value as string != 'never'
	}
	if options.len < 2 {
		return VueHyphenationOptions{
			hyphenated: hyphenated
		}
	}
	o := option_object(rule, options[1..], keys)!
	return VueHyphenationOptions{
		hyphenated:  hyphenated
		ignore:      o.string_list('ignore')!
		ignore_tags: vue_regexp_group(o.string_list('ignoreTags')!)!
		autofix:     o.bool_value('autofix')!
	}
}

fn vah_options(options []json2.Any) !VueHyphenationOptions {
	return vue_hyphenation_options(vue_attribute_hyphenation, options, ['ignore', 'ignoreTags'])
}

fn voeh_options(options []json2.Any) !VueHyphenationOptions {
	return vue_hyphenation_options(vue_v_on_event_hyphenation, options, ['autofix', 'ignore',
		'ignoreTags'])
}

// vue_hyphenation_ignored is isIgnoredAttribute: the name holds an ignored text, or is already in
// the expected style (all lower case for "always", without `-` for "never").
fn vue_hyphenation_ignored(name string, ignored []string, hyphenated bool) bool {
	if ignored.any(name.contains(it)) {
		return true
	}
	if hyphenated {
		units := utf16_units(name)
		return jsregexp.js_to_lower(units) == units
	}
	return !name.contains('-')
}

fn (mut c Checker) lint_vue_attribute_hyphenation(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vah_options(c.rule_options(vue_attribute_hyphenation))!
	mut ignored := ['data-', 'aria-', 'slot-scope']
	for name, _ in vue_svg_attributes_weird_case {
		ignored << name
	}
	ignored << opts.ignore
	case_name := if opts.hyphenated { 'kebab-case' } else { 'camelCase' }
	message_id := if opts.hyphenated { 'mustBeHyphenated' } else { 'cannotBeHyphenated' }
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		element := c.vue_attribute_element(i)
		if (!c.vue_is_custom_component(element, false) && c.vue.doc.nodes[element].name != 'slot')
			|| opts.ignore_tags.matches(c.vue.doc.nodes[element].raw_name) {
			continue
		}
		stats.checked++
		// getAttributeName
		mut name := ''
		if !node.directive {
			name = c.vue.doc.nodes[node.key].raw_name
		} else {
			directive := c.vue_directive_name(i)
			argument := c.vue_directive_argument(i)
			if (directive != 'bind' && directive != 'model') || argument < 0
				|| c.vue.doc.nodes[argument].typ != .v_identifier {
				continue
			}
			name = c.vue.doc.nodes[argument].raw_name
		}
		if vue_hyphenation_ignored(name, ignored, opts.hyphenated) {
			continue
		}
		key := &c.vue.doc.nodes[node.key]
		text := c.vue_text(key.start, key.end)
		report := c.vue_report_vnode(i, message_id, {
			'text': text
		})
		if text.contains('_') || text.ends_with('.sync') || (name.len > 0 && name[0] >= `A`
			&& name[0] <= `Z`) {
			findings << report
			continue
		}
		findings << c.with_fixes(report, [
			fix_replace_range(key.start, key.end, text.replace_once(name, vue_case_exact_convert(case_name,
				name))),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) lint_vue_v_on_event_hyphenation(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := voeh_options(c.rule_options(vue_v_on_event_hyphenation))!
	case_name := if opts.hyphenated { 'kebab-case' } else { 'camelCase' }
	message_id := if opts.hyphenated { 'mustBeHyphenated' } else { 'cannotBeHyphenated' }
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'on') {
			continue
		}
		element := c.vue_attribute_element(i)
		argument := c.vue_directive_argument(i)
		if !c.vue_is_custom_component(element, false)
			|| opts.ignore_tags.matches(c.vue.doc.nodes[element].raw_name) || argument < 0
			|| c.vue.doc.nodes[argument].typ != .v_identifier {
			continue
		}
		stats.checked++
		name := c.vue.doc.nodes[argument].raw_name
		if name == '' || vue_hyphenation_ignored(name, opts.ignore, opts.hyphenated) {
			continue
		}
		key := &c.vue.doc.nodes[c.vue.doc.nodes[i].key]
		report := c.vue_report_vnode(i, message_id, {
			'text': c.vue_text(key.start, key.end)
		})
		if !opts.autofix || name.contains('_') {
			findings << report
			continue
		}
		arg := &c.vue.doc.nodes[argument]
		findings << c.with_fixes(report, [
			fix_replace_range(arg.start, arg.end, vue_case_convert(case_name, name)),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
