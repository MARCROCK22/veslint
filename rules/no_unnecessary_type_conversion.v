module rules

import math
import time
import tsgo { TypeResponse }
import treesitter { Ident, node_end, node_field, node_kind, node_start, nodes_of_kinds, position_of }

// Port of the `no-unnecessary-type-conversion` rule of typescript-eslint 8.62.0 (it has no
// options), with its `suggestRemove` and `suggestSatisfies` suggestions.

const nutc_messages = {
	'suggestRemove':             'Remove the type conversion.'
	'suggestSatisfies':          'Instead, assert that the value satisfies the {{type}} type.'
	'unnecessaryTypeConversion': '{{violation}} does not change the type or value of the {{type}}.'
}

// TypeFlags.EnumLike (Enum | EnumLiteral) and SymbolFlags.EnumMember of TypeScript 7.1.0-beta.
const nutc_enum_like = u32(98304)
const nutc_symbol_flag_enum_member = u32(8)

// NutcKind is the visitor a candidate node comes from.
enum NutcKind {
	concat_assign // `x += ''`
	concat_right  // `x + ''`
	concat_left   // `'' + x`
	builtin_call  // `String(x)`, `Number(x)`, `Boolean(x)`, `BigInt(x)`
	to_string     // `x.toString()`
	double_not    // `!!x`
	unary_plus    // `+x`
	double_tilde  // `~~x`
}

// NutcCandidate is a node a visitor of the rule looks at: the expression whose type decides, and
// where the report goes.
struct NutcCandidate {
	kind    NutcKind
	node    C.TSNode // the visited node
	operand C.TSNode // the expression whose type is checked
	at      Ident    // start of the report
	name    string   // the callee of builtin_call
}

fn (mut c Checker) lint_no_unnecessary_type_conversion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut candidates := []NutcCandidate{}
	for node in c.nodes_of_kinds(root, ['augmented_assignment_expression', 'binary_expression',
		'call_expression', 'unary_expression'], []string{}) {
		c.nutc_candidates(node, mut candidates)
	}
	c.resolve_spans(candidates.map(node_span(it.operand)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for candidate in candidates {
		if candidate.kind == .builtin_call {
			// A variable of that name in the innermost scope of the call (scope.set.get).
			scopes := c.scope_tree(root)
			v := scopes.own_variable(scopes.get_scope(candidate.node), candidate.name)
			if v >= 0 && scopes.variables[v].defs.len > 0 {
				continue
			}
		}
		t := c.node_type(candidate.operand) or { continue }
		type_name, violation := match candidate.kind {
			.concat_assign, .concat_right {
				if !c.nutc_all_parts(t, type_flag_string_like)! {
					continue
				}
				'string', "Concatenating a string with ''"
			}
			.concat_left {
				if !c.nutc_all_parts(t, type_flag_string_like)! {
					continue
				}
				'string', "Concatenating '' with a string"
			}
			.builtin_call {
				flag := match candidate.name {
					'BigInt' { type_flag_bigint_like }
					'Boolean' { type_flag_boolean_like }
					'Number' { type_flag_number_like }
					else { type_flag_string_like }
				}
				if !c.nutc_all_parts(c.constrained(t)!, flag)! {
					continue
				}
				lower := candidate.name.to_lower()
				lower, 'Passing a ${lower} to ${candidate.name}()'
			}
			.to_string {
				constrained := c.constrained(t)!
				if c.nutc_is_enum(constrained)! || !c.nutc_all_parts(constrained, type_flag_string_like)! {
					continue
				}
				'string', "Calling a string's .toString() method"
			}
			.double_not {
				if !c.nutc_all_parts(t, type_flag_boolean_like)! {
					continue
				}
				'boolean', 'Using !! on a boolean'
			}
			.unary_plus {
				if !c.nutc_all_parts(t, type_flag_number_like)! {
					continue
				}
				'number', 'Using the unary + operator on a number'
			}
			.double_tilde {
				if !c.nutc_all_integer_literals(t)! {
					continue
				}
				'number', 'Using ~~ on an integer'
			}
		}
		findings << Finding{
			stmt:        candidate.at
			message_id:  'unnecessaryTypeConversion'
			data:        {
				'type':      type_name
				'violation': violation
			}
			suggestions: c.nutc_suggestions(candidate, type_name)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

// nutc_suggestions ports the two suggestions every report has, both a getWrappingFixer on the
// converted expression: `suggestRemove` leaves it alone in the place of the conversion, and
// `suggestSatisfies` leaves `expression satisfies type`.
fn (mut c Checker) nutc_suggestions(candidate NutcCandidate, type_name string) ![]Suggestion {
	// The node of the fixers: the outer operator of `!!x` and `~~x`, else the visited node.
	outer := if candidate.kind in [.double_not, .double_tilde] {
		estree_parent(candidate.node) or { return []Suggestion{} }
	} else {
		candidate.node
	}
	node := es_inner(outer)
	code := c.wrapping_inner_code(node, es_child(candidate.operand))
	mut remove := fix_replace(node.node, code)
	if candidate.kind == .concat_assign {
		// `x += ''` as a statement: the whole statement goes.
		if statement := node.parent() {
			if !statement.chain && node_kind(statement.node) == 'expression_statement' {
				end := if token := c.last_token(statement.node) {
					token.end
				} else {
					node_end(statement.node)
				}
				remove = fix_remove_range(node_start(statement.node), end)
			}
		}
	}
	mut suggestions := []Suggestion{}
	ok_remove, suggest_remove := c.suggestion('suggestRemove', map[string]string{}, [
		remove,
	])!
	if ok_remove {
		suggestions << suggest_remove
	}
	satisfies := c.wrapping_fix(node, '${code} satisfies ${type_name}')
	ok_satisfies, suggest_satisfies := c.suggestion('suggestSatisfies', {
		'type': type_name
	}, [satisfies])!
	if ok_satisfies {
		suggestions << suggest_satisfies
	}
	return suggestions
}

// nutc_candidates ports the selectors of the rule on a node.
fn (c &Checker) nutc_candidates(node C.TSNode, mut out []NutcCandidate) {
	match node_kind(node) {
		'augmented_assignment_expression' {
			// AssignmentExpression[operator = "+="] with '' on the right.
			if operator_of(node) != '+=' {
				return
			}
			right := node_field(node, 'right') or { return }
			left := node_field(node, 'left') or { return }
			if c.nutc_is_empty_string(unwrap_parens(right)) {
				out << NutcCandidate{
					kind:    .concat_assign
					node:    node
					operand: unwrap_parens(left)
					at:      position_of(node)
				}
			}
		}
		'binary_expression' {
			// BinaryExpression[operator = "+"]: '' on the right, or else on the left.
			if operator_of(node) != '+' {
				return
			}
			left := unwrap_parens(node_field(node, 'left') or { return })
			right := unwrap_parens(node_field(node, 'right') or { return })
			if c.nutc_is_empty_string(right) {
				// From the end of the left operand.
				out << NutcCandidate{
					kind:    .concat_right
					node:    node
					operand: left
					at:      c.position_range(c.tokens.last_end(node_end(left)), c.es_end(node))
				}
			} else if c.nutc_is_empty_string(left) {
				out << NutcCandidate{
					kind:    .concat_left
					node:    node
					operand: right
					at:      c.position_range(node_start(node), node_start(right))
				}
			}
		}
		'call_expression' {
			args := call_arguments(node) or { return }
			callee := unwrap_parens(node_field(node, 'function') or { return })
			if node_kind(callee) == 'identifier' {
				name := c.text(callee)
				if name !in ['BigInt', 'Boolean', 'Number', 'String'] || args.len == 0 {
					return
				}
				out << NutcCandidate{
					kind:    .builtin_call
					node:    node
					operand: unwrap_parens(args[0])
					at:      position_of(callee)
					name:    name
				}
			} else if node_kind(callee) == 'member_expression' {
				// CallExpression > MemberExpression.callee > Identifier[name = "toString"].property
				property := node_field(callee, 'property') or { return }
				if node_kind(property) != 'property_identifier' || c.text(property) != 'toString' {
					return
				}
				object := node_field(callee, 'object') or { return }
				out << NutcCandidate{
					kind:    .to_string
					node:    node
					operand: unwrap_parens(object)
					at:      c.position_range(node_start(property), c.es_end(node))
				}
			}
		}
		'unary_expression' {
			operator := operator_of(node)
			argument := unwrap_parens(node_field(node, 'argument') or { return })
			if operator == '+' {
				out << NutcCandidate{
					kind:    .unary_plus
					node:    node
					operand: argument
					at:      c.position_range(node_start(node), node_start(node) + 1)
				}
				return
			}
			if operator !in ['!', '~'] {
				return
			}
			// `UnaryExpression[operator] > UnaryExpression[operator]`: this node is the argument of
			// another one with the same operator.
			parent := estree_parent(node) or { return }
			if node_kind(parent) != 'unary_expression' || operator_of(parent) != operator {
				return
			}
			parent_argument := node_field(parent, 'argument') or { return }
			if node_key(unwrap_parens(parent_argument)) != node_key(node) {
				return
			}
			out << NutcCandidate{
				kind:    if operator == '!' { NutcKind.double_not } else { NutcKind.double_tilde }
				node:    node
				operand: argument
				at:      c.position_range(node_start(parent), node_start(node) + 1)
			}
		}
		else {}
	}
}

// nutc_is_empty_string: a string Literal whose value is ''.
fn (c &Checker) nutc_is_empty_string(n C.TSNode) bool {
	if node_kind(n) != 'string' {
		return false
	}
	text := c.text(n)
	value := cooked_string(text[1..text.len - 1], false) or { return false }
	return value == ''
}

// nutc_all_parts ports doesUnderlyingTypeMatchFlag: every union part has the flag (the
// union-aware isTypeFlagSet, on a part).
fn (mut c Checker) nutc_all_parts(t TypeResponse, flag u32) !bool {
	for part in c.constituents(t)! {
		if c.type_flags(part)! & flag == 0 {
			return false
		}
	}
	return true
}

// nutc_all_integer_literals: every union part is a number literal with an integer value.
fn (mut c Checker) nutc_all_integer_literals(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		if c.type_flags(part)! & type_flag_number_literal == 0 {
			return false
		}
		value := part.value
		if value !is f64 {
			return false
		}
		x := value as f64
		if math.is_nan(x) || math.is_inf(x, 0) || math.floor(x) != x {
			return false
		}
	}
	return true
}

// nutc_is_enum ports isEnumType (own flags EnumLike) or isEnumMemberType (its symbol is an enum
// member).
fn (mut c Checker) nutc_is_enum(t TypeResponse) !bool {
	if t.flags & nutc_enum_like != 0 {
		return true
	}
	if t.symbol == 0 {
		return false
	}
	return c.symbol_of(t)!.flags & nutc_symbol_flag_enum_member != 0
}
