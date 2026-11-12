module rules

import time
import tsgo { TypeResponse }
import treesitter { position_of }

// Port of the `decorator-target` rule of @slipher/eslint-plugin 1.1.0 (it has no options):
// seyfert's `@Group` on a class that does not extend its SubCommand, and `@Groups`, `@GroupsT` and
// `@AutoLoad` on one that does not extend its Command.

const sy_dt_messages = {
	'wrongTarget': "`@{{decorator}}` can only be used on a class that extends seyfert's `{{base}}`."
}

// The decorators the rule checks, with the class they need (TARGETS).
const sy_dt_targets = {
	'Group':    'SubCommand'
	'Groups':   'Command'
	'GroupsT':  'Command'
	'AutoLoad': 'Command'
}

fn (mut c Checker) lint_seyfert_decorator_target(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			base := sy_dt_targets[name] or { continue }
			if super_type.is_null() || !c.sy_extends_class(super_type, [base])! {
				findings << Finding{
					stmt:       position_of(decorator)
					message_id: 'wrongTarget'
					data:       {
						'decorator': name
						'base':      base
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += classes.len
	return findings
}

// SyClass is a ClassDeclaration or a ClassExpression of the file with decorators: its decorators
// (ESTree's, those before its `export` included), the callee of each (none when it has no
// expression) and its superClass.
struct SyClass {
	node        C.TSNode
	decorators  []C.TSNode
	callees     []C.TSNode
	has_callee  []bool
	super_class C.TSNode
	has_super   bool
}

// sy_decorated_classes are the classes of the file that have decorators, and the nodes to request
// for them: the callees of the decorators and the superClass.
fn (c &Checker) sy_decorated_classes(root C.TSNode) ([]SyClass, []C.TSNode) {
	mut classes := []SyClass{}
	mut asked := []C.TSNode{}
	for node in c.nodes_of_kinds(root, ['class_declaration', 'abstract_class_declaration', 'class'],
		[]) {
		decorators := cm_class_decorators(node)
		if decorators.len == 0 {
			continue
		}
		mut callees := []C.TSNode{}
		mut has_callee := []bool{}
		for decorator in decorators {
			if callee := sy_decorator_callee(decorator) {
				callees << callee
				has_callee << true
				asked << callee
			} else {
				callees << decorator
				has_callee << false
			}
		}
		mut class := SyClass{
			node:       node
			decorators: decorators
			callees:    callees
			has_callee: has_callee
		}
		if value := cm_super_class(node) {
			class = SyClass{
				...class
				super_class: unwrap_parens(value)
				has_super:   true
			}
			asked << unwrap_parens(value)
		}
		classes << class
	}
	return classes, asked
}
