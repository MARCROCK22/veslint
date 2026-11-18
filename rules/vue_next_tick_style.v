module rules

import estree
import json2
import time
import treesitter { node_field, node_kind }

// Port of the `vue/next-tick-style` rule of eslint-plugin-vue 10.12.1 (option "promise", the
// default, or "callback"): a call of `this.$nextTick`, `Vue.nextTick` or the `nextTick` imported
// from `vue`, inside a Vue object, that passes a callback (or, with "callback", that does not or
// whose Promise is used), with the fix to `nextTick().then(…)` for "promise".

const vue_next_tick_style_messages = {
	'usePromise':  'Use the Promise returned by `nextTick` instead of passing a callback function.'
	'useCallback': 'Pass a callback function to `nextTick` instead of using the returned Promise.'
}

fn vue_next_tick_style_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'promise'
	}
	value := options[0]
	if value is string {
		if value !in ['promise', 'callback'] {
			return error('the option of `${vue_next_tick_style}` must be "promise" or "callback"')
		}
		return value
	}
	return error('the option of `${vue_next_tick_style}` must be "promise" or "callback"')
}

fn (mut c Checker) lint_vue_next_tick_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	style := vue_next_tick_style_options(c.rule_options(vue_next_tick_style))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .identifier || s.owner_of(node) < 0 {
			continue
		}
		call := c.vnts_next_tick_call(root, t, node)
		if call < 0 {
			continue
		}
		stats.checked++
		args := (t.list(call, .arguments) or { []int{} }).len
		if style == 'callback' {
			if args != 1 || vnts_is_awaited_promise(t, call) {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'useCallback'
				}
			}
			continue
		}
		if args > 0 || !vnts_is_awaited_promise(t, call) {
			findings << c.with_fixes(Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'usePromise'
			}, [fix_insert_at(t.nodes[node].end, '().then')])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnts_next_tick_call is getVueNextTickCallExpression: the call of `this.$nextTick(…)`,
// `Vue.nextTick(…)` or of the `nextTick` imported from `vue` whose callee is the identifier, -1
// for none.
fn (mut c Checker) vnts_next_tick_call(root C.TSNode, t &estree.EsTree, id int) int {
	parent := t.nodes[id].parent
	if parent < 0 {
		return -1
	}
	if t.typ(parent) == .member_expression {
		grand := t.nodes[parent].parent
		if grand >= 0 && t.typ(grand) == .call_expression
			&& (t.node(grand, .callee) or { -1 }) == parent
			&& c.vnts_is_vue_next_tick_member(root, t, id, parent) {
			return grand
		}
	}
	if t.typ(parent) == .call_expression && (t.node(parent, .callee) or { -1 }) == id
		&& c.vnts_is_vue_next_tick_import(root, t, id) {
		return parent
	}
	return -1
}

// vnts_is_vue_next_tick_member: `$nextTick` with `this` as the object of the member expression,
// or `nextTick` with `Vue`.
fn (mut c Checker) vnts_is_vue_next_tick_member(root C.TSNode, t &estree.EsTree, id int, member int) bool {
	name := t.string_of(id, .name) or { return false }
	object := t.node(member, .object) or { return false }
	return (name == '\$nextTick' && c.vue_is_this(root, t, object)) || (name == 'nextTick'
		&& t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == 'Vue')
}

// vnts_is_vue_next_tick_import: the identifier's variable has one definition, an
// `import { nextTick } from 'vue'`.
fn (mut c Checker) vnts_is_vue_next_tick_import(root C.TSNode, t &estree.EsTree, id int) bool {
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return false
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	if defs.len != 1 || defs[0].kind != .import_binding
		|| node_kind(defs[0].node) != 'import_specifier' {
		return false
	}
	imported := node_field(defs[0].node, 'name') or { return false }
	if node_kind(imported) != 'identifier' || c.text(imported) != 'nextTick' {
		return false
	}
	statement := vue_import_statement_of(defs[0].node) or { return false }
	source := node_field(statement, 'source') or { return false }
	return (c.string_if_constant_unscoped(source) or { '' }) == 'vue'
}

// vnts_is_awaited_promise is next-tick-style's isAwaitedPromise.
fn vnts_is_awaited_promise(t &estree.EsTree, call int) bool {
	parent := t.nodes[call].parent
	if parent < 0 {
		return false
	}
	if t.typ(parent) == .await_expression {
		return true
	}
	if t.typ(parent) == .member_expression {
		property := t.node(parent, .property) or { return false }
		return t.typ(property) == .identifier
			&& (t.string_of(property, .name) or { '' }) == 'then'
	}
	return false
}
