module rules

import estree
import math
import treesitter { Ident }

// Helpers of eslint-plugin-unicorn 64.0.0 (rules/utils, rules/fix and rules/ast) that its ported
// rules share, on the ESTree of the estree module and the tokens of fix_tokens.v. Offsets are
// bytes of the source.

// un_tokens are the tokens of the file of the tree.
fn (mut c Checker) un_tokens(t &estree.EsTree) &SourceTokens {
	return c.source_tokens(t.nodes[t.root].ts)
}

// un_first_token ports getFirstToken(node, skip): the token `skip` tokens after the first one of
// the node.
fn un_first_token(t &estree.EsTree, tokens &SourceTokens, node int, skip int) ?SourceToken {
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if skip >= inside.len {
		return none
	}
	return inside[skip]
}

// un_last_token ports getLastToken(node).
fn un_last_token(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	return tokens.before(t.nodes[node].end, false)
}

// un_token_after_punctuator ports getTokenAfter(node, isOpeningParenToken) and the like: the first
// token at or after `offset` that is that punctuator.
fn (c &Checker) un_token_after_punctuator(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset); i < tokens.tokens.len; i++ {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

// un_parent_syntax_paren ports getParentSyntaxOpeningParenthesis: the `(` of the syntax of the
// parent that has the node right after it (`if (a)`, the only argument of a call…).
fn (c &Checker) un_parent_syntax_paren(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	parent := t.nodes[node].parent
	if parent < 0 {
		return none
	}
	match t.typ(parent) {
		.call_expression, .new_expression {
			args := t.list(parent, .arguments) or { []int{} }
			if args.len == 1 && args[0] == node {
				before := t.node(parent, .type_arguments) or { t.node(parent, .callee)? }
				return c.un_token_after_punctuator(tokens, t.nodes[before].end, '(')
			}
		}
		.do_while_statement {
			if t.node(parent, .test) or { -1 } == node {
				return c.un_token_after_punctuator(tokens, t.nodes[t.node(parent, .body)?].end,
					'(')
			}
		}
		.if_statement, .while_statement {
			if t.node(parent, .test) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		.import_expression {
			if t.node(parent, .source) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		.switch_statement {
			if t.node(parent, .discriminant) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		.with_statement {
			if t.node(parent, .object) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		else {}
	}
	return none
}

// un_parentheses ports getParentheses (iterateSurroundingParentheses): the `(` and `)` around the
// node that are not part of the syntax of its parent, the outermost first and last.
fn (c &Checker) un_parentheses(t &estree.EsTree, tokens &SourceTokens, node int) []SourceToken {
	parent := t.nodes[node].parent
	if parent < 0 || (t.typ(parent) == .catch_clause && t.node(parent, .param) or { -1 } == node) {
		return []
	}
	mut opening := []SourceToken{}
	mut closing := []SourceToken{}
	mut head := t.nodes[node].start
	mut tail := t.nodes[node].end
	mut syntax_found := false
	mut syntax := ?SourceToken(none)
	for {
		before := tokens.before(head, false) or { break }
		if !c.token_is(before, '(') {
			break
		}
		after := tokens.after(tail, false) or { break }
		if !c.token_is(after, ')') {
			break
		}
		if !syntax_found {
			syntax = c.un_parent_syntax_paren(t, tokens, node)
			syntax_found = true
		}
		if s := syntax {
			if s.start == before.start {
				break
			}
		}
		opening << before
		closing << after
		head = before.start
		tail = after.end
	}
	mut out := opening.reverse()
	out << closing
	return out
}

// un_is_parenthesized ports isParenthesized of unicorn's utils/parentheses.
fn (c &Checker) un_is_parenthesized(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	return c.un_parentheses(t, tokens, node).len > 0
}

// un_parenthesized_range ports getParenthesizedRange.
fn (c &Checker) un_parenthesized_range(t &estree.EsTree, tokens &SourceTokens, node int) (int, int) {
	parens := c.un_parentheses(t, tokens, node)
	if parens.len == 0 {
		return t.nodes[node].start, t.nodes[node].end
	}
	return parens[0].start, parens.last().end
}

// un_parenthesized_text ports getParenthesizedText.
fn (c &Checker) un_parenthesized_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return c.src[start..end]
}

// un_remove_spaces_after ports removeSpacesAfter: removes the white space (`\s`) that follows the
// offset.
fn (c &Checker) un_remove_spaces_after(offset int) Fix {
	mut end := offset
	for r in c.src[offset..].runes() {
		if !is_js_space(r) {
			break
		}
		end += r.length_in_bytes()
	}
	return fix_remove_range(offset, end)
}

// un_node_by_range_index ports SourceCode#getNodeByRangeIndex: the innermost node whose range
// holds the offset (the first child in the order of the visitor keys at each level); none when the
// Program does not.
fn un_node_by_range_index(t &estree.EsTree, offset int) ?int {
	mut current := t.root
	if !(t.nodes[current].start <= offset && offset < t.nodes[current].end) {
		return none
	}
	outer: for {
		for child in t.children(current) {
			if t.nodes[child].start <= offset && offset < t.nodes[child].end {
				current = child
				continue outer
			}
		}
		break
	}
	return current
}

// un_needs_semicolon ports needsSemicolon: whether code that starts with `code` and goes right
// after the token `before` needs a `;` first. An empty `code` never does; none is any code.
fn (c &Checker) un_needs_semicolon(t &estree.EsTree, tokens &SourceTokens, before ?SourceToken, code ?string) bool {
	if text := code {
		if text == '' || text[0] !in [`[`, `(`, `/`, `\``, `+`, `-`, `*`, `,`, `.`] {
			return false
		}
	}
	token := before or { return false }
	value := c.token_text(token)
	last_block := un_node_by_range_index(t, token.start) or { t.root }
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

// un_same_line ports isOnSameLine: both offsets start on the same line.
fn un_same_line(t &estree.EsTree, a int, b int) bool {
	line_a, _ := t.line_column(a)
	line_b, _ := t.line_column(b)
	return line_a == line_b
}

// un_remove_parentheses ports removeParentheses: removes the parentheses around the node.
fn (c &Checker) un_remove_parentheses(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	return c.un_parentheses(t, tokens, node).map(fix_remove_range(it.start, it.end))
}

// un_problematic_token: a keyword in lower case, `of` or `await`, which code right next to it
// would join (isProblematicToken of fix-space-around-keywords.js).
fn (c &Checker) un_problematic_token(token SourceToken) bool {
	text := c.token_text(token)
	if token.kind == .keyword {
		return text.bytes().all(it >= `a` && it <= `z`)
	}
	return token.kind == .identifier && text in ['of', 'await']
}

// un_fix_space_around_keyword ports fixSpaceAroundKeyword: a space between the node (with its
// parentheses) and a keyword right before or after it.
fn (c &Checker) un_fix_space_around_keyword(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	mut fixes := []Fix{}
	if before := tokens.before(start, true) {
		if start == before.end && c.un_problematic_token(before) {
			fixes << fix_insert_at(before.end, ' ')
		}
	}
	if after := tokens.after(end, true) {
		if end == after.start && c.un_problematic_token(after) {
			fixes << fix_insert_at(after.start, ' ')
		}
	}
	return fixes
}

// un_add_parens_to_return_or_throw ports addParenthesizesToReturnOrThrowExpression: `return (…)`.
fn (c &Checker) un_add_parens_to_return_or_throw(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	if t.typ(node) !in [.return_statement, .throw_statement] {
		return []
	}
	first := un_first_token(t, tokens, node, 0) or { return [] }
	last := un_last_token(t, tokens, node) or { return [] }
	if !c.token_is(last, ';') {
		return [fix_insert_at(first.end, ' ('), fix_insert_at(t.nodes[node].end, ')')]
	}
	return [fix_insert_at(first.end, ' ('), fix_insert_at(last.start, ')')]
}

// un_static_property_name ports getStaticPropertyName of is-same-reference.js: the name of the
// property of a member expression, the value of getStaticValue (without a scope) as a string when
// it is computed; none when it is not static.
fn (mut c Checker) un_static_property_name(t &estree.EsTree, node int) ?string {
	property := match t.typ(node) {
		.member_expression { t.node(node, .property)? }
		.chain_expression { return c.un_static_property_name(t, t.node(node, .expression)?) }
		.property, .method_definition { t.node(node, .key)? }
		else { return none }
	}
	if t.typ(property) == .identifier && !(t.flag(node, .computed) or { false }) {
		return t.string_of(property, .name)
	}
	ts := t.ts_node(property)?
	result := c.get_static_value_unscoped(ts)
	if !result.found {
		return none
	}
	return js_any_string_value(result.value)
}

// un_equal_literal_value ports equalLiteralValue: the same regular expression, BigInt or value
// (`===`).
fn un_equal_literal_value(t &estree.EsTree, left int, right int) bool {
	left_regex := t.get(left, .regex)
	right_regex := t.get(right, .regex)
	if left_regex is estree.RegexInfo || right_regex is estree.RegexInfo {
		if left_regex is estree.RegexInfo && right_regex is estree.RegexInfo {
			return left_regex.pattern == right_regex.pattern && left_regex.flags == right_regex.flags
		}
		return false
	}
	left_bigint := t.string_of(left, .bigint) or { '' }
	right_bigint := t.string_of(right, .bigint) or { '' }
	if left_bigint != '' || right_bigint != '' {
		return left_bigint == right_bigint
	}
	a := t.get(left, .value)
	b := t.get(right, .value)
	return match a {
		string { b is string && a == b }
		f64 { b is f64 && a == b }
		bool { b is bool && a == b }
		estree.Null { b is estree.Null }
		else { false }
	}
}

// un_is_same_reference ports isSameReference (eslint-plugin-unicorn 79.0.0): two expressions that
// reference the same value (`a`, `a.b`, `a['b']`, `a[0]`, `this`…), without `?.` chains and
// TypeScript wrappers; static strings are compared by their value.
fn (mut c Checker) un_is_same_reference(t &estree.EsTree, left_node int, right_node int) bool {
	left := un_unwrap_chain_and_ts_expression(t, left_node)
	right := un_unwrap_chain_and_ts_expression(t, right_node)
	if left_string := un_static_string_value(t, left) {
		right_string := un_static_string_value(t, right) or { return false }
		return left_string == right_string
	}
	if t.typ(left) != t.typ(right) {
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
				// `x.y` and `x["y"]`
				return c.un_is_same_reference(t, left_object, right_object)
					&& name == c.un_static_property_name(t, right) or { return false }
			}
			return (t.flag(left, .computed) or { false }) == (t.flag(right, .computed) or { false })
				&& c.un_is_same_reference(t, left_object, right_object)
				&& c.un_is_same_reference(t, t.node(left, .property) or { return false }, t.node(right,
				.property) or { return false })
		}
		else {
			return false
		}
	}
}

// un_text is sourceCode.getText(node).
fn (c &Checker) un_text(t &estree.EsTree, node int) string {
	return c.src[t.nodes[node].start..t.nodes[node].end]
}

// un_logical_child_needs_parens ports shouldAddParenthesesToLogicalExpressionChild.
fn un_logical_child_needs_parens(t &estree.EsTree, node int, operator string) bool {
	typ := t.typ(node)
	if typ == .logical_expression && (t.string_of(node, .operator) or { '' }) == operator {
		return false
	}
	return typ in [.await_expression, .binary_expression, .logical_expression,
		.conditional_expression, .assignment_expression, .arrow_function_expression,
		.yield_expression, .sequence_expression]
}

// un_enter_order are the nodes of the tree in the order ESLint's traversal enters them.
fn un_enter_order(t &estree.EsTree) []int {
	return t.steps().filter(!it.leave).map(it.node)
}

// un_indent_string ports getIndentString: the white space right before the node on its line.
fn (c &Checker) un_indent_string(t &estree.EsTree, node int) string {
	start := t.nodes[node].start
	mut line_start := start
	for line_start > 0 && c.src[line_start - 1] !in [`\n`, `\r`] {
		line_start--
	}
	before := c.src[line_start..start].runes()
	mut i := before.len
	for i > 0 && is_js_space(before[i - 1]) {
		i--
	}
	return before[i..].string()
}

// Words getAvailableVariableName never gives: Babel's keywords, its reserved words in strict code
// and in a module (`await`, `enum`, `eval`, `arguments`), and TypeScript's reserved words.
const un_reserved_names = ['break', 'case', 'catch', 'continue', 'debugger', 'default', 'do', 'else',
	'finally', 'for', 'function', 'if', 'return', 'switch', 'throw', 'try', 'var', 'const', 'while',
	'with', 'new', 'this', 'super', 'class', 'extends', 'export', 'import', 'null', 'true', 'false',
	'in', 'instanceof', 'typeof', 'void', 'delete', 'implements', 'interface', 'let', 'package',
	'private', 'protected', 'public', 'static', 'yield', 'await', 'enum', 'eval', 'arguments', 'as',
	'any', 'boolean', 'constructor', 'declare', 'get', 'module', 'require', 'number', 'set', 'string',
	'symbol', 'type', 'from', 'of']

// un_valid_identifier ports isValidIdentifier of get-available-variable-name.js for an ASCII name
// (the names veslint's rules generate).
fn un_valid_identifier(name string) bool {
	if name == '' || name in un_reserved_names || name[0].is_digit() {
		return false
	}
	return name.bytes().all(it.is_letter() || it.is_digit() || it in [`_`, `$`])
}

// un_scopes ports getScopes: the scope and all the scopes inside it, depth first.
fn un_scopes(tree &ScopeTree, scope int) []int {
	mut out := [scope]
	for child in tree.scopes[scope].children {
		out << un_scopes(tree, child)
	}
	return out
}

// un_resolve_variable_name ports resolveVariableName: a variable of that name in the scope or an
// upper one.
fn un_resolve_variable_name(tree &ScopeTree, name string, scope int) bool {
	mut s := scope
	for s >= 0 {
		if name in tree.scopes[s].set {
			return true
		}
		s = tree.scopes[s].upper
	}
	return false
}

// un_is_unresolved_name ports isUnresolvedName: a reference of the scope or of a scope inside it
// to that name resolves to no variable.
fn un_is_unresolved_name(tree &ScopeTree, name string, scope int) bool {
	for s in un_scopes(tree, scope) {
		for r in tree.scopes[s].references {
			if tree.references[r].name == name && tree.references[r].resolved < 0 {
				return true
			}
		}
	}
	return false
}

// un_available_variable_name ports getAvailableVariableName: `name`, with `_` added until no
// scope of `scopes` sees a variable or an unresolved reference of that name and `is_safe` takes it.
fn un_available_variable_name(tree &ScopeTree, base string, scopes []int, is_safe fn (string) bool) ?string {
	mut name := base
	if !un_valid_identifier(name) {
		name += '_'
		if !un_valid_identifier(name) {
			return none
		}
	}
	for scopes.any(un_resolve_variable_name(tree, name, it) || un_is_unresolved_name(tree, name, it))
		|| !is_safe(name) {
		name += '_'
	}
	return name
}

// un_is_type: the node exists (>= 0) and has the type.
fn un_is_type(t &estree.EsTree, node int, typ estree.NodeType) bool {
	return node >= 0 && t.typ(node) == typ
}

// UnSideEffect are the options of hasSideEffect.
@[params]
struct UnSideEffect {
	consider_getters                  bool
	consider_implicit_type_conversion bool
}

// un_has_side_effect ports hasSideEffect of eslint-utils: the node or a descendant (not inside a
// function) assigns, awaits, calls, imports, constructs, updates, yields or deletes; with
// considerGetters, reads a member; with considerImplicitTypeConversion, converts a value that is
// not a literal.
fn un_has_side_effect(t &estree.EsTree, node int, o UnSideEffect) bool {
	conversion := o.consider_implicit_type_conversion
	match t.typ(node) {
		.arrow_function_expression, .function_expression {
			return false
		}
		.assignment_expression, .await_expression, .call_expression, .import_expression,
		.new_expression, .update_expression, .yield_expression {
			return true
		}
		.binary_expression {
			if conversion && (t.string_of(node, .operator) or { '' }) in ['==', '!=', '<', '<=', '>',
				'>=', '<<', '>>', '>>>', '+', '-', '*', '/', '%', '|', '^', '&', 'in']
				&& (!un_is_type(t, t.node(node, .left) or { -1 }, .literal)
				|| !un_is_type(t, t.node(node, .right) or { -1 }, .literal)) {
				return true
			}
		}
		.member_expression {
			if o.consider_getters {
				return true
			}
			if conversion && (t.flag(node, .computed) or { false })
				&& !un_is_type(t, t.node(node, .property) or { -1 }, .literal) {
				return true
			}
		}
		.method_definition, .property, .property_definition {
			if conversion && (t.flag(node, .computed) or { false })
				&& !un_is_type(t, t.node(node, .key) or { -1 }, .literal) {
				return true
			}
		}
		.unary_expression {
			operator := t.string_of(node, .operator) or { '' }
			if operator == 'delete' {
				return true
			}
			if conversion && operator in ['-', '+', '!', '~']
				&& !un_is_type(t, t.node(node, .argument) or { -1 }, .literal) {
				return true
			}
		}
		else {}
	}
	return t.children(node).any(un_has_side_effect(t, it, o))
}

// un_replace_token_and_spaces_before ports replaceNodeOrTokenAndSpacesBefore for a token (which has
// no parentheses): the token and the white space before it become the replacement, after the
// first line break of that white space when it starts with one.
fn (c &Checker) un_replace_token_and_spaces_before(token SourceToken, replacement string) Fix {
	return c.un_replace_range_and_spaces_before(token.start, token.end, replacement)
}

// un_replace_node_and_spaces_before ports replaceNodeOrTokenAndSpacesBefore for a node: its
// parentheses go too, each with the white space before it.
fn (c &Checker) un_replace_node_and_spaces_before(t &estree.EsTree, tokens &SourceTokens, node int, replacement string) []Fix {
	mut fixes := c.un_parentheses(t, tokens, node).map(c.un_replace_range_and_spaces_before(it.start,
		it.end, ''))
	fixes << c.un_replace_range_and_spaces_before(t.nodes[node].start, t.nodes[node].end,
		replacement)
	return fixes
}

fn (c &Checker) un_replace_range_and_spaces_before(start int, end int, replacement string) Fix {
	token := SourceToken{
		start: start
		end:   end
	}
	before := c.src[..token.start].runes()
	mut i := before.len
	for i > 0 && is_js_space(before[i - 1]) {
		i--
	}
	spaces := before[i..].string()
	line_break := if spaces.starts_with('\r\n') {
		'\r\n'
	} else if spaces.starts_with('\n') || spaces.starts_with('\r') {
		spaces[..1]
	} else {
		''
	}
	return fix_replace_range(token.start - spaces.len, token.end, line_break + replacement)
}

// un_is_empty_node ports isEmptyNode (without `additionalEmpty`): an empty statement, or a block
// of empty nodes.
fn un_is_empty_node(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.block_statement { (t.list(node, .body) or { []int{} }).all(un_is_empty_node(t, it)) }
		.empty_statement { true }
		else { false }
	}
}

// un_switch_case_head ports getSwitchCaseHeadLocation: from the start of the case to its `:`.
fn (c &Checker) un_switch_case_head(t &estree.EsTree, tokens &SourceTokens, node int) ?Ident {
	start := if test := t.node(node, .test) {
		t.nodes[test].end
	} else {
		(un_first_token(t, tokens, node, 0)?).end
	}
	colon := c.un_token_after_punctuator(tokens, start, ':')?
	return c.position_range(t.nodes[node].start, colon.end)
}

// UnCall are the options of isCallExpression, isNewExpression and isCallOrNewExpression
// (ast/call-or-new-expression.js); -1 is no limit.
@[params]
struct UnCall {
	names             []string
	arguments_length  int = -1
	minimum_arguments int
	maximum_arguments int = -1
	allow_spread      bool
	optional          ?bool
}

fn un_is_call_or_new_of(t &estree.EsTree, node int, o UnCall, types []estree.NodeType) bool {
	if node < 0 || t.typ(node) !in types {
		return false
	}
	if want := o.optional {
		if (t.flag(node, .optional) or { false }) != want {
			return false
		}
	}
	args := t.list(node, .arguments) or { []int{} }
	if o.arguments_length >= 0 && args.len != o.arguments_length {
		return false
	}
	if o.minimum_arguments != 0 && args.len < o.minimum_arguments {
		return false
	}
	if o.maximum_arguments >= 0 && args.len > o.maximum_arguments {
		return false
	}
	if !o.allow_spread {
		limit := if o.maximum_arguments >= 0 { o.maximum_arguments } else { o.arguments_length }
		if limit >= 0 {
			for i, arg in args {
				if i < limit && t.typ(arg) == .spread_element {
					return false
				}
			}
		}
	}
	if o.names.len > 0 {
		callee := t.node(node, .callee) or { return false }
		if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) !in o.names {
			return false
		}
	}
	return true
}

// un_is_call ports isCallExpression.
fn un_is_call(t &estree.EsTree, node int, o UnCall) bool {
	return un_is_call_or_new_of(t, node, o, [.call_expression])
}

// un_is_new ports isNewExpression.
fn un_is_new(t &estree.EsTree, node int, o UnCall) bool {
	return un_is_call_or_new_of(t, node, o, [.new_expression])
}

// un_is_call_or_new ports isCallOrNewExpression.
fn un_is_call_or_new(t &estree.EsTree, node int, o UnCall) bool {
	return un_is_call_or_new_of(t, node, o, [.call_expression, .new_expression])
}

// UnMember are the options of isMemberExpression (ast/is-member-expression.js).
@[params]
struct UnMember {
	properties []string
	objects    []string
	optional   ?bool
	computed   ?bool
}

// un_is_member ports isMemberExpression.
fn un_is_member(t &estree.EsTree, node int, o UnMember) bool {
	if node < 0 || t.typ(node) != .member_expression {
		return false
	}
	if want := o.optional {
		if (t.flag(node, .optional) or { false }) != want {
			return false
		}
	}
	mut computed := o.computed
	if o.properties.len > 0 {
		property := t.node(node, .property) or { return false }
		if t.typ(property) != .identifier
			|| (t.string_of(property, .name) or { '' }) !in o.properties {
			return false
		}
		if computed == none {
			computed = false
		}
	}
	if want := computed {
		if (t.flag(node, .computed) or { false }) != want {
			return false
		}
	}
	if o.objects.len > 0 {
		object := t.node(node, .object) or { return false }
		if t.typ(object) != .identifier || (t.string_of(object, .name) or { '' }) !in o.objects {
			return false
		}
	}
	return true
}

// UnMethodCall are the options of isMethodCall (ast/is-method-call.js).
@[params]
struct UnMethodCall {
	methods           []string
	objects           []string
	arguments_length  int = -1
	minimum_arguments int
	maximum_arguments int = -1
	allow_spread      bool
	optional_call     ?bool
	optional_member   ?bool
	computed          ?bool
}

// un_is_method_call ports isMethodCall: a call of a member expression.
fn un_is_method_call(t &estree.EsTree, node int, o UnMethodCall) bool {
	return un_is_call(t, node, UnCall{
		arguments_length:  o.arguments_length
		minimum_arguments: o.minimum_arguments
		maximum_arguments: o.maximum_arguments
		allow_spread:      o.allow_spread
		optional:          o.optional_call
	}) && un_is_member(t, t.node(node, .callee) or { -1 }, UnMember{
		objects:    o.objects
		computed:   o.computed
		properties: o.methods
		optional:   o.optional_member
	})
}

// un_new_callee_needs_parens ports shouldAddParenthesesToNewExpressionCallee (eslint-plugin-unicorn
// 79.0.0): a member expression whose object chain (through template tags and TypeScript
// wrappers, up to a parenthesized one) ends with a call (`new (a().b)()`).
fn (c &Checker) un_new_callee_needs_parens(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if t.typ(node) != .member_expression {
		return false
	}
	mut current := t.node(node, .object) or { return false }
	for !c.un_is_parenthesized(t, tokens, current) {
		if un_is_ts_expression_wrapper(t, current) {
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

// un_is_in_unparenthesized_new_callee ports isInUnparenthesizedNewExpressionCallee: the node is
// part of an unparenthesized constructor callee, where a call would become the arguments of
// the constructor.
fn (c &Checker) un_is_in_unparenthesized_new_callee(t &estree.EsTree, tokens &SourceTokens, from int) bool {
	mut node := from
	for !c.un_is_parenthesized(t, tokens, node) {
		parent := t.nodes[node].parent
		if parent < 0 {
			break
		}
		if t.typ(parent) == .new_expression && (t.node(parent, .callee) or { -1 }) == node {
			return true
		}
		if (t.typ(parent) == .member_expression && (t.node(parent, .object) or { -1 }) == node)
			|| (t.typ(parent) == .tagged_template_expression
			&& (t.node(parent, .tag) or { -1 }) == node)
			|| (un_is_ts_expression_wrapper(t, parent) && (t.node(parent, .expression) or { -1 }) == node) {
			node = parent
			continue
		}
		break
	}
	return false
}

// un_is_chain_element is isChainElement of has-optional-chain-element.js.
fn un_is_chain_element(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.member_expression, .call_expression]
}

// un_has_optional_chain_element ports hasOptionalChainElement: an optional member or call in the
// chain of the node (through TypeScript wrappers and chain expressions).
fn un_has_optional_chain_element(t &estree.EsTree, from int) bool {
	node := un_unwrap_ts_expression(t, from)
	if node >= 0 && t.typ(node) == .chain_expression {
		return un_has_optional_chain_element(t, t.node(node, .expression) or { return false })
	}
	if !un_is_chain_element(t, node) {
		return false
	}
	if t.flag(node, .optional) or { false } {
		return true
	}
	next := t.node(node, if t.typ(node) == .member_expression { estree.Key.object } else { .callee }) or {
		return false
	}
	return un_has_optional_chain_element(t, next)
}

// un_has_unparenthesized_optional_chain_element ports hasUnparenthesizedOptionalChainElement.
fn (c &Checker) un_has_unparenthesized_optional_chain_element(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if node < 0 {
		return false
	}
	if un_is_ts_expression_wrapper(t, node) || t.typ(node) == .chain_expression {
		return c.un_parentheses(t, tokens, node).len == 0
			&& c.un_has_unparenthesized_optional_chain_element(t, tokens, t.node(node, .expression) or {
			return false
		})
	}
	if !un_is_chain_element(t, node) {
		return false
	}
	if t.flag(node, .optional) or { false } {
		return true
	}
	next := t.node(node, if t.typ(node) == .member_expression { estree.Key.object } else { .callee }) or {
		return false
	}
	return c.un_has_unparenthesized_optional_chain_element(t, tokens, next)
}

// un_trace_add adds `path` with the use `kind` ('read', 'call' or 'construct') to a trace map of
// es_global_references, merging it with what is there (createTraceMap and mergeTraceMap of
// global-reference-tracker.js).
fn un_trace_add(mut trace map[string]EsTrace, path []string, kind string) {
	entry := trace[path[0]] or { EsTrace{} }
	if path.len == 1 {
		trace[path[0]] = EsTrace{
			...entry
			read:      entry.read || kind == 'read'
			call:      entry.call || kind == 'call'
			construct: entry.construct || kind == 'construct'
		}
		return
	}
	mut children := entry.children.clone()
	un_trace_add(mut children, path[1..], kind)
	trace[path[0]] = EsTrace{
		...entry
		children: children
	}
}

// un_trace_map is the trace map of GlobalReferenceTracker for the objects (names or paths like
// `Intl.Collator`) and the use `kind`.
fn un_trace_map(objects []string, kind string) map[string]EsTrace {
	mut trace := map[string]EsTrace{}
	for object in objects {
		un_trace_add(mut trace, object.split('.'), kind)
	}
	return trace
}

// un_switch_call_to_new ports switchCallExpressionToNewExpression: `Error()` becomes `new Error()`.
fn (c &Checker) un_switch_call_to_new(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
	fixes << fix_insert_at(t.nodes[node].start, 'new ')
	callee := t.node(node, .callee) or { return fixes }
	if !c.un_is_parenthesized(t, tokens, callee) && c.un_new_callee_needs_parens(t, tokens, callee) {
		fixes << fix_insert_at(t.nodes[callee].start, '(')
		fixes << fix_insert_at(t.nodes[callee].end, ')')
	}
	return fixes
}

// un_remove_method_call ports removeMethodCall: `a.b()` becomes `a`.
fn (c &Checker) un_remove_method_call(t &estree.EsTree, tokens &SourceTokens, call int) []Fix {
	member := t.node(call, .callee) or { return [] }
	object := t.node(member, .object) or { return [] }
	_, object_end := c.un_parenthesized_range(t, tokens, object)
	_, member_end := c.un_parenthesized_range(t, tokens, member)
	return [fix_remove_range(object_end, t.nodes[member].end),
		fix_remove_range(member_end, t.nodes[call].end)]
}

// un_static_value is getStaticValue(node, scope) of the ESTree node; not found when it has no
// tree-sitter node.
fn (mut c Checker) un_static_value(t &estree.EsTree, node int) StaticValue {
	ts := t.ts_node(node) or { return StaticValue{} }
	return c.get_static_value(ts)
}

// un_is_static_properties ports isStaticProperties of utils/is-number.js: `object.property`.
fn un_is_static_properties(t &estree.EsTree, node int, object string, properties []string) bool {
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false })
		|| (t.flag(node, .optional) or { false }) {
		return false
	}
	o := t.node(node, .object) or { return false }
	p := t.node(node, .property) or { return false }
	return t.typ(o) == .identifier && (t.string_of(o, .name) or { '' }) == object
		&& t.typ(p) == .identifier && (t.string_of(p, .name) or { '' }) in properties
}

fn un_is_function_call(t &estree.EsTree, node int, name string) bool {
	if t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == name
}

const un_math_properties = ['E', 'LN2', 'LN10', 'LOG2E', 'LOG10E', 'PI', 'SQRT1_2', 'SQRT2']
const un_math_methods = ['abs', 'acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'atan2', 'cbrt',
	'ceil', 'clz32', 'cos', 'cosh', 'exp', 'expm1', 'f16round', 'floor', 'fround', 'hypot', 'imul', 'log', 'log1p',
	'log10', 'log2', 'max', 'min', 'pow', 'random', 'round', 'sign', 'sin', 'sinh', 'sqrt', 'tan',
	'tanh', 'trunc']
const un_number_properties = ['EPSILON', 'MAX_SAFE_INTEGER', 'MAX_VALUE', 'MIN_SAFE_INTEGER',
	'MIN_VALUE', 'NaN', 'NEGATIVE_INFINITY', 'POSITIVE_INFINITY']

// un_new_with_parentheses ports isNewExpressionWithParentheses: `new Foo()` rather than `new Foo`.
fn (c &Checker) un_new_with_parentheses(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if (t.list(node, .arguments) or { []int{} }).len > 0 {
		return true
	}
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return c.token_is(inside[inside.len - 2], '(') && c.token_is(inside.last(), ')')
		&& t.nodes[callee].end < t.nodes[node].end
}

// un_switch_new_to_call ports switchNewExpressionToCallExpression (eslint-plugin-unicorn 79.0.0):
// `new Foo()` becomes `Foo()`, in parentheses when the call would become the arguments of an
// outer `new`, or when the callee on another line would leave a `return`, `throw` or `yield`
// alone.
fn (c &Checker) un_switch_new_to_call(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	new_token := un_first_token(t, tokens, node, 0) or { return [] }
	callee := t.node(node, .callee) or { return [] }
	should_parenthesize := c.un_is_in_unparenthesized_new_callee(t, tokens, node)
		|| (!un_same_line(t, new_token.start, t.nodes[callee].start)
		&& c.un_unparenthesized_keyword_argument_parent(t, tokens, node) != none)
	mut fixes := [
		fix_replace_range(new_token.start, new_token.end, if should_parenthesize { '(' } else { '' }),
		c.un_remove_spaces_after(new_token.end),
	]
	if !c.un_new_with_parentheses(t, tokens, node) {
		fixes << fix_insert_at(t.nodes[node].end, '()')
	}
	if should_parenthesize {
		fixes << fix_insert_at(t.nodes[node].end, ')')
	}
	next := tokens.after(new_token.end, false) or { return fixes }
	if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), c.token_text(next)) {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	return fixes
}

// UnCallTokens are the tokens of getCallExpressionTokens: the `(` and `)` of the arguments, and a
// trailing comma before the `)`.
struct UnCallTokens {
	opening  SourceToken
	closing  SourceToken
	trailing ?SourceToken
}

// un_call_tokens ports getCallOrNewExpressionTokens.
fn (c &Checker) un_call_tokens(t &estree.EsTree, tokens &SourceTokens, node int) ?UnCallTokens {
	start := t.node(node, .type_arguments) or { t.node(node, .callee)? }
	opening := c.un_token_after_punctuator(tokens, t.nodes[start].end, '(')?
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return none
	}
	penultimate := inside[inside.len - 2]
	return UnCallTokens{
		opening:  opening
		closing:  inside.last()
		trailing: if c.token_is(penultimate, ',') { penultimate } else { none }
	}
}

// un_node_matches_name_or_path ports isNodeMatchesNameOrPath: `a.b.c` matches that member chain
// (and `this`, `super` and `new.target` as its first name).
fn un_node_matches_name_or_path(t &estree.EsTree, from int, name_or_path string) bool {
	parts := name_or_path.trim_space().split('.')
	mut node := from
	for index := parts.len - 1; index >= 0; index-- {
		name := parts[index]
		if name == '' {
			return false
		}
		if index == 0 {
			return (t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == name)
				|| (name == 'this' && t.typ(node) == .this_expression)
				|| (name == 'super' && t.typ(node) == .super)
		}
		if index == 1 && t.typ(node) == .meta_property {
			property := t.node(node, .property) or { return false }
			if t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == name {
				node = t.node(node, .meta) or { return false }
				continue
			}
		}
		if t.typ(node) == .member_expression && !(t.flag(node, .optional) or { false })
			&& !(t.flag(node, .computed) or { false }) {
			property := t.node(node, .property) or { return false }
			if t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == name {
				node = t.node(node, .object) or { return false }
				continue
			}
		}
		return false
	}
	return false
}

// un_is_string_literal ports isStringLiteral.
fn un_is_string_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && t.get(node, .value) is string
}

// un_static_string_value ports getStaticStringValue of ast/literal.js (eslint-plugin-unicorn
// 79.0.0): the value of a string literal, or the cooked text of a template literal without
// expressions (none when its cooked value is undefined).
fn un_static_string_value(t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	if un_is_string_literal(t, node) {
		return t.get(node, .value) as string
	}
	if t.typ(node) == .template_literal && (t.list(node, .expressions) or { []int{} }).len == 0 {
		quasis := t.list(node, .quasis) or { return none }
		if quasis.len == 0 {
			return none
		}
		value := t.get(quasis[0], .value)
		if value is estree.TemplateValue && value.has_cooked {
			return value.cooked
		}
	}
	return none
}

// un_is_regex_literal ports isRegexLiteral.
fn un_is_regex_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && t.get(node, .regex) is estree.RegexInfo
}

// un_raw is the `raw` of a Literal.
fn un_raw(t &estree.EsTree, node int) string {
	return t.string_of(node, .raw) or { '' }
}

// un_template_raw is `value.raw` of a TemplateElement.
fn un_template_raw(t &estree.EsTree, node int) string {
	value := t.get(node, .value)
	return if value is estree.TemplateValue { value.raw } else { '' }
}

// un_is_tagged_template ports isTaggedTemplateLiteral(node, tags): the quasi of a tagged template
// whose tag matches one of `tags` (any tag when there are none).
fn un_is_tagged_template(t &estree.EsTree, node int, tags []string) bool {
	if node < 0 || t.typ(node) != .template_literal {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .tagged_template_expression
		|| t.node(parent, .quasi) or { -1 } != node {
		return false
	}
	if tags.len == 0 {
		return true
	}
	tag := t.node(parent, .tag) or { return false }
	return tags.any(un_node_matches_name_or_path(t, tag, it))
}

// un_replace_template_element ports replaceTemplateElement: the text of the element between its
// delimiters (`` ` `` or `}` and `` ` `` or `${`) becomes `replacement`.
fn un_replace_template_element(t &estree.EsTree, node int, replacement string) Fix {
	tail := t.flag(node, .tail) or { false }
	return fix_replace_range(t.nodes[node].start + 1, t.nodes[node].end - (if tail { 1 } else { 2 }),
		replacement)
}

// un_is_escaped_at: the character at `i` follows an odd number of backslashes, the lookbehind
// `(?<=(?:^|[^\\])(?:\\\\)*\\)` of unicorn's escape rules.
fn un_is_escaped_at(text string, i int) bool {
	mut count := 0
	for j := i - 1; j >= 0 && text[j] == `\\`; j-- {
		count++
	}
	return count % 2 == 1
}

// un_reference_node is the ESTree Identifier of a reference the scope tree or the ReferenceTracker
// gives: in a shorthand property the value, not the key, which has the same range.
fn (mut c Checker) un_reference_node(t &estree.EsTree, ts C.TSNode) ?int {
	node := c.es_index_of(t, ts)?
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) == .property && (t.flag(parent, .shorthand) or { false })
		&& t.node(parent, .key) or { -1 } == node {
		return t.node(parent, .value) or { node }
	}
	// `export { a }`: `local` and `exported` have the same range; the reference is `local`.
	if parent >= 0 && t.typ(parent) == .export_specifier
		&& t.node(parent, .exported) or { -1 } == node {
		return t.node(parent, .local) or { node }
	}
	return node
}

// un_is_left_hand_side ports isLeftHandSide: the node is written (assigned, updated, destructured
// into or deleted).
fn un_is_left_hand_side(t &estree.EsTree, from int) bool {
	// eslint-plugin-unicorn 79.0.0: through optional chains and TypeScript wrappers.
	node := un_outermost_chain_and_ts_expression(t, from)
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.assignment_expression, .assignment_pattern { t.node(parent, .left) or { -1 } == node }
		.update_expression, .rest_element { t.node(parent, .argument) or { -1 } == node }
		.array_pattern { node in (t.list(parent, .elements) or { []int{} }) }
		.for_of_statement, .for_in_statement { t.node(parent, .left) or { -1 } == node }
		.property {
			t.node(parent, .value) or { -1 } == node && t.nodes[parent].parent >= 0
				&& t.typ(t.nodes[parent].parent) == .object_pattern
				&& parent in (t.list(t.nodes[parent].parent, .properties) or { []int{} })
		}
		.unary_expression {
			(t.string_of(parent, .operator) or { '' }) == 'delete'
				&& t.node(parent, .argument) or { -1 } == node
		}
		else { false }
	}
}

fn un_is_shorthand_property_value(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) == .property && (t.flag(parent, .shorthand) or { false })
		&& t.node(parent, .value) or { -1 } == node
}

fn un_same_range(t &estree.EsTree, a int, b int) bool {
	return a >= 0 && b >= 0 && t.nodes[a].start == t.nodes[b].start
		&& t.nodes[a].end == t.nodes[b].end
}

// un_replace_reference_identifier ports replaceReferenceIdentifier: the identifier becomes
// `replacement`, keeping a shorthand property, import or export working.
fn (c &Checker) un_replace_reference_identifier(t &estree.EsTree, node int, replacement string) Fix {
	name := t.string_of(node, .name) or { '' }
	parent := t.nodes[node].parent
	start := t.nodes[node].start
	end := t.nodes[node].end
	if un_is_shorthand_property_value(t, node) || (parent >= 0
		&& t.typ(parent) == .assignment_pattern && t.node(parent, .left) or { -1 } == node
		&& un_is_shorthand_property_value(t, parent)) {
		return fix_replace_range(start, end, '${name}: ${replacement}')
	}
	if parent >= 0 && t.typ(parent) == .import_specifier && t.node(parent, .local) or { -1 } == node
		&& un_same_range(t, node, t.node(parent, .imported) or { -1 }) {
		return fix_replace_range(start, end, '${name} as ${replacement}')
	}
	if parent >= 0 && t.typ(parent) == .export_specifier && t.node(parent, .local) or { -1 } == node
		&& un_same_range(t, node, t.node(parent, .exported) or { -1 }) {
		return fix_replace_range(start, end, '${replacement} as ${name}')
	}
	if annotation := t.node(node, .type_annotation) {
		optional := t.flag(node, .optional) or { false }
		return fix_replace_range(start, t.nodes[annotation].start, replacement +
			if optional { '?' } else { '' })
	}
	return fix_replace_range(start, end, replacement)
}

// un_string_if_constant ports getStringIfConstant(node) of eslint-utils without a scope: the
// string of a regular expression or BigInt literal, else String() of getStaticValue.
fn (mut c Checker) un_string_if_constant(t &estree.EsTree, node int) ?string {
	if t.typ(node) == .literal {
		regex := t.get(node, .regex)
		if regex is estree.RegexInfo {
			return '/${regex.pattern}/${regex.flags}'
		}
		if bigint := t.string_of(node, .bigint) {
			return bigint
		}
	}
	result := c.get_static_value_unscoped(t.ts_node(node)?)
	if !result.found {
		return none
	}
	return js_any_string_value(result.value)
}

// un_property_name ports getPropertyName of eslint-utils for a Property, MethodDefinition or
// PropertyDefinition.
fn (mut c Checker) un_property_name(t &estree.EsTree, node int) ?string {
	key := t.node(node, .key)?
	if t.flag(node, .computed) or { false } {
		return c.un_string_if_constant(t, key)
	}
	if t.typ(key) == .literal {
		value := t.get(key, .value)
		return match value {
			string { value }
			f64 { js_number_to_string(value) }
			else { c.un_string_if_constant(t, key) }
		}
	}
	if t.typ(key) == .private_identifier {
		return none
	}
	return t.string_of(key, .name)
}

// un_function_name_with_kind ports getFunctionNameWithKind of eslint-utils (which, unlike
// ESLint's, also names a function after the variable, assignment or default export it is).
fn (mut c Checker) un_function_name_with_kind(t &estree.EsTree, node int) string {
	parent := t.nodes[node].parent
	if parent < 0 {
		return ''
	}
	mut tokens := []string{}
	ptyp := t.typ(parent)
	is_value := t.node(parent, .value) or { -1 } == node
	object_method := ptyp == .property && is_value
	class_method := ptyp == .method_definition && is_value
	field_method := ptyp == .property_definition && is_value
	key := t.node(parent, .key) or { -1 }
	if class_method || field_method {
		if t.flag(parent, .static_) or { false } {
			tokens << 'static'
		}
		if key >= 0 && t.typ(key) == .private_identifier {
			tokens << 'private'
		}
	}
	if t.flag(node, .async) or { false } {
		tokens << 'async'
	}
	if t.flag(node, .generator) or { false } {
		tokens << 'generator'
	}
	if object_method || class_method {
		kind := t.string_of(parent, .kind) or { '' }
		if kind == 'constructor' {
			return 'constructor'
		}
		tokens << match kind {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if field_method {
		tokens << 'method'
	} else {
		if t.typ(node) == .arrow_function_expression {
			tokens << 'arrow'
		}
		tokens << 'function'
	}
	if object_method || class_method || field_method {
		if key >= 0 && t.typ(key) == .private_identifier {
			tokens << '#${t.string_of(key, .name) or { '' }}'
		} else if name := c.un_property_name(t, parent) {
			if name != '' {
				tokens << "'${name}'"
			}
		} else if key >= 0 {
			text := c.un_text(t, key)
			if !text.contains('\n') {
				tokens << '[${text}]'
			}
		}
	} else if id := t.node(node, .id) {
		tokens << "'${t.string_of(id, .name) or { '' }}'"
	} else if ptyp == .variable_declarator {
		id := t.node(parent, .id) or { -1 }
		if id >= 0 && t.typ(id) == .identifier {
			tokens << "'${t.string_of(id, .name) or { '' }}'"
		}
	} else if ptyp in [.assignment_expression, .assignment_pattern] {
		left := t.node(parent, .left) or { -1 }
		if left >= 0 && t.typ(left) == .identifier {
			tokens << "'${t.string_of(left, .name) or { '' }}'"
		}
	} else if ptyp == .export_default_declaration && t.node(parent, .declaration) or { -1 } == node {
		tokens << "'default'"
	}
	return tokens.join(' ')
}

// un_is_empty_array ports isEmptyArrayExpression.
fn un_is_empty_array(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .array_expression && (t.list(node, .elements) or { []int{} }).len == 0
}

// un_is_empty_object ports isEmptyObjectExpression.
fn un_is_empty_object(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .object_expression
		&& (t.list(node, .properties) or { []int{} }).len == 0
}

// un_is_prototype_property ports isPrototypeProperty of utils/array-or-object-prototype-property.js
// (`object` is 'Array' or 'Object'): `Array.prototype.property`, `[].property` or `{}.property`.
fn un_is_prototype_property(t &estree.EsTree, node int, object string, properties []string) bool {
	if !un_is_member(t, node, properties: properties, optional: false) {
		return false
	}
	object_node := t.node(node, .object) or { return false }
	return un_is_member(t, object_node, objects: [object], properties: ['prototype'], optional: false)
		|| (object == 'Array' && un_is_empty_array(t, object_node))
		|| (object == 'Object' && un_is_empty_object(t, object_node))
}

// un_append_argument ports appendArgument (fix/append-argument.js) of a call expression.
fn (c &Checker) un_append_argument(t &estree.EsTree, tokens &SourceTokens, node int, text string) ?Fix {
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return none
	}
	penultimate := inside[inside.len - 2]
	last := inside.last()
	mut appended := text
	if (t.list(node, .arguments) or { []int{} }).len > 0 {
		appended = if c.token_is(penultimate, ',') { ' ${text},' } else { ', ${text}' }
	}
	return fix_insert_at(last.start, appended)
}

// un_is_literal_value ports isLiteral(node, value) for a string value.
fn un_is_literal_string(t &estree.EsTree, node int, value string) bool {
	if node < 0 || t.typ(node) != .literal {
		return false
	}
	v := t.get(node, .value)
	return v is string && v == value
}

// un_is_undefined ports isUndefined: the identifier `undefined`.
fn un_is_undefined(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == 'undefined'
}

// un_is_node_value_not_function ports isNodeValueNotFunction.
fn un_is_node_value_not_function(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.array_expression, .binary_expression, .class_expression, .literal,
		.object_expression, .template_literal, .unary_expression, .update_expression,
		.assignment_expression, .await_expression, .new_expression, .tagged_template_expression,
		.this_expression] || un_is_undefined(t, node) || (un_is_call(t, node)
		&& !un_is_method_call(t, node, methods: ['bind'], optional_call: false, optional_member: false))
}

// un_is_logical ports isLogicalExpression: `&&` or `||` (not `??`).
fn un_is_logical(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .logical_expression
		&& (t.string_of(node, .operator) or { '' }) in ['&&', '||']
}

fn un_is_logic_not(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == '!'
}

fn un_is_boolean_call(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .call_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'Boolean'
		&& (t.list(node, .arguments) or { []int{} }).len == 1
}

// un_is_boolean_expression ports isBooleanExpression of utils/boolean.js.
fn un_is_boolean_expression(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if un_is_logic_not(t, node) || (un_is_logic_not(t, parent) && t.node(parent, .argument) or { -1 } == node)
		|| un_is_boolean_call(t, node) || (un_is_boolean_call(t, parent)
		&& (t.list(parent, .arguments) or { []int{} })[0] == node) {
		return true
	}
	if un_is_logical(t, parent) {
		return un_is_boolean_expression(t, parent)
	}
	return false
}

// un_is_control_flow_test ports isControlFlowTest of utils/boolean.js.
fn un_is_control_flow_test(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) in [.if_statement, .conditional_expression, .while_statement,
		.do_while_statement, .for_statement] && t.node(parent, .test) or { -1 } == node {
		return true
	}
	if un_is_logical(t, parent) {
		return un_is_control_flow_test(t, parent)
	}
	return false
}

// un_replace_member_property ports replaceMemberExpressionProperty.
fn (c &Checker) un_replace_member_property(t &estree.EsTree, tokens &SourceTokens, member int, text string) Fix {
	object := t.node(member, .object) or { return fix_insert_at(t.nodes[member].end, '') }
	_, start := c.un_parenthesized_range(t, tokens, object)
	return fix_replace_range(start, t.nodes[member].end, text)
}

// un_is_function_self_used_inside ports isFunctionSelfUsedInside: `this`, `arguments` or the name of
// the function is used inside it.
fn (mut c Checker) un_is_function_self_used_inside(root C.TSNode, t &estree.EsTree, function int) bool {
	if t.typ(function) == .arrow_function_expression {
		return false
	}
	// functionScope.thisFound: typescript-eslint's scope manager never sets it, so a `this` inside
	// does not count.
	tree := c.scope_tree(root)
	scope := tree.function_scope_of(t.ts_node(function) or { return false })
	if scope < 0 {
		return false
	}
	arguments := tree.find_variable(scope, 'arguments', -1)
	if arguments >= 0 && tree.variables[arguments].references.any(tree.references[it].from == scope) {
		return true
	}
	if id := t.node(function, .id) {
		v := tree.find_variable(scope, t.string_of(id, .name) or { '' }, -1)
		if v >= 0 && tree.variables[v].references.len > 0 {
			return true
		}
	}
	return false
}

// un_member_object_needs_parens ports shouldAddParenthesesToMemberExpressionObject(node, context)
// (eslint-plugin-unicorn 79.0.0), where the node stays where it is.
fn (c &Checker) un_member_object_needs_parens(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	return c.un_member_object_needs_parens_at(t, tokens, node, node)
}

// un_member_object_needs_parens_at ports shouldAddParenthesesToMemberExpressionObject: the node
// needs parentheses as the object of a member expression that takes the place of `replacement`
// (also so that a statement does not start with a declaration-like token).
fn (c &Checker) un_member_object_needs_parens_at(t &estree.EsTree, tokens &SourceTokens, node int, replacement int) bool {
	if c.un_expression_start_needs_parens(t, tokens, node, replacement) {
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

// un_member_object_text ports getMemberExpressionObjectText: the text of the node (with its
// parentheses) as the object of a member expression where `replacement` is, in parentheses when
// it needs them.
fn (c &Checker) un_member_object_text(t &estree.EsTree, tokens &SourceTokens, node int, replacement int) string {
	text := c.un_parenthesized_text(t, tokens, node)
	if !c.un_is_parenthesized(t, tokens, node)
		&& c.un_member_object_needs_parens_at(t, tokens, node, replacement) {
		return '(${text})'
	}
	return text
}

// un_is_node_matches ports isNodeMatches: the node matches one of the names or paths.
fn un_is_node_matches(t &estree.EsTree, node int, names_or_paths []string) bool {
	return names_or_paths.any(un_node_matches_name_or_path(t, node, it))
}

// un_const_initializer ports getConstVariableInitializer (utils/get-const-variable-initializer.js
// of eslint-plugin-unicorn 79.0.0): the initializer of
// the only definition of the variable of an identifier, a `const` declarator.
fn (mut c Checker) un_const_initializer(root C.TSNode, t &estree.EsTree, node int) ?int {
	if t.typ(node) != .identifier {
		return none
	}
	ts := t.ts_node(node)?
	tree := c.scope_tree(root)
	v := tree.find_variable(tree.get_scope(ts), t.string_of(node, .name)?, t.nodes[node].start)
	if v < 0 || tree.variables[v].defs.len != 1 {
		return none
	}
	def := tree.variables[v].defs[0]
	if def.kind != .variable || treesitter.node_kind(def.node) != 'variable_declarator' || def.parent_kind != 'const' {
		return none
	}
	// A destructured binding (`const {foo} = bar`) does not have the initializer as its value.
	decl_id := def.decl_id or { return none }
	if node_key(decl_id) != node_key(def.name) {
		return none
	}
	return c.es_index_of(t, def.init?)
}

// un_argument_removal_range ports getArgumentRemovalRange (fix/remove-argument.js of
// eslint-plugin-unicorn 79.0.0): the range removing an argument removes, with its parentheses and
// the comma (the following one and the gap after it for the first of several).
fn (c &Checker) un_argument_removal_range(t &estree.EsTree, tokens &SourceTokens, node int) ?UnRange {
	call := t.nodes[node].parent
	arguments := t.list(call, .arguments) or { return none }
	index := arguments.index(node)
	parentheses := c.un_parentheses(t, tokens, node)
	mut start := if parentheses.len > 0 { parentheses[0].start } else { t.nodes[node].start }
	mut end := if parentheses.len > 0 { parentheses.last().end } else { t.nodes[node].end }
	if arguments.len == 1 {
		// The only argument: also a dangling trailing comma (`fn(a,)`).
		if after := tokens.after(end, false) {
			if c.token_is(after, ',') {
				end = after.end
			}
		}
	} else if index == 0 {
		// The first of several: through the following comma and the gap after it.
		comma := tokens.after(end, false)?
		after_comma := tokens.after(comma.end, true)?
		end = after_comma.start
	} else {
		comma := tokens.before(start, false)?
		start = comma.start
	}
	return UnRange{start, end}
}

// un_remove_argument ports removeArgument: the comments in the removed range are kept.
fn (c &Checker) un_remove_argument(t &estree.EsTree, tokens &SourceTokens, node int) ?Fix {
	removal := c.un_argument_removal_range(t, tokens, node)?
	if !un_has_comment_in_range(tokens, removal.start, removal.end) {
		return fix_remove_range(removal.start, removal.end)
	}
	call := t.nodes[node].parent
	arguments := t.list(call, .arguments) or { return none }
	index := arguments.index(node)
	comments := tokens.comments_inside(removal.start, removal.end).filter(it.end <= removal.end)
	linebreak := un_linebreak(c.src)
	comment_text := fn [c, linebreak] (comment SourceToken) string {
		return c.token_text(comment) + if comment.kind == .line_comment { linebreak } else { '' }
	}
	// Removing the first of several arguments swallows the comma after it: the comments after the
	// argument are spliced out of the middle, and the comments inside it go before them.
	if index == 0 && arguments.len > 1 {
		parentheses := c.un_parentheses(t, tokens, node)
		argument_end := if parentheses.len > 0 { parentheses.last().end } else { t.nodes[node].end }
		comma := tokens.after(argument_end, false)?
		argument_comments := comments.filter(it.end <= argument_end).map(comment_text(it)).join(' ')
		replacement := argument_comments + c.src[argument_end..comma.start] + c.src[comma.end..removal.end]
		return fix_replace_range(removal.start, removal.end, replacement)
	}
	return fix_replace_range(removal.start, removal.end, comments.map(' ${comment_text(it)}').join(''))
}

// un_call_callee_needs_parens ports shouldAddParenthesesToCallExpressionCallee.
fn un_call_callee_needs_parens(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.sequence_expression, .yield_expression, .arrow_function_expression,
		.conditional_expression, .assignment_expression, .logical_expression, .binary_expression,
		.unary_expression, .update_expression, .new_expression]
}

// un_is_reference_identifier ports isReferenceIdentifier (ast/is-reference-identifier.js) without
// names.
fn un_is_reference_identifier(t &estree.EsTree, node int) bool {
	if t.typ(node) != .identifier {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return true
	}
	is_key := fn [t, parent, node] (key estree.Key) bool {
		return t.node(parent, key) or { -1 } == node
	}
	in_list := fn [t, parent, node] (key estree.Key) bool {
		return node in (t.list(parent, key) or { []int{} })
	}
	computed := t.flag(parent, .computed) or { false }
	not_reference := match t.typ(parent) {
		.member_expression {
			!computed && is_key(.property)
		}
		.function_declaration, .function_expression {
			in_list(.params) || is_key(.id)
		}
		.arrow_function_expression {
			in_list(.params)
		}
		.class_declaration, .class_expression, .variable_declarator, .ts_declare_function,
		.ts_enum_member, .ts_type_alias_declaration {
			is_key(.id)
		}
		.property_definition, .method_definition, .ts_property_signature, .ts_method_signature {
			!computed && is_key(.key)
		}
		.property {
			grand := t.nodes[parent].parent
			grand_typ := if grand >= 0 { t.typ(grand) } else { estree.NodeType.program }
			(!computed && is_key(.key) && grand_typ in [.object_expression, .object_pattern])
				|| (is_key(.value) && grand_typ == .object_pattern)
		}
		.array_pattern {
			in_list(.elements)
		}
		.labeled_statement, .continue_statement, .break_statement {
			is_key(.label)
		}
		.import_default_specifier, .import_namespace_specifier {
			is_key(.local)
		}
		.export_all_declaration {
			is_key(.exported)
		}
		.import_specifier {
			is_key(.local) || is_key(.imported)
		}
		.export_specifier {
			is_key(.local) || is_key(.exported)
		}
		.ts_index_signature {
			in_list(.parameters)
		}
		.ts_type_parameter {
			is_key(.name)
		}
		.ts_mapped_type {
			is_key(.key)
		}
		else {
			false
		}
	}
	return !not_reference
}

// UnRange is a range [start, end) of the source, in bytes.
struct UnRange {
	start int
	end   int
}

// un_range is the range of a node.
fn un_range(t &estree.EsTree, node int) UnRange {
	return UnRange{t.nodes[node].start, t.nodes[node].end}
}

// un_would_remove_comments ports wouldRemoveComments of utils/comments.js (eslint-plugin-unicorn
// 79.0.0): a comment entirely in [start, end) that is in none of the preserved ranges.
fn un_would_remove_comments(tokens &SourceTokens, start int, end int, preserved []UnRange) bool {
	for comment in tokens.comments_inside(start, end) {
		if comment.end > end {
			continue
		}
		if preserved.any(comment.start >= it.start && comment.end <= it.end) {
			continue
		}
		return true
	}
	return false
}

// un_has_comment_in_range ports hasCommentInRange: a comment entirely in [start, end).
fn un_has_comment_in_range(tokens &SourceTokens, start int, end int) bool {
	return un_would_remove_comments(tokens, start, end, [])
}

// un_last_trailing_comment_on_same_line ports getLastTrailingCommentOnSameLine (without
// ignoreDirectives) for the node or token that ends at `end`: the last of the comments right after
// it that starts on the line where it ends.
fn un_last_trailing_comment_on_same_line(t &estree.EsTree, tokens &SourceTokens, end int) ?SourceToken {
	line, _ := t.line_column(end)
	comments := tokens.comments_after(end)
	for i := comments.len - 1; i >= 0; i-- {
		comment_line, _ := t.line_column(comments[i].start)
		if comment_line == line {
			return comments[i]
		}
	}
	return none
}

// un_linebreak ports getLinebreak: the first line ending of the file, or `\n`.
fn un_linebreak(src string) string {
	for i := 0; i < src.len; i++ {
		match src[i] {
			`\r` {
				return if i + 1 < src.len && src[i + 1] == `\n` { '\r\n' } else { '\r' }
			}
			`\n` {
				return '\n'
			}
			0xe2 {
				// U+2028 and U+2029.
				if i + 2 < src.len && src[i + 1] == 0x80 && src[i + 2] in [u8(0xa8), 0xa9] {
					return src[i..i + 3]
				}
			}
			else {}
		}
	}
	return '\n'
}

// un_starts_with_declaration_like_token ports startsWithDeclarationLikeToken of
// should-add-parentheses-to-expression-statement-expression.js: the node starts with `{`, `class`,
// `function`, `async function` or `let [`.
fn (c &Checker) un_starts_with_declaration_like_token(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	first := un_first_token(t, tokens, node, 0) or { return false }
	text := c.token_text(first)
	if (first.kind == .punctuator && text == '{')
		|| (first.kind == .keyword && text in ['class', 'function']) {
		return true
	}
	if text in ['async', 'let'] {
		after := tokens.after(first.end, false) or { return false }
		return c.token_text(after) == if text == 'async' { 'function' } else { '[' }
	}
	return false
}

// un_expression_statement_needs_parens ports shouldAddParenthesesToExpressionStatementExpression
// (eslint-plugin-unicorn 79.0.0): an expression statement cannot start with `{`, `class`,
// `function`, `async function` or `let [`.
fn (c &Checker) un_expression_statement_needs_parens(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	return !c.un_is_parenthesized(t, tokens, node)
		&& c.un_starts_with_declaration_like_token(t, tokens, node)
}

// un_expression_start_needs_parens ports shouldAddParenthesesToExpressionStart (without the Svelte
// case): moving `expression` to where `replacement` is would expose a block or declaration prefix
// (`let [` in a `for` initializer included).
fn (c &Checker) un_expression_start_needs_parens(t &estree.EsTree, tokens &SourceTokens, expression int, replacement int) bool {
	first := un_first_token(t, tokens, expression, 0) or { return false }
	starts_with_regexp := first.kind == .regular_expression
	if !starts_with_regexp && !c.un_starts_with_declaration_like_token(t, tokens, expression) {
		return false
	}
	text := c.token_text(first)
	mut node := replacement
	for t.nodes[node].parent >= 0 {
		if c.un_is_parenthesized(t, tokens, node) {
			return false
		}
		parent := t.nodes[node].parent
		if t.typ(parent) == .arrow_function_expression && (t.node(parent, .body) or { -1 }) == node {
			return text == '{'
		}
		if t.typ(parent) == .export_default_declaration
			&& (t.node(parent, .declaration) or { -1 }) == node {
			return !starts_with_regexp && text != '{' && text != 'let'
		}
		if t.typ(parent) == .for_statement && (t.node(parent, .init) or { -1 }) == node {
			return text == 'let'
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

// un_unparenthesized_keyword_argument_parent ports getUnparenthesizedKeywordArgumentParent: the
// `return`, `throw` or non-delegated `yield` whose unparenthesized argument starts with the node.
fn (c &Checker) un_unparenthesized_keyword_argument_parent(t &estree.EsTree, tokens &SourceTokens, from int) ?int {
	mut node := from
	for !c.un_is_parenthesized(t, tokens, node) {
		parent := t.nodes[node].parent
		if parent >= 0 && (t.node(parent, .argument) or { -1 }) == node
			&& (t.typ(parent) in [.return_statement, .throw_statement]
			|| (t.typ(parent) == .yield_expression && !(t.flag(parent, .delegate) or { false }))) {
			return parent
		}
		if parent < 0 || t.nodes[parent].start != t.nodes[node].start {
			return none
		}
		node = parent
	}
	return none
}

// un_is_ts_expression_wrapper ports isTypeScriptExpressionWrapper of
// unwrap-typescript-expression.js: `as`, `satisfies`, `!`, `<Type>` or `foo<Type>`.
fn un_is_ts_expression_wrapper(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.ts_as_expression, .ts_satisfies_expression,
		.ts_non_null_expression, .ts_type_assertion, .ts_instantiation_expression]
}

// un_unwrap_ts_expression ports unwrapTypeScriptExpression: the node without its TypeScript
// expression wrappers.
fn un_unwrap_ts_expression(t &estree.EsTree, from int) int {
	mut node := from
	for un_is_ts_expression_wrapper(t, node) {
		node = t.node(node, .expression) or { break }
	}
	return node
}

// un_unwrap_chain_and_ts_expression ports unwrapChainAndTypeScriptExpression.
fn un_unwrap_chain_and_ts_expression(t &estree.EsTree, from int) int {
	mut node := from
	for node >= 0 && (t.typ(node) == .chain_expression || un_is_ts_expression_wrapper(t, node)) {
		node = t.node(node, .expression) or { break }
	}
	return node
}

// un_outermost_ts_expression ports getOutermostTypeScriptExpression: the outermost TypeScript
// expression wrapper around the node, or the node.
fn un_outermost_ts_expression(t &estree.EsTree, from int) int {
	mut node := from
	for {
		parent := t.nodes[node].parent
		if !un_is_ts_expression_wrapper(t, parent) || (t.node(parent, .expression) or { -1 }) != node {
			break
		}
		node = parent
	}
	return node
}

// un_outermost_chain_and_ts_expression ports getOutermostChainAndTypeScriptExpression.
fn un_outermost_chain_and_ts_expression(t &estree.EsTree, from int) int {
	mut node := from
	for {
		parent := t.nodes[node].parent
		if parent < 0 || !(t.typ(parent) == .chain_expression || un_is_ts_expression_wrapper(t, parent))
			|| (t.node(parent, .expression) or { -1 }) != node {
			break
		}
		node = parent
	}
	return node
}

// un_function_return_expression ports getFunctionReturnExpression of function-body.js: the concise
// body of an arrow function, or the argument of the only statement of the body when it is a
// `return`; -1 when there is none.
fn un_function_return_expression(t &estree.EsTree, function int) int {
	body := t.node(function, .body) or { return -1 }
	if t.typ(body) != .block_statement {
		return body
	}
	statements := t.list(body, .body) or { return -1 }
	if statements.len == 1 && t.typ(statements[0]) == .return_statement {
		return t.node(statements[0], .argument) or { -1 }
	}
	return -1
}

// un_function_only_expression ports getFunctionOnlyExpression: the concise body of an arrow
// function, or the expression of the only statement of the body when it is an expression
// statement; -1 when there is none.
fn un_function_only_expression(t &estree.EsTree, function int) int {
	body := t.node(function, .body) or { return -1 }
	if t.typ(body) != .block_statement {
		return body
	}
	statements := t.list(body, .body) or { return -1 }
	if statements.len == 1 && t.typ(statements[0]) == .expression_statement {
		return t.node(statements[0], .expression) or { -1 }
	}
	return -1
}

// un_line_start ports getLineStart: the offset where the line of `offset` starts.
fn un_line_start(src string, offset int) int {
	mut start := offset
	for start > 0 {
		b := src[start - 1]
		if b == `\n` || b == `\r` {
			break
		}
		// U+2028 and U+2029 end in 0xa8 and 0xa9.
		if start >= 3 && src[start - 3] == 0xe2 && src[start - 2] == 0x80
			&& b in [u8(0xa8), 0xa9] {
			break
		}
		start--
	}
	return start
}

// un_line_indent ports getLineIndent: the leading tabs and spaces of the line where `offset` is.
fn (c &Checker) un_line_indent(offset int) string {
	start := un_line_start(c.src, offset)
	mut end := start
	for end < c.src.len && c.src[end] in [` `, `\t`] {
		end++
	}
	return c.src[start..end]
}

// un_source_lines are sourceCode.lines: the lines of the source, split at every line break.
fn un_source_lines(src string) []string {
	mut lines := []string{}
	mut start := 0
	mut i := 0
	for i < src.len {
		b := src[i]
		if b == `\r` || b == `\n` {
			lines << src[start..i]
			i += if b == `\r` && i + 1 < src.len && src[i + 1] == `\n` { 2 } else { 1 }
			start = i
			continue
		}
		if b == 0xe2 && i + 2 < src.len && src[i + 1] == 0x80 && src[i + 2] in [u8(0xa8), 0xa9] {
			lines << src[start..i]
			i += 3
			start = i
			continue
		}
		i++
	}
	lines << src[start..]
	return lines
}

// un_detect_indent_key ports makeIndentsMap and getMostUsedKey of detect-indent 7.0.2: the most
// used indent as `s<n>` or `t<n>`, or '' when there is none.
fn un_detect_indent_key(lines []string, ignore_single_spaces bool) (string, int) {
	mut used := map[string]int{}
	mut weights := map[string]int{}
	mut order := []string{}
	mut previous_size := 0
	mut previous_type := ''
	mut key := ''
	for line in lines {
		if line == '' {
			continue
		}
		// `^(?:( )+|\t+)`
		mut indent := 0
		mut typ := ''
		if line[0] == ` ` {
			for indent < line.len && line[indent] == ` ` {
				indent++
			}
			typ = 'space'
		} else if line[0] == `\t` {
			for indent < line.len && line[indent] == `\t` {
				indent++
			}
			typ = 'tab'
		}
		if typ == '' {
			previous_size = 0
			previous_type = ''
			continue
		}
		if ignore_single_spaces && typ == 'space' && indent == 1 {
			continue
		}
		if typ != previous_type {
			previous_size = 0
		}
		previous_type = typ
		mut use := 1
		mut weight := 0
		difference := indent - previous_size
		previous_size = indent
		if difference == 0 {
			use = 0
			weight = 1
		} else {
			absolute := if difference < 0 { -difference } else { difference }
			if ignore_single_spaces && typ == 'space' && absolute == 1 {
				continue
			}
			key = (if typ == 'space' { 's' } else { 't' }) + absolute.str()
		}
		if key !in used {
			order << key
			used[key] = 1
			weights[key] = 0
		} else {
			used[key] += use
			weights[key] += weight
		}
	}
	mut result := ''
	mut max_used := 0
	mut max_weight := 0
	for k in order {
		if used[k] > max_used || (used[k] == max_used && weights[k] > max_weight) {
			max_used = used[k]
			max_weight = weights[k]
			result = k
		}
	}
	return result, order.len
}

// un_indent_unit ports getIndentUnit: one level of indentation of the file (detect-indent on its
// lines, with the continuation lines of multi-line tokens and comments blanked), a tab when it is
// not made of spaces.
fn (c &Checker) un_indent_unit(t &estree.EsTree, tokens &SourceTokens) string {
	mut lines := un_source_lines(c.src)
	for token in tokens.all {
		start_line, _ := t.line_column(token.start)
		end_line, _ := t.line_column(token.end)
		for line in start_line .. end_line {
			if line < lines.len {
				lines[line] = ''
			}
		}
	}
	mut key, count := un_detect_indent_key(lines, true)
	if count == 0 {
		key, _ = un_detect_indent_key(lines, false)
	}
	if key.starts_with('s') {
		return ' '.repeat(key[1..].int())
	}
	return '\t'
}

// un_primitive_literal_value ports getPrimitiveLiteralValue: the value of a literal (not a
// regular expression), of a template without expressions, or of a signed numeric literal (and a
// negated BigInt); none for other expressions. A BigInt is a JsValue of kind bigint_ with the
// `bigint` text of its literal.
fn un_primitive_literal_value(t &estree.EsTree, from int) ?JsValue {
	node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return none
	}
	if t.typ(node) == .literal && t.prop(node, .regex) == none {
		return un_literal_js_value(t, node)
	}
	if t.typ(node) == .template_literal {
		text := un_static_string_value(t, node)?
		return JsValue{
			kind: .string_
			text: text
		}
	}
	if t.typ(node) != .unary_expression {
		return none
	}
	argument := un_unwrap_ts_expression(t, t.node(node, .argument)?)
	if argument < 0 || t.typ(argument) != .literal {
		return none
	}
	operator := t.string_of(node, .operator)?
	value := t.get(argument, .value)
	if value is f64 && operator in ['-', '+'] {
		return JsValue{
			kind:   .number_
			number: if operator == '-' { -value } else { value }
		}
	}
	if bigint := t.string_of(argument, .bigint) {
		if operator == '-' {
			return JsValue{
				kind: .bigint_
				text: if bigint == '0' { '0' } else { '-${bigint}' }
			}
		}
	}
	return none
}

// un_literal_js_value is the value of a Literal node that is not a regular expression.
fn un_literal_js_value(t &estree.EsTree, node int) ?JsValue {
	if bigint := t.string_of(node, .bigint) {
		return JsValue{
			kind: .bigint_
			text: bigint
		}
	}
	value := t.get(node, .value)
	return match value {
		string {
			JsValue{
				kind: .string_
				text: value
			}
		}
		f64 {
			JsValue{
				kind:   .number_
				number: value
			}
		}
		bool {
			JsValue{
				kind:    .boolean_
				boolean: value
			}
		}
		estree.Null {
			JsValue{
				kind: .null_
			}
		}
		else {
			none
		}
	}
}

// un_js_object_is ports Object.is for numbers: NaN is NaN, and 0 is not -0.
fn un_js_object_is(a f64, b f64) bool {
	if math.is_nan(a) || math.is_nan(b) {
		return math.is_nan(a) && math.is_nan(b)
	}
	return a == b && math.signbit(a) == math.signbit(b)
}

// un_static_number_value ports getStaticNumberValue of utils/numeric.js: a numeric literal, maybe
// signed, without TypeScript wrappers.
fn un_static_number_value(t &estree.EsTree, from int) ?f64 {
	node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return none
	}
	if t.typ(node) == .literal {
		value := t.get(node, .value)
		if value is f64 {
			return value
		}
		return none
	}
	if t.typ(node) == .unary_expression {
		operator := t.string_of(node, .operator) or { '' }
		if operator in ['+', '-'] {
			value := un_static_number_value(t, t.node(node, .argument) or { return none })?
			return if operator == '-' { -value } else { value }
		}
	}
	return none
}

// un_is_length_of ports isLengthOf of utils/comparison.js: the node is `<object>.length` (not
// optional, not computed), without TypeScript wrappers.
fn (mut c Checker) un_is_length_of(t &estree.EsTree, from int, object int) bool {
	if from < 0 || object < 0 {
		return false
	}
	node := un_unwrap_ts_expression(t, from)
	return un_is_member(t, node, properties: ['length'], optional: false, computed: false)
		&& c.un_is_same_reference(t, t.node(node, .object) or { return false }, object)
}

// un_is_length_minus_one_of ports isLengthMinusOneOf: `<object>.length - 1`.
fn (mut c Checker) un_is_length_minus_one_of(t &estree.EsTree, from int, object int) bool {
	node := un_unwrap_ts_expression(t, from)
	if node < 0 || t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return false
	}
	right := t.node(node, .right) or { return false }
	return (un_static_number_value(t, right) or { return false }) == 1
		&& c.un_is_length_of(t, t.node(node, .left) or { return false }, object)
}

// un_function_head_location ports getFunctionHeadLocation of eslint-utils, which (unlike ESLint's
// own, es_tree_function_head) takes the `=>` of an arrow function before the property it is the
// value of.
fn (mut c Checker) un_function_head_location(t &estree.EsTree, node int) Ident {
	if t.typ(node) == .arrow_function_expression {
		if body := t.node(node, .body) {
			tokens := c.source_tokens(t.nodes[t.root].ts)
			mut at := t.nodes[body].start
			for {
				token := tokens.before(at, false) or { break }
				if c.src[token.start..token.end] == '=>' {
					return c.position_range(token.start, token.end)
				}
				at = token.start
			}
		}
	}
	return c.es_tree_function_head(t, node)
}
