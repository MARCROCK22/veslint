module rules

import time
import treesitter { node_start, position_of }

// Port of the `required-options-order` rule of @slipher/eslint-plugin 1.1.0 (it has no options): in
// the object of seyfert's `@Options`, an option made with a `createXOption` builder whose
// configuration has `required: true` after an optional one.

const sy_roo_messages = {
	'requiredAfterOptional': 'Required option `{{name}}` must be declared before optional options (Discord rejects required options placed after optional ones).'
}

fn (mut c Checker) lint_seyfert_required_options_order(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	decorators, callees, arguments := sy_option_decorators(c.nodes_of_kind(root, c'decorator'))
	mut asked := callees.clone()
	asked << arguments
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(callees)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, _ in decorators {
		if !c.sy_is_seyfert(c.sy_symbol_at(callees[i])!, 'Options')! {
			continue
		}
		argument_node := c.sy_node_at(arguments[i])!
		if !argument_node.exists() {
			continue
		}
		mut seen := map[string]bool{}
		options := c.sy_resolve_object_literal(argument_node, mut seen)!
		if !options.exists() {
			continue
		}
		mut saw_optional := false
		for property in options.list('properties') {
			if property.kind() != sy_kind_property_assignment {
				continue
			}
			mut value := sy_unwrap(property.child('initializer'))
			if value.kind() == sy_kind_identifier {
				initializer := c.sy_const_initializer(value)!
				if initializer.exists() {
					value = sy_unwrap(initializer)
				}
			}
			if c.sy_option_builder_name(value)! == '' || value.kind() != sy_kind_call_expression {
				continue
			}
			call_arguments_list := value.list('arguments')
			if call_arguments_list.len == 0 {
				continue
			}
			config := sy_unwrap(call_arguments_list[0])
			if config.kind() != sy_kind_object_literal_expression {
				continue
			}
			required_expression := sy_object_property(config, 'required')
			config_has_spread := config.list('properties').any(it.kind() == sy_kind_spread_assignment)
			mut required := 0 // 1 true, -1 false, 0 undefined
			if required_expression.exists() {
				if b := sy_boolean_literal_value(required_expression) {
					required = if b { 1 } else { -1 }
				}
			}
			if required == 1 {
				if saw_optional {
					place := c.sy_place_of(property) or { position_of(arguments[i]) }
					findings << Finding{
						stmt:       place
						message_id: 'requiredAfterOptional'
						data:       {
							'name': sy_property_name(property.child('name'))
						}
					}
				}
			} else if required == -1 || (!required_expression.exists() && !config_has_spread) {
				saw_optional = true
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += decorators.len
	return findings
}

// sy_option_decorators are the decorators that are calls with a first argument that is not a
// spread, with their callees and those arguments (without parentheses).
fn sy_option_decorators(all []C.TSNode) ([]C.TSNode, []C.TSNode, []C.TSNode) {
	mut decorators := []C.TSNode{}
	mut callees := []C.TSNode{}
	mut arguments := []C.TSNode{}
	for decorator in all {
		argument := sy_first_argument(decorator) or { continue }
		callee := sy_decorator_callee(decorator) or { continue }
		decorators << decorator
		callees << callee
		arguments << argument
	}
	return decorators, callees, arguments
}
