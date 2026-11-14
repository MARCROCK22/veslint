module rules

import estree
import math
import time

// Port of the `unicorn/prefer-string-slice` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const upssl_messages = {
	'substr':    'Prefer `String#slice()` over `String#substr()`.'
	'substring': 'Prefer `String#slice()` over `String#substring()`.'
}

// upssl_numeric ports getNumericValue: a number literal, or `-` of one (NaN when what is negated is
// not one, as `-undefined`); none otherwise.
fn upssl_numeric(t &estree.EsTree, node int) ?f64 {
	if t.typ(node) == .literal {
		v := t.get(node, .value)
		if v is f64 {
			return v
		}
		return none
	}
	if t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == '-' {
		inner := upssl_numeric(t, t.node(node, .argument) or { return none }) or { return math.nan() }
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

fn (mut c Checker) lint_unicorn_prefer_string_slice(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: ['substr', 'substring']) {
			continue
		}
		property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
		method := t.string_of(property, .name) or { continue }
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: method
		}
		if fixes := c.upssl_fix(t, tokens, node, property, method) {
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
fn (mut c Checker) upssl_fix(t &estree.EsTree, tokens &SourceTokens, node int, property int, method string) ?[]Fix {
	mut fixes := [fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'slice')]
	args := t.list(node, .arguments) or { []int{} }
	if args.len == 0 {
		return fixes
	}
	if args.len > 2 || args.any(t.typ(it) == .spread_element) {
		return none
	}
	if method == 'substr' {
		fixes << c.upssl_substr(t, tokens, node, args)?
	} else {
		fixes << c.upssl_substring(t, tokens, args)?
	}
	return fixes
}

fn (c &Checker) upssl_replace_argument(t &estree.EsTree, tokens &SourceTokens, node int, text string) Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return fix_replace_range(start, end, text)
}

fn (c &Checker) upssl_wrap_max(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return [fix_insert_at(start, 'Math.max(0, '), fix_insert_at(end, ')')]
}

// upssl_substr ports fixSubstrArguments.
fn (mut c Checker) upssl_substr(t &estree.EsTree, tokens &SourceTokens, node int, args []int) ?[]Fix {
	if args.len < 2 {
		return []Fix{}
	}
	first := args[0]
	second := args[1]
	first_value := c.un_static_value(t, first)
	if first_value.found && first_value.value.kind == .number_ && first_value.value.number == 0 {
		if upssl_is_number_literal(t, second) || upssl_is_length(t, second) {
			return []Fix{}
		}
		if n := upssl_numeric(t, second) {
			return [c.upssl_replace_argument(t, tokens, second, js_number_to_string(upssl_max0(n)))]
		}
		return c.upssl_wrap_max(t, tokens, second)
	}
	if upssl_is_number_literal(t, first) && upssl_is_number_literal(t, second) {
		a := upssl_numeric(t, first) or { return none }
		b := upssl_numeric(t, second) or { return none }
		return [c.upssl_replace_argument(t, tokens, second, js_number_to_string(a + b))]
	}
	return none
}

// upssl_substring ports fixSubstringArguments.
fn (c &Checker) upssl_substring(t &estree.EsTree, tokens &SourceTokens, args []int) ?[]Fix {
	first := args[0]
	first_number := upssl_numeric(t, first)
	first_text := c.un_parenthesized_text(t, tokens, first)
	if args.len < 2 {
		if upssl_is_length(t, first) {
			return []Fix{}
		}
		if n := first_number {
			return [c.upssl_replace_argument(t, tokens, first, js_number_to_string(upssl_max0(n)))]
		}
		return c.upssl_wrap_max(t, tokens, first)
	}
	second := args[1]
	second_number := upssl_numeric(t, second)
	second_text := c.un_parenthesized_text(t, tokens, second)
	if a := first_number {
		if b := second_number {
			mut values := [upssl_max0(a), upssl_max0(b)]
			if a > b {
				values = values.reverse()
			}
			mut fixes := []Fix{}
			// `!==`: NaN is never the same.
			if values[0] != a || math.is_nan(a) {
				fixes << c.upssl_replace_argument(t, tokens, first, js_number_to_string(values[0]))
			}
			if values[1] != b || math.is_nan(b) {
				fixes << c.upssl_replace_argument(t, tokens, second, js_number_to_string(values[1]))
			}
			return fixes
		}
	}
	first_zero := if a := first_number { a == 0 } else { false }
	second_zero := if b := second_number { b == 0 } else { false }
	if first_zero || second_zero {
		other := if first_zero { second_text } else { first_text }
		return [c.upssl_replace_argument(t, tokens, first, '0'),
			c.upssl_replace_argument(t, tokens, second, 'Math.max(0, ${other})')]
	}
	return none
}
