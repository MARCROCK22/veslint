module rules

import json2
import time

// Port of the `vue/this-in-template` rule of eslint-plugin-vue 10.12.1 (option "never", the
// default, or "always"), on the template's scope (the variables of the enclosing elements: v-for,
// slot scopes):
// - "never": `this` as the object of a member access with a static name that is not a variable of
//   an enclosing element, a reserved word, nor a name that is not an identifier, fixed by the name;
// - "always": a reference of an expression container (but a dynamic argument's) to something that
//   is not a variable of an enclosing element, fixed by `this.` before it.

const vtit_messages = {
	'unexpected': "Unexpected usage of 'this'."
	'expected':   "Expected 'this'."
}

fn vtit_options(options []json2.Any) !bool {
	if options.len == 0 {
		return false
	}
	value := options[0]
	if value is string && value in ['always', 'never'] {
		return value == 'always'
	}
	return error('the option of `${vue_this_in_template}` must be "always" or "never"')
}

// vtit_not_identifier is `/^\d.*$|[^\w$]/.test(name)`: the name starts with a digit or has a
// character that is not a word character nor `$`.
fn vtit_not_identifier(name string) bool {
	if name.len > 0 && name[0].is_digit() {
		return true
	}
	return !name.bytes().all(it.is_letter() || it.is_digit() || it == `_` || it == `$`)
}

fn (mut c Checker) lint_vue_this_in_template(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	always := vtit_options(c.rule_options(vue_this_in_template))!
	mut findings := []Finding{}
	// The names of the variables of the elements entered, one list per element (scopeStack).
	mut scopes := [][]string{}
	for step in c.vue_template_steps() {
		n := step.node
		if n.kind == .vnode {
			node := &c.vue.doc.nodes[n.v]
			if node.typ == .v_element {
				if step.leave {
					scopes.pop()
					continue
				}
				mut names := if scopes.len > 0 { scopes.last().clone() } else { []string{} }
				for v in node.variables {
					name := c.vue.doc.variables[v].name
					if name !in names {
						names << name
					}
				}
				scopes << names
				continue
			}
			if !always || step.leave || node.typ != .v_expression_container || scopes.len == 0 {
				continue
			}
			// Dynamic arguments: in `:[this.prop]`, `.prop]` would be a modifier.
			if node.parent >= 0 && c.vue.doc.nodes[node.parent].typ == .v_directive_key {
				continue
			}
			stats.checked++
			for r in node.references {
				reference := &c.vue.doc.references[r]
				if reference.name in scopes.last() {
					continue
				}
				start, end := c.vue_expr_range(reference.id)
				findings << c.with_fixes(c.vue_report(start, end, 'expected', {}), [
					fix_insert_at(start, 'this.'),
				])!
			}
			continue
		}
		if always || step.leave || n.kind != .estree || scopes.len == 0 {
			continue
		}
		es := &c.vue.doc.snippets[n.snippet].es
		if es.typ(n.es) != .this_expression {
			continue
		}
		parent := es.nodes[n.es].parent
		if parent < 0 || es.typ(parent) != .member_expression {
			continue
		}
		stats.checked++
		name := vue_tpl_static_property_name(es, parent) or { continue }
		if name == '' || name in scopes.last() || name in vue_js_reserved_names
			|| vtit_not_identifier(name) {
			continue
		}
		this_node := es.nodes[n.es]
		member := es.nodes[parent]
		findings << c.with_fixes(c.vue_report(this_node.start, this_node.end, 'unexpected', {}),
			[fix_replace_range(member.start, member.end, name)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
