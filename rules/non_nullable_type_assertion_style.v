module rules

import time
import tsgo { TypeResponse }
import treesitter { first_named_child, has_child_kind, named_children, node_kind, nodes_of_kinds, position_of }

// Port of the `non-nullable-type-assertion-style` rule of typescript-eslint 8.62.0 (it has no
// options), with its fix.

const nntas_messages = {
	'preferNonNullAssertion': 'Use a ! assertion to more succinctly remove null and undefined from the type.'
}

// NntasAssertion is a TSAsExpression or TSTypeAssertion that is not a const assertion.
struct NntasAssertion {
	node       C.TSNode
	expression C.TSNode // without parentheses
	type_node  C.TSNode // the asserted type, without parentheses
}

fn (mut c Checker) lint_non_nullable_type_assertion_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut assertions := []NntasAssertion{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['as_expression', 'type_assertion'], []string{}) {
		assertion := nntas_assertion(node) or { continue }
		spans << node_span(assertion.expression)
		spans << c.type_node_span(assertion.type_node)
		assertions << assertion
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for a in assertions {
		original := c.nntas_types_if_not_loose(a.expression)!
		if original.len == 0 {
			continue
		}
		asserted := c.nntas_types_if_not_loose(a.type_node)!
		if asserted.len == 0 {
			continue
		}
		if c.nntas_same_type_without_nullish(asserted, original)! {
			findings << Finding{
				stmt:       position_of(a.node)
				message_id: 'preferNonNullAssertion'
				has_fix:    true
				fix:        c.nntas_fix(a)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += assertions.len
	return findings
}

// nntas_fix ports the fixer: the assertion becomes its expression with `!`, in parentheses unless
// the TypeScript node of the expression binds tighter than a unary operator.
fn (c &Checker) nntas_fix(a NntasAssertion) Fix {
	expression := c.text(a.expression)
	if ts_operator_precedence(a.expression, '', false) > precedence_unary {
		return fix_replace(a.node, '${expression}!')
	}
	return fix_replace(a.node, '(${expression})!')
}

// nntas_assertion gives the parts of `x as T` or `<T>x`; none for a const assertion (`x as const`,
// `<const>x`: isConstAssertion), whose `const` is an anonymous token in tree-sitter.
fn nntas_assertion(node C.TSNode) ?NntasAssertion {
	if node_kind(node) == 'as_expression' {
		parts := named_children(node)
		if parts.len < 2 {
			return none
		}
		return NntasAssertion{
			node:       node
			expression: unwrap_parens(parts[0])
			type_node:  unwrap_type_parens(parts[1])
		}
	}
	parts := named_children(node)
	if parts.len < 2 || node_kind(parts[0]) != 'type_arguments' || has_child_kind(parts[0], 'const') {
		return none
	}
	type_node := first_named_child(parts[0])?
	return NntasAssertion{
		node:       node
		expression: unwrap_parens(parts[1])
		type_node:  unwrap_type_parens(type_node)
	}
}

// nntas_types_if_not_loose ports getTypesIfNotLoose: the union parts of the type of the node, or
// none (empty) if it is `any` or `unknown` (tsutils.isTypeFlagSet, on the type's own flags).
fn (mut c Checker) nntas_types_if_not_loose(n C.TSNode) ![]TypeResponse {
	t := c.node_type(n) or { return []TypeResponse{} }
	if t.flags & (type_flag_any | type_flag_unknown) != 0 {
		return []TypeResponse{}
	}
	return c.constituents(t)!
}

// nntas_could_be_nullish ports couldBeNullish: a type parameter without a constraint, or a type
// that is or contains null or undefined.
fn (mut c Checker) nntas_could_be_nullish(t TypeResponse, depth int) !bool {
	if depth > max_type_depth {
		return false
	}
	if t.flags & type_flag_type_parameter != 0 {
		constraint := c.base_constraint(t)!
		return constraint.is_null() || c.nntas_could_be_nullish(constraint, depth + 1)!
	}
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if c.nntas_could_be_nullish(part, depth + 1)! {
				return true
			}
		}
		return false
	}
	return t.flags & (type_flag_null | type_flag_undefined) != 0
}

// nntas_same_type_without_nullish ports sameTypeWithoutNullish: the asserted parts are the
// original ones without null and undefined (TypeScript interns types: the same id is the same
// type).
fn (mut c Checker) nntas_same_type_without_nullish(asserted []TypeResponse, original []TypeResponse) !bool {
	non_nullish := original.filter(it.flags & (type_flag_null | type_flag_undefined) == 0)
	if non_nullish.len == original.len {
		return false
	}
	non_nullish_ids := non_nullish.map(it.id)
	for t in asserted {
		if c.nntas_could_be_nullish(t, 0)! || t.id !in non_nullish_ids {
			return false
		}
	}
	asserted_ids := asserted.map(it.id)
	for t in non_nullish {
		if t.id !in asserted_ids {
			return false
		}
	}
	return true
}
