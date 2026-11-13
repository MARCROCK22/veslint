module rules

import json2
import jsregexp
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `func-name-matching` rule of ESLint 10.6.0, with its options.

const fnm_messages = {
	'matchProperty':    'Function name `{{funcName}}` should match property name `{{name}}`.'
	'matchVariable':    'Function name `{{funcName}}` should match variable name `{{name}}`.'
	'notMatchProperty': 'Function name `{{funcName}}` should not match property name `{{name}}`.'
	'notMatchVariable': 'Function name `{{funcName}}` should not match variable name `{{name}}`.'
}

// The reserved words esutils' isReservedWordES6 knows when not in strict mode.
const fnm_reserved_words = ['null', 'true', 'false', 'if', 'in', 'do', 'var', 'for', 'new', 'try',
	'this', 'else', 'case', 'void', 'with', 'enum', 'while', 'break', 'catch', 'throw', 'const',
	'yield', 'class', 'super', 'return', 'typeof', 'delete', 'switch', 'export', 'import', 'default',
	'finally', 'extends', 'function', 'continue', 'debugger', 'instanceof']

struct FnmOptions {
	always              bool
	property_descriptor bool
	module_exports      bool
}

// fnm_options reads "always" or "never" and the object of considerPropertyDescriptor and
// includeCommonJSModuleExports, which may come first.
fn fnm_options(options []json2.Any) !FnmOptions {
	mut always := true
	mut rest := options.clone()
	if rest.len > 0 && rest[0] is string {
		value := rest[0].str()
		if value !in ['always', 'never'] {
			return error('the option of `${func_name_matching}` must be "always" or "never"')
		}
		always = value == 'always'
		rest = rest[1..].clone()
	}
	o := option_object(func_name_matching, rest, ['considerPropertyDescriptor',
		'includeCommonJSModuleExports'])!
	return FnmOptions{
		always:              always
		property_descriptor: o.bool_value('considerPropertyDescriptor') or { false }
		module_exports:      o.bool_value('includeCommonJSModuleExports') or { false }
	}
}

fn (mut c Checker) lint_func_name_matching(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := fnm_options(c.rule_options(func_name_matching))!
	mut findings := []Finding{}
	kinds := ['variable_declarator', 'assignment_expression', 'augmented_assignment_expression',
		'pair', 'public_field_definition']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		match node_kind(node) {
			'variable_declarator' {
				id := node_field(node, 'name') or { continue }
				function := fnm_function(node_field(node, 'value') or { continue }) or { continue }
				if node_kind(id) != 'identifier' {
					continue
				}
				func_name := c.text(es_function_id(function) or { continue })
				if fnm_should_warn(o, c.text(id), func_name) {
					fnm_report(o, node, c.text(id), func_name, false, mut findings)
				}
			}
			'assignment_expression', 'augmented_assignment_expression' {
				function := fnm_function(node_field(node, 'right') or { continue }) or { continue }
				left := unwrap_parens(node_field(node, 'left') or { continue })
				if node_kind(left) == 'subscript_expression' {
					index := unwrap_parens(node_field(left, 'index') or { continue })
					if !es_is_literal(index) {
						continue
					}
				}
				if !o.module_exports && c.fnm_is_module_exports(left) {
					continue
				}
				is_prop := node_kind(left) in ['member_expression', 'subscript_expression']
				if !is_prop && node_kind(left) !in ['identifier', 'undefined'] {
					continue
				}
				name := if is_prop {
					c.es_static_property_name(left) or { continue }
				} else {
					c.identifier_name(left)
				}
				id := es_function_id(function) or { continue }
				// isIdentifier(name) is called without the ecmaVersion: ES5's rules.
				if name != '' && fnm_is_identifier(name, true)
					&& fnm_should_warn(o, name, c.text(id)) {
					fnm_report(o, node, name, c.text(id), is_prop, mut findings)
				}
			}
			else {
				if !es_is_accessor_field(node) {
					c.fnm_property(root, o, node, mut findings)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// fnm_function is the expression when it is a FunctionExpression.
fn fnm_function(n C.TSNode) ?C.TSNode {
	f := unwrap_parens(n)
	if node_kind(f) in ['function_expression', 'generator_function'] {
		return f
	}
	return none
}

fn fnm_should_warn(o FnmOptions, x string, y string) bool {
	return (o.always && x != y) || (!o.always && x == y)
}

fn fnm_report(o FnmOptions, node C.TSNode, name string, func_name string, is_prop bool, mut findings []Finding) {
	message_id := if o.always && is_prop {
		'matchProperty'
	} else if o.always {
		'matchVariable'
	} else if is_prop {
		'notMatchProperty'
	} else {
		'notMatchVariable'
	}
	findings << Finding{
		stmt:       position_of(node)
		message_id: message_id
		data:       {
			'name':     name
			'funcName': func_name
		}
	}
}

// fnm_is_identifier ports esutils' isIdentifierES5 and isIdentifierES6 (not in strict mode): an
// identifier name that is not a reserved word (`yield` is one only in ES6).
fn fnm_is_identifier(name string, es5 bool) bool {
	if name in fnm_reserved_words && !(es5 && name == 'yield') {
		return false
	}
	// ES5's identifiers are of Unicode letters, ES6's of ID_Start and ID_Continue.
	pattern := if es5 {
		'^[\\p{L}\\p{Nl}$_][\\p{L}\\p{Nl}\\p{Mn}\\p{Mc}\\p{Nd}\\p{Pc}$\\u200C\\u200D]*$'
	} else {
		'^[\\p{ID_Start}$_][\\p{ID_Continue}$\\u200C\\u200D]*$'
	}
	program := jsregexp.regexp_compile(pattern) or { return false }
	return jsregexp.regexp_test(program, name) or { false }
}

// fnm_is_module_exports ports isModuleExports: `module.exports` or `module["exports"]`.
fn (c &Checker) fnm_is_module_exports(n C.TSNode) bool {
	if node_kind(n) !in ['member_expression', 'subscript_expression'] {
		return false
	}
	object := unwrap_parens(node_field(n, 'object') or { return false })
	if node_kind(object) != 'identifier' || c.text(object) != 'module' {
		return false
	}
	property := unwrap_parens(node_field(n, if node_kind(n) == 'member_expression' {
		'property'
	} else {
		'index'
	}) or { return false })
	return match node_kind(property) {
		'property_identifier', 'identifier' { c.text(property) == 'exports' }
		'string' { c.literal_name(property) or { '' } == 'exports' }
		else { false }
	}
}

// fnm_property is the check of a Property or a PropertyDefinition with a value.
fn (mut c Checker) fnm_property(root C.TSNode, o FnmOptions, node C.TSNode, mut findings []Finding) {
	function := fnm_function(node_field(node, 'value') or { return }) or { return }
	func_name := c.text(es_function_id(function) or { return })
	key, computed := es_property_key(node) or { return }
	if node_kind(key) == 'property_identifier' && !computed {
		property_name := c.text(key)
		object := node_parent(node) or { return }
		if o.property_descriptor && property_name == 'value' && node_kind(object) == 'object' {
			// The object as an argument of a call, and the call around the property whose value
			// the object is.
			call := fnm_call_of_argument(object) or { node }
			if node_kind(call) == 'call_expression' && (c.fnm_is_property_call(call, 'Object', 'defineProperty')
				|| c.fnm_is_property_call(call, 'Reflect', 'defineProperty')) {
				args := call_arguments(call) or { return }
				list := args.filter(node_kind(it) != 'comment')
				if list.len > 1 {
					property := unwrap_parens(list[1])
					if node_kind(property) == 'string' {
						value := c.literal_name(property) or { return }
						if fnm_should_warn(o, value, func_name) {
							fnm_report(o, node, value, func_name, true, mut findings)
						}
					}
				}
				return
			}
			pair := cti_estree_parent(object) or { node }
			outer_call := if node_kind(pair) == 'pair' {
				fnm_call_of_argument(node_parent(pair) or { node }) or { node }
			} else {
				node
			}
			if node_kind(outer_call) == 'call_expression' && (c.fnm_is_property_call(outer_call, 'Object', 'defineProperties')
				|| c.fnm_is_property_call(outer_call, 'Object', 'create')) {
				outer_key, outer_computed := es_property_key(pair) or { return }
				name := if node_kind(outer_key) == 'property_identifier' {
					c.text(outer_key)
				} else {
					'undefined'
				}
				if !outer_computed && fnm_should_warn(o, name, func_name) {
					fnm_report(o, node, name, func_name, true, mut findings)
				}
				return
			}
		}
		if fnm_should_warn(o, property_name, func_name) {
			fnm_report(o, node, property_name, func_name, true, mut findings)
		}
		return
	}
	if node_kind(key) == 'string' {
		value := c.literal_name(key) or { return }
		if fnm_is_identifier(value, c.ecma_version < 2015) && fnm_should_warn(o, value, func_name) {
			fnm_report(o, node, value, func_name, true, mut findings)
		}
	}
}

// fnm_call_of_argument is the CallExpression the node is an argument of.
fn fnm_call_of_argument(n C.TSNode) ?C.TSNode {
	args := cti_estree_parent(n)?
	if node_kind(args) != 'arguments' {
		return none
	}
	call := node_parent(args)?
	return if node_kind(call) == 'call_expression' { call } else { none }
}

// fnm_is_property_call ports isPropertyCall: a call of `object.method`.
fn (c &Checker) fnm_is_property_call(call C.TSNode, object string, method string) bool {
	callee := node_field(call, 'function') or { return false }
	return c.es_is_specific_member_access(callee, object, method)
}
