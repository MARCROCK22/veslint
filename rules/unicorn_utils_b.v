module rules

import estree
import jsregexp
import treesitter
import tsgo { TypeResponse }

// Helpers of eslint-plugin-unicorn 79.0.0 (rules/utils, rules/fix, rules/ast and rules/shared)
// that are new in it or changed since 64.0.0, for the rules that were brought to 79.0.0 (see
// unicorn_utils.v for the ones that did not change). Offsets are bytes of the source.

// UnbRange is a range of the source, in bytes.
struct UnbRange {
	start int
	end   int
}

// unb_node_range is the range of an ESTree node.
fn unb_node_range(t &estree.EsTree, node int) UnbRange {
	return UnbRange{t.nodes[node].start, t.nodes[node].end}
}

// unb_comment_value is the value of a comment token: its text without `//`, `/*` and `*/`.
fn (c &Checker) unb_comment_value(comment SourceToken) string {
	text := c.src[comment.start..comment.end]
	return match comment.kind {
		.block_comment { text[2..text.len - 2] }
		else { text[2..] }
	}
}

// unb_is_disable_or_enable_directive ports isEslintDisableOrEnableDirective (utils/
// eslint-directive.js): the comment is one of the directives of sourceCode.getDisableDirectives()
// (a `disable`, `enable`, `disable-line` or `disable-next-line` one).
fn (c &Checker) unb_is_disable_or_enable_directive(comment SourceToken) bool {
	if comment.kind == .shebang_comment {
		return false
	}
	label, _, _ := parse_directive(c.unb_comment_value(comment)) or { return false }
	if label !in ['eslint-disable', 'eslint-enable', 'eslint-disable-line', 'eslint-disable-next-line'] {
		return false
	}
	if comment.kind == .line_comment && label !in ['eslint-disable-line', 'eslint-disable-next-line'] {
		return false
	}
	// A multi-line `eslint-disable-line` is a problem, not a directive.
	if label == 'eslint-disable-line' && c.src[comment.start..comment.end].contains_any('\n\r  ') {
		return false
	}
	return true
}

// unb_would_remove_comments ports wouldRemoveComments (utils/comments.js): replacing or removing
// the range would remove a comment that is inside it and outside every preserved range (with
// `ignore_directives`, disable and enable directives do not count).
fn (c &Checker) unb_would_remove_comments(tokens &SourceTokens, replaced UnbRange, preserved []UnbRange, ignore_directives bool) bool {
	for comment in tokens.comments_inside(replaced.start, replaced.end) {
		if comment.end > replaced.end {
			continue
		}
		if preserved.any(comment.start >= it.start && comment.end <= it.end) {
			continue
		}
		if ignore_directives && c.unb_is_disable_or_enable_directive(comment) {
			continue
		}
		return true
	}
	return false
}

// unb_has_non_directive_comment ports hasNonDirectiveComment (utils/comments.js).
fn (c &Checker) unb_has_non_directive_comment(tokens &SourceTokens, replaced UnbRange, preserved []UnbRange) bool {
	return c.unb_would_remove_comments(tokens, replaced, preserved, true)
}

// unb_parenthesized_range is getParenthesizedRange as an UnbRange.
fn (c &Checker) unb_parenthesized_range(t &estree.EsTree, tokens &SourceTokens, node int) UnbRange {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return UnbRange{start, end}
}

// unb_linebreak ports getLinebreak (utils/get-linebreak.js): the first line ending of the file, or
// `\n` for a file of one line.
fn (c &Checker) unb_linebreak() string {
	for i := 0; i < c.src.len; i++ {
		match c.src[i] {
			`\r` {
				return if i + 1 < c.src.len && c.src[i + 1] == `\n` { '\r\n' } else { '\r' }
			}
			`\n` {
				return '\n'
			}
			0xe2 {
				// U+2028 and U+2029: E2 80 A8 and E2 80 A9.
				if i + 2 < c.src.len && c.src[i + 1] == 0x80 && c.src[i + 2] in [u8(0xa8), 0xa9] {
					return c.src[i..i + 3]
				}
			}
			else {}
		}
	}
	return '\n'
}

// unb_needs_semicolon ports needsSemicolon (utils/needs-semicolon.js) of 79.0.0: whether code that
// starts with `code` and goes right after the token `before` needs a `;` first. An empty `code`
// never does; none is any code.
fn (c &Checker) unb_needs_semicolon(t &estree.EsTree, tokens &SourceTokens, before ?SourceToken, code ?string) bool {
	if text := code {
		if text == '' || text[0] !in [`[`, `(`, `/`, `\``, `+`, `-`, `*`, `,`, `.`, `<`] {
			return false
		}
	}
	token := before or { return false }
	value := c.token_text(token)
	if token.kind == .punctuator && value == ';' {
		return false
	}
	// Parser wrapper tokens have no node.
	last_block := un_node_by_range_index(t, token.start) or { return false }
	for node := last_block; node >= 0 && t.nodes[node].end == token.end; node = t.nodes[node].parent {
		if t.typ(node) in [.expression_statement, .variable_declaration, .return_statement,
			.throw_statement, .export_default_declaration] {
			return true
		}
	}
	last_block_parent := t.nodes[last_block].parent
	parent_type := if last_block_parent >= 0 { t.typ(last_block_parent) } else { estree.NodeType.program }
	if token.kind == .punctuator {
		if value == ']' {
			return true
		}
		if value == '}' && ((t.typ(last_block) == .block_statement && parent_type == .function_expression)
			|| (t.typ(last_block) == .class_body && parent_type == .class_expression)) {
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
					if previous := tokens.before(t.nodes[body].start, false) {
						if previous.start == token.start {
							return false
						}
					}
				}
			}
			return true
		}
	}
	if token.kind in [.string_, .null_, .boolean, .numeric, .regular_expression] {
		return true
	}
	if token.kind == .template {
		return value.ends_with('`')
	}
	// The trailing `!`, not the opening parenthesis of `(foo)!`.
	if t.typ(last_block) == .object_expression
		|| (t.typ(last_block) == .ts_non_null_expression && value == '!')
		|| (t.typ(last_block) == .ts_type_parameter_instantiation
		&& parent_type == .ts_instantiation_expression) {
		return true
	}
	if token.kind == .identifier {
		// `for...of`
		if value == 'of' && t.typ(last_block) == .for_of_statement {
			return false
		}
		// `await`
		return !(value == 'await' && t.typ(last_block) == .await_expression)
	}
	return false
}

const unb_precedence_unary = 16
const unb_precedence_call = 18
const unb_precedence_addition = 12

// unb_operator_precedence is the precedence of a binary or logical operator (get-precedence.js).
fn unb_operator_precedence(operator string) int {
	return match operator {
		'??', '||' { 4 }
		'&&' { 5 }
		'|' { 6 }
		'^' { 7 }
		'&' { 8 }
		'==', '!=', '===', '!==' { 9 }
		'<', '<=', '>', '>=', 'in', 'instanceof' { 10 }
		'<<', '>>', '>>>' { 11 }
		'+', '-' { 12 }
		'*', '/', '%' { 13 }
		'**' { 15 }
		else { 0 }
	}
}

// unb_precedence ports getPrecedence (utils/get-precedence.js): a higher number binds tighter.
fn unb_precedence(t &estree.EsTree, node int) int {
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
		.logical_expression, .binary_expression {
			unb_operator_precedence(t.string_of(node, .operator) or { '' })
		}
		.ts_as_expression, .ts_satisfies_expression {
			10
		}
		.unary_expression, .await_expression, .ts_type_assertion, .ts_non_null_expression {
			unb_precedence_unary
		}
		.update_expression {
			if t.flag(node, .prefix) or { false } { unb_precedence_unary } else { 17 }
		}
		.call_expression, .chain_expression, .import_expression {
			unb_precedence_call
		}
		.new_expression {
			19
		}
		else {
			20
		}
	}
}

// unb_should_add_parens_to_comparison ports shouldAddParenthesesToComparison (utils/
// should-add-parentheses-to-comparison.js): replacing `node` with a comparison of `operator` needs
// parentheses where it is.
fn (c &Checker) unb_should_add_parens_to_comparison(t &estree.EsTree, tokens &SourceTokens, node int, operator string) bool {
	if c.un_is_parenthesized(t, tokens, node) {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		// `(foo.length > 0).x`
		.member_expression {
			t.node(parent, .object) or { -1 } == node
		}
		// `(foo.length > 0)()`, `new (foo.length > 0)()`
		.call_expression, .new_expression {
			t.node(parent, .callee) or { -1 } == node
		}
		// `(foo.length > 0)\`x\``
		.tagged_template_expression {
			t.node(parent, .tag) or { -1 } == node
		}
		// `bar === (foo.length === 0)`, `bar + (foo.length > 0)`, `(foo.length > 0) ** 2`
		.binary_expression, .ts_as_expression, .ts_satisfies_expression {
			precedence := unb_operator_precedence(operator)
			parent_precedence := unb_precedence(t, parent)
			parent_precedence > precedence || (parent_precedence == precedence
				&& t.typ(parent) == .binary_expression && t.node(parent, .right) or { -1 } == node)
		}
		// `typeof (foo.length > 0)`, `await (foo.length > 0)`, `(foo.length > 0)!`
		.await_expression, .ts_non_null_expression, .ts_type_assertion, .unary_expression {
			true
		}
		else {
			false
		}
	}
}

// unb_is_ts_wrapper ports isTypeScriptExpressionWrapper (utils/unwrap-typescript-expression.js):
// `as`, `satisfies`, `!`, `<Type>` or `foo<Type>`.
fn unb_is_ts_wrapper(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.ts_as_expression, .ts_satisfies_expression,
		.ts_non_null_expression, .ts_type_assertion, .ts_instantiation_expression]
}

// unb_unwrap_ts ports unwrapTypeScriptExpression: the node without its TypeScript wrappers.
fn unb_unwrap_ts(t &estree.EsTree, node int) int {
	mut n := node
	for unb_is_ts_wrapper(t, n) {
		n = t.node(n, .expression) or { return n }
	}
	return n
}

// unb_unwrap_chain_and_ts ports unwrapChainAndTypeScriptExpression.
fn unb_unwrap_chain_and_ts(t &estree.EsTree, node int) int {
	mut n := node
	for n >= 0 && (t.typ(n) == .chain_expression || unb_is_ts_wrapper(t, n)) {
		n = t.node(n, .expression) or { return n }
	}
	return n
}

// unb_outermost_ts ports getOutermostTypeScriptExpression: the outermost TypeScript wrapper
// around the node, or the node.
fn unb_outermost_ts(t &estree.EsTree, node int) int {
	mut n := node
	for {
		parent := t.nodes[n].parent
		if !unb_is_ts_wrapper(t, parent) || t.node(parent, .expression) or { -1 } != n {
			return n
		}
		n = parent
	}
	return n
}

// unb_outermost_chain_and_ts ports getOutermostChainAndTypeScriptExpression.
fn unb_outermost_chain_and_ts(t &estree.EsTree, node int) int {
	mut n := node
	for {
		parent := t.nodes[n].parent
		if parent < 0 || !(t.typ(parent) == .chain_expression || unb_is_ts_wrapper(t, parent))
			|| t.node(parent, .expression) or { -1 } != n {
			return n
		}
		n = parent
	}
	return n
}

// unb_has_optional_chain_element ports hasOptionalChainElement (utils/
// has-optional-chain-element.js): an optional member or call in the chain of the node.
fn unb_has_optional_chain_element(t &estree.EsTree, node int) bool {
	mut n := unb_unwrap_ts(t, node)
	if n < 0 {
		return false
	}
	if t.typ(n) == .chain_expression {
		return unb_has_optional_chain_element(t, t.node(n, .expression) or { return false })
	}
	if t.typ(n) !in [.member_expression, .call_expression] {
		return false
	}
	if t.flag(n, .optional) or { false } {
		return true
	}
	next := if t.typ(n) == .member_expression {
		t.node(n, .object) or { return false }
	} else {
		t.node(n, .callee) or { return false }
	}
	return unb_has_optional_chain_element(t, next)
}

// unb_has_unparenthesized_optional_chain_element ports hasUnparenthesizedOptionalChainElement.
fn (c &Checker) unb_has_unparenthesized_optional_chain_element(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if node < 0 {
		return false
	}
	if unb_is_ts_wrapper(t, node) || t.typ(node) == .chain_expression {
		return !c.un_is_parenthesized(t, tokens, node)
			&& c.unb_has_unparenthesized_optional_chain_element(t, tokens, t.node(node, .expression) or {
			return false
		})
	}
	if t.typ(node) !in [.member_expression, .call_expression] {
		return false
	}
	if t.flag(node, .optional) or { false } {
		return true
	}
	next := if t.typ(node) == .member_expression {
		t.node(node, .object) or { return false }
	} else {
		t.node(node, .callee) or { return false }
	}
	return c.unb_has_unparenthesized_optional_chain_element(t, tokens, next)
}

// unb_problematic_token is isProblematicToken of fix/fix-space-around-keywords.js: a keyword in
// lower case, or `of`, `await`, `as` or `satisfies`.
fn (c &Checker) unb_problematic_token(token SourceToken) bool {
	text := c.token_text(token)
	if token.kind == .keyword {
		return text.bytes().all(it >= `a` && it <= `z`)
	}
	return token.kind == .identifier && text in ['of', 'await', 'as', 'satisfies']
}

// unb_fix_space_around_keyword ports fixSpaceAroundKeyword of 79.0.0: a space between the node
// (with its parentheses) and a keyword right before or after it.
fn (c &Checker) unb_fix_space_around_keyword(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return c.unb_fix_space_around_range(tokens, start, end)
}

// unb_fix_space_around_range is unb_fix_space_around_keyword for a range.
fn (c &Checker) unb_fix_space_around_range(tokens &SourceTokens, start int, end int) []Fix {
	mut fixes := []Fix{}
	if before := tokens.before(start, true) {
		if start == before.end && c.unb_problematic_token(before) {
			fixes << fix_insert_at(before.end, ' ')
		}
	}
	if after := tokens.after(end, true) {
		if end == after.start && c.unb_problematic_token(after) {
			fixes << fix_insert_at(after.start, ' ')
		}
	}
	return fixes
}

// unb_new_callee_needs_parens ports shouldAddParenthesesToNewExpressionCallee of 79.0.0: a member
// expression whose object chain (through template tags and TypeScript wrappers) has a call.
fn (c &Checker) unb_new_callee_needs_parens(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if t.typ(node) != .member_expression {
		return false
	}
	mut current := t.node(node, .object) or { return false }
	for !c.un_is_parenthesized(t, tokens, current) {
		if unb_is_ts_wrapper(t, current) {
			current = t.node(current, .expression) or { return false }
			continue
		}
		if t.typ(current) !in [.member_expression, .tagged_template_expression] {
			return t.typ(current) == .call_expression
		}
		current = if t.typ(current) == .member_expression {
			t.node(current, .object) or { return false }
		} else {
			t.node(current, .tag) or { return false }
		}
	}
	return false
}

// unb_switch_call_to_new ports switchCallExpressionToNewExpression of 79.0.0: `Error()` becomes
// `new Error()`.
fn (c &Checker) unb_switch_call_to_new(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	mut fixes := c.unb_fix_space_around_keyword(t, tokens, node)
	fixes << fix_insert_at(t.nodes[node].start, 'new ')
	callee := t.node(node, .callee) or { return fixes }
	if !c.un_is_parenthesized(t, tokens, callee) && c.unb_new_callee_needs_parens(t, tokens, callee) {
		fixes << fix_insert_at(t.nodes[callee].start, '(')
		fixes << fix_insert_at(t.nodes[callee].end, ')')
	}
	return fixes
}

// unb_type_of ports withTypeInformation (utils/types.js) for the type of an ESTree node: none
// when the parser has no program (LanguageOptions.type_information) or tsgo has no type for it.
// The rule must not be in untyped_rules.
fn (mut c Checker) unb_type_of(t &estree.EsTree, node int, abs_path string, mut stats Stats) ?TypeResponse {
	if !c.scope_setup.type_information {
		return none
	}
	ts := t.ts_node(node) or { return none }
	c.resolve_node_types([ts], abs_path, mut stats) or { return none }
	return c.node_type(ts)
}

// unb_find_variable ports findVariable(sourceCode.getScope(node), node) of eslint-utils for an
// ESTree Identifier: the index of its variable in the scope tree, -1 for none.
fn (mut c Checker) unb_find_variable(root C.TSNode, t &estree.EsTree, node int) int {
	if node < 0 || t.typ(node) != .identifier {
		return -1
	}
	ts := t.ts_node(node) or { return -1 }
	tree := c.scope_tree(root)
	return tree.find_variable(tree.get_scope(ts), t.string_of(node, .name) or { return -1 },
		t.nodes[node].start)
}

// unb_single_definition is the only definition of a variable (`variable?.defs.length === 1`).
fn (mut c Checker) unb_single_definition(root C.TSNode, v int) ?ScopeDefinition {
	if v < 0 {
		return none
	}
	tree := c.scope_tree(root)
	if tree.variables[v].defs.len != 1 {
		return none
	}
	return tree.variables[v].defs[0]
}

// unb_is_simple_declarator: a definition of a variable whose declarator binds its name directly
// (`definition.node.id === definition.name`).
fn unb_is_simple_declarator(def ScopeDefinition) bool {
	if def.kind != .variable || treesitter.node_kind(def.node) != 'variable_declarator' {
		return false
	}
	id := def.decl_id or { return false }
	return node_key(id) == node_key(def.name)
}

// unb_const_definition ports getConstVariableDefinition (utils/get-static-value.js): the variable
// of an identifier and the initializer of its only definition, a `const` declarator of the name.
fn (mut c Checker) unb_const_definition(root C.TSNode, t &estree.EsTree, node int) ?(int, int) {
	v := c.unb_find_variable(root, t, node)
	def := c.unb_single_definition(root, v)?
	if !unb_is_simple_declarator(def) || def.parent_kind != 'const' {
		return none
	}
	init := c.es_index_of(t, def.init?)?
	return v, init
}

// unb_is_global_identifier ports isGlobalIdentifier (utils/is-global-identifier.js): an
// identifier that references a configured global or no variable at all.
fn (mut c Checker) unb_is_global_identifier(root C.TSNode, t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .identifier {
		return false
	}
	ts := t.ts_node(node) or { return false }
	return c.es_is_global_reference(root, ts) || c.unb_find_variable(root, t, node) < 0
}

// unb_static_string_value ports getStaticStringValue (ast/literal.js): the value of a string
// literal or of a template literal without expressions.
fn unb_static_string_value(t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	if un_is_string_literal(t, node) {
		value := t.get(node, .value)
		if value is string {
			return value
		}
	}
	if t.typ(node) == .template_literal && (t.list(node, .expressions) or { []int{} }).len == 0 {
		quasi := (t.list(node, .quasis) or { return none })[0]
		value := t.get(quasi, .value)
		if value is estree.TemplateValue {
			if value.has_cooked {
				return value.cooked
			}
		}
	}
	return none
}

// unb_evaluated_children ports getEvaluatedChildNodes (utils/get-visitor-child-nodes.js): the
// children in visitor-key order but the names that are not evaluated (a non-computed member
// property, a non-computed key of a Property, PropertyDefinition or MethodDefinition).
fn unb_evaluated_children(t &estree.EsTree, node int) []int {
	computed := t.flag(node, .computed) or { false }
	mut skip := -1
	if !computed {
		if t.typ(node) == .member_expression {
			skip = t.node(node, .property) or { -1 }
		} else if t.typ(node) in [.property, .property_definition, .method_definition] {
			skip = t.node(node, .key) or { -1 }
		}
	}
	return t.children(node).filter(it != skip)
}

// unb_has_side_effect ports hasSideEffect of eslint-utils: with `consider_getters`, member
// accesses count too.
fn unb_has_side_effect(t &estree.EsTree, node int, consider_getters bool) bool {
	match t.typ(node) {
		.arrow_function_expression, .function_expression {
			return false
		}
		.assignment_expression, .await_expression, .call_expression, .import_expression,
		.new_expression, .update_expression, .yield_expression {
			return true
		}
		.unary_expression {
			if (t.string_of(node, .operator) or { '' }) == 'delete' {
				return true
			}
		}
		.member_expression {
			if consider_getters {
				return true
			}
		}
		else {}
	}
	return t.children(node).any(unb_has_side_effect(t, it, consider_getters))
}

const unb_static_global_properties = {
	'Math':   ['E', 'LN2', 'LN10', 'LOG2E', 'LOG10E', 'PI', 'SQRT1_2', 'SQRT2']
	'Number': ['EPSILON', 'MAX_SAFE_INTEGER', 'MAX_VALUE', 'MIN_SAFE_INTEGER', 'MIN_VALUE', 'NaN',
		'NEGATIVE_INFINITY', 'POSITIVE_INFINITY']
	'String': ['raw']
	'Symbol': ['asyncIterator', 'hasInstance', 'isConcatSpreadable', 'iterator', 'match', 'matchAll',
		'replace', 'search', 'species', 'split', 'toPrimitive', 'toStringTag', 'unscopables']
}

// unb_is_safe_static_global_member ports isSafeStaticGlobalMember: a constant property of a
// builtin global (`Math.PI`).
fn (mut c Checker) unb_is_safe_static_global_member(root C.TSNode, t &estree.EsTree, node int) bool {
	if t.typ(node) != .member_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	object := t.node(node, .object) or { return false }
	if t.typ(object) != .identifier || !c.unb_is_global_identifier(root, t, object) {
		return false
	}
	properties := unb_static_global_properties[t.string_of(object, .name) or { '' }] or {
		return false
	}
	property := t.node(node, .property) or { return false }
	name := if t.flag(node, .computed) or { false } {
		unb_static_string_value(t, property) or { return false }
	} else if t.typ(property) == .identifier {
		t.string_of(property, .name) or { return false }
	} else {
		return false
	}
	return name in properties
}

// unb_is_safe_static_pass_through_call ports isSafeStaticPassThroughCall: `Object.freeze(x)`,
// `Object.preventExtensions(x)` or `Object.seal(x)` of a static value without side effects.
fn (mut c Checker) unb_is_safe_static_pass_through_call(root C.TSNode, t &estree.EsTree, n int, mut visited map[int]bool) bool {
	node := unb_unwrap_ts(t, n)
	if t.typ(node) != .call_expression {
		return false
	}
	callee := unb_unwrap_ts(t, t.node(node, .callee) or { return false })
	args := t.list(node, .arguments) or { return false }
	if (t.flag(node, .optional) or { false }) || args.len != 1 || t.typ(args[0]) == .spread_element
		|| t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false })
		|| (t.flag(callee, .optional) or { false }) {
		return false
	}
	object := unb_unwrap_ts(t, t.node(callee, .object) or { return false })
	property := t.node(callee, .property) or { return false }
	if t.typ(object) != .identifier || (t.string_of(object, .name) or { '' }) != 'Object'
		|| !c.unb_is_global_identifier(root, t, object) || t.typ(property) != .identifier
		|| (t.string_of(property, .name) or { '' }) !in ['freeze', 'preventExtensions', 'seal'] {
		return false
	}
	c.unb_static_value_internal(root, t, args[0], mut visited) or { return false }
	return true
}

// unb_is_branch_expression ports isBranchExpression: a conditional or logical expression, maybe
// under unary operators.
fn unb_is_branch_expression(t &estree.EsTree, n int) bool {
	mut node := unb_unwrap_ts(t, n)
	for t.typ(node) == .unary_expression {
		node = unb_unwrap_ts(t, t.node(node, .argument) or { return false })
	}
	return t.typ(node) in [.conditional_expression, .logical_expression]
}

fn (mut c Checker) unb_has_side_effectful_const_reference(root C.TSNode, t &estree.EsTree, node int, mut visited map[int]bool) bool {
	if t.typ(node) == .identifier {
		return c.unb_has_side_effectful_const_initializer(root, t, node, mut visited)
	}
	if t.typ(node) in [.function_expression, .arrow_function_expression, .class_expression] {
		return false
	}
	for child in unb_evaluated_children(t, node) {
		if c.unb_has_side_effectful_const_reference(root, t, child, mut visited) {
			return true
		}
	}
	return false
}

// unb_has_side_effectful_const_initializer ports hasSideEffectfulConstInitializer.
fn (mut c Checker) unb_has_side_effectful_const_initializer(root C.TSNode, t &estree.EsTree, node int, mut visited map[int]bool) bool {
	v, init := c.unb_const_definition(root, t, node) or {
		return t.typ(node) != .identifier
			&& c.unb_has_side_effectful_const_reference(root, t, node, mut visited)
	}
	if visited[v] {
		return true
	}
	visited[v] = true
	result := (!c.unb_is_safe_static_pass_through_call(root, t, init, mut visited)
		&& unb_has_side_effect(t, init, true))
		|| c.unb_has_side_effectful_const_reference(root, t, init, mut visited)
	visited.delete(v)
	return result
}

// unb_static_value_text is String(value) of a string or a number of a static value.
fn unb_static_value_text(v StaticValue) ?string {
	if !v.found || v.value.kind !in [.string_, .number_] {
		return none
	}
	return js_any_string_value(v.value)
}

// unb_literal_property_text is String(property.value) of a literal string or number.
fn unb_literal_property_text(t &estree.EsTree, property int) ?string {
	if t.typ(property) != .literal {
		return none
	}
	value := t.get(property, .value)
	return match value {
		string { value }
		f64 { js_number_to_string(value) }
		else { none }
	}
}

// unb_static_property_name ports getStaticPropertyName of utils/get-static-value.js; without
// `with_context` a computed key is never resolved.
fn (mut c Checker) unb_static_property_name(root C.TSNode, t &estree.EsTree, node int, property int, with_context bool) ?string {
	computed := t.flag(node, .computed) or { false }
	if t.typ(property) == .identifier && !computed {
		return t.string_of(property, .name)
	}
	if text := unb_literal_property_text(t, property) {
		return text
	}
	if !computed || !with_context {
		return none
	}
	if t.typ(property) == .identifier {
		c.unb_const_definition(root, t, property) or { return none }
	}
	return unb_static_value_text(c.un_static_value(t, property))
}

fn (mut c Checker) unb_is_safe_static_object_member(root C.TSNode, t &estree.EsTree, node int, name ?string, mut visited map[int]bool) bool {
	property_name := name or { return false }
	properties := t.list(node, .properties) or { return false }
	for p in properties {
		if t.typ(p) != .property || (t.flag(p, .computed) or { false }) {
			return false
		}
		key := t.node(p, .key) or { return false }
		if (t.string_of(key, .name) or { '' }) == '__proto__'
			|| (t.typ(key) == .literal && t.get(key, .value) is string
			&& (t.get(key, .value) as string) == '__proto__') {
			return false
		}
		if c.unb_has_potentially_mutable_member_access(root, t, t.node(p, .value) or { return false }, mut
			visited)
		{
			return false
		}
	}
	mut found := -1
	for candidate in properties {
		key := t.node(candidate, .key) or { continue }
		if candidate_name := c.unb_static_property_name(root, t, candidate, key, false) {
			if candidate_name == property_name {
				found = candidate
			}
		}
	}
	return found >= 0 && (t.string_of(found, .kind) or { '' }) == 'init'
		&& !(t.flag(found, .method) or { false })
}

// unb_canonical_index: the property name is the canonical string of a safe integer in [0, len).
fn unb_canonical_index(name string, len int) bool {
	if name == '' || (name.len > 1 && name[0] == `0`) || !name.bytes().all(it.is_digit()) || name.len > 15 {
		return false
	}
	return name.i64() < len
}

fn (mut c Checker) unb_is_safe_static_array_member(root C.TSNode, t &estree.EsTree, node int, name ?string, mut visited map[int]bool) bool {
	elements := t.list(node, .elements) or { return false }
	for element in elements {
		if element >= 0 && (t.typ(element) == .spread_element
			|| c.unb_has_potentially_mutable_member_access(root, t, element, mut visited)) {
			return false
		}
	}
	property_name := name or { return false }
	if property_name == 'length' {
		return true
	}
	if !unb_canonical_index(property_name, elements.len) {
		return false
	}
	return elements[property_name.int()] >= 0
}

fn (mut c Checker) unb_is_safe_static_member_object(root C.TSNode, t &estree.EsTree, node int, name ?string, mut visited map[int]bool) bool {
	mut primitive := ?string(none)
	if value := unb_static_string_value(t, node) {
		primitive = value
	} else if _, init := c.unb_const_definition(root, t, node) {
		primitive = unb_static_string_value(t, init)
	}
	if value := primitive {
		property_name := name or { return false }
		if property_name == 'length' {
			return true
		}
		return unb_canonical_index(property_name, estree.utf16_units(value).len)
	}
	if t.typ(node) == .array_expression {
		return c.unb_is_safe_static_array_member(root, t, node, name, mut visited)
	}
	if t.typ(node) == .object_expression {
		return c.unb_is_safe_static_object_member(root, t, node, name, mut visited)
	}
	return false
}

fn (mut c Checker) unb_is_safe_static_member(root C.TSNode, t &estree.EsTree, node int, mut visited map[int]bool) bool {
	property := t.node(node, .property) or { return false }
	name := c.unb_static_property_name(root, t, node, property, true)
	if (t.flag(node, .computed) or { false })
		&& c.unb_has_potentially_mutable_member_access(root, t, property, mut visited) {
		return false
	}
	return c.unb_is_safe_static_member_object(root, t, t.node(node, .object) or { return false },
		name, mut visited)
}

// unb_has_potentially_mutable_member_access ports hasPotentiallyMutableMemberAccess: the
// expression reads a member whose value may change.
fn (mut c Checker) unb_has_potentially_mutable_member_access(root C.TSNode, t &estree.EsTree, n int, mut visited map[int]bool) bool {
	mut node := unb_unwrap_ts(t, n)
	if t.typ(node) == .chain_expression {
		node = t.node(node, .expression) or { return false }
	}
	if c.unb_is_safe_static_pass_through_call(root, t, node, mut visited) {
		return false
	}
	if v, init := c.unb_const_definition(root, t, node) {
		if visited[v] {
			return true
		}
		visited[v] = true
		result := c.unb_has_potentially_mutable_member_access(root, t, init, mut visited)
		visited.delete(v)
		return result
	}
	if t.typ(node) == .member_expression {
		return !c.unb_is_safe_static_global_member(root, t, node)
			&& !c.unb_is_safe_static_member(root, t, node, mut visited)
	}
	for child in unb_evaluated_children(t, node) {
		if c.unb_has_potentially_mutable_member_access(root, t, child, mut visited) {
			return true
		}
	}
	return false
}

// unb_has_unsafe_binding_in_evaluated_path ports hasUnsafeBindingInEvaluatedPath.
fn (mut c Checker) unb_has_unsafe_binding_in_evaluated_path(root C.TSNode, t &estree.EsTree, n int, mut visited map[int]bool) bool {
	node := unb_unwrap_ts(t, n)
	match t.typ(node) {
		.identifier {
			v := c.unb_find_variable(root, t, node)
			def := c.unb_single_definition(root, v) or { return false }
			if def.kind != .variable {
				return false
			}
			if def.parent_kind != 'const' {
				return true
			}
			if treesitter.node_end(def.node) > t.nodes[node].start {
				return true
			}
			init := c.es_index_of(t, def.init or { return false }) or { return false }
			if visited[v] {
				return false
			}
			visited[v] = true
			result := c.unb_has_unsafe_binding_in_evaluated_path(root, t, init, mut visited)
			visited.delete(v)
			return result
		}
		.conditional_expression {
			test := t.node(node, .test) or { return false }
			if c.unb_has_unsafe_binding_in_evaluated_path(root, t, test, mut visited) {
				return true
			}
			consequent := t.node(node, .consequent) or { return false }
			alternate := t.node(node, .alternate) or { return false }
			if value := c.unb_static_value_internal(root, t, test, mut visited) {
				return c.unb_has_unsafe_binding_in_evaluated_path(root, t, if stv_to_boolean(value.value) {
					consequent
				} else {
					alternate
				}, mut visited)
			}
			return c.unb_has_unsafe_binding_in_evaluated_path(root, t, consequent, mut visited)
				|| c.unb_has_unsafe_binding_in_evaluated_path(root, t, alternate, mut visited)
		}
		.logical_expression {
			left := t.node(node, .left) or { return false }
			right := t.node(node, .right) or { return false }
			if c.unb_has_unsafe_binding_in_evaluated_path(root, t, left, mut visited) {
				return true
			}
			if value := c.unb_static_value_internal(root, t, left, mut visited) {
				operator := t.string_of(node, .operator) or { '' }
				evaluates_right := match operator {
					'&&' { stv_to_boolean(value.value) }
					'||' { !stv_to_boolean(value.value) }
					else { value.value.kind in [.null_, .undefined_] }
				}
				return evaluates_right
					&& c.unb_has_unsafe_binding_in_evaluated_path(root, t, right, mut visited)
			}
			return c.unb_has_unsafe_binding_in_evaluated_path(root, t, right, mut visited)
		}
		.sequence_expression {
			for expression in t.list(node, .expressions) or { []int{} } {
				if c.unb_has_unsafe_binding_in_evaluated_path(root, t, expression, mut visited) {
					return true
				}
			}
			return false
		}
		.function_expression, .arrow_function_expression, .class_expression {
			return false
		}
		else {}
	}
	for child in unb_evaluated_children(t, node) {
		if c.unb_has_unsafe_binding_in_evaluated_path(root, t, child, mut visited) {
			return true
		}
	}
	return false
}

// unb_static_value_internal ports getStaticValueIfNoSideEffectsInternal.
fn (mut c Checker) unb_static_value_internal(root C.TSNode, t &estree.EsTree, n int, mut visited map[int]bool) ?StaticValue {
	node := unb_unwrap_ts(t, n)
	if (unb_has_side_effect(t, node, false)
		&& !c.unb_is_safe_static_pass_through_call(root, t, node, mut visited))
		|| c.unb_has_side_effectful_const_initializer(root, t, node, mut visited) {
		return none
	}
	value := c.un_static_value(t, node)
	if !value.found {
		return none
	}
	if c.unb_has_potentially_mutable_member_access(root, t, node, mut visited) {
		return none
	}
	return value
}

// unb_static_value_if_no_side_effects ports getStaticValueIfNoSideEffects.
fn (mut c Checker) unb_static_value_if_no_side_effects(root C.TSNode, t &estree.EsTree, node int) ?StaticValue {
	mut visited := map[int]bool{}
	return c.unb_static_value_internal(root, t, node, mut visited)
}

// unb_static_value_for_control_flow ports getStaticValueForControlFlow: getStaticValue is not
// flow-sensitive, so mutable bindings and constants read before their declarations end on an
// evaluated path give none.
fn (mut c Checker) unb_static_value_for_control_flow(root C.TSNode, t &estree.EsTree, node int) ?StaticValue {
	mut visited := map[int]bool{}
	value := c.unb_static_value_internal(root, t, node, mut visited)?
	mut visited_bindings := map[int]bool{}
	if c.unb_has_unsafe_binding_in_evaluated_path(root, t, node, mut visited_bindings) {
		return none
	}
	return value
}

// unb_found is a static value, none when it was not found.
fn unb_found(v StaticValue) ?StaticValue {
	return if v.found { v } else { none }
}

// unb_template_element_raw ports getTemplateElementRaw (utils/get-template-element-raw.js): the
// source text of a TemplateElement between its delimiters (`value.raw` has its line breaks
// normalized).
fn (c &Checker) unb_template_element_raw(t &estree.EsTree, node int) string {
	tail := t.flag(node, .tail) or { false }
	return c.src[t.nodes[node].start + 1..t.nodes[node].end - (if tail { 1 } else { 2 })]
}

// unb_is_undefined_value ports isUndefinedValue (ast/is-undefined.js): `undefined` or a `void`
// expression.
fn unb_is_undefined_value(t &estree.EsTree, node int) bool {
	return un_is_undefined(t, node) || (node >= 0 && t.typ(node) == .unary_expression
		&& (t.string_of(node, .operator) or { '' }) == 'void')
}

// unb_is_null_literal ports isNullLiteral (ast/literal.js): the literal `null`.
fn (c &Checker) unb_is_null_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && c.un_text(t, node) == 'null'
}

// unb_starts_with_declaration_like_token ports startsWithDeclarationLikeToken (utils/
// should-add-parentheses-to-expression-statement-expression.js): the node starts with `{`,
// `class`, `function`, `async function` or `let [`.
fn (c &Checker) unb_starts_with_declaration_like_token(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	first := un_first_token(t, tokens, node, 0) or { return false }
	value := c.token_text(first)
	next := if after := tokens.after(first.end, false) { c.token_text(after) } else { '' }
	return (first.kind == .punctuator && value == '{')
		|| (first.kind == .keyword && value in ['class', 'function'])
		|| (value == 'async' && next == 'function') || (value == 'let' && next == '[')
}

// unb_should_add_parens_to_expression_statement_expression ports
// shouldAddParenthesesToExpressionStatementExpression of 79.0.0.
fn (c &Checker) unb_should_add_parens_to_expression_statement_expression(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	return !c.un_is_parenthesized(t, tokens, node)
		&& c.unb_starts_with_declaration_like_token(t, tokens, node)
}

// unb_should_add_parens_to_expression_start ports shouldAddParenthesesToExpressionStart: moving
// `expression` to where `replacement` is would expose a block or declaration prefix (`let [` in a
// `for` initializer too). A `-1` replacement is the expression itself.
fn (c &Checker) unb_should_add_parens_to_expression_start(t &estree.EsTree, tokens &SourceTokens, expression int, replacement int) bool {
	first := un_first_token(t, tokens, expression, 0) or { return false }
	starts_with_regexp := first.kind == .regular_expression
	if !starts_with_regexp && !c.unb_starts_with_declaration_like_token(t, tokens, expression) {
		return false
	}
	value := c.token_text(first)
	mut node := if replacement < 0 { expression } else { replacement }
	for t.nodes[node].parent >= 0 {
		if c.un_is_parenthesized(t, tokens, node) {
			return false
		}
		parent := t.nodes[node].parent
		if t.typ(parent) == .arrow_function_expression && t.node(parent, .body) or { -1 } == node {
			return value == '{'
		}
		if t.typ(parent) == .export_default_declaration
			&& t.node(parent, .declaration) or { -1 } == node {
			return !starts_with_regexp && value != '{' && value != 'let'
		}
		if t.typ(parent) == .for_statement && t.node(parent, .init) or { -1 } == node {
			return value == 'let'
		}
		if t.typ(node).type_name().ends_with('Statement') {
			return !starts_with_regexp
		}
		if t.nodes[parent].start != t.nodes[node].start {
			return false
		}
		node = parent
	}
	return false
}

// unb_unparenthesized_keyword_argument_parent ports getUnparenthesizedKeywordArgumentParent: the
// `return`, `throw` or non-delegated `yield` whose unparenthesized argument starts with the node;
// -1 for none.
fn (c &Checker) unb_unparenthesized_keyword_argument_parent(t &estree.EsTree, tokens &SourceTokens, n int) int {
	mut node := n
	for !c.un_is_parenthesized(t, tokens, node) {
		parent := t.nodes[node].parent
		if parent >= 0 && t.node(parent, .argument) or { -1 } == node
			&& (t.typ(parent) in [.return_statement, .throw_statement]
			|| (t.typ(parent) == .yield_expression && !(t.flag(parent, .delegate) or { false }))) {
			return parent
		}
		if parent < 0 || t.nodes[parent].start != t.nodes[node].start {
			return -1
		}
		node = parent
	}
	return -1
}

// unb_trim_start is String#trimStart: without JavaScript's white space and line terminators at the
// start.
fn unb_trim_start(s string) string {
	runes := s.runes()
	mut start := 0
	for start < runes.len && is_js_space(runes[start]) {
		start++
	}
	return runes[start..].string()
}

// unb_is_logical_expression ports isLogicalExpression (utils/is-logical-expression.js): a `&&` or
// `||` (not `??`).
fn unb_is_logical_expression(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .logical_expression
		&& (t.string_of(node, .operator) or { '' }) in ['&&', '||']
}

// unb_logical_operands ports getLogicalExpressionOperands: the operands of a chain of logical
// expressions of one operator, from left to right.
fn unb_logical_operands(t &estree.EsTree, node int, operator string) []int {
	if node < 0 || t.typ(node) != .logical_expression
		|| (t.string_of(node, .operator) or { '' }) != operator {
		return [node]
	}
	mut out := unb_logical_operands(t, t.node(node, .left) or { return [node] }, operator)
	out << unb_logical_operands(t, t.node(node, .right) or { return [node] }, operator)
	return out
}

// unb_logical_root ports getLogicalExpressionRoot: the outermost logical expression of the
// operator that has the node as an operand, or the node.
fn unb_logical_root(t &estree.EsTree, node int, operator string) int {
	mut n := node
	for {
		parent := t.nodes[n].parent
		if parent < 0 || t.typ(parent) != .logical_expression
			|| (t.string_of(parent, .operator) or { '' }) != operator {
			return n
		}
		n = parent
	}
	return n
}

// unb_expression_text ports getExpressionText (utils/get-expression-text.js): the text of the
// node, in parentheses when `needs_parens`; redundant parentheses go away unless they hold
// comments, and then the parenthesized text is kept as it is.
fn (c &Checker) unb_expression_text(t &estree.EsTree, tokens &SourceTokens, node int, needs_parens bool) string {
	if c.un_is_parenthesized(t, tokens, node) && c.unb_would_remove_comments(tokens,
		c.unb_parenthesized_range(t, tokens, node), [unb_node_range(t, node)], false) {
		return c.un_parenthesized_text(t, tokens, node)
	}
	text := c.un_text(t, node)
	return if needs_parens { '(${text})' } else { text }
}

// unb_call_argument_text ports getCallArgumentText: the text of the node as the only argument of a
// call (a sequence expression in parentheses).
fn (c &Checker) unb_call_argument_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	return c.unb_expression_text(t, tokens, node, t.typ(node) == .sequence_expression)
}

// unb_call_arguments_text ports getCallExpressionArgumentsText: the text between the parentheses
// of the arguments of a call (without the trailing comma unless `include_trailing_comma`).
fn (c &Checker) unb_call_arguments_text(t &estree.EsTree, tokens &SourceTokens, call int, include_trailing_comma bool) ?string {
	call_tokens := c.un_call_tokens(t, tokens, call)?
	end := if include_trailing_comma {
		call_tokens.closing.start
	} else {
		(call_tokens.trailing or { call_tokens.closing }).start
	}
	return c.src[call_tokens.opening.end..end]
}

// unb_is_number_literal_of ports isLiteral(node, value) for a number.
fn unb_is_number_literal_of(t &estree.EsTree, node int, value f64) bool {
	if node < 0 || t.typ(node) != .literal {
		return false
	}
	v := t.get(node, .value)
	return v is f64 && v == value
}

// unb_is_global_reference_or_undefined is isGlobalReference of utils/boolean.js: a configured
// global, or a name of no variable or of one without definitions.
fn (mut c Checker) unb_is_global_reference_or_undefined(root C.TSNode, t &estree.EsTree, node int) bool {
	ts := t.ts_node(node) or { return false }
	if c.es_is_global_reference(root, ts) {
		return true
	}
	v := c.unb_find_variable(root, t, node)
	return v < 0 || c.scope_tree(root).variables[v].defs.len == 0
}

// unb_is_global_boolean_call ports isGlobalBooleanCall (utils/boolean.js): `Boolean(x)` of the
// global, not optional, with one argument that is not a spread.
fn (mut c Checker) unb_is_global_boolean_call(root C.TSNode, t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	args := t.list(node, .arguments) or { return false }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'Boolean'
		&& args.len == 1 && t.typ(args[0]) != .spread_element
		&& c.unb_is_global_reference_or_undefined(root, t, callee)
}

// unb_is_boolean_expression ports isBooleanExpression of utils/boolean.js of 79.0.0.
fn (mut c Checker) unb_is_boolean_expression(root C.TSNode, t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if un_is_logic_not(t, node) || (un_is_logic_not(t, parent) && t.node(parent, .argument) or { -1 } == node)
		|| c.unb_is_global_boolean_call(root, t, node) || (c.unb_is_global_boolean_call(root, t, parent)
		&& (t.list(parent, .arguments) or { []int{} })[0] == node) {
		return true
	}
	if un_is_logical(t, parent) {
		return c.unb_is_boolean_expression(root, t, parent)
	}
	return false
}

// unb_is_boolean_context ports isBooleanContext: the value of the node is only used for its
// truthiness (TypeScript wrappers around it are not looked through).
fn (mut c Checker) unb_is_boolean_context(root C.TSNode, t &estree.EsTree, node int) bool {
	return c.unb_is_boolean_expression(root, t, node) || un_is_control_flow_test(t, node)
}

// unb_logical_child_text ports getLogicalExpressionChildText: the text of the node (with its
// parentheses) as an operand of `operator`, in parentheses when it needs them.
fn (c &Checker) unb_logical_child_text(t &estree.EsTree, tokens &SourceTokens, node int, operator string) string {
	text := c.un_parenthesized_text(t, tokens, node)
	return if !c.un_is_parenthesized(t, tokens, node) && un_logical_child_needs_parens(t, node, operator) {
		'(${text})'
	} else {
		text
	}
}

// unb_has_static_string: getStaticStringValue(node) !== undefined.
fn unb_has_static_string(t &estree.EsTree, node int) bool {
	unb_static_string_value(t, node) or { return false }
	return true
}

// unb_should_add_parens_to_unary_argument ports shouldAddParenthesesToUnaryExpressionArgument of
// 79.0.0 (any prefix operator): the node binds more loosely than a unary operator, or is an
// update, a `!` or a `<T>` assertion.
fn unb_should_add_parens_to_unary_argument(t &estree.EsTree, node int) bool {
	return unb_precedence(t, node) < unb_precedence_unary
		|| t.typ(node) in [.update_expression, .ts_non_null_expression, .ts_type_assertion]
}

// The type checkers of utils/type-helpers.js (createTypeCheckers): what a node is known to be,
// from its annotations (TypeScript and JSDoc), its definition, its static value, its syntax and,
// when the parser has a program, its type.

enum UnbKind {
	target
	non_target
	nullish
	unknown
}

// UnbFamily selects the hooks of a type checker (isTargetNode, isNonTargetNode, getStaticType,
// isTargetTypeAnnotation, isTargetType): those of utils/is-array.js, utils/is-number.js,
// utils/is-string.js or utils/is-reg-exp.js, or none for a builtin.
enum UnbFamily {
	array
	indexed_collection
	bigint_typed_array
	builtin
	number_
	string_
	reg_exp
}

const unb_typed_arrays = ['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array',
	'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array', 'Float64Array', 'BigInt64Array',
	'BigUint64Array']

const unb_known_non_indexed_collections = ['Map', 'ReadonlyMap', 'WeakMap', 'Set', 'ReadonlySet',
	'WeakSet', 'URLSearchParams', 'Headers', 'FormData', 'CanvasRenderingContext2D',
	'OffscreenCanvasRenderingContext2D']

struct UnbTypeOptions {
	family                            UnbFamily
	check_class_heritage              bool = true
	check_class_syntax                bool
	prefer_type_reference_definitions bool
	treat_mixed_union_as_target       bool
	treat_mixed_union_as_non_target   bool
	allow_nullish_in_mixed_union      bool
	target_type_names                 []string
	non_target_type_names             []string
	aliases                           map[string]string // typeReferenceAliases
	target_call_names                 []string
	target_constructor_names          []string
}

// unb_array_options are arrayTypeCheckerOptions (isArray, isKnownNonArray).
fn unb_array_options() UnbTypeOptions {
	mut non_targets := unb_typed_arrays.clone()
	non_targets << unb_known_non_indexed_collections
	return UnbTypeOptions{
		family:                            .array
		check_class_heritage:              false
		prefer_type_reference_definitions: true
		target_type_names:                 ['Array', 'ReadonlyArray']
		non_target_type_names:             non_targets
		target_call_names:                 ['Array']
		target_constructor_names:          ['Array']
	}
}

// unb_indexed_collection_options are those of isIndexedCollection and
// isKnownNonIndexedCollection: Array and the typed arrays.
fn unb_indexed_collection_options() UnbTypeOptions {
	mut targets := ['Array', 'ReadonlyArray']
	targets << unb_typed_arrays
	mut constructors := ['Array']
	constructors << unb_typed_arrays
	return UnbTypeOptions{
		...unb_array_options()
		family:                   .indexed_collection
		target_type_names:        targets
		non_target_type_names:    unb_known_non_indexed_collections
		target_constructor_names: constructors
	}
}

// unb_builtin_options ports createBuiltinTypeCheckers: the builtin `name` and its aliases.
fn unb_builtin_options(name string, aliases []string) UnbTypeOptions {
	mut alias_map := map[string]string{}
	for alias in aliases {
		alias_map[alias] = name
	}
	return UnbTypeOptions{
		family:                   .builtin
		target_type_names:        [name]
		aliases:                  alias_map
		target_constructor_names: [name]
	}
}

fn unb_normalize_kind(kind UnbKind) UnbKind {
	return if kind == .nullish { UnbKind.non_target } else { kind }
}

// unb_combine_union ports combineUnionTypes.
fn unb_combine_union(kinds []UnbKind, o UnbTypeOptions) UnbKind {
	types := if o.allow_nullish_in_mixed_union {
		kinds.filter(it != .nullish)
	} else {
		kinds.map(unb_normalize_kind(it))
	}
	if types.len == 0 {
		return .non_target
	}
	all_target := if o.treat_mixed_union_as_target {
		UnbKind.target in types
	} else {
		types.all(it == .target)
	}
	if all_target {
		return .target
	}
	all_non_target := if o.treat_mixed_union_as_non_target {
		UnbKind.non_target in types
	} else {
		types.all(it == .non_target)
	}
	if all_non_target {
		return .non_target
	}
	return .unknown
}

// unb_combine_intersection ports combineIntersectionTypes: an unknown member may be `any`.
fn unb_combine_intersection(kinds []UnbKind) UnbKind {
	types := kinds.map(unb_normalize_kind(it))
	if UnbKind.unknown in types {
		return .unknown
	}
	return if UnbKind.target in types { UnbKind.target } else { UnbKind.non_target }
}

// unb_known_type_reference ports getKnownTypeReferenceType.
fn unb_known_type_reference(name string, o UnbTypeOptions) UnbKind {
	alias := o.aliases[name] or { '' }
	if name in o.target_type_names || (alias != '' && alias in o.target_type_names) {
		return .target
	}
	return if name in o.non_target_type_names { UnbKind.non_target } else { UnbKind.unknown }
}

// unb_type_name ports getTypeName: `Foo` or `Foo.Bar` of a type name.
fn unb_type_name(t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	if t.typ(node) == .identifier {
		return t.string_of(node, .name)
	}
	if t.typ(node) == .ts_qualified_name {
		left := unb_type_name(t, t.node(node, .left)?)?
		return '${left}.${t.string_of(t.node(node, .right)?, .name)?}'
	}
	return none
}

// UnbDefinition is a definition with its ESTree nodes: `node` is def.node and `name` def.name
// (-1 when the tree has none), and `scope` the scope that declares it.
struct UnbDefinition {
	def   ScopeDefinition
	node  int
	name  int
	scope int
}

fn (mut c Checker) unb_definition(t &estree.EsTree, def ScopeDefinition, scope int) UnbDefinition {
	return UnbDefinition{
		def:   def
		node:  c.es_index_of(t, def.node) or { -1 }
		name:  c.es_index_of(t, def.name) or { -1 }
		scope: scope
	}
}

// unb_type_reference_definition ports getTypeReferenceDefinition: the nearest class, import, enum
// or type definition of the name, from the scope upward.
fn (mut c Checker) unb_type_reference_definition(root C.TSNode, t &estree.EsTree, name string, from int) ?UnbDefinition {
	tree := c.scope_tree(root)
	mut scope := from
	for scope >= 0 {
		if v := tree.scopes[scope].set[name] {
			for def in tree.variables[v].defs {
				if def.kind in [.class_name, .import_binding, .ts_enum_name, .type_definition] {
					return c.unb_definition(t, def, scope)
				}
			}
		}
		scope = tree.scopes[scope].upper
	}
	return none
}

// unb_scope_of is sourceCode.getScope(node) of an ESTree node.
fn (mut c Checker) unb_scope_of(root C.TSNode, t &estree.EsTree, node int) int {
	ts := t.ts_node(node) or { return 0 }
	return c.scope_tree(root).get_scope(ts)
}

// unb_import_binding_type ports getImportBindingType (without targetTypeImports, which none of
// the ported checkers has).
fn (mut c Checker) unb_import_binding_type(t &estree.EsTree, d UnbDefinition, o UnbTypeOptions) UnbKind {
	if d.def.kind != .import_binding || d.node < 0 {
		return .unknown
	}
	local := t.string_of(t.node(d.node, .local) or { return .unknown }, .name) or { '' }
	if t.typ(d.node) == .import_default_specifier {
		return if unb_known_type_reference(local, o) == .unknown {
			UnbKind.unknown
		} else {
			UnbKind.non_target
		}
	}
	imported_node := t.node(d.node, .imported) or { return .unknown }
	imported := t.string_of(imported_node, .name) or {
		value := t.get(imported_node, .value)
		if value is string { value } else { '' }
	}
	if imported == '' {
		return .unknown
	}
	// getKnownImportedType without targetTypeImports.
	if unb_known_type_reference(imported, o) != .unknown || unb_known_type_reference(local, o) != .unknown {
		return .non_target
	}
	return .unknown
}

// unb_type_reference_type ports getTypeReferenceType.
fn (mut c Checker) unb_type_reference_type(root C.TSNode, t &estree.EsTree, type_name int, scope int, o UnbTypeOptions, mut visited map[string]bool) UnbKind {
	name := unb_type_name(t, type_name) or { return .unknown }
	// getNamespaceImportBindingType needs targetTypeNamespaceImports, which none of the ported
	// checkers has.
	if !o.prefer_type_reference_definitions {
		known := unb_known_type_reference(name, o)
		if known != .unknown {
			return known
		}
	}
	d := c.unb_type_reference_definition(root, t, name, scope) or {
		return unb_known_type_reference(name, o)
	}
	key := '${node_key(d.def.node)}:${d.def.kind}'
	if visited[key] {
		return .unknown
	}
	visited[key] = true
	mut kind := UnbKind.unknown
	import_kind := c.unb_import_binding_type(t, d, o)
	if import_kind != .unknown {
		kind = import_kind
	} else if d.def.kind == .type_definition && d.node >= 0 {
		match t.typ(d.node) {
			.ts_type_alias_declaration {
				kind = c.unb_annotation_type(root, t, t.node(d.node, .type_annotation) or { -1 },
					d.scope, o, mut visited)
			}
			.ts_type_parameter {
				kind = c.unb_annotation_type(root, t, t.node(d.node, .constraint) or { -1 },
					d.scope, o, mut visited)
			}
			.ts_interface_declaration {
				extends := t.list(d.node, .extends_) or { []int{} }
				kind = if extends.len == 0 {
					UnbKind.non_target
				} else {
					unb_combine_intersection(extends.map(c.unb_type_reference_type(root, t,
						t.node(it, .expression) or { -1 }, d.scope, o, mut visited)))
				}
			}
			else {}
		}
	} else if d.def.kind == .class_name && d.node >= 0 {
		kind = c.unb_class_heritage_type(root, t, d.node, d.scope, o, mut visited)
	}
	visited.delete(key)
	return kind
}

// unb_class_heritage_type ports getClassHeritageType.
fn (mut c Checker) unb_class_heritage_type(root C.TSNode, t &estree.EsTree, node int, scope int, o UnbTypeOptions, mut visited map[string]bool) UnbKind {
	super_class := t.node(node, .super_class) or { return .non_target }
	if !o.check_class_heritage {
		return .non_target
	}
	if t.typ(super_class) != .identifier {
		return .unknown
	}
	return c.unb_class_reference_type(root, t, super_class, scope, o, mut visited)
}

// unb_class_type ports getClassType.
fn (mut c Checker) unb_class_type(root C.TSNode, t &estree.EsTree, node int, scope int, o UnbTypeOptions, mut visited map[string]bool) UnbKind {
	super_class := t.node(node, .super_class) or { return .non_target }
	if !o.check_class_heritage {
		return .non_target
	}
	return c.unb_class_reference_type(root, t, super_class, scope, o, mut visited)
}

// unb_class_reference_type ports getClassReferenceTypeFromScope.
fn (mut c Checker) unb_class_reference_type(root C.TSNode, t &estree.EsTree, node int, scope int, o UnbTypeOptions, mut visited map[string]bool) UnbKind {
	if t.typ(node) == .identifier {
		name := t.string_of(node, .name) or { return .unknown }
		if !o.check_class_heritage {
			return unb_known_type_reference(name, o)
		}
		tree := c.scope_tree(root)
		v := tree.find_variable(scope, name, -1)
		if v < 0 || tree.variables[v].defs.len == 0 {
			return unb_known_type_reference(name, o)
		}
		def := tree.variables[v].defs[0]
		key := '${node_key(def.node)}:${def.kind}'
		if visited[key] {
			return .unknown
		}
		visited[key] = true
		mut kind := UnbKind.unknown
		d := c.unb_definition(t, def, tree.variables[v].scope)
		if def.kind == .variable && def.parent_kind == 'const' && unb_is_simple_declarator(def) {
			if init := def.init {
				if init_node := c.es_index_of(t, init) {
					kind = c.unb_class_reference_type(root, t, init_node, tree.variables[v].scope,
						o, mut visited)
				}
			}
		} else if def.kind == .class_name && d.node >= 0 {
			kind = c.unb_class_type(root, t, d.node, tree.variables[v].scope, o, mut visited)
		}
		visited.delete(key)
		return kind
	}
	if t.typ(node) in [.class_declaration, .class_expression] {
		return c.unb_class_type(root, t, node, scope, o, mut visited)
	}
	return .unknown
}

// unb_annotation_type ports getTypeAnnotationType.
fn (mut c Checker) unb_annotation_type(root C.TSNode, t &estree.EsTree, node int, scope int, o UnbTypeOptions, mut visited map[string]bool) UnbKind {
	if node < 0 {
		return .unknown
	}
	match t.typ(node) {
		.ts_type_annotation {
			return c.unb_annotation_type(root, t, t.node(node, .type_annotation) or { -1 }, scope,
				o, mut visited)
		}
		.ts_type_operator {
			return if (t.string_of(node, .operator) or { '' }) == 'readonly' {
				c.unb_annotation_type(root, t, t.node(node, .type_annotation) or { -1 }, scope, o, mut
					visited)
			} else {
				UnbKind.unknown
			}
		}
		.ts_type_reference {
			return c.unb_type_reference_type(root, t, t.node(node, .type_name) or { -1 }, scope, o, mut
				visited)
		}
		.ts_union_type {
			types := t.list(node, .types) or { []int{} }
			return unb_combine_union(types.map(c.unb_annotation_type(root, t, it, scope, o, mut
				visited)), o)
		}
		.ts_intersection_type {
			types := t.list(node, .types) or { []int{} }
			return unb_combine_intersection(types.map(c.unb_annotation_type(root, t, it, scope, o, mut
				visited)))
		}
		else {
			if o.family in [.array, .indexed_collection] && t.typ(node) in [.ts_array_type, .ts_tuple_type] {
				return .target
			}
			if (o.family == .number_ && unb_is_number_type_annotation(t, node))
				|| (o.family == .string_ && unb_is_string_type_annotation(t, node)) {
				return .target
			}
			if t.typ(node) in [.ts_null_keyword, .ts_undefined_keyword] {
				return .nullish
			}
			return if t.typ(node) in [.ts_big_int_keyword, .ts_boolean_keyword, .ts_never_keyword,
				.ts_number_keyword, .ts_string_keyword, .ts_symbol_keyword, .ts_void_keyword,
				.ts_array_type, .ts_literal_type, .ts_tuple_type, .ts_type_literal, .ts_function_type,
				.ts_constructor_type] {
				UnbKind.non_target
			} else {
				UnbKind.unknown
			}
		}
	}
}

// unb_intrinsic_flags are the flags of the types that have an intrinsicName (any, unknown,
// undefined, null, void, string, number, bigint, true and false, symbol, object, never).
const unb_intrinsic_flags = u32(1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 512 | 8192 | 131072 | 262144)

// unb_ts_type ports getTypeScriptType: what the type of TypeScript is.
fn (mut c Checker) unb_ts_type(t TypeResponse, o UnbTypeOptions, depth int) !UnbKind {
	if depth > 50 {
		return .unknown
	}
	// isUnknownType: any, error and unknown.
	if t.intrinsic_name in ['any', 'error', 'unknown'] {
		return .unknown
	}
	if t.intrinsic_name in ['null', 'undefined'] {
		return .nullish
	}
	if t.flags & type_flag_type_parameter != 0 {
		constraint := c.constraint_of(t)!
		return if constraint.is_null() {
			UnbKind.unknown
		} else {
			c.unb_ts_type(constraint, o, depth + 1)!
		}
	}
	if t.flags & type_flag_union != 0 {
		mut kinds := []UnbKind{}
		for part in c.members_of(t)! {
			kinds << c.unb_ts_type(part, o, depth + 1)!
		}
		return unb_combine_union(kinds, o)
	}
	if t.flags & type_flag_intersection != 0 {
		mut kinds := []UnbKind{}
		for part in c.members_of(t)! {
			kinds << c.unb_ts_type(part, o, depth + 1)!
		}
		return unb_combine_intersection(kinds)
	}
	if o.family in [.array, .indexed_collection] && (c.is_array(t)! || c.is_tuple(t)!) {
		return .target
	}
	// isTargetType of utils/is-number.js and utils/is-string.js.
	if (o.family == .number_ && (t.flags & type_flag_number_literal != 0
		|| t.intrinsic_name == 'number')) || (o.family == .string_
		&& (t.flags & type_flag_string_literal != 0 || t.intrinsic_name == 'string')) {
		return .target
	}
	constraint := c.base_constraint(t)!
	if !constraint.is_null() && constraint.id != t.id {
		return c.unb_ts_type(constraint, o, depth + 1)
	}
	if o.check_class_heritage && t.symbol != 0 {
		symbol := c.symbol_of(t)!
		for base in c.bases_of(symbol.id) or { []TypeResponse{} } {
			if c.unb_ts_type(base, o, depth + 1)! == .target {
				return .target
			}
		}
	}
	if t.intrinsic_name != '' || t.flags & unb_intrinsic_flags != 0 {
		return .non_target
	}
	// getTypeSymbol: the symbol, or the alias symbol.
	name := if t.symbol != 0 {
		c.symbol_of(t)!.name
	} else if t.alias_symbol != 0 {
		c.alias_symbol_of(t)!.name
	} else {
		return .unknown
	}
	alias := o.aliases[name] or { '' }
	return if name in o.target_type_names || (alias != '' && alias in o.target_type_names) {
		UnbKind.target
	} else {
		UnbKind.non_target
	}
}

// unb_type_from_type_information ports getTypeFromTypeInformation.
fn (mut c Checker) unb_type_from_type_information(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) UnbKind {
	type_ := c.unb_type_of(t, node, ctx.abs_path, mut ctx.stats) or { return .unknown }
	return c.unb_ts_type(type_, o, 0) or { UnbKind.unknown }
}

// UnbTypeContext is what a type check needs from the rule: the file and its counters.
@[heap]
struct UnbTypeContext {
	root     C.TSNode
	abs_path string
mut:
	stats &Stats = unsafe { nil }
}

// unb_is_rest_parameter ports isRestParameter: a simple rest parameter never written.
fn (mut c Checker) unb_is_rest_parameter(root C.TSNode, t &estree.EsTree, node int) bool {
	if t.typ(node) != .identifier {
		return false
	}
	v := c.unb_find_variable(root, t, node)
	def := c.unb_single_definition(root, v) or { return false }
	if def.kind != .parameter {
		return false
	}
	name := c.es_index_of(t, def.name) or { return false }
	rest := t.nodes[name].parent
	function := c.es_index_of(t, def.node) or { return false }
	if rest < 0 || t.typ(rest) != .rest_element || t.typ(function) !in [.function_declaration,
		.function_expression, .arrow_function_expression] || rest !in (t.list(function, .params) or {
		[]int{}
	}) {
		return false
	}
	tree := c.scope_tree(root)
	return tree.variables[v].references.all(!tree.references[it].write)
}

fn unb_is_typed_array_factory(t &estree.EsTree, node int) bool {
	return un_is_method_call(t, node,
		objects:         unb_typed_arrays
		methods:         ['from', 'of']
		optional_call:   false
		optional_member: false
	)
}

// unb_is_array_node ports isArrayNode of utils/is-array.js; the receiver of the copying methods
// is an array of the array checker.
fn (mut c Checker) unb_is_array_node(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	if t.typ(node) == .array_expression || c.unb_is_rest_parameter(ctx.root, t, node)
		|| un_is_method_call(t, node,
		objects:         ['Array']
		methods:         ['from', 'of']
		optional_call:   false
		optional_member: false
	) || un_is_method_call(t, node,
		objects:         ['Object']
		methods:         ['keys', 'values', 'entries', 'getOwnPropertyNames', 'getOwnPropertySymbols']
		optional_call:   false
		optional_member: false
	) {
		return true
	}
	if un_is_method_call(t, node,
		methods:         ['copyWithin', 'fill', 'reverse', 'sort', 'toReversed', 'toSorted', 'toSpliced',
			'with']
		optional_call:   false
		optional_member: false
	) {
		object := t.node(t.node(node, .callee) or { return false }, .object) or { return false }
		mut visited := map[int]bool{}
		return c.unb_get_type(t, object, unb_array_options(), mut ctx, mut visited) == .target
	}
	return false
}

// unb_is_target_node is the isTargetNode hook of the family.
// `visited` is that of the getType calling it: isStringNode's `isTarget` shares it.
fn (mut c Checker) unb_is_target_node(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext, mut visited map[int]bool) bool {
	return match o.family {
		.array {
			c.unb_is_array_node(t, node, mut ctx)
		}
		.indexed_collection {
			c.unb_is_array_node(t, node, mut ctx) || unb_is_typed_array_factory(t, node)
		}
		.bigint_typed_array {
			unb_is_typed_array_factory(t, node) && (t.string_of(t.node(t.node(node, .callee) or {
				return false
			}, .object) or { return false }, .name) or { '' }) in ['BigInt64Array', 'BigUint64Array']
		}
		.builtin, .number_ {
			false
		}
		.string_ {
			c.unb_is_string_node(t, node, o, mut ctx, mut visited)
		}
		.reg_exp {
			un_is_regex_literal(t, node)
		}
	}
}

// unb_is_non_target_node is the isNonTargetNode hook of the family.
fn unb_is_non_target_node(t &estree.EsTree, node int, o UnbTypeOptions) bool {
	return match o.family {
		.array, .indexed_collection {
			t.typ(node) in [.new_expression, .object_expression, .function_expression,
				.arrow_function_expression, .class_expression, .template_literal]
				|| unb_is_typed_array_factory(t, node)
		}
		else {
			false
		}
	}
}

// unb_type_from_static_value ports getTypeFromStaticValue.
fn (mut c Checker) unb_type_from_static_value(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) UnbKind {
	if o.family !in [.array, .indexed_collection, .string_, .reg_exp] {
		return .unknown
	}
	value := c.unb_static_value_for_control_flow(ctx.root, t, node) or { return .unknown }
	kind := match o.family {
		// getStaticType of utils/is-string.js and utils/is-reg-exp.js.
		.string_ {
			if value.value.kind == .string_ { UnbKind.target } else { UnbKind.unknown }
		}
		.reg_exp {
			if value.value.kind == .regexp_ { UnbKind.target } else { UnbKind.unknown }
		}
		else {
			if value.value.kind == .array_ {
				UnbKind.target
			} else if t.typ(node) in [.identifier, .member_expression] {
				UnbKind.unknown
			} else {
				UnbKind.non_target
			}
		}
	}
	if kind != .unknown && c.unb_has_jsdoc_type_reference(ctx.root, t, node) {
		return .unknown
	}
	return kind
}

// unb_type_from_variable ports getTypeFromVariable.
fn (mut c Checker) unb_type_from_variable(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext, mut visited map[int]bool) UnbKind {
	v := c.unb_find_variable(ctx.root, t, node)
	if v < 0 || visited[v] {
		return .unknown
	}
	def := c.unb_single_definition(ctx.root, v) or { return .unknown }
	visited[v] = true
	name := c.es_index_of(t, def.name) or { -1 }
	mut annotation_kind := UnbKind.unknown
	if name >= 0 {
		mut type_visited := map[string]bool{}
		annotation_kind = c.unb_annotation_type(ctx.root, t, t.node(name, .type_annotation) or { -1 },
			c.unb_scope_of(ctx.root, t, name), o, mut type_visited)
		if t.flag(name, .optional) or { false } {
			annotation_kind = unb_combine_union([annotation_kind, .nullish], o)
		}
	}
	mut kind := UnbKind.unknown
	if annotation_kind != .unknown {
		kind = annotation_kind
	} else if def.kind == .variable && def.parent_kind == 'const' && unb_is_simple_declarator(def) {
		if init := def.init {
			if init_node := c.es_index_of(t, init) {
				kind = c.unb_get_type(t, init_node, o, mut ctx, mut visited)
			}
		}
	}
	visited.delete(v)
	return kind
}

// unb_definition_initializer ports getDefinitionInitializer: the initializer of a variable or the
// default value of a simple parameter.
fn (mut c Checker) unb_definition_initializer(t &estree.EsTree, def ScopeDefinition) int {
	if def.kind == .variable {
		return c.es_index_of(t, def.init or { return -1 }) or { -1 }
	}
	if def.kind != .parameter {
		return -1
	}
	name := c.es_index_of(t, def.name) or { return -1 }
	parent := t.nodes[name].parent
	if parent >= 0 && t.typ(parent) == .assignment_pattern && t.node(parent, .left) or { -1 } == name {
		return t.node(parent, .right) or { -1 }
	}
	return -1
}

fn unb_is_function(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.function_declaration, .function_expression,
		.arrow_function_expression]
}

// unb_has_native_type_assertion ports hasNativeTypeAssertion: an `as` or `<T>` among the
// TypeScript wrappers of the node.
fn unb_has_native_type_assertion(t &estree.EsTree, n int) bool {
	mut node := n
	for unb_is_ts_wrapper(t, node) {
		if t.typ(node) in [.ts_as_expression, .ts_type_assertion] {
			return true
		}
		node = t.node(node, .expression) or { return false }
	}
	return false
}

// unb_type_from_function_call ports getTypeFromFunctionCall: the return type of a local function.
fn (mut c Checker) unb_type_from_function_call(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) UnbKind {
	callee := t.node(node, .callee) or { return .unknown }
	if t.typ(callee) != .identifier {
		return .unknown
	}
	v := c.unb_find_variable(ctx.root, t, callee)
	def := c.unb_single_definition(ctx.root, v) or { return .unknown }
	tree := c.scope_tree(ctx.root)
	if tree.variables[v].references.any(tree.references[it].write && !tree.references[it].init) {
		return .unknown
	}
	name := c.es_index_of(t, def.name) or { -1 }
	if name >= 0 && t.node(name, .type_annotation) != none {
		return .unknown
	}
	initializer := c.unb_definition_initializer(t, def)
	value := if def.kind == .function_name {
		c.es_index_of(t, def.node) or { -1 }
	} else if initializer >= 0 {
		unb_unwrap_ts(t, initializer)
	} else {
		-1
	}
	if value >= 0 && ((t.flag(value, .async) or { false }) || (t.flag(value, .generator) or { false })
		|| (def.kind == .parameter && (t.node(value, .return_type) != none
		|| unb_has_native_type_assertion(t, initializer)))) {
		return .unknown
	}
	mut function := -1
	if def.kind == .function_name {
		function = c.es_index_of(t, def.node) or { -1 }
	} else if def.kind == .variable && unb_is_simple_declarator(def) {
		mut init := c.es_index_of(t, def.init or { return .unknown }) or { -1 }
		for init >= 0 && t.typ(init) in [.ts_satisfies_expression, .ts_non_null_expression] {
			init = t.node(init, .expression) or { -1 }
		}
		if unb_is_function(t, init) {
			function = init
		}
	}
	if function >= 0 && t.node(function, .type_parameters) != none {
		return .unknown
	}
	if function >= 0 {
		if return_type := t.node(function, .return_type) {
			scope := c.unb_scope_of(ctx.root, t, function)
			mut type_visited := map[string]bool{}
			return c.unb_annotation_type(ctx.root, t, return_type, c.scope_tree(ctx.root).scopes[scope].upper,
				o, mut type_visited)
		}
	}
	if name >= 0 {
		if annotation := c.unb_jsdoc_type_annotation(ctx.root, t, name) {
			if annotation.optional {
				return .unknown
			}
			return c.unb_jsdoc_kind(UnbJsdocAnnotation{
				typ: unb_jsdoc_callable_return_type(annotation.typ)
			}, o)
		}
	}
	if function >= 0 {
		if annotation := c.unb_jsdoc_return_type(ctx.root, t, function) {
			return c.unb_jsdoc_kind(annotation, o)
		}
	}
	return .unknown
}

// unb_this_type ports getThisExpressionType.
fn (mut c Checker) unb_this_type(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) UnbKind {
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		typ := t.typ(parent)
		if typ in [.class_declaration, .class_expression] {
			mut visited := map[string]bool{}
			return c.unb_class_type(ctx.root, t, parent, c.unb_scope_of(ctx.root, t, parent), o, mut
				visited)
		}
		if typ == .static_block || (typ in [.accessor_property, .property_definition]
			&& (t.flag(parent, .static_) or { false })) {
			return .non_target
		}
		if typ in [.function_declaration, .function_expression] {
			params := t.list(parent, .params) or { []int{} }
			mut this_kind := UnbKind.unknown
			for param in params {
				if t.typ(param) == .identifier && (t.string_of(param, .name) or { '' }) == 'this' {
					mut visited := map[string]bool{}
					this_kind = c.unb_annotation_type(ctx.root, t, t.node(param, .type_annotation) or {
						-1
					}, c.unb_scope_of(ctx.root, t, parent), o, mut visited)
					break
				}
			}
			if this_kind != .unknown {
				return this_kind
			}
			grand := t.nodes[parent].parent
			if grand >= 0 && t.typ(grand) == .property && t.nodes[grand].parent >= 0
				&& t.typ(t.nodes[grand].parent) == .object_expression {
				return .non_target
			}
			if grand >= 0 && t.typ(grand) == .method_definition {
				if t.flag(grand, .static_) or { false } {
					return .non_target
				}
				parent = t.nodes[parent].parent
				continue
			}
			return .unknown
		}
		parent = t.nodes[parent].parent
	}
	return .unknown
}

// unb_super_type ports getSuperExpressionType.
fn (mut c Checker) unb_super_type(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) UnbKind {
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		typ := t.typ(parent)
		if typ == .static_block || (typ in [.accessor_property, .property_definition, .method_definition]
			&& (t.flag(parent, .static_) or { false })) {
			return .non_target
		}
		if typ in [.class_declaration, .class_expression] {
			super_class := t.node(parent, .super_class) or { return .non_target }
			mut visited := map[string]bool{}
			return c.unb_class_reference_type(ctx.root, t, super_class, c.unb_scope_of(ctx.root,
				t, parent), o, mut visited)
		}
		parent = t.nodes[parent].parent
	}
	return .unknown
}

// unb_type_from_expression ports getTypeFromExpression.
fn (mut c Checker) unb_type_from_expression(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext, mut visited map[int]bool) UnbKind {
	match t.typ(node) {
		.identifier {
			return c.unb_type_from_variable(t, node, o, mut ctx, mut visited)
		}
		.call_expression {
			return c.unb_type_from_function_call(t, node, o, mut ctx)
		}
		.assignment_expression {
			return if (t.string_of(node, .operator) or { '' }) == '=' {
				c.unb_get_type(t, t.node(node, .right) or { -1 }, o, mut ctx, mut visited)
			} else {
				UnbKind.unknown
			}
		}
		.this_expression {
			return if o.check_class_syntax { c.unb_this_type(t, node, o, mut ctx) } else { UnbKind.unknown }
		}
		.super {
			return if o.check_class_syntax { c.unb_super_type(t, node, o, mut ctx) } else { UnbKind.unknown }
		}
		.new_expression {
			if !o.check_class_syntax {
				return .unknown
			}
			callee := t.node(node, .callee) or { return .unknown }
			mut type_visited := map[string]bool{}
			return c.unb_class_reference_type(ctx.root, t, callee, c.unb_scope_of(ctx.root, t, callee),
				o, mut type_visited)
		}
		.ts_as_expression, .ts_type_assertion {
			annotation := t.node(node, .type_annotation) or { return .unknown }
			mut type_visited := map[string]bool{}
			kind := c.unb_annotation_type(ctx.root, t, annotation, c.unb_scope_of(ctx.root, t, node),
				o, mut type_visited)
			return if kind == .unknown && t.typ(annotation) in [.ts_any_keyword, .ts_unknown_keyword] {
				c.unb_get_type(t, t.node(node, .expression) or { -1 }, o, mut ctx, mut visited)
			} else {
				kind
			}
		}
		.ts_non_null_expression {
			return c.unb_get_type(t, t.node(node, .expression) or { -1 }, o, mut ctx, mut visited)
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { return .unknown }
			return c.unb_get_type(t, if expressions.len > 0 { expressions.last() } else { -1 }, o, mut
				ctx, mut visited)
		}
		.logical_expression {
			left := c.unb_get_type(t, t.node(node, .left) or { -1 }, o, mut ctx, mut visited)
			right := c.unb_get_type(t, t.node(node, .right) or { -1 }, o, mut ctx, mut visited)
			return unb_combine_union([left, right], o)
		}
		.conditional_expression {
			consequent := c.unb_get_type(t, t.node(node, .consequent) or { -1 }, o, mut ctx, mut
				visited)
			alternate := c.unb_get_type(t, t.node(node, .alternate) or { -1 }, o, mut ctx, mut
				visited)
			return unb_combine_union([consequent, alternate], o)
		}
		else {
			return .unknown
		}
	}
}

// unb_get_type ports getType.
fn (mut c Checker) unb_get_type(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext, mut visited map[int]bool) UnbKind {
	if node < 0 {
		return .unknown
	}
	if t.typ(node) == .ts_satisfies_expression {
		return c.unb_get_type(t, t.node(node, .expression) or { -1 }, o, mut ctx, mut visited)
	}
	if annotation := t.node(node, .type_annotation) {
		// TSAsExpression and TSTypeAssertion have a typeAnnotation of their own too.
		mut type_visited := map[string]bool{}
		own := c.unb_annotation_type(ctx.root, t, annotation, c.unb_scope_of(ctx.root, t, node),
			o, mut type_visited)
		if own != .unknown {
			return own
		}
	} else if annotation := c.unb_jsdoc_type_annotation(ctx.root, t, node) {
		kind := c.unb_jsdoc_kind(annotation, o)
		return if kind == .unknown {
			c.unb_type_from_type_information(t, node, o, mut ctx)
		} else {
			kind
		}
	}
	from_expression := c.unb_type_from_expression(t, node, o, mut ctx, mut visited)
	if from_expression != .unknown {
		return from_expression
	}
	if t.typ(node) != .identifier {
		from_static := c.unb_type_from_static_value(t, node, o, mut ctx)
		if from_static != .unknown {
			return from_static
		}
	}
	if c.unb_is_target_node(t, node, o, mut ctx, mut visited) {
		return .target
	}
	if o.target_constructor_names.any(un_is_new(t, node, names: [it]))
		|| o.target_call_names.any(un_is_call(t, node, names: [it])) {
		return .target
	}
	from_types := c.unb_type_from_type_information(t, node, o, mut ctx)
	if from_types != .unknown {
		return from_types
	}
	return if unb_is_non_target_node(t, node, o) { UnbKind.non_target } else { UnbKind.unknown }
}

// unb_kind_of is the normalized kind of the node (getType of createTypeCheckers).
fn (mut c Checker) unb_kind_of(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) UnbKind {
	mut visited := map[int]bool{}
	return unb_normalize_kind(c.unb_get_type(t, node, o, mut ctx, mut visited))
}

// unb_is_target ports isTarget of createTypeCheckers.
fn (mut c Checker) unb_is_target(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) bool {
	mut visited := map[int]bool{}
	return c.unb_get_type(t, node, o, mut ctx, mut visited) == .target
}

// unb_is_known_non_target ports isKnownNonTarget of createTypeCheckers.
fn (mut c Checker) unb_is_known_non_target(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext) bool {
	return c.unb_kind_of(t, node, o, mut ctx) == .non_target
}

// unb_should_skip_known_non_array_receiver ports shouldSkipKnownNonArrayReceiver
// (utils/should-skip-known-non-array-receiver.js): the receiver is known not to be an array or a
// typed array, and is not written as a literal, array, object, function or template.
fn (mut c Checker) unb_should_skip_known_non_array_receiver(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	return t.typ(node) !in [.array_expression, .function_expression, .literal, .object_expression,
		.template_literal] && c.unb_is_known_non_target(t, node, unb_indexed_collection_options(), mut
		ctx)
}

// JSDoc types (utils/parse-jsdoc-type.js, utils/jsdoc.js and utils/jsdoc-type.js): the type facts
// the type checkers read from `@type`, `@param` and `@returns` tags. Texts are taken as code points,
// where JavaScript takes UTF-16 units: only the positions inside the comment differ.

// UnbJsdocType is a parsed JSDoc type: `kind` is unknown, name (`name`), nullish (`name`),
// non-primitive, nullable or optional (`children[0]` the element), union or intersection
// (`children`), or function (`children[0]` the return type).
struct UnbJsdocType {
	kind     string
	name     string
	children []UnbJsdocType
}

const unb_jsdoc_unknown = UnbJsdocType{
	kind: 'unknown'
}
const unb_jsdoc_array = UnbJsdocType{
	kind: 'name'
	name: 'Array'
}
const unb_jsdoc_non_primitive = UnbJsdocType{
	kind: 'non-primitive'
}
const unb_jsdoc_aliases = {
	'Boolean':   'boolean'
	'String':    'string'
	'Number':    'number'
	'Void':      'void'
	'Null':      'null'
	'Undefined': 'undefined'
}
const unb_jsdoc_reserved = ['import', 'typeof', 'extends', 'new']
const unb_jsdoc_unsupported = ['import', 'typeof', 'extends', 'new', 'keyof', 'infer', 'asserts', 'is',
	'readonly']
const unb_jsdoc_primitive_names = ['boolean', 'string', 'number', 'bigint', 'symbol', 'void', 'null',
	'undefined', 'true', 'false', 'Boolean', 'String', 'Number', 'Void', 'Null', 'Undefined', 'any',
	'unknown', 'never']

// unb_jsdoc_primitive is primitiveTypes.get(name).
fn unb_jsdoc_primitive(name string) ?UnbJsdocType {
	if name !in unb_jsdoc_primitive_names {
		return none
	}
	normalized := unb_jsdoc_aliases[name] or { name }
	if normalized in ['any', 'unknown', 'never'] {
		return unb_jsdoc_unknown
	}
	if normalized in ['null', 'undefined'] {
		return UnbJsdocType{
			kind: 'nullish'
			name: normalized
		}
	}
	return UnbJsdocType{
		kind: 'name'
		name: if normalized in ['true', 'false'] { 'boolean' } else { normalized }
	}
}

fn unb_is_id_start(r rune) bool {
	if r < 128 {
		return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || r == `$` || r == `_`
	}
	program := jsregexp.regexp_compile('^\\p{ID_Start}$') or { return false }
	return jsregexp.regexp_test(program, r.str()) or { false }
}

fn unb_is_id_continue(r rune) bool {
	if r < 128 {
		return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`) || r == `$`
			|| r == `_`
	}
	if r in [`‌`, `‍`] {
		return true
	}
	program := jsregexp.regexp_compile('^\\p{ID_Continue}$') or { return false }
	return jsregexp.regexp_test(program, r.str()) or { false }
}

// unb_is_identifier tests identifierPattern.
fn unb_is_identifier(text string) bool {
	runes := text.runes()
	return runes.len > 0 && unb_is_id_start(runes[0]) && runes[1..].all(unb_is_id_continue(it))
}

fn unb_is_digit(r rune) bool {
	return r >= `0` && r <= `9`
}

fn unb_is_hex_digit(r rune) bool {
	return unb_is_digit(r) || (r >= `a` && r <= `f`) || (r >= `A` && r <= `F`)
}

// unb_digits matches `d(?:_?d)*` at `i` for the digits of `is_digit`; the end, or `i` when none.
fn unb_digits(runes []rune, i int, is_digit fn (rune) bool) int {
	if i >= runes.len || !is_digit(runes[i]) {
		return i
	}
	mut j := i + 1
	for j < runes.len {
		if is_digit(runes[j]) {
			j++
		} else if runes[j] == `_` && j + 1 < runes.len && is_digit(runes[j + 1]) {
			j += 2
		} else {
			break
		}
	}
	return j
}

// unb_exponent matches `(?:[Ee][+\-]?\d(?:_?\d)*)?` at `i`.
fn unb_exponent(runes []rune, i int) int {
	if i < runes.len && runes[i] in [`e`, `E`] {
		mut j := i + 1
		if j < runes.len && runes[j] in [`+`, `-`] {
			j++
		}
		k := unb_digits(runes, j, unb_is_digit)
		if k > j {
			return k
		}
	}
	return i
}

// unb_number_token matches the numeric alternative of tokenPattern at `i` (with its `n`); -1 for
// none.
fn unb_number_token(runes []rune, i int) int {
	mut end := -1
	if i + 1 < runes.len && runes[i] == `0` && runes[i + 1] in [`x`, `X`, `b`, `B`, `o`, `O`] {
		digit := match runes[i + 1] {
			`x`, `X` { unb_is_hex_digit }
			`b`, `B` { fn (r rune) bool {
					return r in [`0`, `1`]
				} }
			else { fn (r rune) bool {
					return r >= `0` && r <= `7`
				} }
		}
		k := unb_digits(runes, i + 2, digit)
		if k > i + 2 {
			end = k
		}
	}
	if end < 0 && i < runes.len && unb_is_digit(runes[i]) {
		mut j := if runes[i] == `0` { i + 1 } else { unb_digits(runes, i, unb_is_digit) }
		if j < runes.len && runes[j] == `.` {
			j = unb_digits(runes, j + 1, unb_is_digit)
		}
		end = unb_exponent(runes, j)
	}
	if end < 0 && i + 1 < runes.len && runes[i] == `.` && unb_is_digit(runes[i + 1]) {
		end = unb_exponent(runes, unb_digits(runes, i + 1, unb_is_digit))
	}
	if end < 0 {
		return -1
	}
	if end < runes.len && runes[end] == `n` {
		end++
	}
	return end
}

// unb_jsdoc_tokens splits a JSDoc type like tokenPattern; none for a bad string literal. The
// second result holds the indexes of the tokens that follow a line break.
fn unb_jsdoc_tokens(text string) ?([]string, map[int]bool) {
	runes := text.runes()
	mut tokens := []string{}
	mut line_breaks := map[int]bool{}
	mut i := 0
	for i < runes.len {
		r := runes[i]
		if is_js_space(r) {
			mut j := i
			mut has_break := false
			for j < runes.len && is_js_space(runes[j]) {
				if runes[j] in [`\n`, `\r`, ` `, ` `] {
					has_break = true
				}
				j++
			}
			if has_break {
				line_breaks[tokens.len] = true
			}
			i = j
			continue
		}
		mut end := i + 1
		if r == `=` && i + 1 < runes.len && runes[i + 1] == `>` {
			end = i + 2
		} else if r == `.` && i + 2 < runes.len && runes[i + 1] == `.` && runes[i + 2] == `.` {
			end = i + 3
		} else if unb_is_id_start(r) {
			end = i + 1
			for end < runes.len && unb_is_id_continue(runes[end]) {
				end++
			}
		} else if number := unb_number_token_or_none(runes, i) {
			end = number
		} else if r in [`"`, `'`] {
			mut j := i + 1
			mut closed := false
			for j < runes.len {
				if runes[j] in [`\n`, `\r`] {
					break
				}
				if runes[j] == `\\` {
					if j + 1 < runes.len && runes[j + 1] !in [`\n`, `\r`] {
						j += 2
						continue
					}
					break
				}
				if runes[j] == r {
					closed = true
					break
				}
				j++
			}
			if closed {
				end = j + 1
			}
		}
		token := runes[i..end].string()
		if token[0] in [`"`, `'`] && (token.len == 1 || !unb_jsdoc_valid_string_escapes(token)) {
			return none
		}
		tokens << token
		i = end
	}
	return tokens, line_breaks
}

fn unb_number_token_or_none(runes []rune, i int) ?int {
	end := unb_number_token(runes, i)
	return if end < 0 { none } else { end }
}

// unb_jsdoc_valid_string_escapes ports hasValidStringEscapes.
fn unb_jsdoc_valid_string_escapes(token string) bool {
	runes := token.runes()
	mut i := 0
	for i + 1 < runes.len {
		if runes[i] != `\\` {
			i++
			continue
		}
		escape := runes[i + 1]
		following := if i + 2 <= runes.len - 1 { runes[i + 2..runes.len - 1] } else { []rune{} }
		if escape == `x` && !(following.len >= 2 && following[..2].all(unb_is_hex_digit(it))) {
			return false
		}
		if escape == `u` {
			four := following.len >= 4 && following[..4].all(unb_is_hex_digit(it))
			mut code_point_ok := false
			if following.len > 0 && following[0] == `{` {
				mut j := 1
				for j < following.len && j <= 6 && unb_is_hex_digit(following[j]) {
					j++
				}
				if j > 1 && j < following.len && following[j] == `}` {
					code_point_ok = following[1..j].string().parse_int(16, 64) or { 0x110000 } <= 0x10ffff
				}
			}
			if !four && !code_point_ok {
				return false
			}
		}
		i += 2
	}
	return true
}

// unb_is_numeric_literal_token ports isNumericLiteralToken.
fn unb_is_numeric_literal_token(token string) bool {
	if token == '' || !(unb_is_digit(token[0]) || (token[0] == `.` && token.len > 1
		&& unb_is_digit(token[1]))) {
		return false
	}
	if !token.ends_with('n') {
		return true
	}
	lower := token.to_lower()
	return lower.starts_with('0b') || lower.starts_with('0o') || lower.starts_with('0x')
		|| !lower.contains_any('.e')
}

// UnbJsdocParser is the state of parseJSDocumentType.
struct UnbJsdocParser {
	tokens      []string
	line_breaks map[int]bool
	closes      map[int]int // the closing `)` of each `(`
mut:
	index int
}

fn (p &UnbJsdocParser) at(i int) string {
	return if i >= 0 && i < p.tokens.len { p.tokens[i] } else { '' }
}

fn (mut p UnbJsdocParser) consume(token string) bool {
	if p.at(p.index) == token && p.index < p.tokens.len {
		p.index++
		return true
	}
	return false
}

fn (mut p UnbJsdocParser) expect(token string) ! {
	if !p.consume(token) {
		return error('Unsupported JSDoc type')
	}
}

fn (mut p UnbJsdocParser) parse_optional() !UnbJsdocType {
	typ := p.parse_union()!
	return if p.consume('=') {
		UnbJsdocType{
			kind:     'optional'
			children: [typ]
		}
	} else {
		typ
	}
}

fn (mut p UnbJsdocParser) parse_union() !UnbJsdocType {
	p.consume('|')
	mut elements := [p.parse_intersection()!]
	for p.consume('|') {
		elements << p.parse_intersection()!
	}
	return if elements.len == 1 {
		elements[0]
	} else {
		UnbJsdocType{
			kind:     'union'
			children: elements
		}
	}
}

fn (mut p UnbJsdocParser) parse_intersection() !UnbJsdocType {
	p.consume('&')
	mut elements := [p.parse_postfix()!]
	for p.consume('&') {
		elements << p.parse_postfix()!
	}
	return if elements.len == 1 {
		elements[0]
	} else {
		UnbJsdocType{
			kind:     'intersection'
			children: elements
		}
	}
}

fn (mut p UnbJsdocParser) parse_postfix() !UnbJsdocType {
	mut typ := UnbJsdocType{}
	if p.consume('?') {
		if p.at(p.index) in ['?', '!'] && p.index < p.tokens.len {
			return error('Unsupported JSDoc type')
		}
		typ = if p.index >= p.tokens.len || p.at(p.index) in [')', '>', ']', '}', ',', ';', '|', '&'] {
			unb_jsdoc_unknown
		} else {
			UnbJsdocType{
				kind:     'nullable'
				children: [p.parse_postfix()!]
			}
		}
	} else if p.consume('!') {
		if p.at(p.index) == '!' && p.index < p.tokens.len {
			return error('Unsupported JSDoc type')
		}
		typ = p.parse_postfix()!
	} else if p.consume('...') {
		p.parse_postfix()!
		typ = unb_jsdoc_non_primitive
	} else if p.consume('readonly') {
		typ = p.parse_postfix()!
		if typ.kind != 'name' || typ.name !in ['Array', 'ReadonlyArray'] {
			return error('Unsupported JSDoc type')
		}
	} else {
		typ = p.parse_primary()!
	}
	for p.index + 1 < p.tokens.len && p.tokens[p.index] == '[' && p.tokens[p.index + 1] == ']' {
		p.index += 2
		typ = unb_jsdoc_array
	}
	if p.consume('?') {
		return UnbJsdocType{
			kind:     'nullable'
			children: [typ]
		}
	}
	p.consume('!')
	return typ
}

// parse_list parses `opening member, member… closing` with a member parser chosen by `member`.
fn (mut p UnbJsdocParser) parse_list(opening string, closing string, member string) ! {
	p.expect(opening)!
	if p.consume(closing) {
		return
	}
	for {
		match member {
			'arrow' { p.parse_arrow_parameter()! }
			'function' { p.parse_function_parameter()! }
			'tuple' { p.parse_tuple_member()! }
			else { p.parse_union()! }
		}
		if p.consume(closing) {
			return
		}
		p.expect(',')!
		if p.consume(closing) {
			return
		}
	}
}

fn (mut p UnbJsdocParser) parse_arrow_parameter() ! {
	p.consume('...')
	token := p.at(p.index)
	if p.index >= p.tokens.len || !unb_is_identifier(token) || token in unb_jsdoc_reserved {
		return error('Unsupported JSDoc parameter')
	}
	p.index++
	p.consume('?')
	if p.consume(':') {
		p.parse_union()!
	}
}

fn (mut p UnbJsdocParser) parse_function_parameter() ! {
	if p.consume('this') {
		p.expect(':')!
	}
	p.parse_optional()!
}

fn (mut p UnbJsdocParser) parse_tuple_member() ! {
	name_index := p.index + if p.at(p.index) == '...' { 1 } else { 0 }
	colon_index := name_index + if p.at(name_index + 1) == '?' { 2 } else { 1 }
	if name_index < p.tokens.len && unb_is_identifier(p.at(name_index)) && p.at(colon_index) == ':' {
		p.index = colon_index + 1
	}
	p.parse_optional()!
}

fn (mut p UnbJsdocParser) parse_record() !UnbJsdocType {
	p.expect('{')!
	if p.consume('}') {
		return unb_jsdoc_unknown
	}
	mut signatures := []UnbJsdocType{}
	for !p.consume('}') {
		if p.index >= p.tokens.len {
			return error('Unsupported JSDoc property')
		}
		if p.at(p.index) == 'readonly' && p.at(p.index + 1) !in [':', '?', '(', ',', ';', '}'] {
			p.index++
		}
		if p.at(p.index) == '(' {
			p.parse_list('(', ')', 'arrow')!
			p.expect(':')!
			signatures << UnbJsdocType{
				kind:     'function'
				children: [p.parse_union()!]
			}
		} else if p.consume('[') {
			key := p.at(p.index)
			p.index++
			if !unb_is_identifier(key) {
				return error('Unsupported JSDoc index signature')
			}
			p.expect(':')!
			p.parse_union()!
			p.expect(']')!
			p.expect(':')!
			p.parse_union()!
		} else {
			key := p.at(p.index)
			p.index++
			if !unb_is_identifier(key) && !(key != '' && key[0] in [`"`, `'`])
				&& !unb_is_numeric_literal_token(key) {
				return error('Unsupported JSDoc property')
			}
			p.consume('?')
			if p.at(p.index) == '(' {
				p.parse_list('(', ')', 'arrow')!
			}
			if p.consume(':') {
				p.parse_union()!
			}
		}
		if !p.consume(',') && !p.consume(';') && p.at(p.index) != '}' && !p.line_breaks[p.index] {
			return error('Unsupported JSDoc property')
		}
	}
	if signatures.len == 0 {
		return unb_jsdoc_non_primitive
	}
	return if signatures.len == 1 {
		signatures[0]
	} else {
		UnbJsdocType{
			kind:     'intersection'
			children: signatures
		}
	}
}

fn (mut p UnbJsdocParser) parse_primary() !UnbJsdocType {
	token := p.at(p.index)
	if token == '(' {
		if close := p.closes[p.index] {
			if p.at(close + 1) == '=>' {
				p.parse_list('(', ')', 'arrow')!
				p.expect('=>')!
				return UnbJsdocType{
					kind:     'function'
					children: [p.parse_union()!]
				}
			}
		}
		p.index++
		typ := p.parse_optional()!
		p.expect(')')!
		return typ
	}
	if token == '[' {
		p.parse_list('[', ']', 'tuple')!
		return unb_jsdoc_array
	}
	if token == '{' {
		return p.parse_record()!
	}
	if token == 'function' && p.at(p.index + 1) == '(' {
		p.index++
		p.parse_list('(', ')', 'function')!
		return UnbJsdocType{
			kind:     'function'
			children: [if p.consume(':') { p.parse_union()! } else { unb_jsdoc_unknown }]
		}
	}
	if token == '*' {
		p.index++
		return unb_jsdoc_unknown
	}
	if token != '' && token[0] in [`"`, `'`] {
		p.index++
		return UnbJsdocType{
			kind: 'name'
			name: 'string'
		}
	}
	if token == '-' || (token != '' && (unb_is_digit(token[0]) || (token[0] == `.` && token.len > 1
		&& unb_is_digit(token[1])))) {
		p.consume('-')
		literal := p.at(p.index)
		p.index++
		if !unb_is_numeric_literal_token(literal) {
			return error('Unsupported JSDoc literal')
		}
		return UnbJsdocType{
			kind: 'name'
			name: if literal.ends_with('n') { 'bigint' } else { 'number' }
		}
	}
	return p.parse_named_type()!
}

fn (mut p UnbJsdocParser) parse_named_type() !UnbJsdocType {
	token := p.at(p.index)
	if p.index >= p.tokens.len || !unb_is_identifier(token) || token in unb_jsdoc_unsupported {
		return error('Unsupported JSDoc type')
	}
	mut name := token
	p.index++
	for p.consume('.') {
		if p.at(p.index) == '<' {
			break
		}
		if !unb_is_identifier(p.at(p.index)) {
			return error('Unsupported JSDoc type name')
		}
		name += '.${p.at(p.index)}'
		p.index++
	}
	if p.at(p.index) == '<' {
		if p.at(p.index + 1) == '>' || name in unb_jsdoc_primitive_names {
			return error('Unsupported JSDoc generic')
		}
		p.parse_list('<', '>', 'union')!
		if name == 'Object' {
			return unb_jsdoc_non_primitive
		}
	}
	return unb_jsdoc_primitive(name) or {
		UnbJsdocType{
			kind: 'name'
			name: name
		}
	}
}

// unb_parse_jsdoc_type ports parseJSDocumentType: unsupported or malformed syntax is unknown.
fn unb_parse_jsdoc_type(text string) UnbJsdocType {
	trimmed := js_trim(text)
	if primitive := unb_jsdoc_primitive(trimmed) {
		return primitive
	}
	if unb_is_identifier(trimmed) {
		return if trimmed in unb_jsdoc_unsupported {
			unb_jsdoc_unknown
		} else {
			UnbJsdocType{
				kind: 'name'
				name: trimmed
			}
		}
	}
	tokens, line_breaks := unb_jsdoc_tokens(text) or { return unb_jsdoc_unknown }
	pairs := {
		'(': ')'
		'[': ']'
		'{': '}'
		'<': '>'
	}
	mut closes := map[int]int{}
	mut openings := []int{}
	for index, token in tokens {
		if token in pairs {
			openings << index
		} else if token in [')', ']', '}', '>'] {
			if openings.len == 0 {
				return unb_jsdoc_unknown
			}
			opening := openings.pop()
			if pairs[tokens[opening]] != token {
				return unb_jsdoc_unknown
			}
			if tokens[opening] == '(' {
				closes[opening] = index
			}
		}
	}
	if openings.len > 0 {
		return unb_jsdoc_unknown
	}
	mut p := UnbJsdocParser{
		tokens:      tokens
		line_breaks: line_breaks
		closes:      closes
	}
	typ := p.parse_optional() or { return unb_jsdoc_unknown }
	return if p.index == tokens.len { typ } else { unb_jsdoc_unknown }
}

// unb_horizontal_space is `[^\S\n]`.
fn unb_horizontal_space(r rune) bool {
	return r != `\n` && is_js_space(r)
}

fn unb_skip_horizontal_whitespace(text []rune, from int, end int) int {
	mut start := from
	for start < end && unb_horizontal_space(text[start]) {
		start++
	}
	return start
}

// unb_skip_template_whitespace ports skipJSDocumentTemplateWhitespace: white space, and the `*`
// that starts a line of the comment.
fn unb_skip_template_whitespace(text []rune, from int, end int) int {
	mut start := from
	for start < end {
		start = unb_skip_horizontal_whitespace(text, start, end)
		if start >= text.len || text[start] != `\n` {
			return start
		}
		start++
		start = unb_skip_horizontal_whitespace(text, start, end)
		if start < text.len && text[start] == `*` {
			start++
		}
	}
	return start
}

// unb_delimited_end ports getJSDocumentDelimitedEnd: after the closing bracket that matches the
// one at `start`, skipping quoted text; -1 for none.
fn unb_delimited_end(text []rune, start int, end int, opening rune) int {
	closing := match opening {
		`{` { `}` }
		`[` { `]` }
		else { `)` }
	}
	mut depth := 0
	mut quote := rune(0)
	mut index := start
	for index < end {
		character := text[index]
		if quote != 0 {
			if character == `\\` {
				index += 2
				continue
			}
			if character == quote {
				quote = 0
			}
			index++
			continue
		}
		if character in [`"`, `'`, `\``] {
			quote = character
		} else if character == opening {
			depth++
		} else if character == closing {
			depth--
			if depth == 0 {
				return index + 1
			}
		}
		index++
	}
	return -1
}

// UnbJsdocTagStart is a tag of getJSDocumentTag: its lowercase name and where its content starts.
struct UnbJsdocTagStart {
	name          string
	content_start int
	line_start    int
}

// unb_jsdoc_tag ports getJSDocumentTag on the line [start, end):
// /^\s*(?:\*\s*)?(?<tag>@[\d\p{Letter}][\d\p{Letter}\-]*!?)(?=\s|\{|$)/v.
fn unb_jsdoc_tag(text []rune, start int, end int) ?UnbJsdocTagStart {
	is_letter_or_digit := fn (r rune) bool {
		if r < 128 {
			return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`)
		}
		program := jsregexp.regexp_compile('^[\\d\\p{Letter}]$') or { return false }
		return jsregexp.regexp_test(program, r.str()) or { false }
	}
	mut i := start
	for i < end && is_js_space(text[i]) {
		i++
	}
	if i < end && text[i] == `*` {
		i++
		for i < end && is_js_space(text[i]) {
			i++
		}
	}
	if i >= end || text[i] != `@` || i + 1 >= end || !is_letter_or_digit(text[i + 1]) {
		return none
	}
	tag_start := i
	mut j := i + 2
	for j < end && (is_letter_or_digit(text[j]) || text[j] == `-`) {
		j++
	}
	if j < end && text[j] == `!` {
		j++
	}
	if j < end && !is_js_space(text[j]) && text[j] != `{` {
		// Backtracking cannot help: the name stops before `-` or `!` only to be followed by them.
		return none
	}
	mut name := text[tag_start + 1..j].string().to_lower()
	if name.ends_with('!') {
		name = name[..name.len - 1]
	}
	return UnbJsdocTagStart{
		name:          name
		content_start: j
		line_start:    start
	}
}

// unb_jsdoc_tags ports getJSDocumentTags: the tag that starts each line.
fn unb_jsdoc_tags(text []rune) []UnbJsdocTagStart {
	mut tags := []UnbJsdocTagStart{}
	mut line_start := 0
	for line_start < text.len {
		mut line_end := line_start
		for line_end < text.len && text[line_end] != `\n` {
			line_end++
		}
		if tag := unb_jsdoc_tag(text, line_start, line_end) {
			tags << tag
		}
		line_start = line_end + 1
	}
	return tags
}

// UnbJsdocTag is a parsed `@param`, `@type` or `@returns` tag (parseTag).
struct UnbJsdocTag {
	tag      string
	name     string
	typ      ?UnbJsdocType
	optional bool
}

// unb_parse_tag_type ports parseTagType: the braced type at `start` and where it ends.
fn unb_parse_tag_type(text []rune, start int, end int) ?(UnbJsdocType, int) {
	if start >= text.len || text[start] != `{` {
		return none
	}
	type_end := unb_delimited_end(text, start, end, `{`)
	if type_end < 0 {
		return none
	}
	// `\r?\n[^\S\n]*\*?` becomes a line break.
	inner := text[start + 1..type_end - 1]
	mut cleaned := []rune{cap: inner.len}
	mut i := 0
	for i < inner.len {
		if inner[i] == `\n` || (inner[i] == `\r` && i + 1 < inner.len && inner[i + 1] == `\n`) {
			i += if inner[i] == `\r` { 2 } else { 1 }
			for i < inner.len && unb_horizontal_space(inner[i]) {
				i++
			}
			if i < inner.len && inner[i] == `*` {
				i++
			}
			cleaned << `\n`
			continue
		}
		cleaned << inner[i]
		i++
	}
	return unb_parse_jsdoc_type(cleaned.string()), type_end
}

// unb_parse_tag ports parseTag; none for a tag that is dropped.
fn unb_parse_tag(text []rune, tag UnbJsdocTagStart, end int) ?UnbJsdocTag {
	is_parameter := tag.name in ['param', 'arg', 'argument']
	if !is_parameter && tag.name !in ['type', 'return', 'returns'] {
		return none
	}
	mut start := unb_skip_template_whitespace(text, tag.content_start, end)
	mut typ := ?UnbJsdocType(none)
	if start < text.len && text[start] == `{` {
		parsed, type_end := unb_parse_tag_type(text, start, end) or {
			return UnbJsdocTag{
				tag: tag.name
			}
		}
		typ = parsed
		start = unb_skip_template_whitespace(text, type_end, end)
	} else if !is_parameter {
		return UnbJsdocTag{
			tag: tag.name
		}
	}
	mut optional := false
	mut name := ''
	if is_parameter {
		optional = start < text.len && text[start] == `[`
		name_end := if optional { unb_delimited_end(text, start, end, `[`) } else { end }
		if name_end < 0 || (name_end < end && !is_js_space(text[name_end])) {
			return none
		}
		if optional {
			start++
		}
		// parameterNamePattern
		if start >= name_end || !unb_is_id_start(text[start]) {
			return none
		}
		mut after_name := start + 1
		for after_name < name_end && unb_is_id_continue(text[after_name]) {
			after_name++
		}
		name = text[start..after_name].string()
		next := unb_skip_template_whitespace(text, after_name, name_end)
		if optional {
			if next >= text.len || text[next] !in [`]`, `=`] {
				return none
			}
		} else if after_name < end && !is_js_space(text[after_name]) {
			return none
		}
		if typ == none {
			type_start := unb_skip_template_whitespace(text, if optional {
				name_end
			} else {
				after_name
			}, end)
			if parsed, _ := unb_parse_tag_type(text, type_start, end) {
				typ = parsed
			}
		}
	}
	return UnbJsdocTag{
		tag:      tag.name
		name:     name
		typ:      typ
		optional: optional
	}
}

// unb_comment_tags ports getCommentTags: the parsed tags of a documentation comment (none when it
// has a `@typedef`, `@callback` or `@overload`).
fn (c &Checker) unb_comment_tags(comment SourceToken) []UnbJsdocTag {
	value := c.unb_comment_value(comment).runes()
	tags := unb_jsdoc_tags(value)
	if tags.any(it.name in ['typedef', 'callback', 'overload']) {
		return []
	}
	mut out := []UnbJsdocTag{}
	for i, tag in tags {
		end := if i + 1 < tags.len { tags[i + 1].line_start } else { value.len }
		if parsed := unb_parse_tag(value, tag, end) {
			out << parsed
		}
	}
	return out
}

// unb_has_jsdoc_comments ports hasJSDocumentComments: the file has a block comment that starts
// with `*`.
fn (c &Checker) unb_has_jsdoc_comments(tokens &SourceTokens) bool {
	return tokens.comments.any(it.kind == .block_comment && c.src[it.start..it.end].starts_with('/**'))
}

// unb_documentation_tags ports getDocumentationTags: the tags of the comment right before the
// first of the nodes that has one.
fn (c &Checker) unb_documentation_tags(t &estree.EsTree, tokens &SourceTokens, nodes []int) []UnbJsdocTag {
	for node in nodes {
		if node < 0 {
			continue
		}
		comments := tokens.comments_before(t.nodes[node].start)
		if comments.len > 0 {
			comment := comments.last()
			return if comment.kind == .block_comment && c.src[comment.start..comment.end].starts_with('/**') {
				c.unb_comment_tags(comment)
			} else {
				[]UnbJsdocTag{}
			}
		}
	}
	return []
}

fn unb_with_export(t &estree.EsTree, node int) []int {
	parent := t.nodes[node].parent
	return if parent >= 0 && t.typ(parent) in [.export_named_declaration, .export_default_declaration] {
		[node, parent]
	} else {
		[node]
	}
}

// unb_function_owners ports getFunctionOwners: the nodes whose comment documents the function.
fn unb_function_owners(t &estree.EsTree, function int) []int {
	mut node := function
	mut owners := [node]
	for {
		parent := t.nodes[node].parent
		if !unb_is_ts_wrapper(t, parent) || t.node(parent, .expression) or { -1 } != node {
			break
		}
		node = parent
		owners << node
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return owners
	}
	if t.typ(parent) == .variable_declarator && t.node(parent, .init) or { -1 } == node {
		declaration := t.nodes[parent].parent
		owners << parent
		if (t.list(declaration, .declarations) or { []int{} }).len == 1 {
			owners << unb_with_export(t, declaration)
		}
		return owners
	}
	if t.typ(parent) == .assignment_expression && (t.string_of(parent, .operator) or { '' }) == '='
		&& t.node(parent, .right) or { -1 } == node && t.nodes[parent].parent >= 0
		&& t.typ(t.nodes[parent].parent) == .expression_statement {
		owners << parent
		owners << t.nodes[parent].parent
		return owners
	}
	if t.typ(parent) in [.property, .property_definition, .accessor_property, .method_definition]
		&& t.node(parent, .value) or { -1 } == node {
		owners << parent
		return owners
	}
	if t.typ(parent) in [.export_named_declaration, .export_default_declaration] {
		owners << parent
	}
	return owners
}

// UnbJsdocAnnotation is an annotation of getAnnotation: its type (none when the tag has none) and
// whether it is optional.
struct UnbJsdocAnnotation {
	typ      ?UnbJsdocType
	optional bool
}

// unb_jsdoc_annotation ports getAnnotation: the only tag that matches.
fn unb_jsdoc_annotation(tags []UnbJsdocTag, predicate fn (UnbJsdocTag) bool) ?UnbJsdocAnnotation {
	matches := tags.filter(predicate(it))
	if matches.len != 1 {
		return none
	}
	return UnbJsdocAnnotation{
		typ:      matches[0].typ
		optional: matches[0].optional
	}
}

fn unb_jsdoc_has_type(a ?UnbJsdocAnnotation) bool {
	annotation := a or { return false }
	annotation.typ or { return false }
	return true
}

fn unb_jsdoc_is_optional_type(a ?UnbJsdocAnnotation) bool {
	annotation := a or { return false }
	typ := annotation.typ or { return false }
	return typ.kind == 'optional'
}

// unb_jsdoc_parameter_annotation ports getParameterAnnotation: the inline `@type` or the `@param`
// of a simple parameter.
fn (mut c Checker) unb_jsdoc_parameter_annotation(t &estree.EsTree, tokens &SourceTokens, node int) ?UnbJsdocAnnotation {
	parent := t.nodes[node].parent
	mut parameter := if parent >= 0 && t.typ(parent) == .assignment_pattern
		&& t.node(parent, .left) or { -1 } == node {
		parent
	} else {
		node
	}
	if t.nodes[parameter].parent >= 0 && t.typ(t.nodes[parameter].parent) == .ts_parameter_property {
		parameter = t.nodes[parameter].parent
	}
	function := t.nodes[parameter].parent
	if !unb_is_function(t, function) || parameter !in (t.list(function, .params) or { []int{} }) {
		return none
	}
	name := t.string_of(node, .name) or { '' }
	inline := unb_jsdoc_annotation(c.unb_documentation_tags(t, tokens, [node, parameter]), fn (tag UnbJsdocTag) bool {
		return tag.tag == 'type'
	})
	named := unb_jsdoc_annotation(c.unb_documentation_tags(t, tokens, unb_function_owners(t,
		function)), fn [name] (tag UnbJsdocTag) bool {
		return tag.tag in ['param', 'arg', 'argument'] && tag.name == name
	})
	annotation := if unb_jsdoc_has_type(inline) { inline? } else { named? }
	optional := (t.flag(node, .optional) or { false })
		|| [inline, named].any(fn (a ?UnbJsdocAnnotation) bool {
		x := a or { return false }
		return x.optional || unb_jsdoc_is_optional_type(x)
	}(it))
	mut typ := annotation.typ
	if inner := annotation.typ {
		if inner.kind == 'optional' {
			typ = inner.children[0]
		}
	}
	return UnbJsdocAnnotation{
		typ:      typ
		optional: optional
	}
}

// unb_jsdoc_type_annotation ports getJSDocumentTypeAnnotation: the documented type of a binding or
// property, through the declaration of a simple identifier.
fn (mut c Checker) unb_jsdoc_type_annotation(root C.TSNode, t &estree.EsTree, node int) ?UnbJsdocAnnotation {
	tokens := c.un_tokens(t)
	if node < 0 || !c.unb_has_jsdoc_comments(tokens) || t.node(node, .type_annotation) != none {
		return none
	}
	parent := t.nodes[node].parent
	mut owners := []int{}
	if t.typ(node) in [.property, .property_definition, .accessor_property] {
		if unb_has_native_type_assertion(t, t.node(node, .value) or { -1 }) {
			return none
		}
		owners = [node]
	} else if t.typ(node) == .identifier {
		if parent >= 0 && t.typ(parent) == .variable_declarator && t.node(parent, .id) or { -1 } == node {
			if unb_has_native_type_assertion(t, t.node(parent, .init) or { -1 }) {
				return none
			}
			declaration := t.nodes[parent].parent
			owners = [node, parent]
			if (t.list(declaration, .declarations) or { []int{} }).len == 1 {
				owners << unb_with_export(t, declaration)
			}
		} else {
			if annotation := c.unb_jsdoc_parameter_annotation(t, tokens, node) {
				if unb_jsdoc_has_type(annotation) {
					return annotation
				}
			}
			v := c.unb_find_variable(root, t, node)
			def := c.unb_single_definition(root, v) or { return none }
			name := c.es_index_of(t, def.name) or { return none }
			return if name != node { c.unb_jsdoc_type_annotation(root, t, name) } else { none }
		}
	} else {
		return none
	}
	annotation := unb_jsdoc_annotation(c.unb_documentation_tags(t, tokens, owners), fn (tag UnbJsdocTag) bool {
		return tag.tag == 'type'
	})?
	return if unb_jsdoc_has_type(annotation) { annotation } else { none }
}

// unb_jsdoc_return_type ports getJSDocumentReturnType: the documented return type of a function
// (or the `@type` of a getter).
fn (mut c Checker) unb_jsdoc_return_type(root C.TSNode, t &estree.EsTree, node int) ?UnbJsdocAnnotation {
	tokens := c.un_tokens(t)
	if !c.unb_has_jsdoc_comments(tokens) || t.node(node, .return_type) != none {
		return none
	}
	owners := unb_function_owners(t, node)
	for owner in owners {
		if t.typ(owner) == .variable_declarator {
			id := t.node(owner, .id) or { continue }
			if t.node(id, .type_annotation) != none {
				return none
			}
		} else if t.typ(owner) in [.property, .property_definition, .accessor_property]
			&& t.node(owner, .type_annotation) != none {
			return none
		}
	}
	parent := t.nodes[node].parent
	getter := parent >= 0 && (t.string_of(parent, .kind) or { '' }) == 'get'
		&& t.node(parent, .value) or { -1 } == node
	annotation := unb_jsdoc_annotation(c.unb_documentation_tags(t, tokens, owners), fn [getter] (tag UnbJsdocTag) bool {
		return tag.tag in ['return', 'returns'] || (tag.tag == 'type' && getter)
	})?
	return if unb_jsdoc_has_type(annotation) { annotation } else { none }
}

// unb_has_jsdoc_type_reference ports hasJSDocumentTypeReference: a documented type, through
// aliases or inside the expression, that static inference must not bypass.
fn (mut c Checker) unb_has_jsdoc_type_reference(root C.TSNode, t &estree.EsTree, node int) bool {
	mut visited := map[int]bool{}
	return c.unb_has_jsdoc_type_reference_in(root, t, node, mut visited)
}

fn (mut c Checker) unb_has_jsdoc_type_reference_in(root C.TSNode, t &estree.EsTree, n int, mut visited map[int]bool) bool {
	if !c.unb_has_jsdoc_comments(c.un_tokens(t)) {
		return false
	}
	node := unb_unwrap_ts(t, n)
	if t.typ(node) == .identifier {
		if _ := c.unb_jsdoc_type_annotation(root, t, node) {
			return true
		}
		v := c.unb_find_variable(root, t, node)
		def := c.unb_single_definition(root, v) or { return false }
		if !unb_is_simple_declarator(def) || visited[v] {
			return false
		}
		init := c.es_index_of(t, def.init or { return false }) or { return false }
		visited[v] = true
		return c.unb_has_jsdoc_type_reference_in(root, t, init, mut visited)
	}
	if unb_is_function(t, node) || t.typ(node) in [.class_declaration, .class_expression] {
		return false
	}
	for child in unb_evaluated_children(t, node) {
		if c.unb_has_jsdoc_type_reference_in(root, t, child, mut visited) {
			return true
		}
	}
	return false
}

// unb_jsdoc_members ports getJSDocumentTypeMembers: the members of a union or intersection, with
// the nested ones of the same kind.
fn unb_jsdoc_members(typ UnbJsdocType) []UnbJsdocType {
	mut out := []UnbJsdocType{}
	for element in typ.children {
		if element.kind == typ.kind {
			out << unb_jsdoc_members(element)
		} else {
			out << element
		}
	}
	return out
}

// unb_jsdoc_callable_return_type ports getJSDocumentCallableReturnType.
fn unb_jsdoc_callable_return_type(t ?UnbJsdocType) ?UnbJsdocType {
	typ := t?
	if typ.kind == 'function' {
		return typ.children[0]
	}
	if typ.kind !in ['union', 'intersection'] {
		return none
	}
	members := if typ.kind == 'intersection' {
		unb_jsdoc_members(typ).filter(it.kind != 'non-primitive')
	} else {
		typ.children
	}
	mut return_types := []UnbJsdocType{}
	for member in members {
		return_types << unb_jsdoc_callable_return_type(member)?
	}
	if return_types.len == 0 {
		return none
	}
	return UnbJsdocType{
		kind:     'union'
		children: return_types
	}
}

// unb_jsdoc_node_kind ports getJSDocumentTypeNodeType.
fn unb_jsdoc_node_kind(t ?UnbJsdocType, o UnbTypeOptions) UnbKind {
	typ := t or { return .unknown }
	match typ.kind {
		'nullable', 'optional' {
			return unb_combine_union([unb_jsdoc_node_kind(typ.children[0], o), .nullish], o)
		}
		'union' {
			return unb_combine_union(unb_jsdoc_members(typ).map(unb_jsdoc_node_kind(it, o)), o)
		}
		'intersection' {
			return unb_combine_intersection(typ.children.map(unb_jsdoc_node_kind(it, o)))
		}
		'nullish' {
			return .nullish
		}
		else {
			if typ.kind == 'name' {
				known := unb_known_type_reference(typ.name, o)
				if known != .unknown {
					return known
				}
				if typ.name in ['boolean', 'string', 'number', 'bigint', 'symbol', 'void'] {
					return .non_target
				}
			}
			return if typ.kind in ['non-primitive', 'function'] {
				UnbKind.non_target
			} else {
				UnbKind.unknown
			}
		}
	}
}

// unb_jsdoc_kind ports getJSDocumentType: what an annotation says, nullish too when optional.
fn (c &Checker) unb_jsdoc_kind(annotation UnbJsdocAnnotation, o UnbTypeOptions) UnbKind {
	kind := unb_jsdoc_node_kind(annotation.typ, o)
	return if annotation.optional { unb_combine_union([kind, .nullish], o) } else { kind }
}

// unb_argument_removal_range ports getArgumentRemovalRange (fix/remove-argument.js of 79.0.0):
// the argument with its parentheses, and the comma that goes with it.
fn (c &Checker) unb_argument_removal_range(t &estree.EsTree, tokens &SourceTokens, node int) ?UnbRange {
	call := t.nodes[node].parent
	arguments := t.list(call, .arguments)?
	index := arguments.index(node)
	parentheses := c.un_parentheses(t, tokens, node)
	mut start := if parentheses.len > 0 { parentheses[0].start } else { t.nodes[node].start }
	mut end := if parentheses.len > 0 { parentheses.last().end } else { t.nodes[node].end }
	if arguments.len == 1 {
		// The only argument: a dangling trailing comma goes too (`fn(a,)`).
		if after := tokens.after(end, false) {
			if c.token_is(after, ',') {
				end = after.end
			}
		}
	} else if index == 0 {
		// The first of several: through the comma after it and the gap after the comma.
		comma := tokens.after(end, false)?
		after_comma := tokens.after(comma.end, true)?
		end = after_comma.start
	} else {
		comma := tokens.before(start, false)?
		start = comma.start
	}
	return UnbRange{start, end}
}

// unb_remove_argument ports removeArgument of 79.0.0: the comments of the removed range stay.
fn (c &Checker) unb_remove_argument(t &estree.EsTree, tokens &SourceTokens, node int) ?Fix {
	removal := c.unb_argument_removal_range(t, tokens, node)?
	call := t.nodes[node].parent
	arguments := t.list(call, .arguments)?
	index := arguments.index(node)
	comments := tokens.comments_inside(removal.start, removal.end).filter(it.end <= removal.end)
	if comments.len == 0 {
		return fix_remove_range(removal.start, removal.end)
	}
	// A line comment runs to the end of the line: it needs a line break after it.
	comment_text := fn [c] (comment SourceToken) string {
		text := c.src[comment.start..comment.end]
		return if comment.kind == .line_comment { text + c.unb_linebreak() } else { text }
	}
	if index == 0 && arguments.len > 1 {
		parentheses := c.un_parentheses(t, tokens, node)
		argument_end := if parentheses.len > 0 { parentheses.last().end } else { t.nodes[node].end }
		comma := tokens.after(argument_end, false)?
		range_text := c.src[removal.start..removal.end]
		argument_comments := comments.filter(it.end <= argument_end).map(comment_text(it)).join(' ')
		replacement := argument_comments + range_text[argument_end - removal.start..comma.start - removal.start] +
			range_text[comma.end - removal.start..]
		return fix_replace_range(removal.start, removal.end, replacement)
	}
	return fix_replace_range(removal.start, removal.end, comments.map(' ${comment_text(it)}').join(''))
}

// unb_member_object_needs_parens ports shouldAddParenthesesToMemberExpressionObject of 79.0.0:
// the node as the object of a member expression, where `replacement` is (-1: the node itself).
fn (c &Checker) unb_member_object_needs_parens(t &estree.EsTree, tokens &SourceTokens, node int, replacement int) bool {
	if c.unb_should_add_parens_to_expression_start(t, tokens, node, replacement) {
		return true
	}
	return match t.typ(node) {
		.identifier, .member_expression, .call_expression, .chain_expression, .template_literal,
		.this_expression, .super, .array_expression, .meta_property, .import_expression,
		.tagged_template_expression, .ts_non_null_expression {
			false
		}
		.new_expression {
			!c.un_new_with_parentheses(t, tokens, node)
		}
		.literal {
			t.get(node, .value) is f64 && un_is_decimal_integer(un_raw(t, node))
		}
		else {
			true
		}
	}
}

// unb_member_object_text ports getMemberExpressionObjectText: the text of the node (with its
// parentheses) as the object of a member expression.
fn (c &Checker) unb_member_object_text(t &estree.EsTree, tokens &SourceTokens, node int, replacement int) string {
	text := c.un_parenthesized_text(t, tokens, node)
	if !c.un_is_parenthesized(t, tokens, node)
		&& c.unb_member_object_needs_parens(t, tokens, node, replacement) {
		return '(${text})'
	}
	return text
}

// unb_parent_pattern ports getParentPattern: the destructuring pattern that directly holds the
// node, through defaults, rest elements, object pattern properties and TypeScript wrappers; -1 for
// none.
fn unb_parent_pattern(t &estree.EsTree, node int) int {
	parent := t.nodes[node].parent
	if parent < 0 {
		return -1
	}
	if (unb_is_ts_wrapper(t, parent) && t.node(parent, .expression) or { -1 } == node)
		|| (t.typ(parent) == .assignment_pattern && t.node(parent, .left) or { -1 } == node)
		|| (t.typ(parent) == .rest_element && t.node(parent, .argument) or { -1 } == node) {
		return unb_parent_pattern(t, parent)
	}
	if t.typ(parent) == .property && t.node(parent, .value) or { -1 } == node
		&& t.nodes[parent].parent >= 0 && t.typ(t.nodes[parent].parent) == .object_pattern {
		return t.nodes[parent].parent
	}
	if t.typ(parent) in [.object_pattern, .array_pattern] {
		return parent
	}
	return -1
}

// unb_is_left_hand_side ports isLeftHandSide of 79.0.0: the node (through optional chains and
// TypeScript wrappers) is written: assigned, updated, destructured into, iterated into or deleted.
fn unb_is_left_hand_side(t &estree.EsTree, n int) bool {
	node := unb_outermost_chain_and_ts(t, n)
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.assignment_expression, .assignment_pattern, .for_of_statement, .for_in_statement {
			t.node(parent, .left) or { -1 } == node
		}
		.update_expression, .rest_element {
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

// unb_is_in_unparenthesized_new_callee ports isInUnparenthesizedNewExpressionCallee: a call put
// there would become the argument list of the constructor.
fn (c &Checker) unb_is_in_unparenthesized_new_callee(t &estree.EsTree, tokens &SourceTokens, n int) bool {
	mut node := n
	for !c.un_is_parenthesized(t, tokens, node) {
		parent := t.nodes[node].parent
		if parent < 0 {
			return false
		}
		if t.typ(parent) == .new_expression && t.node(parent, .callee) or { -1 } == node {
			return true
		}
		if (t.typ(parent) == .member_expression && t.node(parent, .object) or { -1 } == node)
			|| (t.typ(parent) == .tagged_template_expression && t.node(parent, .tag) or { -1 } == node)
			|| (unb_is_ts_wrapper(t, parent) && t.node(parent, .expression) or { -1 } == node) {
			node = parent
			continue
		}
		break
	}
	return false
}

// unb_new_callee_member_of_needs_parens is shouldAddParenthesesToNewExpressionCallee of a member
// expression whose object is the node (doesMemberExpressionContainCallExpression from it).
fn (c &Checker) unb_new_callee_member_of_needs_parens(t &estree.EsTree, tokens &SourceTokens, object int) bool {
	mut current := object
	for !c.un_is_parenthesized(t, tokens, current) {
		if unb_is_ts_wrapper(t, current) {
			current = t.node(current, .expression) or { return false }
			continue
		}
		if t.typ(current) !in [.member_expression, .tagged_template_expression] {
			return t.typ(current) == .call_expression
		}
		current = if t.typ(current) == .member_expression {
			t.node(current, .object) or { return false }
		} else {
			t.node(current, .tag) or { return false }
		}
	}
	return false
}

// unb_contains_node ports containsNode without shouldSkip: the node or a node inside it is of
// one of the types.
fn unb_contains_type(t &estree.EsTree, node int, types []estree.NodeType) bool {
	if t.typ(node) in types {
		return true
	}
	return t.children(node).any(unb_contains_type(t, it, types))
}

// unb_has_possible_side_effect ports hasPossibleSideEffect: hasSideEffect, and tagged templates
// and spread elements too.
fn unb_has_possible_side_effect(t &estree.EsTree, node int) bool {
	return unb_has_side_effect(t, node, false)
		|| unb_contains_type(t, node, [.tagged_template_expression, .spread_element])
}

// unb_is_side_effect_free_function ports isSideEffectFreeFunction: an inline function whose
// parameters and body have no side effects.
fn unb_is_side_effect_free_function(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) !in [.arrow_function_expression, .function_expression] {
		return false
	}
	mut parts := t.list(node, .params) or { []int{} }
	parts << t.node(node, .body) or { return false }
	return parts.all(!unb_has_possible_side_effect(t, it))
}

// unb_has_type_arguments ports hasTypeArguments: `foo<string>()`.
fn unb_has_type_arguments(t &estree.EsTree, node int) bool {
	return t.node(node, .type_arguments) != none
}

// The checkers of utils/is-reg-exp.js, utils/is-string.js and utils/is-number.js, and the two
// builtin checkers they use: `Date` and the sized collections.

// unb_reg_exp_options are the options of isRegExp (createBuiltinTypeCheckers of `RegExp`, with
// isRegexLiteral and a RegExp static value as targets).
fn unb_reg_exp_options(check_class_heritage bool) UnbTypeOptions {
	return UnbTypeOptions{
		...unb_builtin_options('RegExp', [])
		family:               .reg_exp
		check_class_heritage: check_class_heritage
		target_call_names:    ['RegExp']
	}
}

// unb_date_options are those of isDate of utils/is-number.js and utils/is-string.js.
fn unb_date_options() UnbTypeOptions {
	return UnbTypeOptions{
		...unb_builtin_options('Date', [])
		check_class_heritage: false
	}
}

// unb_sized_collection_options are those of isSizedCollection of utils/is-number.js.
fn unb_sized_collection_options() UnbTypeOptions {
	return UnbTypeOptions{
		family:                   .builtin
		check_class_heritage:     false
		target_type_names:        ['Map', 'Set', 'ReadonlyMap', 'ReadonlySet']
		target_constructor_names: ['Map', 'Set']
	}
}

// unb_string_options are those of isStringTarget and isKnownNonString of utils/is-string.js.
fn unb_string_options() UnbTypeOptions {
	return UnbTypeOptions{
		family:            .string_
		target_type_names: ['string']
		target_call_names: ['String', 'Date', 'encodeURI', 'encodeURIComponent', 'decodeURI',
			'decodeURIComponent', 'atob', 'btoa']
	}
}

// unb_number_options are those of isNumberTarget and isKnownNonNumber of utils/is-number.js.
fn unb_number_options() UnbTypeOptions {
	return UnbTypeOptions{
		family:            .number_
		target_type_names: ['number']
		target_call_names: ['Number']
	}
}

// unb_is_reg_exp ports isRegExp of utils/is-reg-exp.js (`checkClassHeritage` is an override).
fn (mut c Checker) unb_is_reg_exp(t &estree.EsTree, node int, check_class_heritage bool, mut ctx UnbTypeContext) bool {
	return c.unb_is_target(t, node, unb_reg_exp_options(check_class_heritage), mut ctx)
}

// unb_is_string_type_annotation ports isStringTypeAnnotation of utils/is-string.js: `string` or
// a string literal type.
fn unb_is_string_type_annotation(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	return match t.typ(node) {
		.ts_string_keyword { true }
		.ts_literal_type { unb_static_string_value(t, t.node(node, .literal) or { -1 }) != none }
		else { false }
	}
}

// unb_is_unmodified_mutable_variable ports isUnmodifiedMutableVariable of utils/is-string.js: a
// `let` or `var` declarator of the name, with an initializer and no other write.
fn (mut c Checker) unb_is_unmodified_mutable_variable(root C.TSNode, t &estree.EsTree, node int) bool {
	if t.typ(node) != .identifier {
		return false
	}
	v := c.unb_find_variable(root, t, node)
	def := c.unb_single_definition(root, v) or { return false }
	if def.kind != .variable || def.parent_kind !in ['let', 'var'] || !unb_is_simple_declarator(def)
		|| def.init == none {
		return false
	}
	tree := c.scope_tree(root)
	return tree.variables[v].references.all(!tree.references[it].write || tree.references[it].init)
}

const unb_string_returning_methods = ['charAt', 'concat', 'normalize', 'padEnd', 'padStart', 'repeat',
	'slice', 'substring', 'toLocaleLowerCase', 'toLocaleUpperCase', 'toLowerCase', 'toString',
	'toUpperCase', 'toWellFormed', 'trim', 'trimEnd', 'trimStart', 'valueOf']

const unb_date_string_returning_methods = ['toDateString', 'toISOString', 'toLocaleDateString',
	'toLocaleString', 'toLocaleTimeString', 'toString', 'toTimeString', 'toUTCString']

// unb_is_string_node ports isStringNode of utils/is-string.js, the isTargetNode hook of the string
// checker: its `isTarget` is getType with the same options and `visited`.
fn (mut c Checker) unb_is_string_node(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext, mut visited map[int]bool) bool {
	if un_is_string_literal(t, node) || un_is_function_call(t, node, 'String')
		|| (t.typ(node) == .call_expression && !(t.flag(node, .optional) or { false })
		&& un_is_static_properties(t, t.node(node, .callee) or { -1 }, 'String', ['fromCharCode',
		'fromCodePoint', 'raw'])) {
		return true
	}
	match t.typ(node) {
		.member_expression {
			return un_is_member(t, node, properties: ['source', 'flags'], optional: false)
				&& c.unb_is_reg_exp(t, t.node(node, .object) or { -1 }, false, mut ctx)
		}
		.tagged_template_expression {
			return un_is_member(t, t.node(node, .tag) or { -1 },
				objects:    ['String']
				properties: ['raw']
				optional:   false
			)
		}
		.call_expression {
			object := t.node(t.node(node, .callee) or { -1 }, .object) or { -1 }
			if un_is_method_call(t, node,
				methods:         ['join']
				optional_call:   false
				optional_member: false
			) {
				return c.unb_is_target(t, object, unb_indexed_collection_options(), mut ctx)
			}
			if un_is_method_call(t, node,
				methods:         unb_date_string_returning_methods
				optional_call:   false
				optional_member: false
			) && c.unb_is_target(t, object, unb_date_options(), mut ctx) {
				return true
			}
			return un_is_method_call(t, node,
				methods:         unb_string_returning_methods
				optional_call:   false
				optional_member: false
			) && c.unb_is_string_with(t, object, o, mut ctx, mut visited)
		}
		.template_literal {
			return true
		}
		.unary_expression {
			return (t.string_of(node, .operator) or { '' }) == 'typeof'
		}
		.binary_expression, .assignment_expression {
			operator := t.string_of(node, .operator) or { '' }
			left := t.node(node, .left) or { -1 }
			right := t.node(node, .right) or { -1 }
			if operator == '=' {
				return c.unb_is_string_with(t, right, o, mut ctx, mut visited)
			}
			return operator in ['+', '+='] && (c.unb_is_string_with(t, left, o, mut ctx, mut visited)
				|| c.unb_is_string_with(t, right, o, mut ctx, mut visited))
		}
		else {
			return false
		}
	}
}

// unb_is_string_with ports isString(node, context, isTarget) of utils/is-string.js, `isTarget`
// being getType of `o` with `visited`.
fn (mut c Checker) unb_is_string_with(t &estree.EsTree, node int, o UnbTypeOptions, mut ctx UnbTypeContext, mut visited map[int]bool) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_satisfies_expression
		&& unb_is_string_type_annotation(t, t.node(node, .type_annotation) or { -1 }) {
		return true
	}
	if c.unb_get_type(t, node, o, mut ctx, mut visited) == .target {
		return true
	}
	value := if c.unb_is_unmodified_mutable_variable(ctx.root, t, node) {
		c.unb_static_value_if_no_side_effects(ctx.root, t, node)
	} else {
		c.unb_static_value_for_control_flow(ctx.root, t, node)
	}
	v := value or { return false }
	return v.value.kind == .string_ && !c.unb_has_jsdoc_type_reference(ctx.root, t, node)
}

// unb_is_string ports isString of utils/is-string.js (with its default `isTarget`, isStringTarget).
fn (mut c Checker) unb_is_string(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	mut visited := map[int]bool{}
	return c.unb_is_string_with(t, node, unb_string_options(), mut ctx, mut visited)
}

// unb_is_known_non_string ports isKnownNonString of utils/is-string.js.
fn (mut c Checker) unb_is_known_non_string(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	return c.unb_is_known_non_target(t, node, unb_string_options(), mut ctx)
}

// unb_is_number_type_annotation ports isNumberTypeAnnotation of utils/is-number.js: the bare
// `number` keyword or a numeric literal type.
fn unb_is_number_type_annotation(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_number_keyword {
		return true
	}
	if t.typ(node) != .ts_literal_type {
		return false
	}
	literal := t.node(node, .literal) or { return false }
	return t.typ(literal) == .literal && t.get(literal, .value) is f64
}

// unb_has_number_type_annotation ports hasNumberTypeAnnotation of utils/is-number.js
// (hasTypeAnnotation of utils/type-check.js): a definition of the variable, not optional, is
// annotated `number` or a numeric literal type.
fn (mut c Checker) unb_has_number_type_annotation(root C.TSNode, t &estree.EsTree, node int) bool {
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return false
	}
	tree := c.scope_tree(root)
	for def in tree.variables[v].defs {
		name := c.es_index_of(t, def.name) or { continue }
		if t.flag(name, .optional) or { false } {
			continue
		}
		annotation := t.node(name, .type_annotation) or { continue }
		if unb_is_number_type_annotation(t, t.node(annotation, .type_annotation) or { -1 }) {
			return true
		}
	}
	return false
}

const unb_math_methods = ['abs', 'acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'atan2', 'cbrt',
	'ceil', 'clz32', 'cos', 'cosh', 'exp', 'expm1', 'f16round', 'floor', 'fround', 'hypot', 'imul',
	'log', 'log1p', 'log10', 'log2', 'max', 'min', 'pow', 'random', 'round', 'sign', 'sin', 'sinh',
	'sqrt', 'tan', 'tanh', 'trunc']

const unb_date_number_returning_methods = ['getDate', 'getDay', 'getFullYear', 'getHours',
	'getMilliseconds', 'getMinutes', 'getMonth', 'getSeconds', 'getTime', 'getTimezoneOffset',
	'getUTCDate', 'getUTCDay', 'getUTCFullYear', 'getUTCHours', 'getUTCMilliseconds',
	'getUTCMinutes', 'getUTCMonth', 'getUTCSeconds', 'setDate', 'setFullYear', 'setHours',
	'setMilliseconds', 'setMinutes', 'setMonth', 'setSeconds', 'setTime', 'setUTCDate',
	'setUTCFullYear', 'setUTCHours', 'setUTCMilliseconds', 'setUTCMinutes', 'setUTCMonth',
	'setUTCSeconds', 'valueOf']

// unb_is_number_returning_method_call ports isNumberReturningMethodCall of utils/is-number.js:
// `string.indexOf()`, `array.push()`, `indexed.findIndex()`, `date.getTime()`…
fn (mut c Checker) unb_is_number_returning_method_call(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	if t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false })
		|| (t.flag(callee, .optional) or { false }) {
		return false
	}
	property := t.node(callee, .property) or { return false }
	if t.typ(property) != .identifier {
		return false
	}
	name := t.string_of(property, .name) or { '' }
	object := t.node(callee, .object) or { return false }
	return (name in ['charCodeAt', 'indexOf', 'lastIndexOf', 'localeCompare']
		&& c.unb_is_string(t, object, mut ctx))
		|| (name in ['push', 'unshift'] && c.unb_is_target(t, object, unb_array_options(), mut ctx))
		|| (name in ['indexOf', 'lastIndexOf', 'findIndex', 'findLastIndex']
		&& c.unb_is_target(t, object, unb_indexed_collection_options(), mut ctx))
		|| (name in unb_date_number_returning_methods
		&& c.unb_is_target(t, object, unb_date_options(), mut ctx))
}

// unb_is_numeric_property ports isNumericProperty of utils/is-number.js: the `length` of a
// function, a string or an indexed collection, the `size` of a Map or a Set.
fn (mut c Checker) unb_is_numeric_property(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false })
		|| (t.flag(node, .optional) or { false }) {
		return false
	}
	property := t.node(node, .property) or { return false }
	if t.typ(property) != .identifier {
		return false
	}
	object := t.node(node, .object) or { return false }
	name := t.string_of(property, .name) or { '' }
	return match name {
		'length' {
			unb_is_function(t, object) || c.unb_is_string(t, object, mut ctx)
				|| c.unb_is_target(t, object, unb_indexed_collection_options(), mut ctx)
		}
		'size' {
			c.unb_is_target(t, object, unb_sized_collection_options(), mut ctx)
		}
		else {
			false
		}
	}
}

// unb_is_number ports isNumber of utils/is-number.js (79.0.0): the expression is surely a number
// (not a BigInt), from its syntax, its annotations, its static value or its type.
fn (mut c Checker) unb_is_number(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	if node < 0 {
		return false
	}
	typ := t.typ(node)
	is_call := typ == .call_expression && !(t.flag(node, .optional) or { false })
	callee := if is_call { t.node(node, .callee) or { -1 } } else { -1 }
	if (typ == .literal && t.get(node, .value) is f64)
		|| un_is_static_properties(t, node, 'Math', un_math_properties)
		|| (is_call && un_is_static_properties(t, callee, 'Math', unb_math_methods))
		|| un_is_function_call(t, node, 'Number')
		|| c.unb_is_number_returning_method_call(t, node, mut ctx)
		|| un_is_static_properties(t, node, 'Number', un_number_properties)
		|| (is_call && (un_is_static_properties(t, callee, 'Number', ['parseFloat', 'parseInt'])
		|| un_is_static_properties(t, callee, 'Date', ['now', 'parse', 'UTC'])))
		|| un_is_function_call(t, node, 'parseInt') || un_is_function_call(t, node, 'parseFloat')
		|| c.unb_is_numeric_property(t, node, mut ctx) {
		return true
	}
	mut operator := t.string_of(node, .operator) or { '' }
	match typ {
		.assignment_expression, .binary_expression {
			left := t.node(node, .left) or { -1 }
			right := t.node(node, .right) or { -1 }
			if typ == .assignment_expression {
				if operator == '=' && c.unb_is_number(t, right, mut ctx) {
					return true
				}
				operator = operator[..operator.len - 1]
			}
			if operator == '+' && c.unb_is_number(t, left, mut ctx)
				&& c.unb_is_number(t, right, mut ctx) {
				return true
			}
			// `>>>` cannot be used on a BigInt.
			if operator == '>>>' {
				return true
			}
			// `a * b` may be a BigInt: one side must be a number.
			if operator in ['-', '*', '/', '%', '**', '<<', '>>', '|', '^', '&']
				&& (c.unb_is_number(t, left, mut ctx) || c.unb_is_number(t, right, mut ctx)) {
				return true
			}
		}
		.unary_expression {
			// `+` cannot be used on a BigInt.
			if operator == '+' {
				return true
			}
			if operator in ['-', '~']
				&& c.unb_is_number(t, t.node(node, .argument) or { -1 }, mut ctx) {
				return true
			}
		}
		.update_expression {
			if c.unb_is_number(t, t.node(node, .argument) or { -1 }, mut ctx) {
				return true
			}
		}
		.conditional_expression {
			consequent := c.unb_is_number(t, t.node(node, .consequent) or { -1 }, mut ctx)
			alternate := c.unb_is_number(t, t.node(node, .alternate) or { -1 }, mut ctx)
			if consequent && alternate {
				return true
			}
			test := t.node(node, .test) or { -1 }
			if value := c.unb_static_value_for_control_flow(ctx.root, t, test) {
				if !c.unb_has_jsdoc_type_reference(ctx.root, t, test)
					&& ((consequent && stv_to_boolean(value.value))
					|| (alternate && !stv_to_boolean(value.value))) {
					return true
				}
			}
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { []int{} }
			if expressions.len > 0 && c.unb_is_number(t, expressions.last(), mut ctx) {
				return true
			}
		}
		.identifier {
			if c.unb_has_number_type_annotation(ctx.root, t, node) {
				return true
			}
		}
		// `foo as number`, `foo satisfies number`, `<number>foo`
		.ts_as_expression, .ts_satisfies_expression, .ts_type_assertion {
			if unb_is_number_type_annotation(t, t.node(node, .type_annotation) or { -1 }) {
				return true
			}
		}
		// `foo!`
		.ts_non_null_expression {
			if c.unb_is_number(t, t.node(node, .expression) or { -1 }, mut ctx) {
				return true
			}
		}
		else {}
	}
	if c.unb_is_target(t, node, unb_number_options(), mut ctx) {
		return true
	}
	if c.unb_has_jsdoc_type_reference(ctx.root, t, node) {
		return false
	}
	value := c.unb_static_value_for_control_flow(ctx.root, t, node) or { return false }
	return value.value.kind == .number_
}
