module rules

import time
import treesitter { node_start }

// Port of the `options-use-builders` rule of @slipher/eslint-plugin 1.1.0 (it has no options): in
// the object of seyfert's `@Options` (through `const` bindings, imports and spreads), a value that
// is not made with a seyfert `createXOption` builder.

const sy_oub_messages = {
	'useBuilder': "Option '{{name}}' must be created with a seyfert `createXOption` builder (e.g. `createStringOption`)."
}

// SyViolation is an option that is not made with a builder (Violation): the node to report and
// its name.
struct SyViolation {
	node SyNode
	name string
}

fn (mut c Checker) lint_seyfert_options_use_builders(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
		mut resolve_seen := map[string]bool{}
		options := c.sy_resolve_object_literal(argument_node, mut resolve_seen)!
		if !options.exists() {
			continue
		}
		mut violations := []SyViolation{}
		mut seen := map[string]bool{}
		c.sy_oub_check_object(options, options, mut seen, mut violations)!
		for violation in violations {
			offset := c.sy_position_of(violation.node) or { node_start(arguments[i]) }
			findings << Finding{
				stmt:       c.position_at(offset)
				message_id: 'useBuilder'
				data:       {
					'name': violation.name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += decorators.len
	return findings
}

// sy_oub_check_value ports checkValue: a value is a builder's call, or an identifier whose `const`
// is one; otherwise it is a violation.
fn (mut c Checker) sy_oub_check_value(value SyNode, name string, mut seen map[string]bool, mut violations []SyViolation) ! {
	expression := sy_unwrap(value)
	if c.sy_option_builder_name(expression)! != '' {
		return
	}
	if expression.kind() == sy_kind_identifier && expression.handle() !in seen {
		seen[expression.handle()] = true
		initializer := c.sy_const_initializer(expression)!
		if initializer.exists() {
			c.sy_oub_check_value(initializer, name, mut seen, mut violations)!
			return
		}
	}
	violations << SyViolation{
		node: value
		name: name
	}
}

// sy_oub_check_object ports checkObject: every property of the object, and of the objects it
// spreads.
fn (mut c Checker) sy_oub_check_object(object SyNode, root SyNode, mut seen map[string]bool, mut violations []SyViolation) ! {
	key := object.handle()
	if key in seen && key != root.handle() {
		return
	}
	seen[key] = true
	for property in object.list('properties') {
		match property.kind() {
			sy_kind_property_assignment {
				c.sy_oub_check_value(property.child('initializer'), sy_property_name(property.child('name')), mut
					seen, mut violations)!
			}
			sy_kind_shorthand_property_assignment {
				name := property.child('name').text()
				value_symbol := c.client.shorthand_assignment_value_symbol(c.snapshot, c.project,
					property.handle())!
				initializer := c.sy_symbol_const_initializer(value_symbol)!
				if initializer.exists() {
					c.sy_oub_check_value(initializer, name, mut seen, mut violations)!
				} else {
					violations << SyViolation{
						node: property
						name: name
					}
				}
			}
			sy_kind_spread_assignment {
				spread := c.sy_resolve_object_literal(property.child('expression'), mut seen)!
				if spread.exists() {
					c.sy_oub_check_object(spread, root, mut seen, mut violations)!
				}
			}
			else {
				violations << SyViolation{
					node: property
					name: sy_property_name(property.child('name'))
				}
			}
		}
	}
}
