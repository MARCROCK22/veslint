module rules

import estree
import time
import x.json2

// Port of the `@stylistic/space-infix-ops` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`int32Hint` and `ignoreTypes`) and its fixes: the spaces around the operators of binary,
// logical and assignment expressions, assignment patterns, conditional expressions and types,
// variable declarators, class properties, enum members, type aliases, and union and intersection
// types.

const ssio_messages = {
	'missingSpace': "Operator '{{operator}}' must be spaced."
}

struct SsioOptions {
	int32_hint   bool
	ignore_types bool
}

fn ssio_options(given []json2.Any) !SsioOptions {
	options := sty_options(given, [
		json2.Any({
			'int32Hint':   json2.Any(false)
			'ignoreTypes': json2.Any(false)
		}),
	])
	object := sty_option_object(options, 0)
	return SsioOptions{
		int32_hint:   sty_option_bool(object, 'int32Hint') or { false }
		ignore_types: sty_option_bool(object, 'ignoreTypes') or { false }
	}
}

fn (mut c Checker) lint_stylistic_space_infix_ops(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := ssio_options(c.rule_options(stylistic_space_infix_ops))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.assignment_expression, .assignment_pattern, .binary_expression, .logical_expression {
				stats.checked++
				c.ssio_check_binary(t, tokens, node, options, mut findings)
			}
			.conditional_expression {
				stats.checked++
				test := t.node(node, .test) or { continue }
				consequent := t.node(node, .consequent) or { continue }
				alternate := t.node(node, .alternate) or { continue }
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[test].end,
					t.nodes[consequent].start, mut findings)
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[consequent].end,
					t.nodes[alternate].start, mut findings)
			}
			.variable_declarator {
				stats.checked++
				id := t.node(node, .id) or { continue }
				init := t.node(node, .init) or { continue }
				left := t.node(id, .type_annotation) or { id }
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[left].end, t.nodes[init].start, mut
					findings)
			}
			.property_definition, .accessor_property {
				stats.checked++
				c.ssio_check_property_assignment(t, tokens, node, mut findings)
			}
			.ts_enum_member {
				stats.checked++
				id := t.node(node, .id) or { continue }
				initializer := t.node(node, .initializer) or { continue }
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[id].end,
					t.nodes[initializer].start, mut findings)
			}
			.ts_type_alias_declaration {
				stats.checked++
				left := t.node(node, .type_parameters) or { t.node(node, .id) or { continue } }
				annotation := t.node(node, .type_annotation) or { continue }
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[left].end,
					t.nodes[annotation].start, mut findings)
			}
			.ts_union_type, .ts_intersection_type {
				stats.checked++
				c.ssio_check_ts_binary(t, tokens, node, options, mut findings)
			}
			.ts_conditional_type {
				stats.checked++
				extends_type := t.node(node, .extends_type) or { continue }
				true_type := t.node(node, .true_type) or { continue }
				false_type := t.node(node, .false_type) or { continue }
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[extends_type].end,
					t.nodes[true_type].start, mut findings)
				c.ssio_check_assignment_space(t, tokens, node, t.nodes[true_type].end,
					t.nodes[false_type].start, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ssio_report ports report: the operator must be spaced, fixed by adding the missing spaces.
fn (c &Checker) ssio_report(tokens &SourceTokens, operator SourceToken, mut findings []Finding) {
	value := c.token_text(operator)
	previous := tokens.before(operator.start, false) or { return }
	after := tokens.after(operator.end, false) or { return }
	mut fix_string := ''
	if operator.start == previous.end {
		fix_string = ' '
	}
	fix_string += value
	if after.start == operator.end {
		fix_string += ' '
	}
	findings << Finding{
		stmt:       c.position_range(operator.start, operator.end)
		message_id: 'missingSpace'
		data:       {
			'operator': value
		}
		has_fix:    true
		fix:        fix_replace_range(operator.start, operator.end, fix_string)
	}
}

// ssio_not_spaced is `!isSpaceBetween(prev, operator) || !isSpaceBetween(operator, next)`.
fn ssio_not_spaced(tokens &SourceTokens, operator SourceToken) bool {
	previous := tokens.before(operator.start, false) or { return false }
	next := tokens.after(operator.end, false) or { return false }
	return !tokens.is_space_between(previous.end, operator.start)
		|| !tokens.is_space_between(operator.end, next.start)
}

// ssio_check_binary ports checkBinary.
fn (c &Checker) ssio_check_binary(t &estree.EsTree, tokens &SourceTokens, node int, options SsioOptions, mut findings []Finding) {
	left := t.node(node, .left) or { return }
	right := t.node(node, .right) or { return }
	left_node := t.node(left, .type_annotation) or { left }
	operator_value := t.string_of(node, .operator) or { '=' }
	// getFirstTokenBetween(left, right, token => token.value === op)
	mut operator := SourceToken{}
	mut found := false
	for token in tokens.inside(t.nodes[left_node].end, t.nodes[right].start, false) {
		if c.token_text(token) == operator_value {
			operator = token
			found = true
			break
		}
	}
	if !found || !ssio_not_spaced(tokens, operator) {
		return
	}
	if options.int32_hint && c.un_text(t, node).ends_with('|0') {
		return
	}
	c.ssio_report(tokens, operator, mut findings)
}

// ssio_check_assignment_space ports checkAndReportAssignmentSpace for what ends at `left_end` and
// what starts at `right_start`: the first `=`, `?` or `:` between them.
fn (c &Checker) ssio_check_assignment_space(t &estree.EsTree, tokens &SourceTokens, node int, left_end int, right_start int, mut findings []Finding) {
	for token in tokens.inside(left_end, right_start, false) {
		if token.kind == .punctuator && c.token_text(token) in ['=', '?', ':'] {
			if ssio_not_spaced(tokens, token) {
				c.ssio_report(tokens, token, mut findings)
			}
			return
		}
	}
}

// ssio_check_property_assignment ports checkPropertyAssignment.
fn (c &Checker) ssio_check_property_assignment(t &estree.EsTree, tokens &SourceTokens, node int, mut findings []Finding) {
	value := t.node(node, .value) or { return }
	key := t.node(node, .key) or { return }
	annotation := t.node(node, .type_annotation) or { -1 }
	mut left_end := 0
	if (t.flag(node, .optional) or { false }) && annotation < 0 {
		token := tokens.after(t.nodes[key].end, false) or { return }
		left_end = token.end
	} else if annotation >= 0 {
		left_end = t.nodes[annotation].end
	} else {
		left_end = t.nodes[key].end
	}
	c.ssio_check_assignment_space(t, tokens, node, left_end, t.nodes[value].start, mut findings)
}

// ssio_check_ts_binary ports checkTSBinary.
fn (c &Checker) ssio_check_ts_binary(t &estree.EsTree, tokens &SourceTokens, node int, options SsioOptions, mut findings []Finding) {
	if options.ignore_types {
		return
	}
	for typ in t.list(node, .types) or { []int{} } {
		mut index := source_tokens_index(tokens.tokens, t.nodes[typ].start) - 1
		if t.typ(typ) == .ts_function_type {
			// getTokenBefore(type, isNotOpeningParenToken)
			for index >= 0 && c.token_is(tokens.tokens[index], '(') {
				index--
			}
		}
		if index < 0 {
			continue
		}
		operator := tokens.tokens[index]
		if c.token_text(operator) !in ['|', '&'] {
			continue
		}
		if ssio_not_spaced(tokens, operator) {
			c.ssio_report(tokens, operator, mut findings)
		}
	}
}
