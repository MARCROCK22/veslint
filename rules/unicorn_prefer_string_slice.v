module rules

import estree
import math
import time

// Port of the `unicorn/prefer-string-slice` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const upssl_messages = {
	'substr':    'Prefer `String#slice()` over `String#substr()`.'
	'substring': 'Prefer `String#slice()` over `String#substring()`.'
}

// upssl_numeric ports getNumericValue: a number literal, or `-` of one; none otherwise.
fn upssl_numeric(t &estree.EsTree, node int) ?f64 {
	if t.typ(node) == .literal {
		v := t.get(node, .value)
		if v is f64 {
			return v
		}
		return none
	}
	if t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == '-' {
		inner := upssl_numeric(t, t.node(node, .argument) or { return none })?
		return -inner
	}
	return none
}

fn upssl_is_length(t &estree.EsTree, node int) bool {
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false }) {
		return false
	}
	property := t.node(node, .property) or { return false }
	return t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == 'length'
}

fn upssl_is_number_literal(t &estree.EsTree, node int) bool {
	return t.typ(node) == .literal && t.get(node, .value) is f64
}

// upssl_max0 is `Math.max(0, x)`.
fn upssl_max0(x f64) f64 {
	if math.is_nan(x) {
		return x
	}
	return if x > 0 { x } else { 0.0 }
}

// un_has_possible_side_effect ports hasPossibleSideEffect: hasSideEffect, or a tagged template or
// a spread element in the node.
fn un_has_possible_side_effect(t &estree.EsTree, node int) bool {
	return un_has_side_effect(t, node) || un_contains_node(t, node, fn [t] (n int) bool {
		return t.typ(n) in [.tagged_template_expression, .spread_element]
	})
}

// un_precedence ports getPrecedence of utils/get-precedence.js.
fn un_precedence(t &estree.EsTree, node int) int {
	operator := t.string_of(node, .operator) or { '' }
	return match t.typ(node) {
		.sequence_expression {
			0
		}
		.assignment_expression, .arrow_function_expression, .yield_expression {
			1
		}
		.conditional_expression {
			3
		}
		.logical_expression {
			if operator == '&&' { 5 } else { 4 }
		}
		.binary_expression {
			match operator {
				'|' { 6 }
				'^' { 7 }
				'&' { 8 }
				'==', '!=', '===', '!==' { 9 }
				'<', '<=', '>', '>=', 'in', 'instanceof' { 10 }
				'<<', '>>', '>>>' { 11 }
				'+', '-' { 12 }
				'*', '/', '%' { 13 }
				else { 15 }
			}
		}
		.ts_as_expression, .ts_satisfies_expression {
			10
		}
		.unary_expression, .await_expression, .ts_type_assertion, .ts_non_null_expression {
			16
		}
		.update_expression {
			if t.flag(node, .prefix) or { false } { 16 } else { 17 }
		}
		.call_expression, .chain_expression, .import_expression {
			18
		}
		.new_expression {
			19
		}
		else {
			20
		}
	}
}

// upssl_is_literal_one ports isOne: the literal `1`.
fn upssl_is_literal_one(t &estree.EsTree, node int) bool {
	value := t.get(node, .value)
	return t.typ(node) == .literal && value is f64 && value == 1
}

// upssl_is_non_negative_integer ports isNonNegativeIntegerLiteral.
fn upssl_is_non_negative_integer(t &estree.EsTree, node int) bool {
	value := t.get(node, .value)
	return t.typ(node) == .literal && value is f64 && value >= 0 && value == math.trunc(value)
		&& value <= 9007199254740991.0
}

// upssl_index_from_plus_one ports getIndexFromPlusOne: `index + 1` or `1 + index`.
fn (mut c Checker) upssl_index_from_plus_one(t &estree.EsTree, node int, index int) bool {
	if t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) != '+' {
		return false
	}
	left := t.node(node, .left) or { return false }
	right := t.node(node, .right) or { return false }
	return (c.un_is_same_reference(t, left, index) && upssl_is_literal_one(t, right))
		|| (upssl_is_literal_one(t, left) && c.un_is_same_reference(t, right, index))
}

// upssl_single_character ports getSubstringSingleCharacterIndex (shared/substring.js): whether
// `substring()` takes a single character (`substring(i, i + 1)`).
fn (mut c Checker) upssl_single_character(t &estree.EsTree, node int) bool {
	if !un_is_method_call(t, node, methods: ['substring'], arguments_length: 2) {
		return false
	}
	args := t.list(node, .arguments) or { return false }
	first := args[0]
	second := args[1]
	if upssl_is_non_negative_integer(t, first) && upssl_is_non_negative_integer(t, second) {
		a := t.get(first, .value) as f64
		b := t.get(second, .value) as f64
		if math.abs(a - b) == 1 {
			return true
		}
	}
	if c.upssl_index_from_plus_one(t, second, first) || c.upssl_index_from_plus_one(t, first, second) {
		return true
	}
	// getIndexFromMinusOne
	if t.typ(first) == .binary_expression && (t.string_of(first, .operator) or { '' }) == '-'
		&& upssl_is_literal_one(t, t.node(first, .right) or { return false }) {
		return c.un_is_same_reference(t, t.node(first, .left) or { return false }, second)
	}
	return false
}

fn (mut c Checker) lint_unicorn_prefer_string_slice(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: ['substr', 'substring']) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		if c.un_is_known_non_string(mut ctx, t.node(callee, .object) or { continue }) {
			continue
		}
		property := t.node(callee, .property) or { continue }
		method := t.string_of(property, .name) or { continue }
		if method == 'substring' && c.upssl_single_character(t, node) {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: method
		}
		if fixes := c.upssl_fix(mut ctx, node, property, method) {
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upssl_fix ports the fixer; none where it aborts.
fn (mut c Checker) upssl_fix(mut ctx UnCtx, node int, property int, method string) ?[]Fix {
	t := ctx.t
	tokens := ctx.tokens
	mut fixes := [fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'slice')]
	args := t.list(node, .arguments) or { []int{} }
	if args.len == 0 {
		return fixes
	}
	if args.len > 2 || args.any(t.typ(it) == .spread_element) {
		return none
	}
	if method == 'substr' {
		fixes << c.upssl_substr(mut ctx, node, args)?
	} else {
		fixes << c.upssl_substring(t, tokens, args)?
	}
	return fixes
}

// upssl_replace_argument ports getArgumentReplacement: none (the fix aborts) when a comment in the
// parentheses would be lost.
fn (c &Checker) upssl_replace_argument(t &estree.EsTree, tokens &SourceTokens, node int, text string) ?Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	if un_has_comment_in_range(tokens, start, end) {
		return none
	}
	return fix_replace_range(start, end, text)
}

fn (c &Checker) upssl_wrap_max(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return [fix_insert_at(start, 'Math.max(0, '), fix_insert_at(end, ')')]
}

// upssl_coalesced_end_text ports getCoalescedEndText: `end === undefined ? Infinity : end`, none
// when reading the end twice could have a side effect.
fn (c &Checker) upssl_coalesced_end_text(t &estree.EsTree, tokens &SourceTokens, node int) ?string {
	if un_has_possible_side_effect(t, node) {
		return none
	}
	mut text := c.un_parenthesized_text(t, tokens, node)
	if !c.un_is_parenthesized(t, tokens, node)
		&& (t.typ(node) == .logical_expression || un_precedence(t, node) < 12) {
		text = '(${text})'
	}
	return '${text} === undefined ? Infinity : ${text}'
}

// upssl_negative_index ports getNegativeIndex: `-n` for `receiver.length - n`.
fn (mut c Checker) upssl_negative_index(t &estree.EsTree, tokens &SourceTokens, node int, receiver int) ?string {
	if t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return none
	}
	right := t.node(node, .right)?
	left := t.node(node, .left)?
	value := t.get(right, .value)
	if !(t.typ(right) == .literal && value is f64 && value > 0 && value == math.trunc(value)
		&& value <= 9007199254740991.0) || !upssl_is_length(t, left) {
		return none
	}
	if !(t.typ(receiver) == .identifier || un_static_string_value(t, receiver) != none)
		|| !c.un_is_same_reference(t, t.node(left, .object)?, receiver) {
		return none
	}
	// getArgumentRangeWithLeadingComments
	start, end := c.un_parenthesized_range(t, tokens, node)
	previous := tokens.before(start, false)?
	if un_has_comment_in_range(tokens, previous.end, end) {
		return none
	}
	return '-${un_raw(t, right)}'
}

// upssl_substr ports fixSubstrArguments; none where it aborts.
fn (mut c Checker) upssl_substr(mut ctx UnCtx, node int, args []int) ?[]Fix {
	t := ctx.t
	tokens := ctx.tokens
	if args.len < 2 {
		return []Fix{}
	}
	first := args[0]
	second := args[1]
	first_value := c.un_static_value_if_no_side_effects(mut ctx, first) or { StaticValue{} }
	if first_value.found && first_value.value.kind == .number_ && first_value.value.number == 0 {
		receiver := t.node(t.node(node, .callee)?, .object)?
		if negative := c.upssl_negative_index(t, tokens, second, receiver) {
			return [c.upssl_replace_argument(t, tokens, second, negative)?]
		}
		if upssl_is_number_literal(t, second) || upssl_is_length(t, second) {
			return []Fix{}
		}
		if n := upssl_numeric(t, second) {
			return [c.upssl_replace_argument(t, tokens, second, js_number_to_string(upssl_max0(n)))?]
		}
		end_text := c.upssl_coalesced_end_text(t, tokens, second)?
		start, end := c.un_parenthesized_range(t, tokens, second)
		return [fix_replace_range(start, end, 'Math.max(0, ${end_text})')]
	}
	if upssl_is_number_literal(t, first) && upssl_is_number_literal(t, second) {
		a := t.get(first, .value) as f64
		b := t.get(second, .value) as f64
		// `substr()` runs ToInteger on each argument before adding them.
		return [c.upssl_replace_argument(t, tokens, second, js_number_to_string(math.trunc(a) +
			math.trunc(b)))?]
	}
	return none
}

// upssl_substring ports fixSubstringArguments; none where it aborts.
fn (c &Checker) upssl_substring(t &estree.EsTree, tokens &SourceTokens, args []int) ?[]Fix {
	first := args[0]
	first_number := upssl_numeric(t, first)
	if args.len < 2 {
		if upssl_is_length(t, first) {
			return []Fix{}
		}
		if n := first_number {
			return [c.upssl_replace_argument(t, tokens, first, js_number_to_string(upssl_max0(n)))?]
		}
		return c.upssl_wrap_max(t, tokens, first)
	}
	second := args[1]
	second_number := upssl_numeric(t, second)
	if a := first_number {
		if b := second_number {
			mut values := [upssl_max0(a), upssl_max0(b)]
			if a > b {
				values = values.reverse()
			}
			mut fixes := []Fix{}
			// `!==`: NaN is never the same.
			if values[0] != a || math.is_nan(a) {
				fixes << c.upssl_replace_argument(t, tokens, first, js_number_to_string(values[0]))?
			}
			if values[1] != b || math.is_nan(b) {
				fixes << c.upssl_replace_argument(t, tokens, second, js_number_to_string(values[1]))?
			}
			return fixes
		}
	}
	first_zero := if a := first_number { a == 0 } else { false }
	second_zero := if b := second_number { b == 0 } else { false }
	if first_zero || second_zero {
		// Swapped, the moved argument is the start, where `undefined` means 0: used as is.
		end_text := if second_zero {
			c.un_parenthesized_text(t, tokens, first)
		} else {
			c.upssl_coalesced_end_text(t, tokens, second)?
		}
		return [c.upssl_replace_argument(t, tokens, first, '0')?,
			c.upssl_replace_argument(t, tokens, second, 'Math.max(0, ${end_text})')?]
	}
	return none
}
