module rules

import time
import tsgo { TypeResponse }
import treesitter { position_of }

// Port of the `decorator-on-command` rule of @slipher/eslint-plugin 1.1.0 (it has no options):
// seyfert's `@Declare`, `@Options`, `@Locales` and `@LocalesT` on a class that does not extend one
// of its command bases, and `@Middlewares` on one that extends neither one of them nor one of its
// component bases.

const sy_doc_messages = {
	'onCommandOnly':            '`@{{decorator}}` can only be applied to a class that extends a seyfert command base (e.g. `Command`, `SubCommand`).'
	'onCommandOrComponentOnly': '`@{{decorator}}` can only be applied to a class that extends a seyfert command or component base (e.g. `Command`, `ComponentCommand`, `ModalCommand`).'
}

const sy_doc_command_decorators = ['Declare', 'Options', 'Middlewares', 'Locales', 'LocalesT']
const sy_doc_component_bases = ['ComponentCommand', 'ModalCommand']

fn (mut c Checker) lint_seyfert_decorator_on_command(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	classes, asked := c.sy_decorated_classes(root)
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(asked)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for class in classes {
		super_type := if class.has_super {
			c.sy_instance_type(class.super_class)!
		} else {
			TypeResponse{}
		}
		for i, decorator in class.decorators {
			if !class.has_callee[i] {
				continue
			}
			callee := class.callees[i]
			name := c.sy_export_name(c.sy_symbol_at(callee)!)!
			if name !in sy_doc_command_decorators {
				continue
			}
			middlewares := name == 'Middlewares'
			if !super_type.is_null() && (c.sy_extends_class(super_type, sy_command_bases)!
				|| (middlewares && c.sy_extends_class(super_type, sy_doc_component_bases)!)) {
				continue
			}
			findings << Finding{
				stmt:       position_of(decorator)
				message_id: if middlewares { 'onCommandOrComponentOnly' } else { 'onCommandOnly' }
				data:       {
					'decorator': name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += classes.len
	return findings
}
