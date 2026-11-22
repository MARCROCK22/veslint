module rules

import estree
import time
import treesitter { node_end, node_start }

// Port of the `unicorn/no-thenable` rule of eslint-plugin-unicorn 79.0.0 (it has no options).

const unt_messages = {
	'no-thenable-object': 'Do not add `then` to an object.'
	'no-thenable-export': 'Do not export `then`.'
	'no-thenable-class':  'Do not add `then` to a class.'
}

fn (mut c Checker) lint_unicorn_no_thenable(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			// `{then() {}}`, `{get then() {}}`, `{[computedKey]() {}}`
			.object_expression {
				stats.checked++
				for property in t.list(node, .properties) or { []int{} } {
					if t.typ(property) == .property && c.unt_is_then_key(mut ctx, property) {
						findings << c.unt_finding(t, t.node(property, .key) or { continue }, 'no-thenable-object')
					}
				}
			}
			// `class Foo {then}`, `class Foo {get then() {}}`
			.property_definition, .method_definition {
				stats.checked++
				if c.unt_is_then_key(mut ctx, node) {
					findings << c.unt_finding(t, t.node(node, .key) or { continue }, 'no-thenable-class')
				}
			}
			// `foo.then = …`, `foo[computedKey] = …`
			.member_expression {
				stats.checked++
				parent := t.nodes[node].parent
				if parent >= 0 && t.typ(parent) == .assignment_expression
					&& (t.node(parent, .left) or { -1 }) == node && c.unt_is_then_key(mut ctx, node) {
					findings << c.unt_finding(t, t.node(node, .property) or { continue }, 'no-thenable-object')
				}
			}
			.call_expression {
				stats.checked++
				c.unt_call(mut ctx, node, mut findings)
			}
			.identifier {
				if (t.string_of(node, .name) or { '' }) != 'then' {
					continue
				}
				stats.checked++
				parent := t.nodes[node].parent
				if parent < 0 {
					continue
				}
				// `export {then}`
				if t.typ(parent) == .export_specifier && (t.node(parent, .exported) or { -1 }) == node {
					findings << c.unt_finding(t, node, 'no-thenable-export')
					continue
				}
				// `export function then() {}`, `export class then {}`
				if t.typ(parent) in [.function_declaration, .class_declaration]
					&& (t.node(parent, .id) or { -1 }) == node {
					grand := t.nodes[parent].parent
					if grand >= 0 && t.typ(grand) == .export_named_declaration
						&& (t.node(grand, .declaration) or { -1 }) == parent {
						findings << c.unt_finding(t, node, 'no-thenable-export')
					}
				}
			}
			// `export const … = …`
			.variable_declaration {
				stats.checked++
				parent := t.nodes[node].parent
				if parent < 0 || t.typ(parent) != .export_named_declaration
					|| (t.node(parent, .declaration) or { -1 }) != node {
					continue
				}
				c.unt_exported_variables(mut ctx, node, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) unt_finding(t &estree.EsTree, node int, message_id string) Finding {
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: message_id
	}
}

// unt_is_string_then ports isStringThen: the static value of the node is `'then'`.
fn (mut c Checker) unt_is_string_then(mut ctx UnCtx, node int) bool {
	value := c.un_static_value_for_control_flow(mut ctx, node) or { return false }
	return value.value.kind == .string_ && stv_units_string(value.value.units) == 'then'
}

// unt_is_then_key ports isThenKey: the key of a property, class member or member expression is
// `then`.
fn (mut c Checker) unt_is_then_key(mut ctx UnCtx, node int) bool {
	t := ctx.t
	key := if t.typ(node) == .member_expression {
		t.node(node, .property) or { return false }
	} else {
		t.node(node, .key) or { return false }
	}
	if t.typ(key) == .literal {
		value := t.get(key, .value)
		return value is string && value == 'then'
	}
	if !(t.flag(node, .computed) or { false }) && t.typ(key) == .identifier {
		return (t.string_of(key, .name) or { '' }) == 'then'
	}
	return c.unt_is_string_then(mut ctx, key)
}

// unt_call is the CallExpression listener: `Object.defineProperty(foo, 'then', …)` and
// `Object.fromEntries([['then', …]])`.
fn (mut c Checker) unt_call(mut ctx UnCtx, node int, mut findings []Finding) {
	t := ctx.t
	arguments := t.list(node, .arguments) or { return }
	if un_is_method_call(t, node,
		objects:           ['Object', 'Reflect']
		methods:           ['defineProperty']
		minimum_arguments: 3
		optional_call:     false
		optional_member:   false
	) && t.typ(arguments[0]) != .spread_element {
		if c.unt_is_string_then(mut ctx, arguments[1]) {
			findings << c.unt_finding(t, arguments[1], 'no-thenable-object')
		}
	}
	if !(un_is_method_call(t, node,
		objects:          ['Object']
		methods:          ['fromEntries']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) && t.typ(arguments[0]) == .array_expression) {
		return
	}
	for pair in t.list(arguments[0], .elements) or { []int{} } {
		if pair < 0 || t.typ(pair) != .array_expression {
			continue
		}
		elements := t.list(pair, .elements) or { continue }
		if elements.len == 0 || elements[0] < 0 || t.typ(elements[0]) == .spread_element {
			continue
		}
		if c.unt_is_string_then(mut ctx, elements[0]) {
			findings << c.unt_finding(t, elements[0], 'no-thenable-object')
		}
	}
}

// unt_exported_variables reports the identifiers of each variable named `then` that an exported
// declaration declares (getDeclaredVariables).
fn (mut c Checker) unt_exported_variables(mut ctx UnCtx, declaration int, mut findings []Finding) {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	ts := t.ts_node(declaration) or { return }
	mut seen := []int{}
	for v, variable in tree.variables {
		if variable.name != 'then' || v in seen {
			continue
		}
		if !variable.defs.any(it.kind == .variable && node_start(it.node) >= node_start(ts)
			&& node_end(it.node) <= node_end(ts)) {
			continue
		}
		seen << v
		for identifier in variable.identifiers {
			index := c.es_index_of(t, identifier) or { continue }
			findings << c.unt_finding(t, index, 'no-thenable-export')
		}
	}
}
