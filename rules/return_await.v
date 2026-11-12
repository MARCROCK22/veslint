module rules

import json2
import time
import treesitter { first_named_child, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kind, position_of }

// Port of the `return-await` rule of typescript-eslint 8.62.0 with its option, its fix and its
// suggestions: whether a returned Promise must be awaited, must not, or either, in an
// error-handling context and outside of it (the default, 'in-try-catch': it must inside, and must
// not outside). Limits of the port: README, "Rules" section.

const rw_messages = {
	'disallowedPromiseAwait':           'Returning an awaited promise is not allowed in this context.'
	'disallowedPromiseAwaitSuggestion': 'Remove `await` before the expression. Use caution as this may impact control flow.'
	'nonPromiseAwait':                  'Returning an awaited value that is not a promise is not allowed.'
	'requiredPromiseAwait':             'Returning an awaited promise is required in this context.'
	'requiredPromiseAwaitSuggestion':   'Add `await` before the expression. Use caution as this may impact control flow.'
}

// RwContext is what the option asks of a returned Promise in a context.
enum RwContext {
	await_
	no_await
	dont_care
}

// RwOptions ports getConfiguration.
struct RwOptions {
	error_handling RwContext
	ordinary       RwContext
}

fn rw_options(options []json2.Any) !RwOptions {
	option := if options.len > 0 { options[0] } else { json2.Any('in-try-catch') }
	if option is string {
		match option {
			'always' {
				return RwOptions{
					error_handling: .await_
					ordinary:       .await_
				}
			}
			'error-handling-correctness-only' {
				return RwOptions{
					error_handling: .await_
					ordinary:       .dont_care
				}
			}
			'in-try-catch' {
				return RwOptions{
					error_handling: .await_
					ordinary:       .no_await
				}
			}
			'never' {
				return RwOptions{
					error_handling: .no_await
					ordinary:       .no_await
				}
			}
			else {}
		}
	}
	return error("the option of `${return_await}` must be 'always', 'error-handling-correctness-only', 'in-try-catch' or 'never'")
}

// ReturnedNode is a value the function may return.
struct ReturnedNode {
	node     C.TSNode // the ESTree node, where the rule reports
	is_await bool
	typed    C.TSNode // the node whose type counts: the operand of the await or the node itself
mut:
	affects bool // it is in an error-handling context (affectsExplicitErrorHandling)
}

fn (mut c Checker) lint_return_await(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := rw_options(c.rule_options(return_await))!
	mut returned := []ReturnedNode{}
	// ReturnStatement inside an async function.
	for ret in c.nodes_of_kind(root, c'return_statement') {
		arg := first_named_child(ret) or { continue }
		f := enclosing_function(ret) or { continue }
		if has_child_kind(f, 'async') {
			// Between the value and the `return` there are only conditionals and parentheses: the
			// error-handling context is the `return`'s, computed once.
			affects := affects_error_handling(ret)
			for mut r in c.possibly_returned(arg, 0) {
				r.affects = affects
				returned << r
			}
		}
	}
	// ArrowFunctionExpression[async = true] with an expression body.
	for f in c.nodes_of_kind(root, c'arrow_function') {
		body := node_field(f, 'body') or { continue }
		if has_child_kind(f, 'async') && node_kind(body) != 'statement_block' {
			returned << c.possibly_returned(body, 0)
		}
	}
	mut spans := returned.map(node_span(it.typed))
	for r in returned {
		if r.is_await {
			// needsToBeAwaited is asked at the whole expression, the `await` included.
			spans << Span{
				...node_span(r.node)
				optional: true
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for r in returned {
		t := c.node_type(r.typed) or { continue }
		certainty := c.needs_to_be_awaited(t, c.symbol_location(r.node))!
		affects := r.affects || affects_resource_management(r.node)
		context := if affects { o.error_handling } else { o.ordinary }
		message_id := if certainty != .always {
			if r.is_await && certainty == .never { 'nonPromiseAwait' } else { '' }
		} else if context == .await_ && !r.is_await {
			'requiredPromiseAwait'
		} else if context == .no_await && r.is_await {
			'disallowedPromiseAwait'
		} else {
			''
		}
		if message_id != '' {
			finding := Finding{
				stmt:       position_of(r.node)
				message_id: message_id
			}
			// A value that is not a promise always gets the fix; a promise only outside an
			// error-handling context, where the fix could change the control flow and is suggested.
			findings << match message_id {
				'nonPromiseAwait' {
					c.with_fixes(finding, c.rw_remove_await(r.node))!
				}
				'requiredPromiseAwait' {
					c.rw_fix_or_suggest(finding, !affects, 'requiredPromiseAwaitSuggestion',
						rw_insert_await(r.node))!
				}
				else {
					c.rw_fix_or_suggest(finding, !affects, 'disallowedPromiseAwaitSuggestion',
						c.rw_remove_await(r.node))!
				}
			}
		}
	}
	findings.sort(a.stmt.start_byte < b.stmt.start_byte)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += returned.len
	return findings
}

// rw_fix_or_suggest ports getFixOrSuggest: the fixes as the fix of the finding or as its only
// suggestion.
fn (c &Checker) rw_fix_or_suggest(finding Finding, as_fix bool, suggestion_id string, fixes []Fix) !Finding {
	if as_fix {
		return c.with_fixes(finding, fixes)
	}
	ok, suggestion := c.suggestion(suggestion_id, map[string]string{}, fixes)!
	return Finding{
		...finding
		suggestions: if ok { [suggestion] } else { []Suggestion{} }
	}
}

// rw_remove_await ports removeAwait: the `await` keyword of the AwaitExpression goes, with what
// follows it up to the next token or comment.
fn (mut c Checker) rw_remove_await(node C.TSNode) []Fix {
	if node_kind(node) != 'await_expression' {
		return []Fix{}
	}
	keyword := c.first_token(node) or { return []Fix{} }
	if c.token_text(keyword) != 'await' {
		return []Fix{}
	}
	mut end := keyword.end
	if next := c.source_tokens(node).after(keyword.end, true) {
		end = next.start
	}
	return [fix_remove_range(keyword.start, end)]
}

// rw_insert_await ports insertAwait: `await ` before the expression, around parentheses unless
// the expression binds tighter than `await`.
fn rw_insert_await(node C.TSNode) []Fix {
	if is_higher_precedence_than_await(node) {
		return [fix_insert_before(node, 'await ')]
	}
	return [fix_insert_before(node, 'await ('), fix_insert_after(node, ')')]
}

// possibly_returned ports findPossiblyReturnedNodes: the branches of conditionals, without
// parentheses (they are not nodes in ESTree).
fn (mut c Checker) possibly_returned(n C.TSNode, depth int) []ReturnedNode {
	if depth > max_expression_depth {
		c.too_deep++
		return []ReturnedNode{}
	}
	node := unwrap_parens(n)
	match node_kind(node) {
		'ternary_expression' {
			mut out := []ReturnedNode{}
			if alternative := node_field(node, 'alternative') {
				out << c.possibly_returned(alternative, depth + 1)
			}
			if consequence := node_field(node, 'consequence') {
				out << c.possibly_returned(consequence, depth + 1)
			}
			return out
		}
		'await_expression' {
			operand := first_named_child(node) or { return []ReturnedNode{} }
			return [ReturnedNode{
				node:     node
				is_await: true
				typed:    operand
			}]
		}
		else {
			return [ReturnedNode{
				node:  node
				typed: node
			}]
		}
	}
}

// affects_resource_management ports affectsExplicitResourceManagement: a `using` or `await using`
// declaration that ends before the node, in the scope of the node or in one around it up to the
// function's: the blocks and the `for` headers that contain the node, inside its function.
fn affects_resource_management(n C.TSNode) bool {
	start := node_start(n)
	mut node := node_parent(n) or { return false }
	for node_kind(node) !in function_kinds {
		match node_kind(node) {
			'statement_block', 'program' {
				for child in named_children(node) {
					if node_kind(child) == 'lexical_declaration' && using_kind(child) != ''
						&& using_declarator_before(child, start) {
						return true
					}
				}
			}
			'for_statement' {
				if initializer := node_field(node, 'initializer') {
					if using_kind(initializer) != '' && using_declarator_before(initializer, start) {
						return true
					}
				}
			}
			'for_in_statement' {
				if using_kind(node) != '' {
					if left := node_field(node, 'left') {
						if node_end(left) < start {
							return true
						}
					}
				}
			}
			else {}
		}
		node = node_parent(node) or { return false }
	}
	return false
}

// using_declarator_before: some declarator of the declaration ends before `offset`.
fn using_declarator_before(declaration C.TSNode, offset int) bool {
	for declarator in named_children(declaration) {
		if node_kind(declarator) == 'variable_declarator' && node_end(declarator) < offset {
			return true
		}
	}
	return false
}

// affects_error_handling ports affectsExplicitErrorHandling: the node is in the block of a try, or
// in a catch followed by a finally; from a catch without a finally or from a finally, the try that
// contains them counts. The search stops at the function that contains the node.
fn affects_error_handling(n C.TSNode) bool {
	mut child := n
	mut node := node_parent(n) or { return false }
	for node_kind(node) !in function_kinds {
		if node_kind(node) == 'try_statement' {
			if same_node(node_field(node, 'body'), child) {
				return true
			}
			if same_node(node_field(node, 'handler'), child) {
				if _ := node_field(node, 'finalizer') {
					return true
				}
			}
			return affects_error_handling(node)
		}
		child = node
		node = node_parent(node) or { return false }
	}
	return false
}
