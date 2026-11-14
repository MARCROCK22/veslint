module rules

import estree
import time

// Port of the `unicorn/prefer-math-min-max` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const upmmm_messages = {
	'prefer-math-min-max': 'Prefer `Math.{{method}}()` to simplify ternary expressions.'
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

fn (mut c Checker) lint_unicorn_prefer_math_min_max(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
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
		if [left, right].any((t.typ(it) == .literal && t.string_of(it, .bigint) != none)
			|| un_is_call(t, it, names: ['BigInt'], arguments_length: 1, optional: false)) {
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
		if !c.upmmm_numbers(root, t, [left, right]) {
			continue
		}
		mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
		texts := [left, right].map(if t.typ(it) == .sequence_expression {
			'(${c.un_text(t, it)})'
		} else {
			c.un_text(t, it)
		})
		fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Math.${method}(${texts.join(', ')})')
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-math-min-max'
			data:       {
				'method': method
			}
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upmmm_numbers: neither operand is asserted or declared to be something other than a number
// (the checks of the loop over `[left, right]`).
fn (mut c Checker) upmmm_numbers(root C.TSNode, t &estree.EsTree, operands []int) bool {
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
		ts := t.ts_node(expression) or { continue }
		tree := c.scope_tree(root)
		v := tree.own_variable(tree.get_scope(ts), t.string_of(expression, .name) or { continue })
		if v < 0 {
			continue
		}
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
						if t.typ(default_value) == .literal && t.get(default_value, .value) !is f64 {
							return false
						}
					}
				}
				.variable {
					declarator := c.es_index_of(t, def.node) or { continue }
					id := t.node(declarator, .id) or { continue }
					if annotation := t.node(id, .type_annotation) {
						if t.typ(annotation) == .ts_type_annotation
							&& !upmmm_number_annotation(t, annotation) {
							return false
						}
					}
					if init := t.node(declarator, .init) {
						if t.typ(init) == .literal && t.get(init, .value) !is f64 {
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
