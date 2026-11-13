module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `strict` rule of ESLint 10.6.0.

const strict_messages = {
	'function':               "Use the function form of 'use strict'."
	'global':                 "Use the global form of 'use strict'."
	'multiple':               "Multiple 'use strict' directives."
	'never':                  'Strict mode is not permitted.'
	'unnecessary':            "Unnecessary 'use strict' directive."
	'module':                 "'use strict' is unnecessary inside of modules."
	'implied':                "'use strict' is unnecessary when implied strict mode is enabled."
	'unnecessaryInClasses':   "'use strict' is unnecessary inside of classes."
	'nonSimpleParameterList': "'use strict' directive inside a function with non-simple parameter list throws a syntax error since ES2016."
	'wrap':                   "Wrap {{name}} in a function with 'use strict' directive."
}

fn strict_options(options []json2.Any) !string {
	mode := if options.len > 0 { options[0] } else { json2.Any('safe') }
	if mode !is string || mode.str() !in ['never', 'global', 'function', 'safe'] {
		return error('the option of `${strict_rule}` must be "never", "global", "function" or "safe"')
	}
	return mode.str()
}

struct StrictState {
mut:
	mode     string
	scopes   []bool // the strictness of the enclosing functions (function mode)
	classes  int    // enclosing class bodies (function mode)
	findings []Finding
}

fn (mut c Checker) lint_strict(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut mode := strict_options(c.rule_options(strict_rule))!
	if c.language.implied_strict {
		mode = 'implied'
	} else if mode == 'safe' {
		mode = if c.language.global_return || c.language.source_type == 'commonjs' {
			'global'
		} else {
			'function'
		}
	}
	function_handlers := mode == 'function'
	// Program
	if !c.scope_setup.script {
		mode = 'module'
	}
	mut st := StrictState{
		mode: mode
	}
	statements := strict_statements(root)
	directives := c.strict_directives(statements)
	if mode == 'global' {
		if statements.len > 0 && directives.len == 0 {
			st.findings << Finding{
				// The Program: from its first token to the end of its last one.
				stmt:       c.position_range(node_start(statements[0]), c.es_end(statements.last()))
				message_id: 'global'
			}
		}
		c.strict_report(mut st, directives, 1, 'multiple', true)
	} else {
		c.strict_report(mut st, directives, 0, mode, strict_should_fix(mode))
	}
	stats.checked++
	c.strict_visit(root, function_handlers, mut st)
	stats.eval_ms += ms(sw.elapsed())
	return st.findings
}

fn strict_should_fix(mode string) bool {
	return mode in ['multiple', 'unnecessary', 'module', 'implied', 'unnecessaryInClasses']
}

// strict_statements are the statements of a program or block (ESTree `body`).
fn strict_statements(n C.TSNode) []C.TSNode {
	return named_children(n).filter(node_kind(it) !in ['comment', 'hash_bang_line', 'html_comment'])
}

// strict_directives ports getUseStrictDirectives: the leading statements that are the string
// 'use strict'.
fn (c &Checker) strict_directives(statements []C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	for statement in statements {
		if node_kind(statement) != 'expression_statement' {
			break
		}
		expressions := named_children(statement).filter(node_kind(it) != 'comment')
		if expressions.len != 1 {
			break
		}
		value := c.literal_string_value(unwrap_parens(expressions[0])) or { break }
		if value != 'use strict' {
			break
		}
		out << statement
	}
	return out
}

// strict_report ports reportSlice from `start` to the end.
fn (c &Checker) strict_report(mut st StrictState, directives []C.TSNode, start int, message_id string, fix bool) {
	for i in start .. directives.len {
		st.findings << Finding{
			stmt:       position_of(directives[i])
			message_id: message_id
			has_fix:    fix
			fix:        if fix {
				Fix{node_start(directives[i]), c.es_end(directives[i]), ''}
			} else {
				Fix{}
			}
		}
	}
}

fn (mut c Checker) strict_visit(n C.TSNode, function_handlers bool, mut st StrictState) {
	kind := node_kind(n)
	is_function := kind in function_kinds
	is_class_body := kind == 'class_body' && function_handlers
	// Only function mode keeps the strictness of the functions (its exit handlers pop it).
	pushes := is_function && st.mode == 'function'
	if is_function {
		c.strict_enter_function(n, mut st)
	}
	if is_class_body {
		st.classes++
	}
	for child in named_children(n) {
		c.strict_visit(child, function_handlers, mut st)
	}
	if is_class_body {
		st.classes--
	}
	if pushes {
		st.scopes.pop()
	}
}

// strict_simple_parameters ports isSimpleParameterList: every parameter is an identifier.
fn strict_simple_parameters(f C.TSNode) bool {
	if _ := node_field(f, 'parameter') {
		return true
	}
	parameters := node_field(f, 'parameters') or { return true }
	for p in named_children(parameters) {
		match node_kind(p) {
			'required_parameter', 'optional_parameter' {
				pattern := node_field(p, 'pattern') or { return false }
				if node_kind(pattern) !in ['identifier', 'undefined', 'this'] {
					return false
				}
				if _ := node_field(p, 'value') {
					return false
				}
				for child in named_children(p) {
					if node_kind(child) in ['accessibility_modifier', 'override_modifier', 'readonly'] {
						return false
					}
				}
			}
			'comment', 'decorator' {}
			else {
				return false
			}
		}
	}
	return true
}

// strict_enter_function ports enterFunction.
fn (mut c Checker) strict_enter_function(f C.TSNode, mut st StrictState) {
	mut directives := []C.TSNode{}
	if body := node_field(f, 'body') {
		if node_kind(body) == 'statement_block' {
			directives = c.strict_directives(strict_statements(body))
		}
	}
	simple := strict_simple_parameters(f)
	if st.mode == 'function' {
		c.strict_enter_function_mode(f, directives, simple, mut st)
		return
	}
	if directives.len > 0 {
		if simple {
			c.strict_report(mut st, directives, 0, st.mode, strict_should_fix(st.mode))
		} else {
			st.findings << Finding{
				stmt:       position_of(directives[0])
				message_id: 'nonSimpleParameterList'
			}
			c.strict_report(mut st, directives, 1, 'multiple', true)
		}
	}
}

// strict_enter_function_mode ports enterFunctionInFunctionMode.
fn (mut c Checker) strict_enter_function_mode(f C.TSNode, directives []C.TSNode, simple bool, mut st StrictState) {
	in_class := st.classes > 0
	parent_global := st.scopes.len == 0 && st.classes == 0
	parent_strict := st.scopes.len > 0 && st.scopes.last()
	is_strict := directives.len > 0
	if is_strict {
		if !simple {
			st.findings << Finding{
				stmt:       position_of(directives[0])
				message_id: 'nonSimpleParameterList'
			}
		} else if parent_strict {
			st.findings << Finding{
				stmt:       position_of(directives[0])
				message_id: 'unnecessary'
				has_fix:    true
				fix:        Fix{node_start(directives[0]), c.es_end(directives[0]), ''}
			}
		} else if in_class {
			st.findings << Finding{
				stmt:       position_of(directives[0])
				message_id: 'unnecessaryInClasses'
				has_fix:    true
				fix:        Fix{node_start(directives[0]), c.es_end(directives[0]), ''}
			}
		}
		c.strict_report(mut st, directives, 1, 'multiple', true)
	} else if parent_global {
		if simple {
			st.findings << Finding{
				stmt:       es_function_position(f)
				message_id: 'function'
			}
		} else {
			st.findings << Finding{
				stmt:       es_function_position(f)
				message_id: 'wrap'
				data:       {
					'name': c.es_function_name_with_kind(f)
				}
			}
		}
	}
	st.scopes << (parent_strict || is_strict)
}
