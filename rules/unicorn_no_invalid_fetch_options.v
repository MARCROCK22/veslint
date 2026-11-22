module rules

import time

// Port of the `unicorn/no-invalid-fetch-options` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options).

const unifo_messages = {
	'no-invalid-fetch-options': '"body" is not allowed when method is "{{method}}".'
}

fn (mut c Checker) lint_unicorn_no_invalid_fetch_options(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		is_target := match t.typ(node) {
			.call_expression {
				un_is_call(t, node, names: ['fetch'], minimum_arguments: 2, optional: false)
			}
			.new_expression {
				un_is_new(t, node, names: ['Request'], minimum_arguments: 2)
			}
			else {
				false
			}
		}
		if !is_target {
			continue
		}
		stats.checked++
		options := (t.list(node, .arguments) or { continue })[1]
		if f := c.unifo_problem(mut ctx, options) {
			findings << f
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unifo_is_property_named ports isObjectPropertyWithName: `'method'`, `['method']` and
// `` [`method`] `` are the same property.
fn (mut c Checker) unifo_is_property_named(ctx &UnCtx, property int, name string) bool {
	t := ctx.t
	if t.typ(property) != .property {
		return false
	}
	key := t.node(property, .key) or { return false }
	property_name := if t.flag(property, .computed) or { false } {
		c.un_string_if_constant(t, key) or { return false }
	} else if t.typ(key) == .literal {
		es_tree_static_string_value(t, key) or { return false }
	} else if t.typ(key) == .private_identifier {
		return false
	} else {
		t.string_of(key, .name) or { return false }
	}
	return property_name == name
}

// unifo_problem ports getFetchOptionsProblem.
fn (mut c Checker) unifo_problem(mut ctx UnCtx, from int) ?Finding {
	t := ctx.t
	// `as`, `satisfies` and `!` are erased at compile time: the object literal is what runs.
	node := un_unwrap_ts_expression(t, from)
	if node < 0 || t.typ(node) != .object_expression {
		return none
	}
	properties := t.list(node, .properties) or { return none }
	mut body := -1
	mut method_index := -1
	for i, property in properties {
		if c.unifo_is_property_named(ctx, property, 'body') {
			body = property
		}
		if c.unifo_is_property_named(ctx, property, 'method') {
			method_index = i
		}
	}
	if body < 0 {
		return none
	}
	body_value := t.node(body, .value)?
	// `void …` always evaluates to `undefined`: the body is effectively absent.
	if un_is_undefined(t, body_value) || c.unb_is_null_literal(t, body_value)
		|| (t.typ(body_value) == .unary_expression
		&& (t.string_of(body_value, .operator) or { '' }) == 'void') {
		return none
	}
	// A spread after `method` can replace it.
	for i, property in properties {
		if t.typ(property) == .spread_element && i > method_index {
			return none
		}
	}
	key := t.node(body, .key)?
	if method_index < 0 {
		return Finding{
			stmt:       c.es_tree_position(t, key)
			message_id: 'no-invalid-fetch-options'
			data:       {
				'method': 'GET'
			}
		}
	}
	method_value := t.node(properties[method_index], .value)?
	value := c.un_static_value_for_control_flow(mut ctx, method_value)?
	if value.value.kind != .string_ {
		return none
	}
	method := stv_units_string(value.value.units).to_upper()
	if method !in ['GET', 'HEAD'] {
		return none
	}
	return Finding{
		stmt:       c.es_tree_position(t, key)
		message_id: 'no-invalid-fetch-options'
		data:       {
			'method': method
		}
	}
}
