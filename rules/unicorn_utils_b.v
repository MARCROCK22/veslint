module rules

import estree
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
