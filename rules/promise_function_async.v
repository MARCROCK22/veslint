module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { has_child_kind, node_field, node_kind, node_parent, node_start, nodes_of_kinds }

// Port of the `promise-function-async` rule of typescript-eslint 8.62.0, with its options and
// its fixer.

const pfa_messages = {
	'missingAsync':             'Functions that return promises must be async.'
	'missingAsyncHybridReturn': 'Functions that return promises must be async. Consider adding an explicit return type annotation if the function is intended to return a union of promise and non-promise types.'
}

struct PfaOptions {
	allow_any                   bool
	allowed_promise_names       []string
	check_arrow_functions       bool
	check_function_declarations bool
	check_function_expressions  bool
	check_method_declarations   bool
}

fn pfa_options(options []json2.Any) !PfaOptions {
	o := option_object(promise_function_async, options, ['allowAny', 'allowedPromiseNames',
		'checkArrowFunctions', 'checkFunctionDeclarations', 'checkFunctionExpressions',
		'checkMethodDeclarations'])!
	return PfaOptions{
		allow_any:                   o.bool_value('allowAny')!
		allowed_promise_names:       o.string_list('allowedPromiseNames')!
		check_arrow_functions:       o.bool_value('checkArrowFunctions')!
		check_function_declarations: o.bool_value('checkFunctionDeclarations')!
		check_function_expressions:  o.bool_value('checkFunctionExpressions')!
		check_method_declarations:   o.bool_value('checkMethodDeclarations')!
	}
}

fn (mut c Checker) lint_promise_function_async(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := pfa_options(c.rule_options(promise_function_async))!
	mut promise_names := ['Promise']
	promise_names << options.allowed_promise_names
	mut sw := time.new_stopwatch()
	mut functions := []C.TSNode{}
	for f in c.nodes_of_kinds(root, function_kinds, []string{}) {
		// '[async = false]'
		if has_child_kind(f, 'async') || !c.pfa_is_checked(f, options) {
			continue
		}
		functions << f
	}
	c.resolve_spans(functions.map(function_span(it)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for f in functions {
		t := c.node_type(f) or { continue }
		signatures := c.signatures_of(t, signature_kind_call)!
		if signatures.len == 0 {
			continue
		}
		mut return_types := []TypeResponse{}
		for signature in signatures {
			return_types << c.return_type(signature.id)!
		}
		mut any_or_unknown := false
		for return_type in return_types {
			if c.type_flags(return_type)! & (type_flag_any | type_flag_unknown) != 0 {
				any_or_unknown = true
			}
		}
		if !options.allow_any && any_or_unknown {
			// Reported without a fix, as the return type is unknown.
			findings << Finding{
				stmt:       function_head(f)
				message_id: 'missingAsync'
			}
			continue
		}
		// Every possible return type must be a promise. Without an explicit return type, a part
		// of it that is one is enough.
		match_any := if _ := node_field(f, 'return_type') { false } else { true }
		mut all := true
		mut hybrid := false
		for return_type in return_types {
			if !c.contains_all_types_by_name(return_type, true, promise_names, match_any, 0)! {
				all = false
				break
			}
			if return_type.flags & type_flag_union != 0 {
				for part in c.members_of(return_type)! {
					if !c.contains_all_types_by_name(part, true, promise_names, false, 0)! {
						hybrid = true
						break
					}
				}
			}
		}
		if !all {
			continue
		}
		findings << Finding{
			stmt:       function_head(f)
			message_id: if hybrid { 'missingAsyncHybridReturn' } else { 'missingAsync' }
			has_fix:    true
			fix:        c.pfa_fix(f)
		}
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += functions.len
	return findings
}

// pfa_is_checked: the options have the rule look at this function, and it is not a getter or a
// setter, which cannot be async. A method of a class is a "method declaration"; a constructor, the
// method of an object and any other function expression are "function expressions".
fn (c &Checker) pfa_is_checked(f C.TSNode, options PfaOptions) bool {
	match node_kind(f) {
		'arrow_function' {
			return options.check_arrow_functions
		}
		'function_declaration', 'generator_function_declaration' {
			return options.check_function_declarations
		}
		'method_definition' {
			if has_child_kind(f, 'get') || has_child_kind(f, 'set') {
				return false
			}
			parent := node_parent(f) or { return false }
			if node_kind(parent) == 'class_body' && !c.pfa_is_constructor(f) {
				return options.check_method_declarations
			}
			return options.check_function_expressions
		}
		else {
			// `export default function () {}` is a declaration.
			if parent := node_parent(f) {
				if node_kind(parent) == 'export_statement' {
					return options.check_function_declarations
				}
			}
			return options.check_function_expressions
		}
	}
}

// pfa_is_constructor: the class member is its constructor (MethodDefinition with kind
// "constructor": a method named `constructor` that is neither static nor computed).
fn (c &Checker) pfa_is_constructor(method C.TSNode) bool {
	name := node_field(method, 'name') or { return false }
	if has_child_kind(method, 'static') {
		return false
	}
	return c.text(name) in ['constructor', "'constructor'", '"constructor"']
}

// contains_all_types_by_name ports containsAllTypesByName from type-utils: the type, or every part
// of it (any part, with `match_any`), is named like one of `allowed` or extends something that is.
fn (mut c Checker) contains_all_types_by_name(t TypeResponse, allow_any bool, allowed []string, match_any bool, depth int) !bool {
	if c.type_flags(t)! & (type_flag_any | type_flag_unknown) != 0 {
		return !allow_any
	}
	if depth >= max_type_depth {
		return false
	}
	target := if is_type_reference(t) { c.target_of(t)! } else { t }
	if target.symbol != 0 {
		symbol := c.symbol_of(target)!
		if symbol.name in allowed {
			return true
		}
	}
	if target.flags & (type_flag_union | type_flag_intersection) != 0 {
		for part in c.members_of(target)! {
			matches := c.contains_all_types_by_name(part, allow_any, allowed, match_any, depth + 1)!
			if matches == match_any {
				return match_any
			}
		}
		return !match_any
	}
	bases := c.base_types_for_type(target)!
	if bases.len == 0 {
		return false
	}
	for base in bases {
		matches := c.contains_all_types_by_name(base, allow_any, allowed, match_any, depth + 1)!
		if matches == match_any {
			return match_any
		}
	}
	return !match_any
}

// pfa_fix ports the fixer: `async ` before the function, or before the key of a method, after
// its modifiers.
fn (mut c Checker) pfa_fix(f C.TSNode) Fix {
	if node_kind(f) != 'method_definition' {
		return fix_insert_at(node_start(f), 'async ')
	}
	tokens := c.source_tokens(f)
	// The first token of the method, after its decorators.
	mut key_token := tokens.after(node_start(f), false) or { return fix_insert_at(node_start(f), 'async ') }
	key_start := if name := node_field(f, 'name') { node_start(name) } else { node_start(f) }
	// Keywords like `static` or `public`, and `override`, are skipped.
	for (key_token.kind == .keyword
		|| (key_token.kind == .identifier && c.token_text(key_token) == 'override'))
		&& key_token.start < key_start {
		key_token = tokens.after(key_token.end, false) or { break }
	}
	mut code := 'async '
	if previous := tokens.before(key_token.start, false) {
		if !tokens.is_space_between(previous.end, key_token.start) {
			code = ' async '
		}
	}
	return fix_insert_at(key_token.start, code)
}
