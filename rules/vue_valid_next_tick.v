module rules

import estree
import time

// Port of the `vue/valid-next-tick` rule of eslint-plugin-vue 10.12.1 (no options): a
// `this.$nextTick`, `Vue.nextTick` or `nextTick` imported from `vue`, inside a Vue object, that
// is not called (fix: `()`), called without a callback and not awaited (suggestion: `await`),
// with more than one argument, or with a callback and awaited.

const vue_valid_next_tick_messages = {
	'shouldBeFunction':       '`nextTick` is a function.'
	'missingCallbackOrAwait': 'Await the Promise returned by `nextTick` or pass a callback function.'
	'addAwait':               'Add missing `await` statement.'
	'tooManyParameters':      '`nextTick` expects zero or one parameters.'
	'eitherAwaitOrCallback':  'Either await the Promise or pass a callback function to `nextTick`.'
}

fn (mut c Checker) lint_vue_valid_next_tick(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
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
		next_tick := c.vvnt_next_tick_node(root, t, node)
		if next_tick < 0 || t.nodes[next_tick].parent < 0 {
			continue
		}
		stats.checked++
		mut parent := t.nodes[next_tick].parent
		if t.typ(parent) == .conditional_expression {
			parent = t.nodes[parent].parent
		}
		if (t.typ(parent) == .call_expression && (t.node(parent, .callee) or { -1 }) != next_tick)
			|| t.typ(parent) in [.variable_declarator, .assignment_expression] {
			continue
		}
		if t.typ(parent) != .call_expression {
			findings << c.with_fixes(Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'shouldBeFunction'
			}, [fix_insert_at(t.nodes[node].end, '()')])!
			continue
		}
		args := (t.list(parent, .arguments) or { []int{} }).len
		if args == 0 {
			if !vvnt_is_awaited_promise(t, parent) {
				mut suggestions := []Suggestion{}
				ok, suggestion := c.suggestion('addAwait', {}, [
					fix_insert_at(t.nodes[parent].start, 'await '),
				])!
				if ok {
					suggestions << suggestion
				}
				findings << Finding{
					stmt:        c.es_tree_position(t, node)
					message_id:  'missingCallbackOrAwait'
					suggestions: suggestions
				}
			}
			continue
		}
		if args > 1 {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'tooManyParameters'
			}
			continue
		}
		if vvnt_is_awaited_promise(t, parent) {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'eitherAwaitOrCallback'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vvnt_next_tick_node is getVueNextTickNode: the member expression `this.$nextTick` or
// `Vue.nextTick` the identifier is in, or the identifier when it is the `nextTick` imported from
// `vue`; -1 for none.
fn (mut c Checker) vvnt_next_tick_node(root C.TSNode, t &estree.EsTree, id int) int {
	parent := t.nodes[id].parent
	if parent >= 0 && t.typ(parent) == .member_expression
		&& c.vnts_is_vue_next_tick_member(root, t, id, parent) {
		return parent
	}
	return if c.vnts_is_vue_next_tick_import(root, t, id) { id } else { -1 }
}

// vvnt_is_awaited_promise is valid-next-tick's isAwaitedPromise.
fn vvnt_is_awaited_promise(t &estree.EsTree, call int) bool {
	parent := t.nodes[call].parent
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.await_expression, .return_statement, .variable_declarator, .assignment_expression {
			return true
		}
		.arrow_function_expression {
			return (t.node(parent, .body) or { -1 }) == call
		}
		.member_expression {
			property := t.node(parent, .property) or { return false }
			return t.typ(property) == .identifier
				&& (t.string_of(property, .name) or { '' }) == 'then'
		}
		.array_expression {
			grand := t.nodes[parent].parent
			if grand < 0 || t.typ(grand) != .call_expression {
				return false
			}
			callee := t.node(grand, .callee) or { return false }
			if t.typ(callee) != .member_expression {
				return false
			}
			object := t.node(callee, .object) or { return false }
			property := t.node(callee, .property) or { return false }
			return t.typ(object) == .identifier
				&& (t.string_of(object, .name) or { '' }) == 'Promise'
				&& t.typ(property) == .identifier
		}
		else {
			return false
		}
	}
}
