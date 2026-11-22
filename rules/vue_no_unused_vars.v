module rules

import json2
import jsregexp
import time

// Port of the `vue/no-unused-vars` rule of eslint-plugin-vue 10.12.1 (option `ignorePattern`, a
// regular expression of names to leave), on the template's scope: a variable of a `v-for` or a
// slot scope without references, unless a later variable of the same directive is used (and it
// is not destructured), or an element inside uses its name as a tag. With the pattern `^_`, a
// suggestion renames it with a `_` before.

const vnuv_messages = {
	'unusedVariable':        "'{{name}}' is defined but never used."
	'replaceWithUnderscore': 'Replace `{{name}}` with `_{{name}}` to ignore the unused variable.'
}

struct VnuvOptions {
	pattern    string
	has_ignore bool
	ignore     jsregexp.JsRegex
}

fn vnuv_options(options []json2.Any) !VnuvOptions {
	o := option_object(vue_no_unused_vars, options, ['ignorePattern'])!
	value := o.values['ignorePattern'] or { return VnuvOptions{} }
	if value !is string {
		return error('option `ignorePattern` of `${vue_no_unused_vars}` must be a string')
	}
	pattern := value as string
	if pattern == '' {
		return VnuvOptions{}
	}
	return VnuvOptions{
		pattern:    pattern
		has_ignore: true
		ignore:     jsregexp.js_regex_new(pattern, 'u')!
	}
}

fn (mut c Checker) lint_vue_no_unused_vars(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnuv_options(c.rule_options(vue_no_unused_vars))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.variables.len == 0 {
			continue
		}
		stats.checked++
		// groupingVariables: by kind, the kinds in the order they first appear.
		mut kinds := []string{}
		for v in node.variables {
			kind := c.vue.doc.variables[v].kind
			if kind !in kinds {
				kinds << kind
			}
		}
		for kind in kinds {
			group := node.variables.filter(c.vue.doc.variables[it].kind == kind)
			c.vnuv_check_group(i, group, opts, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnuv_check_group is checkVariableGroup.
fn (c &Checker) vnuv_check_group(element int, variables []int, opts VnuvOptions, mut findings []Finding) ! {
	mut has_after_used := false
	for k := variables.len - 1; k >= 0; k-- {
		v := variables[k]
		variable := &c.vue.doc.variables[v]
		if variable.references.len > 0 {
			has_after_used = true
			continue
		}
		if (opts.has_ignore && vue_regexp_test(opts.ignore, variable.name))
			|| (has_after_used && !c.vnuv_is_destructuring(element, v))
			|| c.vnuv_used_as_tag(variable.name, element) {
			continue
		}
		start, end := c.vue_expr_range(variable.id)
		mut report := c.vue_report(start, end, 'unusedVariable', {
			'name': variable.name
		})
		if opts.pattern == '^_' {
			_, suggestion := c.suggestion('replaceWithUnderscore', {
				'name': variable.name
			}, [fix_replace_range(start, end, '_${variable.name}')])!
			report = Finding{
				...report
				suggestions: [suggestion]
			}
		}
		findings << report
	}
}

// vnuv_is_destructuring is isDestructuringVar: on the way from the variable's identifier up to
// the parameter of the directive (a pattern of the VForExpression or VSlotScopeExpression of the
// element), there is a Property or an ArrayPattern.
fn (c &Checker) vnuv_is_destructuring(element int, v int) bool {
	id := c.vue.doc.variables[v].id
	if id.kind != .estree {
		return false
	}
	mut params := []int{}
	for a in c.vue_attributes(element) {
		value := c.vue.doc.nodes[a].value
		if value < 0 || c.vue.doc.nodes[value].typ != .v_expression_container {
			continue
		}
		e := c.vue.doc.nodes[value].expression
		if e.kind != .vnode || c.vue.doc.nodes[e.node].typ !in [.v_for_expression,
			.v_slot_scope_expression, .v_generic_expression] {
			continue
		}
		for p in c.vue.doc.nodes[e.node].exprs {
			if p.kind == .estree && p.snippet == id.snippet {
				params << p.node
			}
		}
	}
	es := &c.vue.doc.snippets[id.snippet].es
	mut cur := id.node
	for cur !in params {
		parent := es.nodes[cur].parent
		if parent < 0 {
			return false
		}
		if es.typ(parent) in [.property, .array_pattern] {
			return true
		}
		cur = parent
	}
	return false
}

// vnuv_used_as_tag is isUsedAsComponentTag: an element inside `element` has the name as rawName.
fn (c &Checker) vnuv_used_as_tag(name string, element int) bool {
	for child in c.vue.doc.nodes[element].children {
		ch := &c.vue.doc.nodes[child]
		if ch.typ != .v_element {
			continue
		}
		if ch.raw_name == name || c.vnuv_used_as_tag(name, child) {
			return true
		}
	}
	return false
}
