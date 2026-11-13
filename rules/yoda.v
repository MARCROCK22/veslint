module rules

import json2
import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `yoda` rule of ESLint 10.6.0, with its options and its fix.

const yoda_messages = {
	'expected': 'Expected literal to be on the {{expectedSide}} side of {{operator}}.'
}

const yoda_flip = {
	'===': '==='
	'!==': '!=='
	'==':  '=='
	'!=':  '!='
	'<':   '>'
	'>':   '<'
	'<=':  '>='
	'>=':  '<='
}

struct YodaOptions {
	always        bool
	except_range  bool
	only_equality bool
}

// yoda_options reads "always" or "never", exceptRange and onlyEquality.
fn yoda_options(options []json2.Any) !YodaOptions {
	when := if options.len > 0 { options[0] } else { json2.Any('never') }
	if when !is string || when.str() !in ['always', 'never'] {
		return error('the first option of `${yoda}` must be "always" or "never"')
	}
	o := option_object(yoda, if options.len > 1 { options[1..] } else { []json2.Any{} },
		['exceptRange', 'onlyEquality'])!
	return YodaOptions{
		always:        when.str() == 'always'
		except_range:  o.bool_value('exceptRange') or { false }
		only_equality: o.bool_value('onlyEquality') or { false }
	}
}

fn (mut c Checker) lint_yoda(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := yoda_options(c.rule_options(yoda))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		operator := operator_of(node)
		if operator !in yoda_flip {
			continue
		}
		stats.checked++
		left := unwrap_parens(node_field(node, 'left') or { continue })
		right := unwrap_parens(node_field(node, 'right') or { continue })
		expected_literal := if o.always { left } else { right }
		expected_other := if o.always { right } else { left }
		if !c.yoda_looks_like_literal(expected_other) || c.yoda_looks_like_literal(expected_literal) {
			continue
		}
		if o.only_equality && operator !in ['==', '==='] {
			continue
		}
		if o.except_range {
			if parent := cti_estree_parent(node) {
				if c.yoda_is_range_test(parent) {
					continue
				}
			}
		}
		has_fix, fix := c.yoda_fix(root, node, left, right, operator)
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'expected'
			data:       {
				'operator':     operator
				'expectedSide': if o.always { 'left' } else { 'right' }
			}
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// yoda_is_negative_number ports isNegativeNumericLiteral: `-` before a number.
fn yoda_is_negative_number(n C.TSNode) bool {
	if node_kind(n) != 'unary_expression' || operator_of(n) != '-' {
		return false
	}
	argument := unwrap_parens(node_field(n, 'argument') or { return false })
	return node_kind(argument) == 'number'
}

// yoda_looks_like_literal: a Literal, a negative number or a template without substitutions.
fn (c &Checker) yoda_looks_like_literal(n C.TSNode) bool {
	if es_is_literal(n) || yoda_is_negative_number(n) {
		return true
	}
	if node_kind(n) == 'template_string' {
		expressions, _ := c.es_template_parts(n)
		return expressions.len == 0
	}
	return false
}

// yoda_value ports getNormalizedLiteral: the value of a literal-like node.
fn (c &Checker) yoda_value(n C.TSNode) ?JsValue {
	match node_kind(n) {
		'number' {
			text := c.text(n)
			if text.ends_with('n') {
				return JsValue{
					kind: .bigint_
					text: text.replace('_', '').trim_right('n')
				}
			}
			return JsValue{
				kind:   .number_
				number: number_literal_value(text)?
			}
		}
		'string', 'template_string', 'regex' {
			if node_kind(n) == 'template_string' {
				expressions, _ := c.es_template_parts(n)
				if expressions.len > 0 {
					return none
				}
			}
			return JsValue{
				kind: .string_
				text: c.literal_name(n)?
			}
		}
		'true', 'false' {
			return JsValue{
				kind:    .boolean_
				boolean: node_kind(n) == 'true'
			}
		}
		'null' {
			return JsValue{
				kind: .null_
			}
		}
		'unary_expression' {
			if !yoda_is_negative_number(n) {
				return none
			}
			value := c.yoda_value(unwrap_parens(node_field(n, 'argument')?))?
			if value.kind == .bigint_ {
				return JsValue{
					kind: .bigint_
					text: if value.text.starts_with('-') {
						value.text[1..]
					} else {
						'-' + value.text
					}
				}
			}
			return JsValue{
				kind:   .number_
				number: -value.number
			}
		}
		else {
			return none
		}
	}
}

// yoda_is_range_test ports isRangeTest: `(a < x && x < b)` or `(x < a || b < x)`, in
// parentheses, with the literals in order.
fn (mut c Checker) yoda_is_range_test(n C.TSNode) bool {
	if node_kind(n) != 'binary_expression' || estree_binary_kind(n) != 'LogicalExpression' {
		return false
	}
	left := unwrap_parens(node_field(n, 'left') or { return false })
	right := unwrap_parens(node_field(n, 'right') or { return false })
	if estree_binary_kind(left) != 'BinaryExpression' || estree_binary_kind(right) != 'BinaryExpression'
		|| operator_of(left) !in ['<', '<='] || operator_of(right) !in ['<', '<='] {
		return false
	}
	ll := unwrap_parens(node_field(left, 'left') or { return false })
	lr := unwrap_parens(node_field(left, 'right') or { return false })
	rl := unwrap_parens(node_field(right, 'left') or { return false })
	rr := unwrap_parens(node_field(right, 'right') or { return false })
	operator := operator_of(n)
	mut in_order := false
	if operator == '&&' && c.es_is_same_reference(lr, rl, false) {
		in_order = c.yoda_in_order(ll, rr)
	} else if operator == '||' && c.es_is_same_reference(ll, rr, false) {
		in_order = c.yoda_in_order(lr, rl)
	}
	return in_order && c.es_is_parenthesised(n)
}

// yoda_in_order: one side is not a literal, or the first is not greater than the second.
fn (c &Checker) yoda_in_order(a C.TSNode, b C.TSNode) bool {
	x := c.yoda_value(a)
	y := c.yoda_value(b)
	if x == none && y == none {
		return false
	}
	first := x or { return true }
	second := y or { return true }
	return js_compare(first, '<=', second)
}

// yoda_fix ports getFlippedString: the right side, the operator flipped, then the left side.
fn (mut c Checker) yoda_fix(root C.TSNode, node C.TSNode, left C.TSNode, right C.TSNode, operator string) (bool, Fix) {
	tokens := c.source_tokens(root)
	mut operator_token := tokens.after(c.es_end(left), false) or { return false, Fix{} }
	for c.src[operator_token.start..operator_token.end] != operator {
		operator_token = tokens.after(operator_token.end, false) or { return false, Fix{} }
	}
	last_left := tokens.before(operator_token.start, false) or { return false, Fix{} }
	first_right := tokens.after(operator_token.end, false) or { return false, Fix{} }
	start := node_start(node)
	end := c.es_end(node)
	left_text := c.src[start..last_left.end]
	before_operator := c.src[last_left.end..operator_token.start]
	after_operator := c.src[operator_token.end..first_right.start]
	right_text := c.src[first_right.start..end]
	mut prefix := ''
	mut suffix := ''
	if before := tokens.before(start, false) {
		if before.end == start && !c.es_can_tokens_be_adjacent(before, first_right) {
			prefix = ' '
		}
	}
	if after := tokens.after(end, false) {
		if after.start == end && !c.es_can_tokens_be_adjacent(last_left, after) {
			suffix = ' '
		}
	}
	return true, fix_replace_range(start, end, prefix + right_text + before_operator +
		yoda_flip[operator] + after_operator + left_text + suffix)
}
