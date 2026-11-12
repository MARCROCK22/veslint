module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `array-type` rule of typescript-eslint 8.62.0, with its options `default` and
// `readonly` ('array', 'generic' or 'array-simple'), and its fix.

const arty_messages = {
	'errorStringArray':               "Array type using '{{className}}<{{type}}>' is forbidden. Use '{{readonlyPrefix}}{{type}}[]' instead."
	'errorStringArrayReadonly':       "Array type using '{{className}}<{{type}}>' is forbidden. Use '{{readonlyPrefix}}{{type}}' instead."
	'errorStringArraySimple':         "Array type using '{{className}}<{{type}}>' is forbidden for simple types. Use '{{readonlyPrefix}}{{type}}[]' instead."
	'errorStringArraySimpleReadonly': "Array type using '{{className}}<{{type}}>' is forbidden for simple types. Use '{{readonlyPrefix}}{{type}}' instead."
	'errorStringGeneric':             "Array type using '{{readonlyPrefix}}{{type}}[]' is forbidden. Use '{{className}}<{{type}}>' instead."
	'errorStringGenericSimple':       "Array type using '{{readonlyPrefix}}{{type}}[]' is forbidden for non-simple types. Use '{{className}}<{{type}}>' instead."
}

const arty_option_values = ['array', 'generic', 'array-simple']

struct ArtyOptions {
	default_option  string
	readonly_option string
}

fn arty_options(options []json2.Any) !ArtyOptions {
	o := option_object(array_type, options, ['default', 'readonly'])!
	default_option := o.string_value('default', arty_option_values)!
	readonly_option := o.string_value('readonly', arty_option_values)!
	return ArtyOptions{
		// The default of `default` is 'array' (defaultOptions); `readonly` falls back on it.
		default_option:  if default_option == '' { 'array' } else { default_option }
		readonly_option: if readonly_option == '' {
			if default_option == '' { 'array' } else { default_option }
		} else {
			readonly_option
		}
	}
}

fn (mut c Checker) lint_array_type(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := arty_options(c.rule_options(array_type))!
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['array_type', 'generic_type'], []) {
		if node_kind(node) == 'array_type' {
			checked++
			c.arty_array(o, node, mut findings)!
		} else if c.arty_reference(o, root, node, mut findings)! {
			checked++
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// arty_array ports the TSArrayType listener: `T[]` where the option asks for `Array<T>`.
fn (mut c Checker) arty_array(o ArtyOptions, node C.TSNode, mut findings []Finding) ! {
	element := unwrap_type_parens(first_named(node) or { return })
	// `readonly T[]`: the TSTypeOperator is reported.
	mut is_readonly := false
	mut error_node := node
	if parent := type_parent(node) {
		if node_kind(parent) == 'readonly_type' {
			is_readonly = true
			error_node = parent
		}
	}
	current := if is_readonly { o.readonly_option } else { o.default_option }
	if current == 'array' || (current == 'array-simple' && arty_is_simple_type(c, element)) {
		return
	}
	array_name := if is_readonly { 'ReadonlyArray' } else { 'Array' }
	findings << c.with_fixes(Finding{
		stmt:       position_of(error_node)
		message_id: if current == 'generic' {
			'errorStringGeneric'
		} else {
			'errorStringGenericSimple'
		}
		data:       {
			'type':           c.arty_message_type(element)
			'className':      array_name
			'readonlyPrefix': if is_readonly { 'readonly ' } else { '' }
		}
	}, [
		fix_replace_range(node_start(error_node), node_start(element), '${array_name}<'),
		fix_replace_range(node_end(element), node_end(error_node), '>'),
	])!
}

// arty_reference ports the TSTypeReference listener: `Array<T>`, `ReadonlyArray<T>` or
// `Readonly<T[]>` where the option asks for `T[]`. It tells whether the node is one of them.
fn (mut c Checker) arty_reference(o ArtyOptions, root C.TSNode, node C.TSNode, mut findings []Finding) !bool {
	name_node := node_field(node, 'name') or { return false }
	if node_kind(name_node) != 'type_identifier' || type_name_role(name_node) != .reference {
		return false
	}
	name := c.identifier_name(name_node)
	if name !in ['Array', 'ReadonlyArray', 'Readonly'] {
		return false
	}
	args := node_field(node, 'type_arguments') or { return false }
	params := named_children(args).map(unwrap_type_parens(it))
	if name == 'Readonly' && (params.len == 0 || node_kind(params[0]) != 'array_type') {
		return false
	}
	// A type of that name declared in the file, in any scope but the global one.
	tree := c.scope_tree(root)
	mut scope := tree.get_scope(node)
	for tree.scopes[scope].upper >= 0 {
		if tree.own_variable(scope, name) >= 0 {
			return true
		}
		scope = tree.scopes[scope].upper
	}
	is_readonly_generic := name == 'Readonly'
	is_readonly_array := name == 'ReadonlyArray' || is_readonly_generic
	current := if is_readonly_array { o.readonly_option } else { o.default_option }
	if current == 'generic' {
		return true
	}
	message_id := if current == 'array' {
		if is_readonly_generic { 'errorStringArrayReadonly' } else { 'errorStringArray' }
	} else if is_readonly_array && name != 'ReadonlyArray' {
		'errorStringArraySimpleReadonly'
	} else {
		'errorStringArraySimple'
	}
	if params.len != 1 || (current == 'array-simple' && !arty_is_simple_type(c, params[0])) {
		return true
	}
	type_node := params[0]
	type_parens := arty_needs_parentheses(c, type_node)
	readonly_prefix := if is_readonly_array { 'readonly ' } else { '' }
	// The new `readonly T[]` inside an array type needs parentheses, unless it has them.
	mut parent_parens := false
	if is_readonly_array {
		if parent := type_parent(node) {
			if node_kind(parent) == 'array_type' {
				direct := node_parent(node) or { parent }
				parent_parens = node_kind(direct) != 'parenthesized_type'
			}
		}
	}
	mut start := if parent_parens { '(' } else { '' }
	start += readonly_prefix
	mut end := ''
	if type_parens {
		start += '('
		end += ')'
	}
	if !is_readonly_generic {
		end += '[]'
	}
	if parent_parens {
		end += ')'
	}
	findings << c.with_fixes(Finding{
		stmt:       position_of(node)
		message_id: message_id
		data:       {
			'type':           c.arty_message_type(type_node)
			'className':      if is_readonly_array { name } else { 'Array' }
			'readonlyPrefix': readonly_prefix
		}
	}, [
		fix_replace_range(node_start(node), node_start(type_node), start),
		fix_replace_range(node_end(type_node), node_end(node), end),
	])!
	return true
}

// arty_message_type ports getMessageType: the text of a simple type, otherwise 'T'.
fn (c &Checker) arty_message_type(n C.TSNode) string {
	return if arty_is_simple_type(c, n) { c.text(n) } else { 'T' }
}

// arty_is_simple_type ports isSimpleType for a type without parentheses: a keyword (`bigint` is a
// type_identifier in tree-sitter; `unique symbol` is a TSTypeOperator), `null`, `undefined`,
// `this`, an array type, a name or a qualified name without type arguments, or `Array<T>` of a
// simple type.
fn arty_is_simple_type(c &Checker, n C.TSNode) bool {
	match node_kind(n) {
		'predefined_type' {
			return !c.text(n).starts_with('unique')
		}
		'type_identifier', 'nested_type_identifier', 'array_type', 'this_type' {
			return true
		}
		'literal_type' {
			literal := first_named(n) or { return false }
			return node_kind(literal) in ['null', 'undefined']
		}
		'generic_type' {
			name := node_field(n, 'name') or { return false }
			if node_kind(name) != 'type_identifier' || c.identifier_name(name) != 'Array' {
				return false
			}
			args := node_field(n, 'type_arguments') or { return true }
			params := named_children(args)
			return params.len == 1 && arty_is_simple_type(c, unwrap_type_parens(params[0]))
		}
		else {
			return false
		}
	}
}

// arty_needs_parentheses ports typeNeedsParentheses: a union, an intersection, a function or
// constructor type, a type operator (`keyof`, `readonly`, `unique symbol`), `infer`, a conditional
// type, or a reference to `ReadonlyArray`.
fn arty_needs_parentheses(c &Checker, n C.TSNode) bool {
	match node_kind(n) {
		'union_type', 'intersection_type', 'function_type', 'constructor_type', 'readonly_type',
		'index_type_query', 'infer_type', 'conditional_type' {
			return true
		}
		'predefined_type' {
			return c.text(n).starts_with('unique')
		}
		'type_identifier' {
			return c.identifier_name(n) == 'ReadonlyArray'
		}
		'generic_type' {
			name := node_field(n, 'name') or { return false }
			return node_kind(name) == 'type_identifier' && c.identifier_name(name) == 'ReadonlyArray'
		}
		else {
			return false
		}
	}
}
