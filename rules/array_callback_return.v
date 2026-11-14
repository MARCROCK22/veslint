module rules

import codepath
import estree
import json2
import time

// Port of the `array-callback-return` rule of ESLint 10.15.0, with its options and suggestions, on
// the code path events of the codepath module.

const acr_messages = {
	'expectedAtEnd':         '{{arrayMethodName}}() expects a value to be returned at the end of {{name}}.'
	'expectedInside':        '{{arrayMethodName}}() expects a return value from {{name}}.'
	'expectedReturnValue':   '{{arrayMethodName}}() expects a return value from {{name}}.'
	'expectedNoReturnValue': '{{arrayMethodName}}() expects no useless return value from {{name}}.'
	'wrapBraces':            'Wrap the expression in `{}`.'
	'prependVoid':           'Prepend `void` to the expression.'
}

// acr_target_methods is TARGET_METHODS.
const acr_target_methods = ['every', 'filter', 'find', 'findIndex', 'findLast', 'findLastIndex',
	'flatMap', 'forEach', 'map', 'reduce', 'reduceRight', 'some', 'sort', 'toSorted']

struct AcrOptions {
	allow_implicit bool
	check_for_each bool
	allow_void     bool
}

fn acr_options(options []json2.Any) !AcrOptions {
	o := option_object(array_callback_return, options, ['allowImplicit', 'checkForEach', 'allowVoid'])!
	return AcrOptions{
		allow_implicit: o.bool_value('allowImplicit') or { false }
		check_for_each: o.bool_value('checkForEach') or { false }
		allow_void:     o.bool_value('allowVoid') or { false }
	}
}

struct AcrFuncInfo {
	method string // arrayMethodName; '' when it is not checked
	node   int
mut:
	has_return       bool
	current_segments []int // a Set: insertion order, no duplicates
}

fn (mut c Checker) lint_array_callback_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := acr_options(c.rule_options(array_callback_return))!
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	// The bottom entry is the rule's initial funcInfo (no code path).
	mut stack := [AcrFuncInfo{
		node: -1
	}]
	for ev in an.events {
		top := stack.len - 1
		match ev.kind {
			.code_path_start {
				mut method := ''
				if t.typ(ev.node) in [.function_expression, .arrow_function_expression] {
					method = acr_array_method_name(t, ev.node)
				}
				stack << AcrFuncInfo{
					method: method
					node:   ev.node
				}
			}
			.code_path_end {
				stack.delete_last()
			}
			.segment_start, .unreachable_segment_start {
				if ev.segment !in stack[top].current_segments {
					stack[top].current_segments << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				k := stack[top].current_segments.index(ev.segment)
				if k >= 0 {
					stack[top].current_segments.delete(k)
				}
			}
			.enter_node {
				if t.typ(ev.node) == .return_statement && stack[top].method != '' {
					stack[top].has_return = true
					stats.checked++
					if f := c.acr_check_return(root, t, o, stack[top], ev.node) {
						findings << f
					}
				}
			}
			.leave_node {
				// "FunctionExpression:exit" and "ArrowFunctionExpression:exit": checkLastSegment.
				if t.typ(ev.node) in [.function_expression, .arrow_function_expression] {
					info := stack[top]
					stats.checked++
					if info.method != '' {
						if f := c.acr_check_last_segment(root, t, an, o, info, ev.node) {
							findings << f
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

// acr_full_method_name ports fullMethodName.
fn acr_full_method_name(method string) string {
	if method in ['from', 'fromAsync', 'of', 'isArray'] {
		return 'Array.${method}'
	}
	return 'Array.prototype.${method}'
}

// acr_is_target_method ports isTargetMethod: a member access whose property is one of
// TARGET_METHODS.
fn acr_is_target_method(t &estree.EsTree, node int) bool {
	check := es_tree_skip_chain(t, node)
	if check < 0 || t.typ(check) != .member_expression {
		return false
	}
	return (es_tree_static_property_name(t, check) or { return false }) in acr_target_methods
}

// acr_is_array_from_method ports isArrayFromMethod: `<name ending in Array>.from`.
fn acr_is_array_from_method(t &estree.EsTree, node int) bool {
	check := es_tree_skip_chain(t, node)
	if check < 0 || t.typ(check) != .member_expression {
		return false
	}
	object := t.node(check, .object) or { return false }
	if t.typ(object) != .identifier || !(t.string_of(object, .name) or { '' }).ends_with('Array') {
		return false
	}
	return (es_tree_static_property_name(t, check) or { return false }) == 'from'
}

// acr_upper_function ports getUpperFunction: the nearest function that contains the node, the
// node itself included.
fn acr_upper_function(t &estree.EsTree, node int) int {
	mut current := node
	for current >= 0 {
		if t.typ(current) in [.arrow_function_expression, .function_expression, .function_declaration] {
			return current
		}
		current = t.nodes[current].parent
	}
	return -1
}

// acr_array_method_name ports getArrayMethodName: the name of the array method the function is a
// callback of ('' for none).
fn acr_array_method_name(t &estree.EsTree, node int) string {
	if t.flag(node, .generator) or { false } {
		return ''
	}
	is_async := t.flag(node, .async) or { false }
	mut current := node
	for current >= 0 {
		parent := t.nodes[current].parent
		if parent < 0 {
			return ''
		}
		match t.typ(parent) {
			// Looks up the destination. e.g., foo.every(nativeFoo || function foo() { ... });
			.logical_expression, .conditional_expression, .chain_expression {
				current = parent
			}
			// If the upper function is IIFE, checks the destination of the return value. e.g.
			// foo.every((function() { return function foo() { ... }; })());
			.return_statement {
				func := acr_upper_function(t, parent)
				if func < 0 || !es_tree_is_callee(t, func) {
					return ''
				}
				current = t.nodes[func].parent
			}
			// e.g. Array.from([], function() {}); list.every(function() {});
			.call_expression {
				callee := t.node(parent, .callee) or { return '' }
				arguments := t.list(parent, .arguments) or { []int{} }
				if !is_async {
					if acr_is_array_from_method(t, callee) {
						if arguments.len >= 2 && arguments[1] == current {
							return 'from'
						}
					}
					if acr_is_target_method(t, callee) {
						if arguments.len >= 1 && arguments[0] == current {
							return es_tree_static_property_name(t, callee) or { '' }
						}
					}
				}
				if es_tree_is_specific_member_access(t, callee, 'Array', 'fromAsync') {
					if arguments.len >= 2 && arguments[1] == current {
						return 'fromAsync'
					}
				}
				return ''
			}
			else {
				return ''
			}
		}
	}
	return ''
}

fn acr_is_void(t &estree.EsTree, node int) bool {
	return t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == 'void'
}

// acr_wrap_braces is curlyWrapFixer: `{` after the arrow, `}` after the last token of the function.
fn (mut c Checker) acr_wrap_braces(root C.TSNode, t &estree.EsTree, node int) ?Suggestion {
	body := t.node(node, .body)?
	tokens := c.source_tokens(root)
	mut arrow := tokens.before(t.nodes[body].start, false)?
	for c.src[arrow.start..arrow.end] != '=>' {
		arrow = tokens.before(arrow.start, false)?
	}
	first := tokens.after(arrow.end, false)?
	end := t.nodes[node].end
	return Suggestion{
		message_id: 'wrapBraces'
		fix:        Fix{first.start, end, '{' + c.src[first.start..end] + '}'}
	}
}

// acr_prepend_void is voidPrependFixer.
fn (mut c Checker) acr_prepend_void(root C.TSNode, t &estree.EsTree, expression int, arrow bool) ?Suggestion {
	n := t.ts_node(expression)?
	return Suggestion{
		message_id: 'prependVoid'
		fix:        c.npe_void_fix(root, unwrap_parens(n), arrow)
	}
}

// acr_check_last_segment ports checkLastSegment.
fn (mut c Checker) acr_check_last_segment(root C.TSNode, t &estree.EsTree, an &codepath.Analysis, o AcrOptions, info AcrFuncInfo, node int) ?Finding {
	mut message_id := ''
	mut suggestions := []Suggestion{}
	body := t.node(node, .body)?
	if info.method == 'forEach' {
		if o.check_for_each && t.typ(node) == .arrow_function_expression
			&& (t.flag(node, .expression) or { false }) {
			if o.allow_void {
				if acr_is_void(t, body) {
					return none
				}
				message_id = 'expectedNoReturnValue'
				suggestions << c.acr_wrap_braces(root, t, node)?
				suggestions << c.acr_prepend_void(root, t, body, true)?
			} else {
				message_id = 'expectedNoReturnValue'
				suggestions << c.acr_wrap_braces(root, t, node)?
			}
		}
	} else if t.typ(body) == .block_statement && an.is_any_reachable(info.current_segments) {
		message_id = if info.has_return { 'expectedAtEnd' } else { 'expectedInside' }
	}
	if message_id == '' {
		return none
	}
	return Finding{
		stmt:        c.es_tree_function_head(t, node)
		message_id:  message_id
		data:        {
			'name':            c.es_tree_function_name(t, node)
			'arrayMethodName': acr_full_method_name(info.method)
		}
		suggestions: suggestions
	}
}

// acr_check_return is the ReturnStatement listener.
fn (mut c Checker) acr_check_return(root C.TSNode, t &estree.EsTree, o AcrOptions, info AcrFuncInfo, node int) ?Finding {
	mut message_id := ''
	mut suggestions := []Suggestion{}
	argument := t.node(node, .argument) or { -1 }
	if info.method == 'forEach' {
		if o.check_for_each && argument >= 0 {
			if o.allow_void {
				if acr_is_void(t, argument) {
					return none
				}
				message_id = 'expectedNoReturnValue'
				suggestions << c.acr_prepend_void(root, t, argument, false)?
			} else {
				message_id = 'expectedNoReturnValue'
			}
		}
	} else if !o.allow_implicit && argument < 0 {
		message_id = 'expectedReturnValue'
	}
	if message_id == '' {
		return none
	}
	return Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  message_id
		data:        {
			'name':            c.es_tree_function_name(t, info.node)
			'arrayMethodName': acr_full_method_name(info.method)
		}
		suggestions: suggestions
	}
}
