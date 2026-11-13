module rules

import time
import treesitter { node_kind, node_start, position_of }

// Port of the `context-menu-declare` rule of @slipher/eslint-plugin 1.1.0 (it has no options): the
// `@Declare` of a class that extends seyfert's ContextMenuCommand must set `type` and must not set
// `description`.

const sy_cmd_messages = {
	'missingType':    "A context-menu command's `@Declare` must set `type: ApplicationCommandType.User` or `.Message`."
	'hasDescription': "A context-menu command's `@Declare` must not include a `description`."
}

fn (mut c Checker) lint_seyfert_context_menu_declare(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	classes, mut asked := c.sy_decorated_classes(root)
	// The first argument of each decorator that is a call: the one of `@Declare` is resolved.
	for class in classes {
		for decorator in class.decorators {
			if argument := sy_first_argument(decorator) {
				asked << argument
			}
		}
	}
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(asked)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for class in classes {
		if !class.has_super {
			continue
		}
		super_type := c.sy_instance_type(class.super_class)!
		if super_type.is_null() || !c.sy_extends_class(super_type, ['ContextMenuCommand'])! {
			continue
		}
		mut declare := -1
		for i in 0 .. class.decorators.len {
			if class.has_callee[i] && c.sy_is_seyfert(c.sy_symbol_at(class.callees[i])!, 'Declare')! {
				declare = i
				break
			}
		}
		if declare < 0 {
			continue
		}
		decorator := class.decorators[declare]
		argument := sy_first_argument(decorator) or { continue }
		argument_node := c.sy_node_at(argument)!
		if !argument_node.exists() {
			continue
		}
		mut seen := map[string]bool{}
		options := c.sy_resolve_object_literal(argument_node, mut seen)!
		if !options.exists() {
			continue
		}
		has_spread := options.list('properties').any(it.kind() == sy_kind_spread_assignment)
		if !has_spread && !sy_object_property(options, 'type').exists() {
			findings << Finding{
				stmt:       position_of(decorator)
				message_id: 'missingType'
			}
		}
		description := sy_object_property(options, 'description')
		if description.exists() {
			property := if description.parent().kind() == sy_kind_property_assignment {
				description.parent()
			} else {
				description
			}
			place := c.sy_place_of(property) or { position_of(decorator) }
			findings << Finding{
				stmt:       place
				message_id: 'hasDescription'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += classes.len
	return findings
}

// sy_first_argument is the first argument of the call a decorator is, without parentheses; none
// when the decorator is not a call, the call has no argument or it is a spread.
fn sy_first_argument(decorator C.TSNode) ?C.TSNode {
	call := sy_decorator_call(decorator)?
	arguments := call_arguments(call)?
	if arguments.len == 0 || node_kind(arguments[0]) == 'spread_element' {
		return none
	}
	return unwrap_parens(arguments[0])
}
