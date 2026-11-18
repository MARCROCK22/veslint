module rules

import estree
import json2
import math
import time
import vue

// Port of the `vue/v-on-handler-style` rule of eslint-plugin-vue 10.12.1 (options: "inline",
// "inline-function" or ["method", one of them], default ["method", "inline-function"]; and
// ignoreIncludesComment): the value of a `v-on:x` written as an inline handler (`foo()`), a
// method (`foo`) or an inline function (`() => foo()`) that the first allowed style that applies
// would write otherwise, fixed (or suggested) when it can be.

const vue_v_on_handler_style_messages = {
	'preferMethodOverInline':                           'Prefer method handler over inline handler in v-on.'
	'preferMethodOverInlineWithoutIdCall':              'Prefer method handler over inline handler in v-on. Note that you may need to create a new method.'
	'preferMethodOverInlineFunction':                   'Prefer method handler over inline function in v-on.'
	'preferMethodOverInlineFunctionWithoutIdCall':      'Prefer method handler over inline function in v-on. Note that you may need to create a new method.'
	'preferInlineOverMethod':                           'Prefer inline handler over method handler in v-on.'
	'preferInlineOverInlineFunction':                   'Prefer inline handler over inline function in v-on.'
	'preferInlineOverInlineFunctionWithMultipleParams': 'Prefer inline handler over inline function in v-on. Note that the custom event must be changed to a single payload.'
	'preferInlineFunctionOverMethod':                   'Prefer inline function over method handler in v-on.'
	'preferInlineFunctionOverInline':                   'Prefer inline function over inline handler in v-on.'
	'replaceWithMethodHandler':                         'Replace with method handler. Note that the method will receive the event arguments.'
}

struct VohsOptions {
	allows         []string
	ignore_comment bool
}

fn vohs_options(options []json2.Any) !VohsOptions {
	mut allows := []string{}
	if options.len > 0 {
		first := options[0]
		if first is string && first != '' {
			allows << first
		} else if first is []json2.Any {
			for item in first {
				allows << item.str()
			}
		}
	}
	if allows.len == 0 {
		allows = ['method', 'inline-function']
	}
	o := option_object(vue_v_on_handler_style, if options.len > 1 {
		options[1..].clone()
	} else {
		[]json2.Any{}
	}, ['ignoreIncludesComment'])!
	return VohsOptions{
		allows:         allows
		ignore_comment: o.bool_value('ignoreIncludesComment')!
	}
}

// VohsTokenInfo is getVExpressionContainerTokenInfo.
struct VohsTokenInfo {
	start       int
	end         int
	has_comment bool
	has_quote   bool
}

// VohsCtx is what the rule's functions share.
struct VohsCtx {
	o VohsOptions
mut:
	param_counts map[string]f64
	event_ids    [][]int // the ranges of the `$event` identifiers of the template
	upper        []int   // the elements entered
}

fn (mut c Checker) lint_vue_v_on_handler_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut x := VohsCtx{
		o: vohs_options(c.rule_options(vue_v_on_handler_style))!
	}
	mut findings := []Finding{}
	if 'method' in x.o.allows {
		c.vohs_param_counts(root, abs_path, mut x)
	}
	doc := c.vue.doc
	with_events := 'inline-function' in x.o.allows
	for step in c.vue_template_steps() {
		n := step.node
		if n.kind == .estree {
			if with_events && !step.leave {
				es := &doc.snippets[n.snippet].es
				if es.typ(n.es) == .identifier && (es.string_of(n.es, .name) or { '' }) == r'$event' {
					x.event_ids << [es.nodes[n.es].start, es.nodes[n.es].end]
				}
			}
			continue
		}
		if n.kind != .vnode {
			continue
		}
		node := &doc.nodes[n.v]
		if node.typ == .v_element {
			if step.leave {
				x.upper.pop()
			} else {
				x.upper << n.v
			}
			continue
		}
		if !step.leave || node.typ != .v_expression_container || node.parent < 0 {
			continue
		}
		attr := &doc.nodes[node.parent]
		if attr.typ != .v_attribute || attr.value != n.v || !attr.directive
			|| c.vue_directive_name(node.parent) != 'on' || doc.nodes[attr.key].argument < 0 {
			continue
		}
		expression := node.expression
		if expression.is_null() {
			continue
		}
		stats.checked++
		match c.vue_expr_type(expression) {
			'VOnExpression' {
				if x.o.allows[0] == 'inline' {
					continue
				}
				for allow in x.o.allows {
					if allow == 'method' {
						if c.vohs_method_for_inline(n.v, expression.node, x, mut findings)! {
							break
						}
					} else if allow == 'inline-function' {
						c.vohs_inline_function_for_inline(n.v, expression.node, x, mut findings)!
						break
					}
				}
			}
			'Identifier' {
				if x.o.allows[0] == 'method' {
					continue
				}
				for allow in x.o.allows {
					if allow in ['inline', 'inline-function'] {
						start, end := c.vue_expr_range(expression)
						findings << c.vue_report(start, end, if allow == 'inline' {
							'preferInlineOverMethod'
						} else {
							'preferInlineFunctionOverMethod'
						}, {})
						break
					}
				}
			}
			'ArrowFunctionExpression', 'FunctionExpression' {
				if x.o.allows[0] == 'inline-function' {
					continue
				}
				for allow in x.o.allows {
					if allow == 'method' {
						if c.vohs_method_for_inline_function(n.v, expression, x, mut findings)! {
							break
						}
					} else if allow == 'inline' {
						c.vohs_inline_for_inline_function(expression, mut findings)!
						break
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vohs_param_counts collects the number of parameters of the methods (Infinity with a rest
// parameter): of the `methods` of the Vue objects, and of the top-level function declarations and
// `const` functions of `<script setup>`; a later one of a name wins.
fn (mut c Checker) vohs_param_counts(root C.TSNode, abs_path string, mut x VohsCtx) {
	s := c.vue_script(root, abs_path) or { return }
	t := c.es_tree(root, abs_path) or { return }
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		if s.owner_of(node) == node {
			for method in vue_iterate_properties(t, node, ['methods']) {
				if method.kind != .object {
					continue
				}
				value := vue_property_value(t, method.property)
				if t.typ(value) in [.function_expression, .arrow_function_expression] {
					x.param_counts[method.name] = vohs_param_count(t, value)
				}
			}
			continue
		}
		parent := t.nodes[node].parent
		if parent < 0 || !s.in_script_setup(t, node) {
			continue
		}
		if t.typ(node) == .function_declaration && parent == t.root {
			id := t.node(node, .id) or { continue }
			x.param_counts[vue_identifier_name(t, id)] = vohs_param_count(t, node)
		} else if t.typ(node) == .variable_declarator && t.typ(parent) == .variable_declaration
			&& t.nodes[parent].parent == t.root && (t.string_of(parent, .kind) or { '' }) == 'const' {
			id := t.node(node, .id) or { continue }
			init := t.node(node, .init) or { continue }
			if t.typ(id) == .identifier
				&& t.typ(init) in [.function_expression, .arrow_function_expression] {
				x.param_counts[vue_identifier_name(t, id)] = vohs_param_count(t, init)
			}
		}
	}
}

// vohs_param_count is getParamCount.
fn vohs_param_count(t &estree.EsTree, function int) f64 {
	params := t.list(function, .params) or { []int{} }
	if params.any(t.typ(it) == .rest_element) {
		return math.inf(1)
	}
	return f64(params.len)
}

// vohs_token_info is getVExpressionContainerTokenInfo.
fn (c &Checker) vohs_token_info(container int) VohsTokenInfo {
	node := &c.vue.doc.nodes[container]
	tokens := c.vue_tokens_with_comments_in(node.start, node.end)
	if tokens.len == 0 {
		return VohsTokenInfo{}
	}
	first := tokens[0]
	last := tokens.last()
	has_quote := first.typ == 'Punctuator' && first.value in ['"', "'"]
	return VohsTokenInfo{
		start:       if has_quote { first.end } else { first.start }
		end:         if has_quote { last.start } else { last.end }
		has_comment: tokens.any(it.typ in ['Block', 'Line'])
		has_quote:   has_quote
	}
}

// vohs_identifier_call is isIdentifierCallExpression: a call (not optional) of an Identifier.
fn vohs_identifier_call(t &estree.EsTree, node int) bool {
	if t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	return t.typ(t.node(node, .callee) or { return false }) == .identifier
}

// vohs_identifier_call_of_body is getIdentifierCallExpression: the only statement (through
// blocks) is an expression statement of an identifier call; -1 otherwise.
fn vohs_identifier_call_of_body(t &estree.EsTree, statements []int) int {
	mut body := statements.clone()
	for {
		kept := body.filter(t.typ(it) != .empty_statement)
		if kept.len != 1 {
			return -1
		}
		statement := kept[0]
		if t.typ(statement) == .expression_statement {
			expression := t.node(statement, .expression) or { return -1 }
			return if vohs_identifier_call(t, expression) { expression } else { -1 }
		}
		if t.typ(statement) == .block_statement {
			body = t.list(statement, .body) or { return -1 }
			continue
		}
		return -1
	}
	return -1
}

// vohs_method_fix is getMethodHandlerFix: a fix when the method takes as many parameters as the
// call has arguments, else a suggestion.
fn (c &Checker) vohs_method_fix(t &estree.EsTree, call int, info VohsTokenInfo, x &VohsCtx, finding Finding) !Finding {
	callee := t.node(call, .callee) or { return finding }
	fix := fix_replace_range(info.start, info.end, c.vue.doc.src[t.nodes[callee].start..t.nodes[callee].end])
	args := t.list(call, .arguments) or { []int{} }
	count := x.param_counts[vue_identifier_name(t, callee)] or { -1 }
	if count == f64(args.len) {
		return c.with_fixes(finding, [fix])!
	}
	ok, suggestion := c.suggestion('replaceWithMethodHandler', {}, [fix])!
	return if ok {
		Finding{
			...finding
			suggestions: [suggestion]
		}
	} else {
		finding
	}
}

// vohs_method_for_inline is verifyCanUseMethodHandlerForInlineHandler on a VOnExpression; true
// when it reports.
fn (mut c Checker) vohs_method_for_inline(container int, on int, x &VohsCtx, mut findings []Finding) !bool {
	info := c.vohs_token_info(container)
	if x.o.ignore_comment && info.has_comment {
		return false
	}
	doc := c.vue.doc
	statements := doc.nodes[on].exprs
	mut call := -1
	mut es := &estree.EsTree(unsafe { nil })
	if statements.len > 0 && statements[0].kind == .estree {
		es = &doc.snippets[statements[0].snippet].es
		call = vohs_identifier_call_of_body(es, statements.filter(it.kind == .estree).map(it.node))
	}
	start, end := c.vue_vnode_range(on)
	n := &doc.nodes[on]
	if (call < 0 || (es.list(call, .arguments) or { []int{} }).len > 0)
		&& c.vue_refers_to_upper_variable(x.upper, n.start, n.end) {
		return false
	}
	finding := c.vue_report(start, end, if call >= 0 {
		'preferMethodOverInline'
	} else {
		'preferMethodOverInlineWithoutIdCall'
	}, {})
	if info.has_comment || call < 0 || (es.list(call, .arguments) or { []int{} }).len > 0 {
		findings << finding
	} else {
		findings << c.vohs_method_fix(es, call, info, x, finding)!
	}
	return true
}

// vohs_method_for_inline_function is verifyCanUseMethodHandlerForInlineFunction; true when it
// reports.
fn (mut c Checker) vohs_method_for_inline_function(container int, function vue.Expr, x &VohsCtx, mut findings []Finding) !bool {
	info := c.vohs_token_info(container)
	if x.o.ignore_comment && info.has_comment {
		return false
	}
	es := &c.vue.doc.snippets[function.snippet].es
	node := function.node
	body := es.node(node, .body) or { return false }
	mut call := -1
	if es.typ(body) == .block_statement {
		call = vohs_identifier_call_of_body(es, es.list(body, .body) or { []int{} })
	} else if vohs_identifier_call(es, body) {
		call = body
	}
	same := call >= 0 && vohs_same_params_and_args(es, node, call)
	if !same && c.vue_refers_to_upper_variable(x.upper, es.nodes[node].start,
		es.nodes[node].end) {
		return false
	}
	finding := c.vue_report(es.nodes[node].start, es.nodes[node].end, if call >= 0 {
		'preferMethodOverInlineFunction'
	} else {
		'preferMethodOverInlineFunctionWithoutIdCall'
	}, {})
	if info.has_comment || !same {
		findings << finding
	} else {
		findings << c.vohs_method_fix(es, call, info, x, finding)!
	}
	return true
}

// vohs_same_params_and_args is isSameParamsAndArgs: the parameters (identifiers) are the
// arguments, as they are.
fn vohs_same_params_and_args(t &estree.EsTree, function int, call int) bool {
	params := t.list(function, .params) or { []int{} }
	args := t.list(call, .arguments) or { []int{} }
	if params.len != args.len {
		return false
	}
	for i, param in params {
		if t.typ(param) != .identifier || t.typ(args[i]) != .identifier
			|| vue_identifier_name(t, param) != vue_identifier_name(t, args[i]) {
			return false
		}
	}
	return true
}

// vohs_inline_function_for_inline is reportCanUseInlineFunctionForInlineHandler, fixed with
// `() => ` (and braces around several statements) unless it uses `$event` or has no quotes.
fn (mut c Checker) vohs_inline_function_for_inline(container int, on int, x &VohsCtx, mut findings []Finding) ! {
	doc := c.vue.doc
	n := &doc.nodes[on]
	start, end := c.vue_vnode_range(on)
	finding := c.vue_report(start, end, 'preferInlineFunctionOverInline', {})
	if x.event_ids.any(n.start <= it[0] && it[1] <= n.end) {
		findings << finding
		return
	}
	info := c.vohs_token_info(container)
	if !info.has_quote {
		findings << finding
		return
	}
	mut fixes := [fix_insert_at(info.start, '() => ')]
	first := c.vue_first_token_in(n.start, n.end) or {
		findings << c.with_fixes(finding, fixes)!
		return
	}
	last := c.vue_last_token_in(n.start, n.end) or {
		findings << c.with_fixes(finding, fixes)!
		return
	}
	single := last.value != ';' && n.exprs.len == 1 && c.vue_expr_type(n.exprs[0]) == 'ExpressionStatement'
	if !((first.value == '{' && last.value == '}') || single) {
		fixes << fix_insert_at(first.start, '{')
		fixes << fix_insert_at(last.end, '}')
	}
	findings << c.with_fixes(finding, fixes)!
}

// vohs_inline_for_inline_function is reportCanUseInlineHandlerForInlineFunction, fixed with the
// body of a function without parameters.
fn (mut c Checker) vohs_inline_for_inline_function(function vue.Expr, mut findings []Finding) ! {
	es := &c.vue.doc.snippets[function.snippet].es
	node := function.node
	params := es.list(node, .params) or { []int{} }
	finding := c.vue_report(es.nodes[node].start, es.nodes[node].end, if params.len > 1 {
		'preferInlineOverInlineFunctionWithMultipleParams'
	} else {
		'preferInlineOverInlineFunction'
	}, {})
	if params.len > 0 {
		findings << finding
		return
	}
	body := es.node(node, .body) or { return }
	mut text := c.vue.doc.src[es.nodes[body].start..es.nodes[body].end]
	if es.typ(body) == .block_statement {
		text = text[1..text.len - 1]
	}
	findings << c.with_fixes(finding, [
		fix_replace_range(es.nodes[node].start, es.nodes[node].end, text),
	])!
}
