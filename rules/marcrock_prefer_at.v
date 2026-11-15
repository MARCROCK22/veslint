module rules

import estree
import math
import time
import x.json2
import treesitter { named_children, node_end, node_kind }
import tsgo { TypeResponse }

// Port of the `marcrock/prefer-at` rule of @marcrock22/eslintcf 0.0.1 (src/rules/preferAt.ts and
// the helpers it vendors from eslint-plugin-unicorn in src/rules/preferAt/helpers.ts), with its
// fixes and suggestions: a fork of unicorn's prefer-at (index access, `String#charAt`, the first
// element of `.slice(…)`, get-last functions) that leaves alone an index access whose element is
// provably present (`split('<non-empty>')[0]`, a tuple, a statically known length, a dominating
// length guard), and that reports `.at(0)` on such a split (fixed to `[0]`). The helpers are the
// versions the fork vendors, not unicorn 79.0.0's (rules/unicorn_utils.v): isSameReference,
// isLeftHandSide, needsSemicolon, shouldAddParenthesesToMemberExpressionObject and the negative
// index ones are ported here.

const mpa_messages = {
	'negativeIndex':        'Prefer `.at(…)` over `[….length - index]`.'
	'index':                'Prefer `.at(…)` over index access.'
	'stringCharAtNegative': 'Prefer `String#at(…)` over `String#charAt(….length - index)`.'
	'stringCharAt':         'Prefer `String#at(…)` over `String#charAt(…)`.'
	'slice':                'Prefer `.at(…)` over the first element from `.slice(…)`.'
	'splitIndexAccess':     'Prefer `[0]` over `.at(0)`: `String#split(…)` with a non-empty separator always has a first element, so `[0]` is `string`, not `string | undefined`.'
	'getLastFunction':      'Prefer `.at(-1)` over `{{description}}(…)` to get the last element.'
	'useAt':                'Use `.at(…)`.'
}

const mpa_lodash_last_functions = ['_.last', 'lodash.last', 'underscore.last']

struct MpaOptions {
	check_all_index_access bool
	get_last_functions     []string // the option's, then lodash's
}

fn mpa_options(options []json2.Any) !MpaOptions {
	o := option_object(marcrock_prefer_at, options, ['getLastElementFunctions', 'checkAllIndexAccess'])!
	mut functions := []string{}
	if list := o.values['getLastElementFunctions'] {
		if list is []json2.Any {
			functions = list.map(it.str())
		}
	}
	functions << mpa_lodash_last_functions
	return MpaOptions{
		check_all_index_access: o.bool_value('checkAllIndexAccess')!
		get_last_functions:     functions
	}
}

// MpaCtx is the file the rule looks at.
struct MpaCtx {
	t       &estree.EsTree
	tokens  &SourceTokens
	tree    &ScopeTree
	un      &UnCtx
	options MpaOptions
}

// MpaBounds are the proven lower bounds of the receiver's length: `len` for any receiver with a
// length (from `.length` comparisons), `str` only for a string (from its truthiness or `=== ''`).
struct MpaBounds {
	len f64
	str f64
}

fn mpa_max_bounds(a MpaBounds, b MpaBounds) MpaBounds {
	return MpaBounds{math.max(a.len, b.len), math.max(a.str, b.str)}
}

// --- ast/literal.js, utils/numeric.js -----------------------------------------------------------

fn mpa_is_integer(x f64) bool {
	return !math.is_nan(x) && !math.is_inf(x, 0) && math.trunc(x) == x
}

// mpa_is_literal_zero is isLiteral(node, 0).
fn mpa_is_literal_zero(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .literal {
		return false
	}
	value := t.get(node, .value)
	return value is f64 && value == 0
}

// mpa_is_decimal_integer_node ports isDecimalIntegerNode: a number literal written
// /^(?:0|0[0-7]*[89]\d*|[1-9](?:_?\d)*)$/.
fn mpa_is_decimal_integer_node(t &estree.EsTree, node int) bool {
	if t.typ(node) != .literal || t.get(node, .value) !is f64 {
		return false
	}
	raw := t.string_of(node, .raw) or { return false }
	if raw == '0' {
		return true
	}
	if raw.len == 0 || !raw.bytes().all(it.is_digit() || it == `_`) {
		return false
	}
	if raw[0] == `0` {
		// 0[0-7]*[89]\d*
		mut i := 1
		for i < raw.len && raw[i] >= `0` && raw[i] <= `7` {
			i++
		}
		if i >= raw.len || (raw[i] != `8` && raw[i] != `9`) {
			return false
		}
		return raw[i + 1..].bytes().all(it.is_digit())
	}
	// [1-9](?:_?\d)*
	mut i := 1
	for i < raw.len {
		if raw[i] == `_` {
			i++
			if i >= raw.len || !raw[i].is_digit() {
				return false
			}
		} else if !raw[i].is_digit() {
			return false
		}
		i++
	}
	return true
}

// mpa_utf16_length is the `length` of a string value (WTF-8, a lone surrogate is one unit).
fn mpa_utf16_length(s string) f64 {
	mut n := 0
	for r in s.runes() {
		n += if r > 0xffff { 2 } else { 1 }
	}
	return f64(n)
}

// --- utils/is-same-reference.js (the fork's) ----------------------------------------------------

// mpa_unwrap ports unwrapNode: without ChainExpression, TSAsExpression, TSTypeAssertion and
// TSNonNullExpression around it.
fn mpa_unwrap(t &estree.EsTree, from int) int {
	mut node := from
	for node >= 0
		&& t.typ(node) in [.chain_expression, .ts_as_expression, .ts_type_assertion,
			.ts_non_null_expression] {
		node = t.node(node, .expression) or { break }
	}
	return node
}

fn (mut c Checker) mpa_is_same_reference(t &estree.EsTree, left_node int, right_node int) bool {
	left := mpa_unwrap(t, left_node)
	right := mpa_unwrap(t, right_node)
	if left < 0 || right < 0 || t.typ(left) != t.typ(right) {
		return false
	}
	match t.typ(left) {
		.super, .this_expression {
			return true
		}
		.identifier, .private_identifier {
			return t.string_of(left, .name) or { '' } == t.string_of(right, .name) or { '' }
		}
		.literal {
			return un_equal_literal_value(t, left, right)
		}
		.member_expression {
			left_object := t.node(left, .object) or { return false }
			right_object := t.node(right, .object) or { return false }
			if name := c.un_static_property_name(t, left) {
				if !c.mpa_is_same_reference(t, left_object, right_object) {
					return false
				}
				right_name := c.un_static_property_name(t, right) or { return false }
				return name == right_name
			}
			return (t.flag(left, .computed) or { false }) == (t.flag(right, .computed) or { false })
				&& c.mpa_is_same_reference(t, left_object, right_object)
				&& c.mpa_is_same_reference(t, t.node(left, .property) or { return false }, t.node(right,
					.property) or { return false })
		}
		else {
			return false
		}
	}
}

// --- shared/negative-index.js (the fork's) ------------------------------------------------------

// mpa_length_node ports getNegativeIndexLengthNode: the `<object>.length` of `<object>.length - n`
// (n a positive number literal), through nested subtractions.
fn (mut c Checker) mpa_length_node(t &estree.EsTree, node int, object int) ?int {
	if node < 0 || t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return none
	}
	right := t.node(node, .right)?
	right_value := t.get(right, .value)
	if t.typ(right) != .literal || !(right_value is f64 && right_value > 0) {
		return none
	}
	left := t.node(node, .left)?
	if t.typ(left) == .member_expression && !(t.flag(left, .computed) or { false })
		&& !(t.flag(left, .optional) or { false }) {
		property := t.node(left, .property)?
		if t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == 'length'
			&& c.mpa_is_same_reference(t, t.node(left, .object)?, object) {
			return left
		}
	}
	return c.mpa_length_node(t, left, object)
}

// mpa_remove_length_node ports removeLengthNode: the length node (with its parentheses) and the
// white space after it.
fn (c &Checker) mpa_remove_length_node(m &MpaCtx, node int) Fix {
	start, end := c.un_parenthesized_range(m.t, m.tokens, node)
	return fix_remove_range(start, c.un_remove_spaces_after(end).end)
}

// --- utils/is-left-hand-side.js (the fork's) ----------------------------------------------------

fn mpa_is_left_hand_side(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.assignment_expression, .assignment_pattern {
			t.node(parent, .left) or { -1 } == node
		}
		.update_expression {
			t.node(parent, .argument) or { -1 } == node
		}
		.array_pattern {
			node in (t.list(parent, .elements) or { []int{} })
		}
		.property {
			t.node(parent, .value) or { -1 } == node && t.nodes[parent].parent >= 0
				&& t.typ(t.nodes[parent].parent) == .object_pattern
				&& parent in (t.list(t.nodes[parent].parent, .properties) or { []int{} })
		}
		.unary_expression {
			(t.string_of(parent, .operator) or { '' }) == 'delete'
				&& t.node(parent, .argument) or { -1 } == node
		}
		else {
			false
		}
	}
}

// --- utils/should-add-parentheses-to-member-expression-object.js, needs-semicolon.js ------------

fn (c &Checker) mpa_member_object_needs_parens(m &MpaCtx, node int) bool {
	return match m.t.typ(node) {
		.identifier, .member_expression, .call_expression, .chain_expression, .template_literal,
		.this_expression, .array_expression, .function_expression {
			false
		}
		.new_expression {
			!c.un_new_with_parentheses(m.t, m.tokens, node)
		}
		.literal {
			mpa_is_decimal_integer_node(m.t, node)
		}
		else {
			true
		}
	}
}

// mpa_needs_semicolon ports the fork's needsSemicolon: whether `code` right after the token
// `before` needs a `;` first.
fn (c &Checker) mpa_needs_semicolon(m &MpaCtx, before ?SourceToken, code string) bool {
	t := m.t
	if code == '' || code[0] !in [`+`, `\``, `/`, `*`, `[`, `(`, `.`, `,`, `-`] {
		return false
	}
	token := before or { return false }
	value := c.token_text(token)
	last_block := un_node_by_range_index(t, token.start) or { return false }
	if token.kind == .punctuator {
		if value == ';' {
			return false
		}
		if value == ']' {
			return true
		}
		if value == ')' {
			body_key := match t.typ(last_block) {
				.if_statement {
					?estree.Key(estree.Key.consequent)
				}
				.for_statement, .for_in_statement, .for_of_statement, .while_statement,
				.do_while_statement, .with_statement {
					?estree.Key(estree.Key.body)
				}
				else {
					?estree.Key(none)
				}
			}
			if key := body_key {
				if body := t.node(last_block, key) {
					if previous := m.tokens.before(t.nodes[body].start, false) {
						if previous.start == token.start {
							return false
						}
					}
				}
			}
			return true
		}
	}
	if token.kind in [.string_, .regular_expression, .numeric, .null_, .boolean] {
		return true
	}
	if token.kind == .template {
		return value.ends_with('`')
	}
	if t.typ(last_block) == .object_expression {
		return true
	}
	if token.kind == .identifier {
		if value == 'of' && t.typ(last_block) == .for_of_statement {
			return false
		}
		if value == 'await' && t.typ(last_block) == .await_expression {
			return false
		}
		return true
	}
	return false
}

// mpa_token_before_punctuator ports getTokenBefore(node, isOpeningBracketToken) and the like: the
// last token before `offset` that is that punctuator.
fn (c &Checker) mpa_token_before_punctuator(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset) - 1; i >= 0; i-- {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

// mpa_remove_member_property ports removeMemberExpressionProperty: from the end of the
// (parenthesized) object to the end of the member expression.
fn (c &Checker) mpa_remove_member_property(m &MpaCtx, member int) Fix {
	object := m.t.node(member, .object) or { return Fix{} }
	_, start := c.un_parenthesized_range(m.t, m.tokens, object)
	return fix_remove_range(start, m.t.nodes[member].end)
}

// --- scopes and types ---------------------------------------------------------------------------

// mpa_find_variable ports findVariable(sourceCode.getScope(node), node.name): by the name, from
// the scope of the node outward; -1 if none.
fn (mut c Checker) mpa_find_variable(m &MpaCtx, node int) int {
	ts := m.t.ts_node(node) or { return -1 }
	name := m.t.string_of(node, .name) or { return -1 }
	return m.tree.find_variable(m.tree.get_scope(ts), name, -1)
}

// mpa_is_effectively_const ports isEffectivelyConst: every write to the variable is its
// declarator's initializer.
fn (mut c Checker) mpa_is_effectively_const(m &MpaCtx, id int) bool {
	v := c.mpa_find_variable(m, id)
	if v < 0 {
		return false
	}
	for r in m.tree.variables[v].references {
		reference := m.tree.references[r]
		if reference.write && !reference.init {
			return false
		}
	}
	return true
}

// mpa_is_non_escaping_array ports isNonEscapingArray: every reference to the variable (but its
// initializer and a type predicate) reads `V.length` or `V[index]`.
fn (mut c Checker) mpa_is_non_escaping_array(m &MpaCtx, id int) bool {
	t := m.t
	v := c.mpa_find_variable(m, id)
	if v < 0 {
		return false
	}
	for r in m.tree.variables[v].references {
		reference := m.tree.references[r]
		if reference.init {
			continue
		}
		identifier := c.es_index_of(t, reference.identifier) or { return false }
		member := t.nodes[identifier].parent
		if member < 0 {
			return false
		}
		if t.typ(member) == .ts_type_predicate {
			continue
		}
		if t.typ(member) != .member_expression || t.node(member, .object) or { -1 } != identifier {
			return false
		}
		outer := t.nodes[member].parent
		if outer >= 0 {
			match t.typ(outer) {
				.assignment_expression {
					if t.node(outer, .left) or { -1 } == member {
						return false
					}
				}
				.update_expression {
					if t.node(outer, .argument) or { -1 } == member {
						return false
					}
				}
				.unary_expression {
					if (t.string_of(outer, .operator) or { '' }) == 'delete'
						&& t.node(outer, .argument) or { -1 } == member {
						return false
					}
				}
				.call_expression {
					if t.node(outer, .callee) or { -1 } == member {
						return false
					}
				}
				else {}
			}
		}
		if t.flag(member, .computed) or { false } {
			continue
		}
		property := t.node(member, .property) or { return false }
		if t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != 'length' {
			return false
		}
	}
	return true
}

// mpa_declarator_init is the initializer of the first definition of the variable when it is a
// VariableDeclarator with one, -1 otherwise.
fn (mut c Checker) mpa_declarator_init(m &MpaCtx, v int) int {
	if v < 0 || m.tree.variables[v].defs.len == 0 {
		return -1
	}
	def := m.tree.variables[v].defs[0]
	if def.kind != .variable || node_kind(def.node) != 'variable_declarator' {
		return -1
	}
	init := def.init or { return -1 }
	return c.mpa_es_of(m, init)
}

// mpa_es_of is the ESTree node a tree-sitter expression is: the outermost one made from it (a
// template literal, not its only quasi), inside its parentheses.
fn (mut c Checker) mpa_es_of(m &MpaCtx, n C.TSNode) int {
	t := m.t
	mut node := c.es_index_of(t, n) or {
		if node_kind(n) == 'parenthesized_expression' {
			for child in named_children(n) {
				if node_kind(child) != 'comment' {
					return c.mpa_es_of(m, child)
				}
			}
		}
		return -1
	}
	for {
		parent := t.nodes[node].parent
		if parent < 0 || !t.nodes[parent].has_ts || node_key(t.nodes[parent].ts) != node_key(n) {
			break
		}
		node = parent
	}
	return node
}

// mpa_type is getNodeType: the type of the node, none without type information.
fn (mut c Checker) mpa_type(m &MpaCtx, node int) ?TypeResponse {
	return c.un_ts_type(m.un, node)
}

// mpa_parts are the constituents of a union, or the type itself.
fn (mut c Checker) mpa_parts(typ TypeResponse) []TypeResponse {
	if typ.flags & type_flag_union != 0 {
		return c.members_of(typ) or { [typ] }
	}
	return [typ]
}

// mpa_tuple_min_length ports tupleMinLength: the smallest minLength of the tuples of the type when
// every constituent is a tuple, none otherwise.
fn (mut c Checker) mpa_tuple_min_length(typ TypeResponse) ?f64 {
	mut min := math.inf(1)
	for part in c.mpa_parts(typ) {
		if part.flags & type_flag_object == 0 || !part.is_tuple_type {
			return none
		}
		target := c.target_of(part) or { return none }
		count := target.element_flags.filter(it & (element_flag_required | element_flag_variadic) != 0).len
		min = math.min(min, f64(count))
	}
	if math.is_inf(min, 0) {
		return none
	}
	return min
}

// mpa_tuple_is_readonly ports tupleTypeIsReadonly.
fn (mut c Checker) mpa_tuple_is_readonly(typ TypeResponse) bool {
	for part in c.mpa_parts(typ) {
		if part.flags & type_flag_object == 0 || !part.is_tuple_type {
			return false
		}
		target := c.target_of(part) or { return false }
		if !target.readonly {
			return false
		}
	}
	return true
}

// mpa_is_length_indexable ports isLengthIndexableObject: every constituent of the type is a
// string, an array or a tuple.
fn (mut c Checker) mpa_is_length_indexable(m &MpaCtx, node int) bool {
	typ := c.mpa_type(m, node) or { return false }
	for part in c.mpa_parts(typ) {
		if !(part.flags & type_flag_string_like != 0 || (c.is_array(part) or { false })
			|| part.is_tuple_type) {
			return false
		}
	}
	return true
}

// mpa_is_string_object ports isStringObject: every constituent of the type is a string.
fn (mut c Checker) mpa_is_string_object(m &MpaCtx, node int) bool {
	typ := c.mpa_type(m, node) or { return false }
	for part in c.mpa_parts(typ) {
		if part.flags & type_flag_string_like == 0 {
			return false
		}
	}
	return true
}

// --- control flow -------------------------------------------------------------------------------

fn mpa_negate_operator(operator string) ?string {
	return match operator {
		'===' { '!==' }
		'!==' { '===' }
		'==' { '!=' }
		'!=' { '==' }
		'<' { '>=' }
		'>=' { '<' }
		'>' { '<=' }
		'<=' { '>' }
		else { none }
	}
}

fn mpa_swap_operator(operator string) string {
	return match operator {
		'<' { '>' }
		'>' { '<' }
		'<=' { '>=' }
		'>=' { '<=' }
		else { operator }
	}
}

// mpa_bound_from_comparison ports lenBoundFromCmp: the lower bound of the length that a true
// `length <operator> value` proves.
fn mpa_bound_from_comparison(operator string, value f64) f64 {
	return match operator {
		'===', '==' { value }
		'>' { value + 1 }
		'>=' { value }
		'!==', '!=' {
			if value == 0 { 1.0 } else { 0.0 }
		}
		else { 0.0 }
	}
}

// mpa_definitely_exits ports definitelyExits.
fn mpa_definitely_exits(t &estree.EsTree, statement int) bool {
	return match t.typ(statement) {
		.return_statement, .throw_statement, .break_statement, .continue_statement {
			true
		}
		.block_statement {
			body := t.list(statement, .body) or { []int{} }
			body.len > 0 && mpa_definitely_exits(t, body.last())
		}
		else {
			false
		}
	}
}

// mpa_statement_list ports getStatementListBody.
fn mpa_statement_list(t &estree.EsTree, node int) ?[]int {
	return match t.typ(node) {
		.block_statement, .static_block, .program { t.list(node, .body) or { []int{} } }
		.switch_case { t.list(node, .consequent) or { []int{} } }
		else { none }
	}
}

fn mpa_int_literal_value(t &estree.EsTree, node int) ?f64 {
	if node < 0 || t.typ(node) != .literal {
		return none
	}
	value := t.get(node, .value)
	if value is f64 {
		if mpa_is_integer(value) && value >= 0 {
			return value
		}
	}
	return none
}

// mpa_refs_target ports refsTarget: an Identifier of that name that resolves to the variable.
fn (mut c Checker) mpa_refs_target(m &MpaCtx, node int, target int, name string) bool {
	return m.t.typ(node) == .identifier && (m.t.string_of(node, .name) or { '' }) == name
		&& c.mpa_find_variable(m, node) == target
}

// mpa_is_target_length ports isTargetLength: `<target>.length`.
fn (mut c Checker) mpa_is_target_length(m &MpaCtx, node int, target int, name string) bool {
	t := m.t
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false }) {
		return false
	}
	property := t.node(node, .property) or { return false }
	return t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == 'length'
		&& c.mpa_refs_target(m, t.node(node, .object) or { return false }, target, name)
}

// mpa_condition_bounds ports conditionBounds: the bounds of the target's length that `expr` being
// truthy (or falsy) proves.
fn (mut c Checker) mpa_condition_bounds(m &MpaCtx, expr int, target int, name string, when_truthy bool) MpaBounds {
	t := m.t
	typ := t.typ(expr)
	operator := t.string_of(expr, .operator) or { '' }
	if typ == .unary_expression && operator == '!' {
		return c.mpa_condition_bounds(m, t.node(expr, .argument) or { return MpaBounds{} }, target,
			name, !when_truthy)
	}
	if typ == .logical_expression && operator in ['&&', '||'] {
		a := c.mpa_condition_bounds(m, t.node(expr, .left) or { return MpaBounds{} }, target, name,
			when_truthy)
		b := c.mpa_condition_bounds(m, t.node(expr, .right) or { return MpaBounds{} }, target, name,
			when_truthy)
		// `&&` truthy / `||` falsy: both hold (the stronger bound); otherwise only one (the weaker).
		both_hold := (operator == '&&') == when_truthy
		if both_hold {
			return MpaBounds{math.max(a.len, b.len), math.max(a.str, b.str)}
		}
		return MpaBounds{math.min(a.len, b.len), math.min(a.str, b.str)}
	}
	if typ == .identifier && !c.mpa_refs_target(m, expr, target, name) {
		init := c.mpa_const_initializer(m, expr)
		if init < 0 {
			return MpaBounds{}
		}
		return c.mpa_condition_bounds(m, init, target, name, when_truthy)
	}
	if c.mpa_is_target_length(m, expr, target, name) {
		return if when_truthy { MpaBounds{1, 0} } else { MpaBounds{} }
	}
	if c.mpa_refs_target(m, expr, target, name) {
		return if when_truthy { MpaBounds{0, 1} } else { MpaBounds{} }
	}
	if typ != .binary_expression {
		return MpaBounds{}
	}
	op := if when_truthy {
		operator
	} else {
		mpa_negate_operator(operator) or { return MpaBounds{} }
	}
	left := t.node(expr, .left) or { return MpaBounds{} }
	right := t.node(expr, .right) or { return MpaBounds{} }
	if c.mpa_is_target_length(m, left, target, name) {
		value := mpa_int_literal_value(t, right) or { return MpaBounds{} }
		return MpaBounds{mpa_bound_from_comparison(op, value), 0}
	}
	if c.mpa_is_target_length(m, right, target, name) {
		value := mpa_int_literal_value(t, left) or { return MpaBounds{} }
		return MpaBounds{mpa_bound_from_comparison(mpa_swap_operator(op), value), 0}
	}
	on_empty_string := (c.mpa_refs_target(m, left, target, name) && mpa_is_empty_string(t, right))
		|| (mpa_is_empty_string(t, left) && c.mpa_refs_target(m, right, target, name))
	if on_empty_string && op in ['!==', '!='] {
		return MpaBounds{0, 1}
	}
	return MpaBounds{}
}

fn mpa_is_empty_string(t &estree.EsTree, node int) bool {
	if t.typ(node) != .literal {
		return false
	}
	value := t.get(node, .value)
	return value is string && value == ''
}

// mpa_const_initializer ports constInitializerOf: the initializer of an effectively const
// variable, -1 if none.
fn (mut c Checker) mpa_const_initializer(m &MpaCtx, id int) int {
	if !c.mpa_is_effectively_const(m, id) {
		return -1
	}
	return c.mpa_declarator_init(m, c.mpa_find_variable(m, id))
}

// mpa_switch_bound ports switchBound: the bound of being in a case of `switch (V.length)` whose
// preceding cases are integers that exit.
fn (mut c Checker) mpa_switch_bound(m &MpaCtx, switch_case int, target int, name string) MpaBounds {
	t := m.t
	sw := t.nodes[switch_case].parent
	if sw < 0 || t.typ(sw) != .switch_statement
		|| !c.mpa_is_target_length(m, t.node(sw, .discriminant) or { -1 }, target, name) {
		return MpaBounds{}
	}
	cases := t.list(sw, .cases) or { []int{} }
	my_index := cases.index(switch_case)
	mut excluded := []f64{}
	for i in 0 .. my_index {
		clause := cases[i]
		test := t.node(clause, .test) or { continue }
		consequent := t.list(clause, .consequent) or { []int{} }
		value := mpa_int_literal_value(t, test) or { return MpaBounds{} }
		if consequent.len == 0 || !mpa_definitely_exits(t, consequent.last()) {
			return MpaBounds{}
		}
		excluded << value
	}
	if test := t.node(switch_case, .test) {
		value := mpa_int_literal_value(t, test) or { return MpaBounds{} }
		return MpaBounds{value, 0}
	}
	mut bound := 0.0
	for excluded.any(it == bound) {
		bound++
	}
	return MpaBounds{bound, 0}
}

// mpa_proven_length_bound ports provenLengthBound: the strongest bounds proven by the conditions
// that dominate the access, up to a function or a sequence expression; only guards after
// `min_guard_pos` count.
fn (mut c Checker) mpa_proven_length_bound(m &MpaCtx, access int, target int, name string, min_guard_pos int) MpaBounds {
	t := m.t
	mut best := MpaBounds{}
	mut node := access
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		parent_type := t.typ(parent)
		if parent_type in [.function_expression, .function_declaration, .arrow_function_expression,
			.sequence_expression] {
			break
		}
		guard_live := t.nodes[parent].start > min_guard_pos
		match parent_type {
			.conditional_expression {
				if guard_live && node == t.node(parent, .consequent) or { -1 } {
					best = mpa_max_bounds(best, c.mpa_condition_bounds(m, t.node(parent, .test) or {
						-1
					}, target, name, true))
				} else if guard_live && node == t.node(parent, .alternate) or { -1 } {
					best = mpa_max_bounds(best, c.mpa_condition_bounds(m, t.node(parent, .test) or {
						-1
					}, target, name, false))
				}
			}
			.logical_expression {
				if guard_live && node == t.node(parent, .right) or { -1 } {
					best = mpa_max_bounds(best, c.mpa_condition_bounds(m, t.node(parent, .left) or {
						-1
					}, target, name, (t.string_of(parent, .operator) or { '' }) == '&&'))
				}
			}
			.if_statement {
				if guard_live && node == t.node(parent, .consequent) or { -1 } {
					best = mpa_max_bounds(best, c.mpa_condition_bounds(m, t.node(parent, .test) or {
						-1
					}, target, name, true))
				} else if guard_live && node == t.node(parent, .alternate) or { -1 } {
					best = mpa_max_bounds(best, c.mpa_condition_bounds(m, t.node(parent, .test) or {
						-1
					}, target, name, false))
				}
			}
			else {
				if body := mpa_statement_list(t, parent) {
					index := body.index(node)
					for i in 0 .. index {
						sibling := body[i]
						if t.typ(sibling) == .if_statement && (t.node(sibling, .alternate) or { -1 }) < 0
							&& mpa_definitely_exits(t, t.node(sibling, .consequent) or { -1 })
							&& t.nodes[sibling].start > min_guard_pos {
							best = mpa_max_bounds(best, c.mpa_condition_bounds(m, t.node(sibling,
								.test) or { -1 }, target, name, false))
						}
					}
					if parent_type == .switch_case && guard_live {
						best = mpa_max_bounds(best, c.mpa_switch_bound(m, parent, target, name))
					}
				}
			}
		}
		node = parent
		parent = t.nodes[parent].parent
	}
	return best
}

// mpa_syntactic_min_length ports syntacticMinLength: the length an array literal (up to a hole or
// a spread), a string or a template literal, or a `.concat` chain has at least.
fn mpa_syntactic_min_length(t &estree.EsTree, expr int) ?f64 {
	match t.typ(expr) {
		.array_expression {
			mut count := 0.0
			for element in t.list(expr, .elements) or { []int{} } {
				if element < 0 || t.typ(element) == .spread_element {
					break
				}
				count++
			}
			return count
		}
		.literal {
			value := t.get(expr, .value)
			if value is string {
				return mpa_utf16_length(value)
			}
			return none
		}
		.template_literal {
			if (t.list(expr, .expressions) or { []int{} }).len != 0 {
				return none
			}
			quasis := t.list(expr, .quasis) or { return none }
			if quasis.len == 0 {
				return none
			}
			value := t.get(quasis[0], .value)
			if value is estree.TemplateValue {
				if value.has_cooked {
					return mpa_utf16_length(value.cooked)
				}
			}
			return none
		}
		.call_expression {
			callee := t.node(expr, .callee) or { return none }
			if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false }) {
				return none
			}
			property := t.node(callee, .property) or { return none }
			if t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != 'concat' {
				return none
			}
			mut total := mpa_syntactic_min_length(t, t.node(callee, .object) or { return none }) or {
				0
			}
			for arg in t.list(expr, .arguments) or { []int{} } {
				match t.typ(arg) {
					.spread_element { return none }
					.array_expression { total += mpa_syntactic_min_length(t, arg) or { 0 } }
					.literal { total += 1 }
					else {}
				}
			}
			return total
		}
		else {
			return none
		}
	}
}

// mpa_static_min_length ports staticMinLength: through an effectively const string, or a
// non-escaping array, to its initializer.
fn (mut c Checker) mpa_static_min_length(m &MpaCtx, object int) ?f64 {
	t := m.t
	if t.typ(object) != .identifier {
		return mpa_syntactic_min_length(t, object)
	}
	init := c.mpa_declarator_init(m, c.mpa_find_variable(m, object))
	if init < 0 {
		return none
	}
	min := mpa_syntactic_min_length(t, init)?
	is_string := (t.typ(init) == .literal && t.get(init, .value) is string)
		|| t.typ(init) == .template_literal
	if is_string {
		if !c.mpa_is_effectively_const(m, object) {
			return none
		}
	} else if !c.mpa_is_non_escaping_array(m, object) {
		return none
	}
	return min
}

// mpa_last_write_end_before ports lastWriteEndBefore: the end of the last reassignment of the
// variable before the access, -1 if none.
fn (c &Checker) mpa_last_write_end_before(m &MpaCtx, v int, access int) int {
	access_start := m.t.nodes[access].start
	mut max_end := -1
	for r in m.tree.variables[v].references {
		reference := m.tree.references[r]
		end := node_end(reference.identifier)
		if reference.write && !reference.init && end <= access_start && end > max_end {
			max_end = end
		}
	}
	return max_end
}

// mpa_guaranteed_length_at_least ports guaranteedLengthAtLeast: the receiver's length is provably
// at least `need`.
fn (mut c Checker) mpa_guaranteed_length_at_least(m &MpaCtx, access int, object int, need f64) bool {
	t := m.t
	if need <= 0 {
		return true
	}
	if object_type := c.mpa_type(m, object) {
		if min_length := c.mpa_tuple_min_length(object_type) {
			if min_length >= need {
				if c.mpa_tuple_is_readonly(object_type) {
					return true
				}
				if t.typ(object) == .identifier && c.mpa_is_non_escaping_array(m, object) {
					return true
				}
			}
		}
	}
	if static_length := c.mpa_static_min_length(m, object) {
		if static_length >= need {
			return true
		}
	}
	if t.typ(object) == .identifier {
		target := c.mpa_find_variable(m, object)
		if target >= 0 {
			name := t.string_of(object, .name) or { '' }
			bounds := c.mpa_proven_length_bound(m, access, target, name, c.mpa_last_write_end_before(m,
				target, access))
			if bounds.len >= need && c.mpa_is_length_indexable(m, object)
				&& c.mpa_is_non_escaping_array(m, object) {
				return true
			}
			if math.max(bounds.len, bounds.str) >= need && c.mpa_is_string_object(m, object) {
				return true
			}
		}
	}
	return false
}

// mpa_is_first_split_element_present ports isFirstSplitElementAlwaysPresent:
// `<string>.split('<non-empty>')`.
fn (mut c Checker) mpa_is_first_split_element_present(m &MpaCtx, object int) bool {
	t := m.t
	if !un_is_method_call(t, object, UnMethodCall{
		methods:          ['split']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	}) {
		return false
	}
	args := t.list(object, .arguments) or { return false }
	separator := c.un_static_value(t, args[0])
	if !separator.found || separator.value.kind != .string_ || separator.value.units.len == 0 {
		return false
	}
	callee := t.node(object, .callee) or { return false }
	receiver := t.node(callee, .object) or { return false }
	if _ := c.mpa_type(m, receiver) {
		return c.mpa_is_string_object(m, receiver)
	}
	return true
}

// --- the checks ---------------------------------------------------------------------------------

// mpa_is_literal_negative_integer ports isLiteralNegativeInteger: `-n`, n a positive integer
// literal; its n.
fn mpa_literal_negative_integer(t &estree.EsTree, node int) ?f64 {
	if node < 0 || t.typ(node) != .unary_expression || !(t.flag(node, .prefix) or { false })
		|| (t.string_of(node, .operator) or { '' }) != '-' {
		return none
	}
	argument := t.node(node, .argument)?
	value := t.get(argument, .value)
	if t.typ(argument) == .literal && value is f64 && mpa_is_integer(value) && value > 0 {
		return value
	}
	return none
}

// mpa_is_pop_or_shift_call ports isArrayPopOrShiftCall: `<node>.method()`.
fn mpa_is_pop_or_shift_call(t &estree.EsTree, node int, method string) bool {
	member := t.nodes[node].parent
	if member < 0 {
		return false
	}
	return un_is_method_call(t, t.nodes[member].parent, UnMethodCall{
		methods:          [method]
		arguments_length: 0
		optional_call:    false
		optional_member:  false
	}) && t.node(member, .object) or { -1 } == node
}

struct MpaSlice {
	safe_to_fix bool
	method      string // `zero-index`, `shift` or `pop`
}

// mpa_check_slice_call ports checkSliceCall.
fn mpa_check_slice_call(t &estree.EsTree, node int) ?MpaSlice {
	args := t.list(node, .arguments) or { return none }
	start_value := mpa_literal_negative_integer(t, args[0])?
	parent := t.nodes[node].parent
	mut method := ''
	if parent >= 0 && un_is_member(t, parent, UnMember{ optional: false, computed: true })
		&& t.node(parent, .object) or { -1 } == node
		&& mpa_is_literal_zero(t, t.node(parent, .property) or { -1 }) {
		if mpa_is_left_hand_side(t, parent) {
			return none
		}
		method = 'zero-index'
	} else if mpa_is_pop_or_shift_call(t, node, 'shift') {
		method = 'shift'
	} else if mpa_is_pop_or_shift_call(t, node, 'pop') {
		method = 'pop'
	}
	if method == '' {
		return none
	}
	start_index := -start_value
	if args.len == 1 {
		if start_value == 1 && (method == 'zero-index' || method == 'shift'
			|| (method == 'pop' && start_index == -1)) {
			return MpaSlice{true, method}
		}
		return none
	}
	if end_value := mpa_literal_negative_integer(t, args[1]) {
		if -end_value == start_index + 1 {
			return MpaSlice{true, method}
		}
	}
	if method == 'pop' {
		return none
	}
	return MpaSlice{false, method}
}

// mpa_check_slice ports checkSlice: the first element of `.slice(-n)`.
fn (mut c Checker) mpa_check_slice(m &MpaCtx, node int) ?Finding {
	t := m.t
	if !un_is_method_call(t, node, UnMethodCall{
		methods:           ['slice']
		minimum_arguments: 1
		maximum_arguments: 2
		optional_call:     false
	}) {
		return none
	}
	result := mpa_check_slice_call(t, node) or { return none }
	callee := t.node(node, .callee) or { return none }
	property := t.node(callee, .property) or { return none }
	args := t.list(node, .arguments) or { return none }
	mut fixes := [fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'at')]
	if args.len != 1 {
		_, start := c.un_parenthesized_range(t, m.tokens, args[0])
		last := un_last_token(t, m.tokens, node) or { return none }
		fixes << fix_remove_range(start, last.start)
	}
	parent := t.nodes[node].parent
	if result.method == 'zero-index' {
		fixes << c.mpa_remove_member_property(m, parent)
	} else {
		call := t.nodes[parent].parent
		fixes << c.mpa_remove_member_property(m, parent)
		_, member_end := c.un_parenthesized_range(t, m.tokens, parent)
		fixes << fix_remove_range(member_end, t.nodes[call].end)
	}
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	if result.safe_to_fix {
		return Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'slice'
			has_fix:    has_fix
			fix:        fix
		}
	}
	return Finding{
		stmt:        c.es_tree_position(t, property)
		message_id:  'slice'
		suggestions: [Suggestion{
			message_id: 'useAt'
			fix:        fix
		}]
	}
}

// mpa_check_char_at ports checkCharAt: `string.charAt(…)`.
fn (mut c Checker) mpa_check_char_at(m &MpaCtx, node int) ?Finding {
	t := m.t
	if !un_is_method_call(t, node, UnMethodCall{
		methods:          ['charAt']
		arguments_length: 1
		optional_call:    false
	}) {
		return none
	}
	callee := t.node(node, .callee) or { return none }
	property := t.node(callee, .property) or { return none }
	index := (t.list(node, .arguments) or { return none })[0]
	length_node := c.mpa_length_node(t, index, t.node(callee, .object) or { return none }) or {
		-1
	}
	if length_node < 0 && !m.options.check_all_index_access {
		return none
	}
	mut fixes := []Fix{}
	if length_node >= 0 {
		fixes << c.mpa_remove_length_node(m, length_node)
	}
	fixes << fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'at')
	_, fix := c.merge_fixes(fixes) or { return none }
	return Finding{
		stmt:        c.es_tree_position(t, index)
		message_id:  if length_node >= 0 { 'stringCharAtNegative' } else { 'stringCharAt' }
		suggestions: [Suggestion{
			message_id: 'useAt'
			fix:        fix
		}]
	}
}

// mpa_check_get_last ports checkGetLast: `_.last(array)` and the option's functions.
fn (mut c Checker) mpa_check_get_last(m &MpaCtx, node int) ?Finding {
	t := m.t
	if !un_is_call(t, node, UnCall{ arguments_length: 1, optional: false }) {
		return none
	}
	callee := t.node(node, .callee) or { return none }
	mut matched := ''
	mut found := false
	for name_or_path in m.options.get_last_functions {
		if un_node_matches_name_or_path(t, callee, name_or_path) {
			matched = name_or_path
			found = true
			break
		}
	}
	if !found {
		return none
	}
	array := (t.list(node, .arguments) or { return none })[0]
	data := {
		'description': matched.trim_space()
	}
	if t.typ(array) == .identifier && (t.string_of(array, .name) or { '' }) == 'arguments' {
		return Finding{
			stmt:       c.es_tree_position(t, callee)
			message_id: 'getLastFunction'
			data:       data
		}
	}
	mut fixed := c.un_parenthesized_text(t, m.tokens, array)
	if !c.un_is_parenthesized(t, m.tokens, array) && c.mpa_member_object_needs_parens(m, array) {
		fixed = '(${fixed})'
	}
	fixed = '${fixed}.at(-1)'
	if c.mpa_needs_semicolon(m, m.tokens.before(t.nodes[node].start, false), fixed) {
		fixed = ';${fixed}'
	}
	return Finding{
		stmt:       c.es_tree_position(t, callee)
		message_id: 'getLastFunction'
		data:       data
		has_fix:    true
		fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)
	}
}

// mpa_check_split_at ports checkSplitAt: `<string>.split('<non-empty>').at(0)`, fixed to `[0]`.
fn (mut c Checker) mpa_check_split_at(m &MpaCtx, node int) ?Finding {
	t := m.t
	if !un_is_method_call(t, node, UnMethodCall{
		methods:          ['at']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	}) {
		return none
	}
	callee := t.node(node, .callee) or { return none }
	object := t.node(callee, .object) or { return none }
	property := t.node(callee, .property) or { return none }
	index := (t.list(node, .arguments) or { return none })[0]
	if !mpa_is_literal_zero(t, index) || !c.mpa_is_first_split_element_present(m, object) {
		return none
	}
	_, object_end := c.un_parenthesized_range(t, m.tokens, object)
	return Finding{
		stmt:       c.es_tree_position(t, property)
		message_id: 'splitIndexAccess'
		has_fix:    true
		fix:        fix_replace_range(object_end, t.nodes[node].end, '[${c.un_text(t, index)}]')
	}
}

// mpa_negative_index_k ports negativeIndexK: the k of `<length node> - k` (k a positive integer
// literal).
fn mpa_negative_index_k(t &estree.EsTree, index int, length_node int) ?f64 {
	if t.typ(index) != .binary_expression || (t.string_of(index, .operator) or { '' }) != '-'
		|| t.node(index, .left) or { -1 } != length_node {
		return none
	}
	right := t.node(index, .right)?
	value := t.get(right, .value)
	if t.typ(right) == .literal && value is f64 && mpa_is_integer(value) && value >= 1 {
		return value
	}
	return none
}

// mpa_check_member ports the MemberExpression listener: index access.
fn (mut c Checker) mpa_check_member(m &MpaCtx, node int) ?Finding {
	t := m.t
	if !(t.flag(node, .computed) or { false }) || mpa_is_left_hand_side(t, node) {
		return none
	}
	index := t.node(node, .property) or { return none }
	object := t.node(node, .object) or { return none }
	length_node := c.mpa_length_node(t, index, object) or { -1 }
	if length_node >= 0 {
		if k := mpa_negative_index_k(t, index, length_node) {
			if c.mpa_guaranteed_length_at_least(m, node, object, k) {
				return none
			}
		}
	} else {
		if !m.options.check_all_index_access {
			return none
		}
		static_value := c.un_static_value(t, index)
		if !static_value.found || static_value.value.kind != .number_
			|| !mpa_is_integer(static_value.value.number) || static_value.value.number < 0 {
			return none
		}
		k := static_value.value.number
		if k == 0 && c.mpa_is_first_split_element_present(m, object) {
			return none
		}
		if c.mpa_guaranteed_length_at_least(m, node, object, k + 1) {
			return none
		}
	}
	message_id := if length_node >= 0 { 'negativeIndex' } else { 'index' }
	if t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == 'arguments' {
		return Finding{
			stmt:       c.es_tree_position(t, index)
			message_id: message_id
		}
	}
	mut fixes := []Fix{}
	if length_node >= 0 {
		fixes << c.mpa_remove_length_node(m, length_node)
	}
	// Only remove the space of `foo[foo.length - 1]`.
	if t.typ(index) == .binary_expression && (t.string_of(index, .operator) or { '' }) == '-' {
		left := t.node(index, .left) or { -1 }
		number := t.node(index, .right) or { -1 }
		if length_node >= 0 {
			if left == length_node && number >= 0 && t.typ(number) == .literal {
				raw := t.string_of(number, .raw) or { '' }
				if raw != '' && raw.bytes().all(it.is_digit()) {
					if before := m.tokens.before(t.nodes[number].start, false) {
						between := c.src[before.end..t.nodes[number].start]
						if before.kind == .punctuator && c.token_text(before) == '-'
							&& between != '' && between.runes().all(is_js_space(it)) {
							fixes << fix_remove_range(before.end, t.nodes[number].start)
						}
					}
				}
			}
		}
	}
	opening := c.mpa_token_before_punctuator(m.tokens, t.nodes[index].start, '[') or {
		return none
	}
	optional := t.flag(node, .optional) or { false }
	fixes << fix_replace_range(opening.start, opening.end, if optional { 'at(' } else { '.at(' })
	closing := c.un_token_after_punctuator(m.tokens, t.nodes[index].end, ']') or { return none }
	fixes << fix_replace_range(closing.start, closing.end, ')')
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	return Finding{
		stmt:       c.es_tree_position(t, index)
		message_id: message_id
		has_fix:    has_fix
		fix:        fix
	}
}

fn (mut c Checker) lint_marcrock_prefer_at(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := mpa_options(c.rule_options(marcrock_prefer_at))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	un := c.un_ctx(root, t, tokens, abs_path)
	m := MpaCtx{
		t:       t
		tokens:  tokens
		tree:    c.scope_tree(root)
		un:      &un
		options: options
	}
	for node in un_enter_order(t) {
		match t.typ(node) {
			.member_expression {
				stats.checked++
				if f := c.mpa_check_member(m, node) {
					findings << f
				}
			}
			.call_expression {
				stats.checked++
				// The checks exclude each other: the first that reports ends them.
				if f := c.mpa_check_split_at(m, node) {
					findings << f
					continue
				}
				if f := c.mpa_check_char_at(m, node) {
					findings << f
					continue
				}
				if f := c.mpa_check_slice(m, node) {
					findings << f
					continue
				}
				if f := c.mpa_check_get_last(m, node) {
					findings << f
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
