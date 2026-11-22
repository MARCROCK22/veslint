module rules

import estree
import json2

// Port of the `svelte/no-unnecessary-state-wrap` rule of eslint-plugin-svelte 3.24.1: a reactive
// class of `svelte/reactivity` (or one of `additionalReactiveClasses`, by name) constructed or
// called as the argument of `$state(…)` that initializes a variable is reported, with a
// suggestion that drops the `$state` (with `allowReassign`, not when the variable is assigned
// elsewhere). Its condition is runes mode. It runs on the lint code (ReferenceTracker).

const svnusw_messages = {
	'unnecessaryStateWrap':   '{{className}} is already reactive, \$state wrapping is unnecessary.'
	'suggestRemoveStateWrap': 'Remove unnecessary \$state wrapping'
}

const svnusw_reactive_classes = ['SvelteSet', 'SvelteMap', 'SvelteURL', 'SvelteURLSearchParams',
	'SvelteDate', 'MediaQuery']

struct SvnuswOptions {
	additional_reactive_classes []string
	allow_reassign              bool
}

fn svnusw_options(options []json2.Any) !SvnuswOptions {
	o := option_object(svelte_no_unnecessary_state_wrap, options, [
		'additionalReactiveClasses',
		'allowReassign',
	])!
	return SvnuswOptions{
		additional_reactive_classes: o.string_list('additionalReactiveClasses')!
		allow_reassign:              o.bool_value('allowReassign')!
	}
}

// svnusw_is_state_call: a CallExpression whose callee is the Identifier `$state`.
fn svnusw_is_state_call(t &estree.EsTree, i int) bool {
	if i < 0 || t.typ(i) != .call_expression {
		return false
	}
	callee := t.node(i, .callee) or { return false }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == '\$state'
}

// svnusw_report is reportUnnecessaryStateWrap.
fn (mut c Checker) svnusw_report(root C.vt_node, t &estree.EsTree, o SvnuswOptions, state int, target int, class_name string, declarator int, mut findings []Finding) {
	id := t.node(declarator, .id) or { return }
	if o.allow_reassign {
		// getDeclaredVariables(declarator): any write but the declarator's own.
		tree := c.scope_tree(root)
		id_ts := t.ts_node(id) or { return }
		v := tree.declared_variable(id_ts)
		if v >= 0 && tree.variables[v].references.any(tree.references[it].write
			&& node_key(tree.references[it].identifier) != node_key(id_ts)) {
			return
		}
	}
	findings << Finding{
		stmt:        c.es_tree_position(t, target)
		message_id:  'unnecessaryStateWrap'
		data:        {
			'className': class_name
		}
		suggestions: [
			Suggestion{
				message_id: 'suggestRemoveStateWrap'
				fix:        fix_replace_range(t.nodes[state].start, t.nodes[state].end,
					c.src[t.nodes[target].start..t.nodes[target].end])
			},
		]
	}
}

// svnusw_declarator is the VariableDeclarator whose init is the `$state` call, with an Identifier
// id; -1 otherwise.
fn svnusw_declarator(t &estree.EsTree, state int) int {
	parent := t.nodes[state].parent
	if parent < 0 || t.typ(parent) != .variable_declarator {
		return -1
	}
	id := t.node(parent, .id) or { return -1 }
	return if t.typ(id) == .identifier { parent } else { -1 }
}

fn (mut c Checker) lint_svelte_no_unnecessary_state_wrap(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	o := svnusw_options(c.rule_options(svelte_no_unnecessary_state_wrap))!
	if !c.svsc_runes_on(abs_path) || !c.src.contains('\$state') {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut findings := []Finding{}
	if o.additional_reactive_classes.len > 0 {
		for i in 0 .. t.nodes.len {
			if i in t.foreign || !svnusw_is_state_call(t, i) {
				continue
			}
			for arg in t.list(i, .arguments) or { []int{} } {
				if arg < 0 || t.typ(arg) !in [.new_expression, .call_expression] {
					continue
				}
				callee := t.node(arg, .callee) or { continue }
				name := t.string_of(callee, .name) or { continue }
				if t.typ(callee) != .identifier || name !in o.additional_reactive_classes {
					continue
				}
				declarator := svnusw_declarator(t, i)
				if declarator >= 0 {
					c.svnusw_report(root, t, o, i, arg, name, declarator, mut findings)
				}
			}
		}
	}
	if c.src.contains('svelte/reactivity') {
		mut children := map[string]EsTrace{}
		for name in svnusw_reactive_classes {
			children[name] = EsTrace{
				call:      true
				construct: true
			}
		}
		for traced in c.es_esm_references(root, {
			'svelte/reactivity': EsTrace{
				esm:      true
				children: children
			}
		}) {
			node := c.es_index_of(t, traced.node) or { continue }
			state := t.nodes[node].parent
			if !svnusw_is_state_call(t, state) {
				continue
			}
			declarator := svnusw_declarator(t, state)
			if declarator >= 0 {
				c.svnusw_report(root, t, o, state, node, traced.path.last(), declarator, mut
					findings)
			}
		}
	}
	return c.svsc_moved(findings)
}
