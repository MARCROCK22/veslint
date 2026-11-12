module rules

import time
import treesitter { node_start }

// Port of the `declare-description` rule of @slipher/eslint-plugin 1.1.0 (it has no options): the
// literal `description` of the `@Declare` of a class that extends seyfert's Command or SubCommand,
// and of the configuration of a `createXOption` builder, must not be empty nor longer than 100
// characters.

const sy_dd_messages = {
	'emptyDescription':   '{{what}} description must not be empty.'
	'descriptionTooLong': '{{what}} description must be at most 100 characters (got {{length}}).'
}

const sy_dd_max_description = 100

fn (mut c Checker) lint_seyfert_declare_description(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// The decorators of classes that are calls with a first argument (Decorator), and every call
	// that is not a tagged template (CallExpression).
	mut decorators := []C.TSNode{}
	mut callees := []C.TSNode{}
	mut arguments := []C.TSNode{}
	mut supers := []C.TSNode{}
	mut asked := []C.TSNode{}
	for decorator in c.nodes_of_kind(root, c'decorator') {
		class := sy_class_of_decorator(decorator) or { continue }
		callee := sy_decorator_callee(decorator) or { continue }
		sy_decorator_call(decorator) or { continue }
		decorators << decorator
		callees << callee
		asked << callee
		argument := sy_first_argument(decorator) or { decorator }
		arguments << argument
		if node_key(argument) != node_key(decorator) {
			asked << argument
		}
		super_class := unwrap_parens(cm_super_class(class) or { decorator })
		supers << super_class
		if node_key(super_class) != node_key(decorator) {
			asked << super_class
		}
	}
	mut calls := []C.TSNode{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		call_arguments(call) or { continue }
		calls << call
	}
	asked << calls
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(callees)!
	c.sy_prefetch_symbols(supers)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, decorator in decorators {
		if !c.sy_is_seyfert(c.sy_symbol_at(callees[i])!, 'Declare')! {
			continue
		}
		if node_key(supers[i]) == node_key(decorator) {
			continue
		}
		super_type := c.sy_instance_type(supers[i])!
		if super_type.is_null() || !c.sy_extends_class(super_type, ['Command', 'SubCommand'])! {
			continue
		}
		if node_key(arguments[i]) == node_key(decorator) {
			continue
		}
		argument_node := c.sy_node_at(arguments[i])!
		if !argument_node.exists() {
			continue
		}
		mut seen := map[string]bool{}
		object := c.sy_resolve_object_literal(argument_node, mut seen)!
		if object.exists() {
			c.sy_dd_check_description(object, 'Command', node_start(arguments[i]), mut findings)
		}
	}
	for call in calls {
		ts_call := c.sy_node_at(call)!
		if ts_call.kind() != sy_kind_call_expression || c.sy_option_builder_name(ts_call)! == '' {
			continue
		}
		call_arguments_list := ts_call.list('arguments')
		if call_arguments_list.len == 0 {
			continue
		}
		mut seen := map[string]bool{}
		object := c.sy_resolve_object_literal(call_arguments_list[0], mut seen)!
		if object.exists() {
			c.sy_dd_check_description(object, 'Option', node_start(call), mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += decorators.len + calls.len
	return findings
}

// sy_dd_check_description ports checkDescription: a literal description that is empty or longer
// than 100 code points is reported where ESLint has its node, or else at `fallback`.
fn (c &Checker) sy_dd_check_description(object SyNode, what string, fallback int, mut findings []Finding) {
	description := sy_object_property(object, 'description')
	if !description.exists() {
		return
	}
	value := sy_string_literal_value(description) or { return }
	length := value.runes().len
	if value != '' && length <= sy_dd_max_description {
		return
	}
	offset := c.sy_position_of(description) or { fallback }
	findings << if value == '' {
		Finding{
			stmt:       c.position_at(offset)
			message_id: 'emptyDescription'
			data:       {
				'what': what
			}
		}
	} else {
		Finding{
			stmt:       c.position_at(offset)
			message_id: 'descriptionTooLong'
			data:       {
				'what':   what
				'length': length.str()
			}
		}
	}
}
