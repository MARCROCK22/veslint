module rules

import json2
import jsregexp
import time
import tsgo { TypeResponse }
import treesitter { Ident, children, has_child_kind, named_children, node_field, node_kind, node_parent, nodes_of_kind, nodes_of_kinds, position_of }

// Port of the `consistent-return` rule of typescript-eslint 8.62.0, which extends the rule of
// ESLint 10.6.0 with the same name, with its `treatUndefinedAsUnspecified` option. Whether the
// end of a function is reachable is that of ESLint's code path analysis (code_path.v).

const cr_messages = {
	'missingReturn':         'Expected to return a value at the end of {{name}}.'
	'missingReturnValue':    '{{name}} expected a return value.'
	'unexpectedReturnValue': '{{name}} expected no return value.'
}

struct CrOptions {
	treat_undefined_as_unspecified bool
}

fn cr_options(options []json2.Any) !CrOptions {
	o := option_object(consistent_return, options, ['treatUndefinedAsUnspecified'])!
	return CrOptions{
		treat_undefined_as_unspecified: o.bool_value('treatUndefinedAsUnspecified')!
	}
}

// CrFunction is a code path with `return` statements: a function, or the program.
struct CrFunction {
	node       C.TSNode
	is_program bool
mut:
	returns []C.TSNode
}

fn (mut c Checker) lint_consistent_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := cr_options(c.rule_options(consistent_return))!
	mut sw := time.new_stopwatch()
	// The `return` statements of each function, in the order of the source.
	mut functions := []CrFunction{}
	mut index := map[u64]int{}
	mut spans := []Span{}
	for statement in c.nodes_of_kind(root, c'return_statement') {
		mut owner := root
		mut is_program := true
		if function := enclosing_function(statement) {
			owner = function
			is_program = false
		}
		// The program and a function that spans it all would have the same key.
		key := if is_program { u64(0) } else { node_key(owner) + 1 }
		if key !in index {
			index[key] = functions.len
			functions << CrFunction{
				node:       owner
				is_program: is_program
			}
		}
		functions[index[key]].returns << statement
		argument := cr_argument(statement)
		if value := argument {
			if options.treat_undefined_as_unspecified {
				spans << node_span(value)
			}
		} else if !is_program {
			spans << function_span(owner)
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for function in functions {
		mut has_return := false
		mut has_return_value := false
		mut message_id := ''
		for statement in function.returns {
			argument := cr_argument(statement)
			// A `return;` in a function that returns void, or a promise of void if it is async,
			// says nothing.
			if argument == none && !function.is_program
				&& c.cr_returns_void_or_thenable_void(function.node)! {
				continue
			}
			mut returns_value := argument != none
			if value := argument {
				if options.treat_undefined_as_unspecified {
					mut is_undefined := false
					if value_type := c.node_type(value) {
						is_undefined = value_type.flags == type_flag_undefined
					}
					// isSpecificId(argument, 'undefined') and the `void` operator.
					returns_value = !is_undefined && node_kind(value) != 'undefined'
						&& !(node_kind(value) == 'identifier' && c.text(value) == 'undefined')
						&& !(node_kind(value) == 'unary_expression' && operator_of(value) == 'void')
				}
			}
			if !has_return {
				has_return = true
				has_return_value = returns_value
				message_id = if returns_value {
					'missingReturnValue'
				} else {
					'unexpectedReturnValue'
				}
			} else if has_return_value != returns_value {
				name := if function.is_program {
					'Program'
				} else {
					upper_case_first(c.core_function_name(function.node))
				}
				findings << Finding{
					stmt:       position_of(statement)
					message_id: message_id
					data:       {
						'name': name
					}
				}
			}
		}
		// checkLastSegment: a function that returns a value must do so at its end too, unless it
		// is a constructor.
		if !has_return_value {
			continue
		}
		if function.is_program {
			if c.end_reachable(named_children(root)) {
				findings << Finding{
					stmt:       Ident{}
					message_id: 'missingReturn'
					data:       {
						'name': 'program'
					}
				}
			}
			continue
		}
		body := node_field(function.node, 'body') or { continue }
		if node_kind(body) != 'statement_block' || !c.end_reachable(named_children(body)) {
			continue
		}
		if c.cr_is_es5_constructor(function.node) || c.cr_is_class_constructor(function.node) {
			continue
		}
		findings << Finding{
			stmt:       c.cr_missing_return_position(function.node)
			message_id: 'missingReturn'
			data:       {
				'name': c.core_function_name(function.node)
			}
		}
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += functions.len
	return findings
}

// cr_argument is the argument of a ReturnStatement, without parentheses.
fn cr_argument(statement C.TSNode) ?C.TSNode {
	for argument in named_children(statement) {
		return unwrap_parens(argument)
	}
	return none
}

// upper_case_first ports upperCaseFirst.
fn upper_case_first(text string) string {
	if text.len <= 1 {
		return text.to_upper()
	}
	return text[..1].to_upper() + text[1..]
}

// cr_returns_void_or_thenable_void ports isReturnVoidOrThenableVoid: some call signature of the
// function returns void or, if the function is async, a promise of void.
fn (mut c Checker) cr_returns_void_or_thenable_void(function C.TSNode) !bool {
	function_type := c.node_type(function) or { return false }
	is_async := has_child_kind(function, 'async')
	for signature in c.signatures_of(function_type, signature_kind_call)! {
		return_type := c.return_type(signature.id)!
		if is_async {
			if c.cr_is_promise_void(return_type, c.symbol_location(function), 0)! {
				return true
			}
		} else if c.type_flags(return_type)! & type_flag_void != 0 {
			return true
		}
	}
	return false
}

// cr_is_promise_void ports isPromiseVoid(node, type): a thenable type reference whose first type
// argument is void, or is in turn a promise of void. `at` is the node (the function).
fn (mut c Checker) cr_is_promise_void(t TypeResponse, at SymbolLocation, depth int) !bool {
	if depth >= max_type_depth || !is_type_reference(t) || !c.is_thenable(t, at)! {
		return false
	}
	arguments := c.type_args(t)!
	if arguments.len == 0 {
		return false
	}
	if c.type_flags(arguments[0])! & type_flag_void != 0 {
		return true
	}
	return c.cr_is_promise_void(arguments[0], at, depth + 1)!
}

// cr_is_es5_constructor ports isES5Constructor: a function whose own name starts with an
// uppercase letter.
fn (c &Checker) cr_is_es5_constructor(function C.TSNode) bool {
	if node_kind(function) == 'method_definition' {
		return false
	}
	name := node_field(function, 'name') or { return false }
	// `name[0] !== name[0].toLocaleLowerCase()`, in a locale without mappings of its own.
	units := utf16_units(c.identifier_name(name))
	if units.len == 0 {
		return false
	}
	return jsregexp.js_to_lower(units[..1]) != units[..1]
}

// cr_is_class_constructor ports isClassConstructor.
fn (c &Checker) cr_is_class_constructor(function C.TSNode) bool {
	if node_kind(function) != 'method_definition' {
		return false
	}
	parent := node_parent(function) or { return false }
	return node_kind(parent) == 'class_body' && c.pfa_is_constructor(function)
}

// CrOwner is the ESTree parent of a function when it is a Property, a MethodDefinition or a
// PropertyDefinition, as ESLint's getFunctionNameWithKind looks at it.
struct CrOwner {
	kind       string // 'method' (MethodDefinition), 'property' (Property), 'field' (PropertyDefinition) or ''
	member     C.TSNode
	key        ?C.TSNode
	is_method  bool   // a method of an object literal, not an accessor (Property.method)
	accessor   string // 'get', 'set' or ''
	is_static  bool
	is_private bool
}

fn (c &Checker) cr_owner(function C.TSNode) CrOwner {
	if node_kind(function) == 'method_definition' {
		parent := node_parent(function) or { return CrOwner{} }
		key := node_field(function, 'name')
		accessor := if has_child_kind(function, 'get') {
			'get'
		} else if has_child_kind(function, 'set') {
			'set'
		} else {
			''
		}
		in_class := node_kind(parent) == 'class_body'
		return CrOwner{
			kind:       if in_class { 'method' } else { 'property' }
			member:     function
			key:        key
			is_method:  !in_class && accessor == ''
			accessor:   accessor
			is_static:  in_class && has_child_kind(function, 'static')
			is_private: in_class && cr_is_private_key(key)
		}
	}
	parent := estree_parent(function) or { return CrOwner{} }
	match node_kind(parent) {
		'pair' {
			return CrOwner{
				kind:   'property'
				member: parent
				key:    node_field(parent, 'key')
			}
		}
		'public_field_definition' {
			// An `accessor` field is an AccessorProperty, which getFunctionNameWithKind does not
			// look at.
			if has_child_kind(parent, 'accessor') {
				return CrOwner{}
			}
			key := node_field(parent, 'name')
			return CrOwner{
				kind:       'field'
				member:     parent
				key:        key
				is_static:  has_child_kind(parent, 'static')
				is_private: cr_is_private_key(key)
			}
		}
		else {
			return CrOwner{}
		}
	}
}

fn cr_is_private_key(key ?C.TSNode) bool {
	k := key or { return false }
	return node_kind(k) == 'private_property_identifier'
}

// core_function_name ports getFunctionNameWithKind of ESLint's ast-utils: "static async method
// 'x'", "arrow function", "function 'f'", "constructor"…
fn (c &Checker) core_function_name(function C.TSNode) string {
	owner := c.cr_owner(function)
	mut tokens := []string{}
	if owner.kind in ['method', 'field'] {
		if owner.is_static {
			tokens << 'static'
		}
		if owner.is_private {
			tokens << 'private'
		}
	}
	if has_child_kind(function, 'async') {
		tokens << 'async'
	}
	if is_generator(function) {
		tokens << 'generator'
	}
	if owner.kind in ['method', 'property'] {
		// The MethodDefinition's kind: not a getter, a setter nor a generator named by the
		// identifier `constructor`.
		if owner.kind == 'method' && c.cm_method_kind(function) == 'constructor' {
			return 'constructor'
		}
		tokens << match owner.accessor {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if owner.kind == 'field' {
		tokens << 'method'
	} else {
		if node_kind(function) == 'arrow_function' {
			tokens << 'arrow'
		}
		tokens << 'function'
	}
	own_name := if node_kind(function) != 'method_definition' {
		node_field(function, 'name')
	} else {
		?C.TSNode(none)
	}
	if owner.kind != '' {
		if owner.is_private {
			if key := owner.key {
				tokens << c.text(key)
			}
		} else if name := c.core_static_property_name(owner.key) {
			tokens << "'${name}'"
		} else if id := own_name {
			tokens << "'${c.identifier_name(id)}'"
		}
	} else if id := own_name {
		tokens << "'${c.identifier_name(id)}'"
	}
	return tokens.join(' ')
}

// core_static_property_name ports getStaticPropertyName of ESLint's ast-utils for a key: the name
// of an identifier that is not computed, or the text of a literal or of a template without
// expressions (getStaticStringValue).
fn (c &Checker) core_static_property_name(key ?C.TSNode) ?string {
	mut node := key?
	if node_kind(node) == 'computed_property_name' {
		node = unwrap_parens(first_named(node)?)
		// A computed identifier is not static.
		if node_kind(node) !in ['string', 'number', 'true', 'false', 'null', 'regex', 'template_string'] {
			return none
		}
	}
	text := c.text(node)
	match node_kind(node) {
		'property_identifier', 'identifier' {
			return c.identifier_name(node)
		}
		'regex' {
			return text
		}
		'number' {
			// String(value), also for a BigInt literal, whose value typescript-estree gives
			// (`0x10n` is "16"; its `bigint` is only used where BigInt does not exist).
			return js_number_string(text)
		}
		else {
			return c.literal_name(node)
		}
	}
}

// cr_missing_return_position is where `missingReturn` is reported: the arrow of an arrow function,
// the key of a method, or the name of the function or, without one, its first token.
fn (c &Checker) cr_missing_return_position(function C.TSNode) Ident {
	if node_kind(function) == 'arrow_function' {
		for child in children(function) {
			if node_kind(child) == '=>' {
				return position_of(child)
			}
		}
		return position_of(function)
	}
	if node_kind(function) == 'method_definition' {
		owner := c.cr_owner(function)
		if owner.kind == 'method' || owner.is_method {
			key := node_field(function, 'name') or { return position_of(function) }
			if node_kind(key) == 'computed_property_name' {
				if inner := first_named(key) {
					return position_of(unwrap_parens(inner))
				}
			}
			return position_of(key)
		}
		// The accessor of an object literal: the function starts at its parameters.
		if parameters := node_field(function, 'parameters') {
			return position_of(parameters)
		}
		return position_of(function)
	}
	if name := node_field(function, 'name') {
		return position_of(name)
	}
	return position_of(function)
}
