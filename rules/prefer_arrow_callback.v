module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `prefer-arrow-callback` rule of ESLint 10.6.0, with its options and its fix.

const parc_messages = {
	'preferArrowCallback': 'Unexpected function expression.'
}

struct PacOptions {
	allow_named_functions bool
	allow_unbound_this    bool
}

// pac_options reads allowNamedFunctions and allowUnboundThis.
fn pac_options(options []json2.Any) !PacOptions {
	o := option_object(prefer_arrow_callback, options, ['allowNamedFunctions', 'allowUnboundThis'])!
	return PacOptions{
		allow_named_functions: o.bool_value('allowNamedFunctions')!
		allow_unbound_this:    o.bool_value('allowUnboundThis')!
	}
}

// PacCallback is what getCallbackInfo finds: whether the function is a callback, whether it is
// bound to `this`, and the call of its `.bind(this)`.
struct PacCallback {
	is_callback     bool
	is_lexical_this bool
	bind_call       ?C.TSNode
}

fn (mut c Checker) lint_prefer_arrow_callback(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := pac_options(c.rule_options(prefer_arrow_callback))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['function_expression'], []) {
		stats.checked++
		id := es_function_id(node)
		if o.allow_named_functions && id != none {
			continue
		}
		tree := c.scope_tree(root)
		if name := id {
			v := tree.declared_variable(name)
			if v >= 0 && tree.variables[v].defs.len > 0
				&& tree.variables[v].defs[0].kind == .function_name
				&& tree.variables[v].references.len > 0 {
				continue
			}
		}
		// The function's own `arguments`, used.
		scope := tree.get_scope(node)
		arguments := tree.own_variable(scope, 'arguments')
		if arguments >= 0 && tree.variables[arguments].identifiers.len == 0
			&& tree.variables[arguments].references.len > 0 {
			continue
		}
		info := c.pac_callback_info(node)
		if !info.is_callback {
			continue
		}
		// The `this`, `super` and `new.target` of the function itself.
		mut uses_this := false
		mut uses_super := false
		mut uses_meta := false
		for n in c.nodes_of_kinds(node_field(node, 'body') or { continue }, ['this', 'super',
			'meta_property'], os_function_kinds) {
			match node_kind(n) {
				'this' { uses_this = true }
				'super' { uses_super = true }
				else { uses_meta = uses_meta || c.text(n).replace(' ', '') == 'new.target' }
			}
		}
		if (o.allow_unbound_this && uses_this && !info.is_lexical_this) || uses_super || uses_meta {
			continue
		}
		mut has_fix := false
		mut fix := Fix{}
		if fixes := c.pac_fixes(root, node, info, uses_this) {
			has_fix, fix = c.merge_fixes(fixes) or { false, Fix{} }
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'preferArrowCallback'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// pac_callback_info ports getCallbackInfo: through logical and conditional expressions and
// `.bind()` calls, the function is an argument of a call.
fn (c &Checker) pac_callback_info(f C.TSNode) PacCallback {
	mut current := f
	mut bound := false
	mut lexical := false
	mut bind_call := ?C.TSNode(none)
	for {
		parent := cti_estree_parent(current) or { return PacCallback{} }
		match node_kind(parent) {
			'ternary_expression' {}
			'binary_expression' {
				if estree_binary_kind(parent) != 'LogicalExpression' {
					return PacCallback{}
				}
			}
			'member_expression' {
				object := node_field(parent, 'object') or { return PacCallback{} }
				property := node_field(parent, 'property') or { return PacCallback{} }
				if node_key(unwrap_parens(object)) != node_key(current)
					|| node_kind(property) != 'property_identifier' || c.text(property) != 'bind' {
					return PacCallback{}
				}
				call := cti_estree_parent(parent) or { return PacCallback{} }
				callee := node_field(call, if node_kind(call) == 'new_expression' {
					'constructor'
				} else {
					'function'
				}) or { return PacCallback{} }
				if node_kind(call) !in ['call_expression', 'new_expression']
					|| node_key(unwrap_parens(callee)) != node_key(parent) {
					return PacCallback{}
				}
				if !bound {
					bound = true
					args := (call_arguments(call) or { []C.TSNode{} }).filter(node_kind(it) != 'comment')
					lexical = args.len == 1 && node_kind(unwrap_parens(args[0])) == 'this'
					bind_call = call
				}
				current = call
				continue
			}
			'arguments' {
				call := node_parent(parent) or { return PacCallback{} }
				if node_kind(call) in ['call_expression', 'new_expression'] {
					return PacCallback{
						is_callback:     true
						is_lexical_this: lexical
						bind_call:       bind_call
					}
				}
				return PacCallback{}
			}
			else {
				return PacCallback{}
			}
		}
		current = parent
	}
	return PacCallback{}
}

// pac_fixes is the fix that makes the function an arrow (with the `.bind(this)` removed), or
// none when it cannot keep the meaning.
fn (mut c Checker) pac_fixes(root C.TSNode, f C.TSNode, info PacCallback, uses_this bool) ?[]Fix {
	parameters := node_field(f, 'parameters')?
	params := named_children(parameters).filter(node_kind(it) != 'comment')
	if !info.is_lexical_this && uses_this {
		return none
	}
	// Duplicate param_names, all parameters being identifiers.
	mut param_names := []string{}
	mut all_identifiers := true
	for p in params {
		pattern := node_field(p, 'pattern') or {
			all_identifiers = false
			break
		}
		if node_kind(p) !in ['required_parameter', 'optional_parameter'] || node_field(p, 'value') != none
			|| node_kind(pattern) != 'identifier' {
			all_identifiers = false
			break
		}
		param_names << c.text(pattern)
	}
	if all_identifiers && param_names.len != unique_count(param_names) {
		return none
	}
	if params.len > 0 {
		if pattern := node_field(params[0], 'pattern') {
			if node_kind(pattern) == 'this' {
				return none
			}
		}
	}
	tokens := c.source_tokens(root)
	mut function_token := tokens.after(node_start(f), false)?
	is_async := es_is_async_function(f)
	if is_async {
		function_token = tokens.after(function_token.end, false)?
	}
	mut left_paren := tokens.after(function_token.end, false)?
	for c.src[left_paren.start..left_paren.end] != '(' {
		left_paren = tokens.after(left_paren.end, false)?
	}
	if is_async && es_has_line_break(c.src[function_token.end..left_paren.start]) {
		return none
	}
	mut fixes := []Fix{}
	if info.is_lexical_this {
		member := cti_estree_parent(f)?
		if node_kind(member) != 'member_expression' {
			return none
		}
		call := info.bind_call?
		object := node_field(member, 'object')?
		mut first := tokens.after(c.es_end(object), false)?
		for c.src[first.start..first.end] == ')' {
			first = tokens.after(first.end, false)?
		}
		last := tokens.before(c.es_end(call), false)?
		if c.es_is_parenthesised(member) {
			return none
		}
		if tokens.comments_exist_between(first.start, last.end) {
			return none
		}
		fixes << fix_remove_range(first.start, last.end)
	}
	body := node_field(f, 'body')?
	before_body := tokens.before(node_start(body), false)?
	if tokens.comments_exist_between(function_token.end, left_paren.start) {
		fixes << fix_remove_range(function_token.start, function_token.end)
		if name := es_function_id(f) {
			fixes << fix_remove_range(node_start(name), c.es_end(name))
		}
	} else {
		fixes << fix_remove_range(function_token.start, left_paren.start)
	}
	fixes << fix_insert_at(before_body.end, ' =>')
	replaced := if info.is_lexical_this { info.bind_call? } else { f }
	replaced_parent := cti_estree_parent(replaced)?
	parent_kind := if node_kind(replaced_parent) == 'arguments' {
		node_kind(node_parent(replaced_parent)?)
	} else {
		node_kind(replaced_parent)
	}
	if parent_kind !in ['call_expression', 'ternary_expression'] && !c.es_is_parenthesised(replaced)
		&& !c.es_is_parenthesised(f) {
		fixes << fix_insert_at(node_start(replaced), '(')
		fixes << fix_insert_at(c.es_end(replaced), ')')
	}
	return fixes
}

// unique_count is the number of different strings.
fn unique_count(values []string) int {
	mut seen := map[string]bool{}
	for v in values {
		seen[v] = true
	}
	return seen.len
}
