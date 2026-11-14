module rules

import estree
import time

// Port of the `unicorn/prefer-array-some` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestions. It reads types through the type checkers of
// utils/type-helpers.js (isIndexedCollection, isKnownNonIndexedCollection).

const upas_messages = {
	'some':            'Prefer `.some(…)` over `.{{method}}(…)`.'
	'some-suggestion': 'Replace `.{{method}}(…)` with `.some(…)`.'
	'filter':          'Prefer `.some(…)` over non-zero length check from `.filter(…)`.'
}

fn upas_is_checking_undefined(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .binary_expression || t.node(parent, .left) or { -1 } != node {
		return false
	}
	operator := t.string_of(parent, .operator) or { '' }
	right := t.node(parent, .right) or { return false }
	return (operator in ['!=', '==', '===', '!=='] && un_is_undefined(t, right))
		|| (operator in ['!=', '=='] && t.typ(right) == .literal && un_raw(t, right) == 'null')
}

fn upas_is_negative_one(t &estree.EsTree, node int) bool {
	if t.typ(node) != .unary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return false
	}
	argument := t.node(node, .argument) or { return false }
	value := t.get(argument, .value)
	return t.typ(argument) == .literal && value is f64 && value == 1
}

fn upas_is_literal_zero(t &estree.EsTree, node int) bool {
	value := t.get(node, .value)
	return t.typ(node) == .literal && value is f64 && value == 0
}

// upas_find_result_used_only_as_boolean ports isFindResultVariableUsedOnlyAsBoolean: the call is
// the initializer of a `const` of its own (not exported, without an annotation) only read as a
// boolean: in a boolean context when the receiver is an indexed collection, in a `Boolean(…)` call
// otherwise.
fn (mut c Checker) upas_find_result_used_only_as_boolean(t &estree.EsTree, call int, mut ctx UnbTypeContext) bool {
	declarator := t.nodes[call].parent
	if declarator < 0 || t.typ(declarator) != .variable_declarator
		|| t.node(declarator, .init) or { -1 } != call {
		return false
	}
	id := t.node(declarator, .id) or { return false }
	declaration := t.nodes[declarator].parent
	if t.typ(id) != .identifier || t.node(id, .type_annotation) != none || declaration < 0
		|| t.typ(declaration) != .variable_declaration
		|| (t.string_of(declaration, .kind) or { '' }) != 'const' || (t.nodes[declaration].parent >= 0
		&& t.typ(t.nodes[declaration].parent) == .export_named_declaration) {
		return false
	}
	tree := c.scope_tree(ctx.root)
	v := tree.declared_variable(t.ts_node(id) or { return false })
	// Vue.js template-local declarations may not have scope information.
	if v < 0 || tree.variables[v].identifiers.len != 1 {
		return false
	}
	references := tree.variables[v].references.filter(!tree.references[it].init)
	if references.len == 0 {
		return false
	}
	object := t.node(t.node(call, .callee) or { return false }, .object) or { return false }
	is_indexed_collection_receiver := c.unb_is_target(t, object, unb_indexed_collection_options(), mut
		ctx)
	for r in references {
		if !tree.references[r].read {
			return false
		}
		identifier := c.es_index_of(t, tree.references[r].identifier) or { return false }
		if is_indexed_collection_receiver {
			if !c.unb_is_boolean_context(ctx.root, t, identifier) {
				return false
			}
		} else if !c.unb_is_global_boolean_call(ctx.root, t, t.nodes[identifier].parent) {
			return false
		}
	}
	return true
}

// upas_find_index_fix ports the fixer of `.findIndex(…) !== -1` and the like; none where it aborts.
fn (mut c Checker) upas_find_index_fix(t &estree.EsTree, tokens &SourceTokens, node int, left int, method int, operator string) !(bool, Fix) {
	operator_token := c.un_token_after_punctuator(tokens, t.nodes[left].end, operator) or {
		return false, Fix{}
	}
	token_before_operator := tokens.before(operator_token.start, true) or { return false, Fix{} }
	// Start right after the token or comment before the operator, so the space before the operator
	// is not left dangling.
	start := token_before_operator.end
	end := t.nodes[node].end
	// Removing the comparison would drop comments or the newline ending a line comment.
	if token_before_operator.kind == .line_comment || tokens.comments_inside(start, end).len > 0 {
		return false, Fix{}
	}
	mut fixes := []Fix{}
	if operator in ['===', '==', '<'] {
		mut prefix := '!'
		if c.unb_should_add_parens_to_unary_replacement(t, tokens, node) {
			prefix = '(!'
			fixes << fix_insert_at(t.nodes[node].end, ')')
		}
		if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), prefix) {
			prefix = ';' + prefix
		}
		fixes << fix_insert_at(t.nodes[node].start, prefix)
	}
	fixes << fix_replace_range(t.nodes[method].start, t.nodes[method].end, 'some')
	fixes << fix_remove_range(start, end)
	return c.merge_fixes(fixes)!
}

fn (mut c Checker) lint_unicorn_prefer_array_some(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ == .call_expression {
			stats.checked++
			// `.find(…)`, `.findLast(…)`
			if !un_is_method_call(t, node,
				methods:           ['find', 'findLast']
				minimum_arguments: 1
				maximum_arguments: 2
				optional_call:     false
				optional_member:   false
			) {
				continue
			}
			if unb_has_type_arguments(t, node) {
				continue
			}
			callee := t.node(node, .callee) or { continue }
			if c.unb_is_known_non_target(t, t.node(callee, .object) or { continue },
				unb_indexed_collection_options(), mut ctx)
			{
				continue
			}
			is_compare := upas_is_checking_undefined(t, node)
			if !is_compare && !(c.unb_is_boolean_context(root, t, node)
				|| c.upas_find_result_used_only_as_boolean(t, node, mut ctx)) {
				continue
			}
			method := t.node(callee, .property) or { continue }
			name := t.string_of(method, .name) or { continue }
			parent := t.nodes[node].parent
			start, end := c.un_parenthesized_range(t, tokens, node)
			// Removing the comparison would drop comments between the call and the end of the
			// comparison.
			would_drop_comments := is_compare
				&& c.unb_would_remove_comments(tokens, UnbRange{end, t.nodes[parent].end}, [], false)
			mut suggestions := []Suggestion{}
			if !would_drop_comments {
				mut fixes := [fix_replace_range(t.nodes[method].start, t.nodes[method].end, 'some')]
				if is_compare {
					// The comparison is removed from right after the call, the space before the
					// operator goes with it.
					fixes << fix_remove_range(end, t.nodes[parent].end)
					if (t.string_of(parent, .operator) or { '' }) !in ['!=', '!=='] {
						fixes << fix_insert_at(start, '!')
					}
				}
				_, fix := c.merge_fixes(fixes)!
				suggestions << Suggestion{
					message_id: 'some-suggestion'
					data:       {
						'method': name
					}
					fix:        fix
				}
			}
			findings << Finding{
				stmt:        c.es_tree_position(t, method)
				message_id:  'some'
				data:        {
					'method': name
				}
				suggestions: suggestions
			}
			continue
		}
		if typ != .binary_expression {
			continue
		}
		stats.checked++
		left := t.node(node, .left) or { continue }
		right := t.node(node, .right) or { continue }
		operator := t.string_of(node, .operator) or { continue }
		// `.{findIndex,findLastIndex}(…) !== -1` and the like
		if un_is_method_call(t, left,
			methods:           ['findIndex', 'findLastIndex']
			// The second argument is the `thisArg`, which `.some(…)` takes too
			minimum_arguments: 1
			maximum_arguments: 2
			optional_call:     false
			optional_member:   false
		) && ((operator in ['!==', '!=', '>', '===', '=='] && upas_is_negative_one(t, right))
			|| (operator in ['>=', '<'] && upas_is_literal_zero(t, right))) {
			callee := t.node(left, .callee) or { continue }
			if c.unb_is_known_non_target(t, t.node(callee, .object) or { continue },
				unb_indexed_collection_options(), mut ctx)
			{
				continue
			}
			method := t.node(callee, .property) or { continue }
			name := t.string_of(method, .name) or { '' }
			has_fix, fix := c.upas_find_index_fix(t, tokens, node, left, method, operator)!
			// `.findLastIndex()` visits elements in reverse order, while `.some()` visits them
			// forwards, so only a side-effect-free inline callback is autofixed.
			arguments := t.list(left, .arguments) or { []int{} }
			if name == 'findLastIndex' && !unb_is_side_effect_free_function(t, arguments[0]) {
				findings << Finding{
					stmt:        c.es_tree_position(t, method)
					message_id:  'some'
					data:        {
						'method': name
					}
					suggestions: if has_fix {
						[
							Suggestion{
								message_id: 'some-suggestion'
								data:       {
									'method': name
								}
								fix:        fix
							},
						]
					} else {
						[]Suggestion{}
					}
				}
			} else {
				findings << Finding{
					stmt:       c.es_tree_position(t, method)
					message_id: 'some'
					data:       {
						'method': name
					}
					has_fix:    has_fix
					fix:        fix
				}
			}
		}
		// `.filter(…).length > 0`, `.filter(…).length !== 0`
		if operator in ['>', '!=='] && t.typ(right) == .literal && un_raw(t, right) == '0'
			&& un_is_member(t, left, properties: ['length'], optional: false) {
			filter_call := t.node(left, .object) or { continue }
			if !un_is_method_call(t, filter_call,
				methods:         ['filter']
				optional_call:   false
				optional_member: false
			) {
				continue
			}
			filter_call_object := t.node(t.node(filter_call, .callee) or { continue }, .object) or {
				continue
			}
			if (t.typ(filter_call_object) == .identifier
				&& (t.string_of(filter_call_object, .name) or { '' }).starts_with('$'))
				|| c.unb_is_known_non_target(t, filter_call_object, unb_indexed_collection_options(), mut
					ctx) {
				continue
			}
			arguments := t.list(filter_call, .arguments) or { []int{} }
			if arguments.len == 0 || un_is_node_value_not_function(t, arguments[0]) {
				continue
			}
			property := t.node(t.node(filter_call, .callee) or { continue }, .property) or { continue }
			_, filter_end := c.un_parenthesized_range(t, tokens, filter_call)
			mut has_fix := false
			mut fix := Fix{}
			// Removing `.length > 0` would drop comments in the removed range.
			if !c.unb_would_remove_comments(tokens, UnbRange{filter_end, t.nodes[node].end}, [], false) {
				_, length_end := c.un_parenthesized_range(t, tokens, left)
				has_fix, fix = c.merge_fixes([
					fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'some'),
					c.un_replace_member_property(t, tokens, left, ''),
					fix_remove_range(length_end, t.nodes[node].end),
				])!
			}
			// `.filter()` visits every element, while `.some()` stops at the first match, so only
			// a side-effect-free inline callback is autofixed.
			if unb_is_side_effect_free_function(t, arguments[0]) {
				findings << Finding{
					stmt:       c.es_tree_position(t, property)
					message_id: 'filter'
					has_fix:    has_fix
					fix:        fix
				}
			} else {
				findings << Finding{
					stmt:        c.es_tree_position(t, property)
					message_id:  'filter'
					suggestions: if has_fix {
						[
							Suggestion{
								message_id: 'some-suggestion'
								data:       {
									'method': 'filter'
								}
								fix:        fix
							},
						]
					} else {
						[]Suggestion{}
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
