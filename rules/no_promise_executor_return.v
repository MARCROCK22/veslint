module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-promise-executor-return` rule of ESLint 10.6.0.

const npe_messages = {
	'returnsValue': 'Return values from promise executor functions cannot be read.'
	'prependVoid':  'Prepend `void` to the expression.'
	'wrapBraces':   'Wrap the expression in `{}`.'
}

// npe_void_precedence is getPrecedence of a `void` UnaryExpression.
const npe_void_precedence = 16

fn npe_options(options []json2.Any) !bool {
	o := option_object(no_promise_executor_return, options, ['allowVoid'])!
	return o.bool_value('allowVoid') or { false }
}

fn (mut c Checker) lint_no_promise_executor_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_void := npe_options(c.rule_options(no_promise_executor_return))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['function_expression', 'arrow_function', 'return_statement'], []) {
		stats.checked++
		if node_kind(node) == 'return_statement' {
			argument := named_children(node).filter(node_kind(it) != 'comment')[0] or { continue }
			// The innermost code path: a function, a static block or the program.
			mut current := node
			for {
				current = node_parent(current) or { break }
				if node_kind(current) in function_kinds || node_kind(current) == 'class_static_block' {
					break
				}
			}
			if node_kind(current) !in ['function_expression', 'arrow_function']
				|| !c.npe_is_executor(root, current) {
				continue
			}
			if !allow_void {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'returnsValue'
				}
				continue
			}
			if npe_is_void(unwrap_parens(argument)) {
				continue
			}
			findings << Finding{
				stmt:        position_of(node)
				message_id:  'returnsValue'
				suggestions: [
					Suggestion{
						message_id: 'prependVoid'
						fix:        c.npe_void_fix(root, unwrap_parens(argument), false)
					},
				]
			}
			continue
		}
		if node_kind(node) != 'arrow_function' || !c.npe_is_executor(root, node) {
			continue
		}
		body := node_field(node, 'body') or { continue }
		if node_kind(body) == 'statement_block' {
			continue
		}
		expression := unwrap_parens(body)
		if allow_void && npe_is_void(expression) {
			continue
		}
		mut suggestions := []Suggestion{}
		if allow_void {
			suggestions << Suggestion{
				message_id: 'prependVoid'
				fix:        c.npe_void_fix(root, expression, true)
			}
		}
		if !(node_kind(expression) in ['function_expression', 'generator_function', 'class']
			&& node_field(expression, 'name') == none) {
			// curlyWrapFixer: `{` after the arrow, `}` after the last token of the function.
			tokens := c.source_tokens(root)
			arrow := tokens.before(node_start(body), false) or { continue }
			first := tokens.after(arrow.end, false) or { continue }
			end := c.es_end(node)
			suggestions << Suggestion{
				message_id: 'wrapBraces'
				fix:        Fix{first.start, end, '{' + c.src[first.start..end] + '}'}
			}
		}
		findings << Finding{
			stmt:        position_of(expression)
			message_id:  'returnsValue'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn npe_is_void(n C.TSNode) bool {
	return node_kind(n) == 'unary_expression' && operator_of(n) == 'void'
}

// npe_is_executor ports isPromiseExecutor: the first argument of `new Promise(…)`, where
// `Promise` is the global one.
fn (mut c Checker) npe_is_executor(root C.TSNode, f C.TSNode) bool {
	mut current := f
	mut parent := node_parent(current) or { return false }
	for node_kind(parent) == 'parenthesized_expression' {
		current = parent
		parent = node_parent(current) or { return false }
	}
	if node_kind(parent) != 'arguments' {
		return false
	}
	first := named_children(parent).filter(node_kind(it) != 'comment')[0] or { return false }
	if node_key(first) != node_key(current) {
		return false
	}
	call := node_parent(parent) or { return false }
	if node_kind(call) != 'new_expression' {
		return false
	}
	callee := node_field(call, 'constructor') or { return false }
	return node_kind(callee) == 'identifier' && c.text(callee) == 'Promise'
		&& c.es_is_global_reference(root, callee)
}

// npe_void_fix ports voidPrependFixer: `void ` (with parentheses when the expression binds less
// tightly) before the first token after the `return` or `=>`, as one merged fix.
fn (mut c Checker) npe_void_fix(root C.TSNode, expression C.TSNode, arrow bool) Fix {
	requires_parens := es_precedence(expression) < npe_void_precedence
		&& !c.es_is_parenthesised(expression)
	tokens := c.source_tokens(root)
	mut keyword := tokens.before(node_start(expression), false) or { return Fix{} }
	for {
		text := c.src[keyword.start..keyword.end]
		if (arrow && text == '=>') || (!arrow && text == 'return') {
			break
		}
		keyword = tokens.before(keyword.start, false) or { return Fix{} }
	}
	first := tokens.after(keyword.end, false) or { return Fix{} }
	prepend_space := !arrow && keyword.end == first.start
	end := c.es_end(expression)
	prefix := '${if prepend_space { ' ' } else { '' }}void ${if requires_parens { '(' } else { '' }}'
	suffix := if requires_parens { ')' } else { '' }
	return Fix{first.start, end, prefix + c.src[first.start..end] + suffix}
}
