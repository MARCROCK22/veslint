module rules

import json2
import time

// Port of the `vue/prefer-true-attribute-shorthand` rule of eslint-plugin-vue 10.12.1 (option
// "always", the default, or "never", and `except`: names or regular expressions as strings that
// take the other one): on a custom component, a `:prop="true"` (or `v-model:prop="true"`) that
// should be the shorthand `prop`, or a valueless `prop` that should be written in long form, with
// suggestions.

const vptas_messages = {
	'expectShort':             "Boolean prop with 'true' value should be written in shorthand form."
	'expectLong':              "Boolean prop with 'true' value should be written in long form."
	'rewriteIntoShort':        'Rewrite this prop into shorthand form.'
	'rewriteIntoLongVueProp':  'Rewrite this prop into long-form Vue component prop.'
	'rewriteIntoLongHtmlAttr': 'Rewrite this prop into long-form HTML attribute.'
}

struct VptasOptions {
	always bool = true
	except VueRegexpGroup
}

fn vptas_options(options []json2.Any) !VptasOptions {
	mut always := true
	if options.len > 0 {
		value := options[0]
		if value !is string || value as string !in ['always', 'never'] {
			return error('the first option of `${vue_prefer_true_attribute_shorthand}` must be "always" or "never"')
		}
		always = value as string == 'always'
	}
	mut except := []string{}
	if options.len > 1 {
		o := option_object(vue_prefer_true_attribute_shorthand, options[1..], ['except'])!
		except = o.string_list('except')!
	}
	return VptasOptions{
		always: always
		except: vue_regexp_group(except)!
	}
}

fn (mut c Checker) lint_vue_prefer_true_attribute_shorthand(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vptas_options(c.rule_options(vue_prefer_true_attribute_shorthand))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !c.vue_is_custom_component(c.vue_attribute_element(i), false) {
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
		excepted := opts.except.matches(name)
		if !node.directive && node.value < 0 && (if opts.always { excepted } else { !excepted }) {
			raw := c.vue.doc.nodes[node.key].raw_name
			_, long_vue := c.suggestion('rewriteIntoLongVueProp', {}, [
				fix_replace_range(node.start, node.end, ':${raw}="true"'),
			])!
			_, long_html := c.suggestion('rewriteIntoLongHtmlAttr', {}, [
				fix_replace_range(node.start, node.end, '${raw}="${raw}"'),
			])!
			findings << Finding{
				...c.vue_report_vnode(i, 'expectLong', {})
				suggestions: [long_vue, long_html]
			}
			continue
		}
		if !node.directive {
			continue
		}
		e := c.vue_container_expression(node.value)
		if e.kind != .estree || c.vue_expr_type(e) != 'Literal' {
			continue
		}
		value := c.vue_expr_es(e).get(e.node, .value)
		if !(value is bool && value) || (if opts.always { excepted } else { !excepted }) {
			continue
		}
		_, short := c.suggestion('rewriteIntoShort', {}, [
			fix_replace_range(node.start, node.end, name),
		])!
		findings << Finding{
			...c.vue_report_vnode(i, 'expectShort', {})
			suggestions: [short]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
