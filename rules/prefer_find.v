module rules

import math
import time
import tsgo { TypeResponse }
import treesitter { named_children, node_end, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `prefer-find` rule of typescript-eslint 8.62.0, with its suggestion.

const pfind_messages = {
	'preferFind':           'Prefer .find(...) instead of .filter(...)[0].'
	'preferFindSuggestion': 'Use .find(...) instead of .filter(...)[0].'
}

// PfindCandidate is a `….at(0)` call or a `…[0]` access whose object is made of `.filter(…)`
// calls; it is reported if the object of every one of them is an array.
struct PfindCandidate {
	node    C.TSNode
	object  C.TSNode   // the object of the `.at(0)` callee or of the `[0]` access, without parentheses
	filters []C.TSNode // the `.filter` callees
}

fn (mut c Checker) lint_prefer_find(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut candidates := []PfindCandidate{}
	mut spans := []Span{}
	for n in c.nodes_of_kinds(root, ['call_expression', 'subscript_expression'], []string{}) {
		object := if node_kind(n) == 'call_expression' {
			c.pfind_array_at_zero_object(n) or { continue }
		} else {
			c.pfind_member_access_of_zero_object(n) or { continue }
		}
		mut filters := []C.TSNode{}
		if !c.pfind_filter_expressions(object, mut filters, 0) {
			continue
		}
		for f in filters {
			spans << node_span(pfind_filter_object(f) or { continue })
		}
		candidates << PfindCandidate{
			node:    n
			object:  object
			filters: filters
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for cand in candidates {
		mut all := true
		for f in cand.filters {
			t := c.node_type(pfind_filter_object(f) or { continue }) or {
				all = false
				break
			}
			if !c.pfind_is_arrayish(c.constrained(t)!)! {
				all = false
				break
			}
		}
		if all {
			_, suggestion := c.suggestion('preferFindSuggestion', map[string]string{}, c.pfind_fixes(cand))!
			findings << Finding{
				stmt:        position_of(cand.node)
				message_id:  'preferFind'
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

// pfind_filter_object is the object of a `.filter` callee, without parentheses.
fn pfind_filter_object(callee C.TSNode) ?C.TSNode {
	return unwrap_parens(node_field(callee, 'object')?)
}

// pfind_fixes ports the fixer of the suggestion: every `filter` becomes `find` (`"find"` between
// brackets) and the `.at(0)` or `[0]` goes, from the first `.` or `[` after the object.
fn (mut c Checker) pfind_fixes(cand PfindCandidate) []Fix {
	mut fixes := []Fix{}
	for callee in cand.filters {
		property := member_property(callee) or { continue }
		fixes << fix_replace(property, if node_kind(callee) == 'subscript_expression' {
			'"find"'
		} else {
			'find'
		})
	}
	tokens := c.source_tokens(cand.node)
	mut offset := node_end(cand.object)
	for {
		token := tokens.after(offset, false) or { break }
		if c.token_text(token) in ['.', '['] {
			fixes << fix_remove_range(token.start, node_end(cand.node))
			break
		}
		offset = token.end
	}
	return fixes
}

// pfind_array_at_zero_object ports getObjectIfArrayAtZeroExpression: the object of `x.at(0)` (a
// single argument treated as 0 by Array#at, a callee that is not `?.`).
fn (mut c Checker) pfind_array_at_zero_object(call C.TSNode) ?C.TSNode {
	args := call_arguments(call)?
	if args.len != 1 {
		return none
	}
	callee := unwrap_parens(node_field(call, 'function')?)
	if !is_member(callee) || is_optional_element(callee)
		|| !c.is_static_member_access_of_value(callee, ['at']) {
		return none
	}
	value := c.get_static_value(args[0])
	if !value.found || !pfind_is_zero_for_at(value.value) {
		return none
	}
	return unwrap_parens(node_field(callee, 'object')?)
}

// pfind_is_zero_for_at ports isTreatedAsZeroByArrayAt: Number(value) is NaN or truncates to 0.
fn pfind_is_zero_for_at(v JsAny) bool {
	if v.kind == .symbol_ {
		return false
	}
	p := stv_to_numeric(v) or { return false }
	n := if p.kind == .bigint_ {
		stv_bigint_to_number(p) or { return false }
	} else {
		p.number
	}
	return math.is_nan(n) || math.trunc(n) == 0
}

// pfind_member_access_of_zero_object ports isMemberAccessOfZero: the object of `x[0]` (not `?.`),
// whose key is a static value whose String is "0".
fn (mut c Checker) pfind_member_access_of_zero_object(member C.TSNode) ?C.TSNode {
	if is_optional_element(member) {
		return none
	}
	value := c.get_static_value(node_field(member, 'index')?)
	if !value.found || (js_any_string_value(value.value) or { return none }) != '0' {
		return none
	}
	return unwrap_parens(node_field(member, 'object')?)
}

// pfind_filter_expressions ports parseArrayFilterExpressions on the syntax: the `.filter` callees
// of the `.filter(…)` calls the expression is made of (the last expression of a sequence, both
// branches of a conditional); false when some part is not such a call.
fn (mut c Checker) pfind_filter_expressions(expression C.TSNode, mut out []C.TSNode, depth int) bool {
	if depth > max_expression_depth {
		return false
	}
	node := unwrap_parens(expression)
	match node_kind(node) {
		'sequence_expression' {
			named := named_children(node)
			if named.len == 0 {
				return false
			}
			return c.pfind_filter_expressions(named.last(), mut out, depth + 1)
		}
		'ternary_expression' {
			return c.pfind_filter_expressions(node_field(node, 'consequence') or { return false }, mut
				out, depth + 1)
				&& c.pfind_filter_expressions(node_field(node, 'alternative') or { return false }, mut
					out, depth + 1)
		}
		'call_expression' {
			// `<<stuff>>(…)`, but not `<<stuff>>?.(…)`.
			call_arguments(node) or { return false }
			if is_optional_element(node) {
				return false
			}
			callee := unwrap_parens(node_field(node, 'function') or { return false })
			if !is_member(callee) || !c.is_static_member_access_of_value(callee, ['filter']) {
				return false
			}
			pfind_filter_object(callee) or { return false }
			out << callee
			return true
		}
		else {
			return false
		}
	}
}

// pfind_is_arrayish ports isArrayish: a possibly nullable array or tuple (or an intersection of
// them), or a union of them.
fn (mut c Checker) pfind_is_arrayish(t TypeResponse) !bool {
	mut arrayish := false
	for part in c.constituents(t)! {
		if part.flags & (type_flag_null | type_flag_undefined) != 0 {
			continue
		}
		for inner in c.intersection_parts(part)! {
			if !c.is_array(inner)! && !c.is_tuple(inner)! {
				return false
			}
		}
		arrayish = true
	}
	return arrayish
}
