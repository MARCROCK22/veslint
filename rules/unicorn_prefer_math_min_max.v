module rules

import estree
import time

// Port of the `unicorn/prefer-math-min-max` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its suggestion.

const upmmm_messages = {
	'prefer-math-min-max':       'Prefer `Math.{{method}}()` to simplify ternary expressions.'
	'replace-with-math-min-max': 'Replace with `Math.{{method}}()`.'
}

// upmmm_number_annotation ports isNumberTypeAnnotation.
fn upmmm_number_annotation(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.ts_number_keyword {
			return true
		}
		.ts_type_annotation {
			inner := t.node(node, .type_annotation) or { return false }
			return t.typ(inner) == .ts_number_keyword
		}
		.ts_type_reference {
			name := t.node(node, .type_name) or { return false }
			return (t.string_of(name, .name) or { '' }) == 'Number'
		}
		else {
			return false
		}
	}
}

// upmmm_unwrap ports unwrapNode: without `as`, `<T>` and `!`.
fn upmmm_unwrap(t &estree.EsTree, node int) int {
	mut n := node
	for t.typ(n) in [.ts_as_expression, .ts_type_assertion, .ts_non_null_expression] {
		n = t.node(n, .expression) or { return n }
	}
	return n
}

// upmmm_type_annotation ports getTypeAnnotation: the type of an `as` or `<T>`, through `!`.
fn upmmm_type_annotation(t &estree.EsTree, node int) ?int {
	return match t.typ(node) {
		.ts_non_null_expression { upmmm_type_annotation(t, t.node(node, .expression)?) }
		.ts_as_expression, .ts_type_assertion { t.node(node, .type_annotation) }
		else { none }
	}
}

// upmmm_is_effect_free ports isEffectFreeOperand: reading the operand runs no code and writes
// nothing (a member access is allowed), so reading it once instead of twice is the same.
fn upmmm_is_effect_free(t &estree.EsTree, from int) bool {
	node := upmmm_unwrap(t, from)
	if t.typ(node) in [.assignment_expression, .await_expression, .call_expression, .import_expression,
		.new_expression, .tagged_template_expression, .update_expression, .yield_expression] {
		return false
	}
	if t.typ(node) == .template_literal {
		return (t.list(node, .expressions) or { []int{} }).len == 0
	}
	if t.typ(node) in [.arrow_function_expression, .class_declaration, .class_expression,
		.function_declaration, .function_expression] {
		return true
	}
	return t.children(node).all(upmmm_is_effect_free(t, it))
}

// upmmm_call_argument_text ports getCallArgumentText: the text of the node as one argument of a
// call (a sequence in parentheses); its parentheses are kept when they hold comments.
fn (c &Checker) upmmm_call_argument_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	if c.un_is_parenthesized(t, tokens, node) {
		start, end := c.un_parenthesized_range(t, tokens, node)
		if un_would_remove_comments(tokens, start, end, [un_range(t, node)]) {
			return c.src[start..end]
		}
	}
	text := c.un_text(t, node)
	return if t.typ(node) == .sequence_expression { '(${text})' } else { text }
}

fn (mut c Checker) lint_unicorn_prefer_math_min_max(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	bigint_options := UnTypeOptions{
		...un_type_options(.bigint)
		treat_mixed_union_as_target: true
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .conditional_expression {
			continue
		}
		stats.checked++
		test := t.node(node, .test) or { continue }
		if t.typ(test) != .binary_expression {
			continue
		}
		operator := t.string_of(test, .operator) or { continue }
		left := t.node(test, .left) or { continue }
		right := t.node(test, .right) or { continue }
		consequent := t.node(node, .consequent) or { continue }
		alternate := t.node(node, .alternate) or { continue }
		if c.un_is_bigint(mut ctx, left, bigint_options) || c.un_is_bigint(mut ctx, right, bigint_options) {
			continue
		}
		if [left, right].any(un_is_new(t, it, names: ['Date'])) {
			continue
		}
		left_text := c.un_text(t, upmmm_unwrap(t, left))
		right_text := c.un_text(t, upmmm_unwrap(t, right))
		alternate_text := c.un_text(t, upmmm_unwrap(t, alternate))
		consequent_text := c.un_text(t, upmmm_unwrap(t, consequent))
		greater := operator in ['>', '>=']
		less := operator in ['<', '<=']
		method := if (greater && left_text == alternate_text && right_text == consequent_text)
			|| (less && left_text == consequent_text && right_text == alternate_text) {
			'min'
		} else if (greater && left_text == consequent_text && right_text == alternate_text)
			|| (less && left_text == alternate_text && right_text == consequent_text) {
			'max'
		} else {
			continue
		}
		if !c.upmmm_numbers(mut ctx, [left, right], bigint_options) {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-math-min-max'
			data:       {
				'method': method
			}
		}
		// The replacement is rebuilt from both operands, and reads each once where the source
		// reads it twice; it differs for NaN and signed zero: only a suggestion.
		left_start, left_end := c.un_parenthesized_range(t, tokens, left)
		right_start, right_end := c.un_parenthesized_range(t, tokens, right)
		if !un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, [
			UnRange{left_start, left_end},
			UnRange{right_start, right_end},
		]) && upmmm_is_effect_free(t, left) && upmmm_is_effect_free(t, right) {
			mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
			texts := [left, right].map(c.upmmm_call_argument_text(t, tokens, it))
			fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Math.${method}(${texts.join(', ')})')
			_, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'replace-with-math-min-max'
						data:       {
							'method': method
						}
						fix:        fix
					},
				]
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upmmm_numbers: neither operand is asserted or declared to be something other than a number
// (the checks of the loop over `[left, right]`).
fn (mut c Checker) upmmm_numbers(mut ctx UnCtx, operands []int, bigint_options UnTypeOptions) bool {
	t := ctx.t
	for node in operands {
		expression := upmmm_unwrap(t, node)
		if node != expression {
			if annotation := upmmm_type_annotation(t, node) {
				if !upmmm_number_annotation(t, annotation) {
					return false
				}
			}
		}
		if t.typ(expression) != .identifier {
			continue
		}
		// The declaration can be in any enclosing scope.
		v := c.un_find_variable(ctx, expression)
		if v < 0 {
			continue
		}
		tree := c.scope_tree(ctx.root)
		for def in tree.variables[v].defs {
			match def.kind {
				.parameter {
					identifier := c.es_index_of(t, def.name) or { continue }
					if annotation := t.node(identifier, .type_annotation) {
						if t.typ(annotation) == .ts_type_annotation
							&& !upmmm_number_annotation(t, annotation) {
							return false
						}
					}
					parent := t.nodes[identifier].parent
					if t.typ(parent) == .assignment_pattern {
						default_value := t.node(parent, .right) or { continue }
						if (t.typ(default_value) == .literal && t.get(default_value, .value) !is f64)
							|| un_static_string_value(t, default_value) != none
							|| c.un_is_bigint(mut ctx, default_value, bigint_options) {
							return false
						}
					}
				}
				.variable {
					declarator := c.es_index_of(t, def.node) or { continue }
					if t.typ(declarator) != .variable_declarator {
						continue
					}
					id := t.node(declarator, .id) or { continue }
					if annotation := t.node(id, .type_annotation) {
						if t.typ(annotation) == .ts_type_annotation
							&& !upmmm_number_annotation(t, annotation) {
							return false
						}
					}
					if init := t.node(declarator, .init) {
						if (t.typ(init) == .literal && t.get(init, .value) !is f64)
							|| un_static_string_value(t, init) != none {
							return false
						}
						if c.un_is_bigint(mut ctx, init, bigint_options) {
							return false
						}
						if un_is_new(t, init, names: ['Date']) {
							return false
						}
					}
				}
				else {}
			}
		}
	}
	return true
}
