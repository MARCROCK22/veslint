module rules

import estree
import time

// Port of the `unicorn/custom-error-definition` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes. Some of its reports have a message of their own and no messageId.

const ucedf_messages = {
	'invalidExport':                   'Exported error name should match error class'
	'doNotPassMessageToSuper':         'Do not pass the error message to `super()` when the class defines a `message` accessor.'
	'doNotAssignMessageWithoutSetter': 'Do not assign to `this.message` when the class defines a `message` getter without a setter.'
	'missingOptionsParameter':         'Error constructors should accept an `options` parameter.'
	'invalidOptionsParameter':         'Error constructors should use a non-rest parameter named `options`.'
	'passMessageToSuper':              'Pass the error message to `super()` as the first argument.'
	'passOptionsToSuper':              'Pass `options` to `super()` as the second argument.'
}

// ucedf_class_name ports getClassName: the name in upper first, ending in `Error`.
fn ucedf_class_name(name string) string {
	if name == '' {
		return 'Error'
	}
	upper := name[..1].to_upper() + name[1..]
	if upper.to_lower().ends_with('error') {
		return upper[..upper.len - 5] + 'Error'
	}
	return upper + 'Error'
}

// ucedf_super_class_name ports getSuperClassName: `Foo` or the property of `a.Foo`.
fn ucedf_super_class_name(t &estree.EsTree, super_class int) ?string {
	if super_class < 0 {
		return none
	}
	if t.typ(super_class) == .identifier {
		return t.string_of(super_class, .name)
	}
	if t.typ(super_class) == .member_expression && !(t.flag(super_class, .computed) or { false }) {
		property := t.node(super_class, .property)?
		if t.typ(property) == .identifier {
			return t.string_of(property, .name)
		}
	}
	return none
}

// ucedf_valid_super_class ports hasValidSuperClass.
fn ucedf_valid_super_class(t &estree.EsTree, node int) bool {
	super_class := un_unwrap_ts_expression(t, t.node(node, .super_class) or { return false })
	name := ucedf_super_class_name(t, super_class) or { return false }
	return name != '' && utne_is_error_name(name)
}

// ucedf_native_base_with_options ports isNativeErrorBaseWithStandardOptions: a built-in error
// that takes `ErrorOptions` as its second argument (not AggregateError or SuppressedError),
// directly or through `globalThis`.
fn ucedf_native_base_with_options(t &estree.EsTree, node int) bool {
	super_class := un_unwrap_ts_expression(t, t.node(node, .super_class) or { return false })
	name := ucedf_super_class_name(t, super_class) or { return false }
	return name in un_builtin_errors && name !in ['AggregateError', 'SuppressedError']
		&& (t.typ(super_class) == .identifier
		|| un_node_matches_name_or_path(t, super_class, 'globalThis.${name}'))
}

// ucedf_is_super ports isSuperExpression.
fn ucedf_is_super(t &estree.EsTree, node int) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	expression := t.node(node, .expression) or { return false }
	return t.typ(expression) == .call_expression
		&& un_node_matches_name_or_path(t, t.node(expression, .callee) or { return false }, 'super')
}

// ucedf_is_assignment ports isAssignmentExpression: `this.<name> = …`.
fn ucedf_is_assignment(t &estree.EsTree, node int, name string) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	expression := t.node(node, .expression) or { return false }
	return t.typ(expression) == .assignment_expression
		&& (t.string_of(expression, .operator) or { '' }) == '='
		&& un_node_matches_name_or_path(t, t.node(expression, .left) or { return false }, 'this.${name}')
}

// ucedf_is_name_property ports isPropertyDefinition(node, 'name'): an instance field `name`.
fn ucedf_is_name_property(t &estree.EsTree, node int) bool {
	if t.typ(node) != .property_definition || (t.flag(node, .static_) or { false })
		|| (t.flag(node, .computed) or { false }) {
		return false
	}
	key := t.node(node, .key) or { return false }
	return t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == 'name'
}

// ucedf_valid_name_property ports isValidNameProperty: `name = '<class name>'`.
fn ucedf_valid_name_property(t &estree.EsTree, property int, class_name string) bool {
	if property < 0 {
		return false
	}
	value := t.node(property, .value) or { return false }
	return (un_static_string_value(t, un_unwrap_ts_expression(t, value)) or { return false }) == class_name
}

// ucedf_is_message_accessor ports isMessageAccessor: an instance `get message()` or
// `set message()`.
fn ucedf_is_message_accessor(t &estree.EsTree, node int, kind string) bool {
	if t.typ(node) != .method_definition || (t.string_of(node, .kind) or { '' }) != kind
		|| (t.flag(node, .static_) or { false }) || (t.flag(node, .computed) or { false }) {
		return false
	}
	key := t.node(node, .key) or { return false }
	return t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == 'message'
}

// ucedf_is_missing_or_undefined ports isMissingOrUndefined.
fn ucedf_is_missing_or_undefined(t &estree.EsTree, node int) bool {
	return node < 0 || un_is_undefined(t, un_unwrap_ts_expression(t, node))
}

// ucedf_parameter_identifier ports getParameterIdentifier: the identifier of `a`, `a = …` or a
// parameter property; -1 for anything else.
fn ucedf_parameter_identifier(t &estree.EsTree, parameter int) int {
	if parameter < 0 {
		return -1
	}
	match t.typ(parameter) {
		.ts_parameter_property {
			return ucedf_parameter_identifier(t, t.node(parameter, .parameter) or { -1 })
		}
		.identifier {
			return parameter
		}
		.assignment_pattern {
			left := t.node(parameter, .left) or { return -1 }
			return if t.typ(left) == .identifier { left } else { -1 }
		}
		else {
			return -1
		}
	}
}

fn ucedf_name(t &estree.EsTree, node int) string {
	return if node < 0 { '' } else { t.string_of(node, .name) or { '' } }
}

// ucedf_is_options ports isOptionsIdentifier.
fn ucedf_is_options(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	return ucedf_name(t, ucedf_parameter_identifier(t, un_unwrap_ts_expression(t, node))) == 'options'
}

// ucedf_comment_right_after ports hasCommentImmediatelyAfter.
fn ucedf_comment_right_after(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	after := tokens.after(t.nodes[node].end, true) or { return false }
	return after.is_comment()
}

// ucedf_has_this_or_super ports hasThisOrSuper.
fn ucedf_has_this_or_super(t &estree.EsTree, node int) bool {
	if t.typ(node) in [.this_expression, .super] {
		return true
	}
	return t.children(node).any(ucedf_has_this_or_super(t, it))
}

// ucedf_options_parameter_text ports getOptionsParameterText.
fn ucedf_options_parameter_text(t &estree.EsTree, first int) string {
	identifier := ucedf_parameter_identifier(t, first)
	if identifier < 0 || t.node(identifier, .type_annotation) == none {
		return 'options'
	}
	return if t.flag(identifier, .optional) or { false } {
		'options?: ErrorOptions'
	} else {
		'options: ErrorOptions'
	}
}

// ucedf_is_same_identifier ports isSameIdentifier.
fn ucedf_is_same_identifier(t &estree.EsTree, from int, identifier int) bool {
	if from < 0 || identifier < 0 {
		return false
	}
	node := un_unwrap_ts_expression(t, from)
	return node >= 0 && t.typ(node) == .identifier && ucedf_name(t, node) == ucedf_name(t, identifier)
}

// ucedf_super_argument is an argument of the call of a `super()` statement, -1 if it has none.
fn ucedf_super_argument(t &estree.EsTree, statement int, i int) int {
	call := t.node(statement, .expression) or { return -1 }
	return ucedf_argument(t.list(call, .arguments) or { []int{} }, i)
}

fn ucedf_argument(args []int, i int) int {
	return if i < args.len { args[i] } else { -1 }
}

// ucedf_opening_paren is the `(` of the arguments of the `super()` call.
fn (c &Checker) ucedf_opening_paren(t &estree.EsTree, tokens &SourceTokens, call int) ?SourceToken {
	callee := t.node(call, .callee)?
	return c.un_token_after_punctuator(tokens, t.nodes[callee].end, '(')
}

// ucedf_super_options_fix ports fixSuperOptionsArgument; none when it does not fix.
fn (c &Checker) ucedf_super_options_fix(t &estree.EsTree, tokens &SourceTokens, call int, message_text string) ?Fix {
	if tokens.comments_inside(t.nodes[call].start, t.nodes[call].end).len > 0 {
		return none
	}
	args := t.list(call, .arguments) or { []int{} }
	if args.len == 0 {
		opening := c.ucedf_opening_paren(t, tokens, call)?
		return fix_insert_at(opening.end, '${message_text}, options')
	}
	if args.len != 1 || c.un_is_parenthesized(t, tokens, args[0]) {
		return none
	}
	if message_text != 'undefined' && ucedf_is_missing_or_undefined(t, args[0]) {
		return fix_replace_range(t.nodes[args[0]].start, t.nodes[args[0]].end, '${message_text}, options')
	}
	return fix_insert_at(t.nodes[args[0]].end, ', options')
}

// ucedf_super_message_fix ports fixSuperMessageArgument; none when it does not fix.
fn (c &Checker) ucedf_super_message_fix(t &estree.EsTree, tokens &SourceTokens, call int, message_text string) ?Fix {
	if tokens.comments_inside(t.nodes[call].start, t.nodes[call].end).len > 0 {
		return none
	}
	args := t.list(call, .arguments) or { []int{} }
	if args.len == 0 {
		opening := c.ucedf_opening_paren(t, tokens, call)?
		return fix_insert_at(opening.end, '${message_text}, options')
	}
	if !ucedf_is_missing_or_undefined(t, args[0]) || c.un_is_parenthesized(t, tokens, args[0]) {
		return none
	}
	return fix_replace_range(t.nodes[args[0]].start, t.nodes[args[0]].end, if args.len == 1 {
		'${message_text}, options'
	} else {
		message_text
	})
}

// ucedf_has_inline_options ports hasInlineErrorOptions: `super()` already forwards the error
// options inline, as `super('Fixed message', {cause})`.
fn (mut c Checker) ucedf_has_inline_options(t &estree.EsTree, call int, options_parameter int) bool {
	args := t.list(call, .arguments) or { []int{} }
	if args.len != 2 {
		return false
	}
	options_argument := un_unwrap_ts_expression(t, args[1])
	if t.typ(options_argument) != .object_expression {
		return false
	}
	properties := t.list(options_argument, .properties) or { []int{} }
	if properties.len != 1 || (c.un_property_name(t, properties[0]) or { return false }) != 'cause' {
		return false
	}
	// A dedicated `options` parameter is only unneeded when `super()` already forwards its
	// `cause`.
	if options_parameter >= 0 {
		mut cause := un_unwrap_ts_expression(t, t.node(properties[0], .value) or { return false })
		if t.typ(cause) == .chain_expression {
			cause = t.node(cause, .expression) or { return false }
		}
		return un_is_member(t, cause,
			properties: ['cause']
			objects:    [ucedf_name(t, ucedf_parameter_identifier(t, options_parameter))]
		)
	}
	// Without one, a fixed message plus an inline cause needs no parameter either.
	return un_static_string_value(t, un_unwrap_ts_expression(t, args[0])) != none
}

// ucedf_options_problem ports getErrorOptionsProblem.
fn (mut c Checker) ucedf_options_problem(t &estree.EsTree, tokens &SourceTokens, constructor int, super_statement int, has_message_accessor bool) ?Finding {
	value := t.node(constructor, .value) or { return none }
	parameters := t.list(value, .params) or { []int{} }
	if parameters.len == 0 {
		return none
	}
	first := parameters[0]
	first_identifier := ucedf_parameter_identifier(t, first)
	if first_identifier < 0 {
		return none
	}
	call := t.node(super_statement, .expression) or { return none }
	args := t.list(call, .arguments) or { []int{} }
	mut options_parameter := -1
	for parameter in parameters {
		if ucedf_is_options(t, parameter) {
			options_parameter = parameter
			break
		}
	}
	if options_parameter == first {
		if !ucedf_is_options(t, ucedf_argument(args, 1)) {
			mut finding := Finding{
				stmt:       c.es_tree_position(t, call)
				message_id: 'passOptionsToSuper'
			}
			if !ucedf_is_same_identifier(t, ucedf_argument(args, 0), first_identifier) {
				if fix := c.ucedf_super_options_fix(t, tokens, call, 'undefined') {
					finding = Finding{
						...finding
						has_fix: true
						fix:     fix
					}
				}
			}
			return finding
		}
		return none
	}
	// When `super()` already forwards the options inline, a dedicated `options` parameter is not
	// needed; the message is still checked.
	has_inline_options := c.ucedf_has_inline_options(t, call, options_parameter)
	if has_inline_options && options_parameter < 0 {
		return none
	}
	pass_message := !has_message_accessor && ucedf_name(t, first_identifier) == 'message'
	message_text := if pass_message { ucedf_name(t, first_identifier) } else { 'undefined' }
	if parameters.len < 2 {
		mut finding := Finding{
			stmt:       c.es_tree_position(t, first)
			message_id: 'missingOptionsParameter'
		}
		// fixMissingOptionsParameter
		if !ucedf_comment_right_after(t, tokens, first) {
			if super_fix := c.ucedf_super_options_fix(t, tokens, call, message_text) {
				has_fix, fix := c.merge_fixes([
					fix_insert_at(t.nodes[first].end, ', ${ucedf_options_parameter_text(t, first)}'),
					super_fix,
				]) or { return none }
				finding = Finding{
					...finding
					has_fix: has_fix
					fix:     fix
				}
			}
		}
		return finding
	}
	if options_parameter < 0 {
		key := t.node(constructor, .key) or { constructor }
		return Finding{
			stmt:       c.es_tree_position(t, key)
			message_id: 'invalidOptionsParameter'
		}
	}
	if pass_message && !ucedf_is_same_identifier(t, ucedf_argument(args, 0), first_identifier) {
		mut finding := Finding{
			stmt:       c.es_tree_position(t, call)
			message_id: 'passMessageToSuper'
		}
		if fix := c.ucedf_super_message_fix(t, tokens, call, message_text) {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		}
		return finding
	}
	if has_inline_options || ucedf_is_options(t, ucedf_argument(args, 1)) {
		return none
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, call)
		message_id: 'passOptionsToSuper'
	}
	if !ucedf_is_same_identifier(t, ucedf_argument(args, 0), ucedf_parameter_identifier(t,
		options_parameter))
	{
		if fix := c.ucedf_super_options_fix(t, tokens, call, message_text) {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		}
	}
	return finding
}

// ucedf_has_body: the constructor has a body (an overload has none).
fn ucedf_has_body(t &estree.EsTree, constructor int) bool {
	value := t.node(constructor, .value) or { return false }
	return t.node(value, .body) != none
}

fn ucedf_name_error(c &Checker, t &estree.EsTree, node int, name string) Finding {
	return Finding{
		stmt: c.es_tree_position(t, node)
		text: 'The `name` property should be set to `${name}`.'
	}
}

// ucedf_name_property_text ports getNameProperty: the name field inserted right after the `{` of
// the class body, with the line ending of the file and the indentation of the members.
fn (c &Checker) ucedf_name_property_text(t &estree.EsTree, tokens &SourceTokens, class_name string, class int) string {
	linebreak := un_linebreak(c.src)
	class_body := t.node(class, .body) or { return '' }
	members := t.list(class_body, .body) or { []int{} }
	indent := if members.len > 0 {
		c.un_line_indent(t.nodes[members[0]].start)
	} else {
		c.un_line_indent(t.nodes[class].start) + c.un_indent_unit(t, tokens)
	}
	has_own_line_break := c.src[t.nodes[class_body].start + 1..].starts_with(linebreak)
	return "${linebreak}${indent}name = '${class_name}';" + if has_own_line_break {
		''
	} else {
		linebreak + c.un_line_indent(t.nodes[class].start)
	}
}

fn (mut c Checker) lint_unicorn_custom_error_definition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.class_declaration {
				stats.checked++
				findings << c.ucedf_definition(t, tokens, node)!
			}
			.assignment_expression {
				stats.checked++
				right := t.node(node, .right) or { continue }
				if t.typ(right) == .class_expression {
					findings << c.ucedf_definition(t, tokens, right)!
				}
				left := t.node(node, .left) or { continue }
				if t.typ(left) == .member_expression {
					object := t.node(left, .object) or { continue }
					if t.typ(object) == .identifier
						&& (t.string_of(object, .name) or { '' }) == 'exports' {
						if finding := c.ucedf_export(t, node) {
							findings << finding
						}
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ucedf_definition ports customErrorDefinition.
fn (mut c Checker) ucedf_definition(t &estree.EsTree, tokens &SourceTokens, node int) ![]Finding {
	mut out := []Finding{}
	if (t.flag(node, .abstract_) or { false }) || !ucedf_valid_super_class(t, node) {
		return out
	}
	id := t.node(node, .id) or { return out }
	name := t.string_of(id, .name) or { return out }
	class_name := ucedf_class_name(name)
	if name != class_name {
		out << Finding{
			stmt: c.es_tree_position(t, id)
			text: 'Invalid class name, use `${class_name}`.'
		}
	}
	class_body := t.node(node, .body) or { return out }
	body := t.list(class_body, .body) or { []int{} }
	constructors := body.filter((t.string_of(it, .kind) or { '' }) == 'constructor')
	with_body := constructors.filter(ucedf_has_body(t, it))
	constructor := if with_body.len > 0 {
		with_body[0]
	} else if constructors.len > 0 {
		constructors[0]
	} else {
		-1
	}
	properties := body.filter(ucedf_is_name_property(t, it))
	name_property := if properties.len > 0 { properties[0] } else { -1 }
	if constructor < 0 {
		if ucedf_valid_name_property(t, name_property, name) {
			return out
		}
		value := if name_property >= 0 { t.node(name_property, .value) or { -1 } } else { -1 }
		at := if value >= 0 { value } else { node }
		mut finding := ucedf_name_error(c, t, at, name)
		mut fix := ?Fix(none)
		if value >= 0 {
			unwrapped := un_unwrap_ts_expression(t, value)
			if un_static_string_value(t, unwrapped) != none {
				fix = fix_replace_range(t.nodes[unwrapped].start, t.nodes[unwrapped].end, "'${name}'")
			} else if tokens.comments_inside(t.nodes[value].start, t.nodes[value].end).len == 0 {
				fix = fix_replace_range(t.nodes[value].start, t.nodes[value].end, "'${name}'")
			}
		} else if name_property >= 0 {
			fix = fix_replace_range(t.nodes[name_property].start, t.nodes[name_property].end,
				c.ucedf_name_property_text(t, tokens, name, node).trim_space())
		} else {
			fix = fix_insert_at(t.nodes[class_body].start + 1, c.ucedf_name_property_text(t,
				tokens, name, node))
		}
		if f := fix {
			finding = Finding{
				...finding
				has_fix: true
				fix:     f
			}
		}
		out << finding
		return out
	}
	has_getter := body.any(ucedf_is_message_accessor(t, it, 'get'))
	has_setter := body.any(ucedf_is_message_accessor(t, it, 'set'))
	check_options := name == class_name && ucedf_native_base_with_options(t, node)
	out << c.ucedf_constructor_body(t, tokens, constructor, name, name_property, has_getter,
		has_setter, check_options)!
	return out
}

// ucedf_constructor_body ports getConstructorBodyProblems.
fn (mut c Checker) ucedf_constructor_body(t &estree.EsTree, tokens &SourceTokens, constructor int, name string, name_property int, has_getter bool, has_setter bool, check_options bool) ![]Finding {
	mut out := []Finding{}
	value := t.node(constructor, .value) or { return out }
	// A constructor without a body (TypeScript).
	block := t.node(value, .body) or { return out }
	statements := t.list(block, .body) or { []int{} }
	mut super_index := -1
	mut message_index := -1
	for i, statement in statements {
		if super_index < 0 && ucedf_is_super(t, statement) {
			super_index = i
		}
		if message_index < 0 && ucedf_is_assignment(t, statement, 'message') {
			message_index = i
		}
	}
	has_accessor := has_getter || has_setter
	mut has_body_problem := false
	if super_index < 0 {
		has_body_problem = true
		out << Finding{
			stmt: c.es_tree_position(t, block)
			text: 'Missing call to `super()` in constructor.'
		}
	} else if has_accessor && !ucedf_is_missing_or_undefined(t, ucedf_super_argument(t,
		statements[super_index], 0)) {
		has_body_problem = true
		out << Finding{
			stmt:       c.es_tree_position(t, statements[super_index])
			message_id: 'doNotPassMessageToSuper'
		}
	} else if has_getter && !has_setter && message_index >= 0 {
		has_body_problem = true
		out << Finding{
			stmt:       c.es_tree_position(t, statements[message_index])
			message_id: 'doNotAssignMessageWithoutSetter'
		}
	} else if !has_setter && message_index >= 0 {
		has_body_problem = true
		super_statement := statements[super_index]
		fixes := c.ucedf_message_fix(t, tokens, value, statements, super_index, message_index)
		has_fix, fix := c.merge_fixes(fixes)!
		out << Finding{
			stmt:    c.es_tree_position(t, super_statement)
			text:    'Pass the error message to `super()` instead of setting `this.message`.'
			has_fix: has_fix
			fix:     fix
		}
	}
	// getInvalidErrorNameProblem
	mut has_valid_name := true
	mut name_assignment := -1
	for statement in statements {
		if ucedf_is_assignment(t, statement, 'name') {
			name_assignment = statement
			break
		}
	}
	if name_assignment < 0 {
		if !ucedf_valid_name_property(t, name_property, name) {
			value_node := if name_property >= 0 {
				t.node(name_property, .value) or { block }
			} else {
				block
			}
			has_valid_name = false
			out << ucedf_name_error(c, t, value_node, name)
		}
	} else {
		right := t.node(t.node(name_assignment, .expression) or { return out }, .right) or {
			return out
		}
		value_name := un_static_string_value(t, un_unwrap_ts_expression(t, right))
		if value_name == none || (value_name or { '' }) != name {
			has_valid_name = false
			out << ucedf_name_error(c, t, right, name)
		}
	}
	if !has_valid_name || !check_options || has_body_problem {
		return out
	}
	if problem := c.ucedf_options_problem(t, tokens, constructor, statements[super_index],
		has_accessor)
	{
		out << problem
	}
	return out
}

// ucedf_message_fix is the fix of the `this.message = …` problem: the message goes to `super()`
// (with `options` when the constructor gets that parameter) and the assignment goes away; [] when
// it does not fix.
fn (mut c Checker) ucedf_message_fix(t &estree.EsTree, tokens &SourceTokens, function int, statements []int, super_index int, message_index int) []Fix {
	if message_index < super_index {
		return []
	}
	expression := statements[message_index]
	rhs := t.node(t.node(expression, .expression) or { return [] }, .right) or { return [] }
	params := t.list(function, .params) or { []int{} }
	first := ucedf_argument(params, 0)
	second := ucedf_argument(params, 1)
	first_identifier := ucedf_parameter_identifier(t, first)
	add_options_parameter := params.len == 1 && first_identifier >= 0
		&& !ucedf_is_options(t, first)
	// The `super()` call is before the message assignment, so there is always a previous
	// statement.
	start := t.nodes[statements[message_index - 1]].end
	end := t.nodes[expression].end
	if add_options_parameter && ucedf_comment_right_after(t, tokens, first) {
		return []
	}
	if un_has_comment_in_range(tokens, start, end) || ucedf_comment_right_after(t, tokens, expression) {
		return []
	}
	call := t.node(statements[super_index], .expression) or { return [] }
	if tokens.comments_inside(t.nodes[call].start, t.nodes[call].end).len > 0 {
		return []
	}
	add_options_argument := add_options_parameter || ucedf_is_options(t, second)
	args := t.list(call, .arguments) or { []int{} }
	mut fixes := []Fix{}
	if args.len == 0 {
		if message_index != super_index + 1 || ucedf_has_this_or_super(t, rhs) {
			return []
		}
		opening := c.ucedf_opening_paren(t, tokens, call) or { return [] }
		text := c.un_parenthesized_text(t, tokens, rhs)
		fixes << fix_insert_at(opening.end, if add_options_argument {
			'${text}, options'
		} else {
			text
		})
	} else if c.un_text(t, un_unwrap_ts_expression(t, args[0])) != c.un_text(t,
		un_unwrap_ts_expression(t, rhs)) {
		return []
	} else if add_options_argument && args.len == 1 {
		if c.un_is_parenthesized(t, tokens, args[0]) {
			return []
		}
		fixes << fix_insert_at(t.nodes[args[0]].end, ', options')
	}
	if add_options_parameter {
		fixes << fix_insert_at(t.nodes[first].end, ', ${ucedf_options_parameter_text(t, first)}')
	}
	replacement := if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[expression].start,
		false), none)
	{
		';'
	} else {
		''
	}
	fixes << fix_replace_range(start, end, replacement)
	return fixes
}

// ucedf_export ports customErrorExport: `exports.Name = class Name extends Error {}`.
fn (c &Checker) ucedf_export(t &estree.EsTree, node int) ?Finding {
	left := t.node(node, .left)?
	property := t.node(left, .property)?
	right := t.node(node, .right)?
	if t.typ(right) != .class_expression || !ucedf_valid_super_class(t, right) {
		return none
	}
	id := t.node(right, .id)?
	error_name := t.string_of(id, .name)?
	computed := t.flag(left, .computed) or { false }
	property_value := un_unwrap_ts_expression(t, property)
	exports_name := if computed {
		un_static_string_value(t, property_value)?
	} else {
		t.string_of(property, .name)?
	}
	if exports_name == error_name {
		return none
	}
	replaced := if computed { property_value } else { property }
	return Finding{
		stmt:       c.es_tree_position(t, property)
		message_id: 'invalidExport'
		has_fix:    true
		fix:        fix_replace_range(t.nodes[replaced].start, t.nodes[replaced].end, if computed {
			"'${error_name}'"
		} else {
			error_name
		})
	}
}
