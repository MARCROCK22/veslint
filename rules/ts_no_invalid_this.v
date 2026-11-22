module rules

import json2
import treesitter { has_child_kind, named_children, node_field, node_kind, node_parent }

// Port of the `no-invalid-this` rule of typescript-eslint 8.72.2, which extends the rule of ESLint
// 10.15.0 with the same name (rules/no_invalid_this.v): `this` is also valid in a class property
// or accessor property (its key, decorators and value) and in a function with a `this` parameter.

const tsnit_messages = {
	'unexpectedThis': "Unexpected 'this'."
}

fn tsnit_options(options []json2.Any) !bool {
	o := option_object(ts_no_invalid_this, options, ['capIsConstructor'])!
	if 'capIsConstructor' in o.values {
		return o.bool_value('capIsConstructor')!
	}
	return true
}

fn (mut c Checker) lint_ts_no_invalid_this(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	return c.nith_lint(root, tsnit_options(c.rule_options(ts_no_invalid_this))!, true, mut stats)
}

// tsnit_this_is_valid_here is the top of the wrapper's thisIsValidStack at a ThisExpression: the
// closest AccessorProperty or PropertyDefinition (true), or FunctionDeclaration or
// FunctionExpression (whether it has a parameter `this`) around it; false without one.
fn tsnit_this_is_valid_here(this C.vt_node) bool {
	mut child := this
	mut current := node_parent(this) or { return false }
	for {
		match node_kind(current) {
			'public_field_definition' {
				// A TSAbstractPropertyDefinition or TSAbstractAccessorProperty is not one.
				if !has_child_kind(current, 'abstract') {
					return true
				}
			}
			'function_declaration', 'generator_function_declaration', 'function_expression',
			'generator_function' {
				return tsnit_has_this_parameter(current)
			}
			'method_definition' {
				// Its FunctionExpression: the type parameters, parameters, return type and body.
				if nith_in_method_function(current, child) {
					return tsnit_has_this_parameter(current)
				}
			}
			else {}
		}
		child = current
		current = node_parent(current) or { return false }
	}
	return false
}

fn tsnit_has_this_parameter(function C.vt_node) bool {
	parameters := node_field(function, 'parameters') or { return false }
	for p in named_children(parameters) {
		if pattern := node_field(p, 'pattern') {
			if node_kind(pattern) == 'this' {
				return true
			}
		}
	}
	return false
}
