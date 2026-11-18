module rules

import estree
import json2
import time

// Port of the `vue/no-async-in-computed-properties` rule of eslint-plugin-vue 10.12.1 (option
// `ignoredObjectNames`): an async getter, `await`, Promise method, `new Promise`, timer or
// `nextTick` directly in the getter of a computed property of a Vue object or of a `computed(…)`
// (in a Vue object, or in `<script setup>` for a file that has it).

const vue_no_async_in_computed_properties_messages = {
	'unexpectedInFunction': 'Unexpected {{expressionName}} in computed function.'
	'unexpectedInProperty': 'Unexpected {{expressionName}} in "{{propertyName}}" computed property.'
}

const vnaicp_promise_functions = ['then', 'catch', 'finally']
const vnaicp_promise_methods = ['all', 'allSettled', 'any', 'race', 'reject', 'resolve', 'try',
	'withResolvers']
const vnaicp_timed_functions = ['setTimeout', 'setInterval', 'setImmediate', 'requestAnimationFrame']

fn vue_no_async_in_computed_properties_options(options []json2.Any) ![]string {
	o := option_object(vue_no_async_in_computed_properties, options, ['ignoredObjectNames'])!
	value := o.values['ignoredObjectNames'] or { return []string{} }
	if value !is []json2.Any {
		return error('`ignoredObjectNames` of `${vue_no_async_in_computed_properties}` must be a list')
	}
	mut out := []string{}
	for item in value as []json2.Any {
		if item !is string {
			return error('`ignoredObjectNames` of `${vue_no_async_in_computed_properties}` must be strings')
		}
		out << item as string
	}
	return out
}

fn (mut c Checker) lint_vue_no_async_in_computed_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignored := vue_no_async_in_computed_properties_options(c.rule_options(vue_no_async_in_computed_properties))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	setup_mode := s.has_setup
	if !setup_mode && s.objects.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut getters := []int{}
	for call in c.vaa_trace_map_calls(root, t, ['computed']) {
		getter := vue_getter_body_from_computed_function(t, call)
		if getter >= 0 {
			getters << getter
		}
	}
	mut computed := map[int][]VueComputedProperty{}
	if !setup_mode {
		for obj in s.objects {
			computed[obj] = vue_computed_properties(t, obj)
		}
	}
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		owner := s.owner_of(node)
		if setup_mode {
			if !s.in_script_setup(t, node) {
				continue
			}
		} else if owner < 0 {
			continue
		}
		mut kind := ''
		mut target_body := -1
		typ := t.typ(node)
		if typ in [.function_expression, .function_declaration, .arrow_function_expression] {
			if !(t.flag(node, .async) or { false }) {
				continue
			}
			kind = 'async function declaration'
			target_body = t.node(node, .body) or { continue }
		} else {
			if typ == .new_expression {
				callee := t.node(node, .callee) or { continue }
				if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != 'Promise' {
					continue
				}
				kind = 'Promise object'
			} else if typ == .call_expression {
				if vnaicp_is_promise(t, node, ignored) {
					kind = 'asynchronous action'
				} else if vnaicp_is_timed_function(t, node) {
					kind = 'timed function'
				} else if c.vnaicp_is_next_tick(root, t, node) {
					kind = 'asynchronous action'
				} else {
					continue
				}
			} else if typ == .await_expression {
				kind = 'await operator'
			} else {
				continue
			}
			f := vaa_innermost_function(t, node)
			if f < 0 {
				continue
			}
			target_body = t.node(f, .body) or { continue }
		}
		stats.checked++
		properties := if setup_mode { []VueComputedProperty{} } else { computed[owner] or {
				[]VueComputedProperty{}} }
		start_line, _ := t.line_column(t.nodes[node].start)
		end_line, _ := t.line_column(t.nodes[node].end)
		within := fn [t, start_line, end_line] (body int) bool {
			body_start, _ := t.line_column(t.nodes[body].start)
			body_end, _ := t.line_column(t.nodes[body].end)
			return start_line >= body_start && end_line <= body_end
		}
		mut reported := false
		for cp in properties {
			if cp.value >= 0 && cp.value == target_body && within(cp.value) {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'unexpectedInProperty'
					data:       {
						'expressionName': kind
						'propertyName':   if cp.has_key && cp.key != '' { cp.key } else { 'unknown' }
					}
				}
				reported = true
				break
			}
		}
		if reported {
			continue
		}
		for getter in getters {
			body := t.node(getter, .body) or { continue }
			if body == target_body && within(body) {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'unexpectedInFunction'
					data:       {
						'expressionName': kind
					}
				}
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnaicp_skip_wrapper is skipWrapper: through the nodes with an `expression` node.
fn vnaicp_skip_wrapper(t &estree.EsTree, node int) int {
	mut n := node
	for n >= 0 {
		if t.typ(n) == .arrow_function_expression && (t.flag(n, .expression) or { false }) {
			// `expression: true`: the walk ends on a boolean.
			return -1
		}
		next := t.node(n, .expression) or { return n }
		n = next
	}
	return n
}

// vnaicp_root_object_name is getRootObjectName ('' for null).
fn vnaicp_root_object_name(t &estree.EsTree, member int) string {
	mut current := vnaicp_skip_wrapper(t, t.node(member, .object) or { -1 })
	for current >= 0 {
		match t.typ(current) {
			.member_expression {
				current = vnaicp_skip_wrapper(t, t.node(current, .object) or { -1 })
			}
			.call_expression {
				callee := vnaicp_skip_wrapper(t, t.node(current, .callee) or { -1 })
				if callee >= 0 && t.typ(callee) == .member_expression {
					current = vnaicp_skip_wrapper(t, t.node(callee, .object) or { -1 })
				} else if callee >= 0 && t.typ(callee) == .identifier {
					return t.string_of(callee, .name) or { '' }
				} else {
					return ''
				}
			}
			.identifier {
				return t.string_of(current, .name) or { '' }
			}
			else {
				return ''
			}
		}
	}
	return ''
}

// vnaicp_is_promise is isPromise.
fn vnaicp_is_promise(t &estree.EsTree, node int, ignored []string) bool {
	callee := vue_skip_chain(t, t.node(node, .callee) or { return false })
	if t.typ(callee) != .member_expression {
		return false
	}
	name := vue_static_property_name(t, callee) or { return false }
	if name == '' {
		return false
	}
	object := t.node(callee, .object) or { return false }
	is_promise_method := name in vnaicp_promise_functions || (t.typ(object) == .identifier
		&& (t.string_of(object, .name) or { '' }) == 'Promise' && name in vnaicp_promise_methods)
	if !is_promise_method {
		return false
	}
	root_name := vnaicp_root_object_name(t, callee)
	return root_name == '' || root_name !in ignored
}

// vnaicp_is_timed_function is isTimedFunction.
fn vnaicp_is_timed_function(t &estree.EsTree, node int) bool {
	callee := vue_skip_chain(t, t.node(node, .callee) or { return false })
	if (t.list(node, .arguments) or { []int{} }).len == 0 {
		return false
	}
	if t.typ(callee) == .identifier {
		return (t.string_of(callee, .name) or { '' }) in vnaicp_timed_functions
	}
	if t.typ(callee) == .member_expression {
		object := t.node(callee, .object) or { return false }
		return t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == 'window'
			&& (vue_static_property_name(t, callee) or { '' }) in vnaicp_timed_functions
	}
	return false
}

// vnaicp_is_next_tick is isNextTick.
fn (mut c Checker) vnaicp_is_next_tick(root C.TSNode, t &estree.EsTree, node int) bool {
	callee := vue_skip_chain(t, t.node(node, .callee) or { return false })
	if t.typ(callee) != .member_expression {
		return false
	}
	name := vue_static_property_name(t, callee) or { '' }
	object := t.node(callee, .object) or { return false }
	return (c.vue_is_this(root, t, object) && name == '\$nextTick') || (t.typ(object) == .identifier
		&& (t.string_of(object, .name) or { '' }) == 'Vue' && name == 'nextTick')
}
