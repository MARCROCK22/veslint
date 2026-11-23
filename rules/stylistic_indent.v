module rules

import esquery
import estree
import math
import time
import treesitter { Ident }
import x.json2

// Port of the `@stylistic/indent` rule of @stylistic/eslint-plugin 6.0.1 (rules/indent/indent.ts
// and its utils: the OffsetStorage of the desired offsets of the tokens, TokenInfo, the handlers of
// the node listeners and the validator), with all its options and its fixes. Tokens and comments
// are their index in SourceTokens.all; offsets are bytes of the source (ESLint's are UTF-16 units:
// the two only differ in how far apart the keys of the offset map are, never in their order).

const sti_messages = {
	'wrongIndentation': 'Expected indentation of {{expected}} but found {{actual}}.'
}

// The node types the rule knows (KNOWN_NODES): it ignores the indentation of the others.
const sti_known_nodes = ['AssignmentExpression', 'AssignmentPattern', 'ArrayExpression', 'ArrayPattern',
	'ArrowFunctionExpression', 'AwaitExpression', 'BlockStatement', 'BinaryExpression', 'BreakStatement',
	'CallExpression', 'CatchClause', 'ChainExpression', 'ClassBody', 'ClassDeclaration',
	'ClassExpression', 'ConditionalExpression', 'ContinueStatement', 'DoWhileStatement',
	'DebuggerStatement', 'EmptyStatement', 'ExpressionStatement', 'ForStatement', 'ForInStatement',
	'ForOfStatement', 'FunctionDeclaration', 'FunctionExpression', 'Identifier', 'IfStatement',
	'Literal', 'LabeledStatement', 'LogicalExpression', 'MemberExpression', 'MetaProperty',
	'MethodDefinition', 'NewExpression', 'ObjectExpression', 'ObjectPattern', 'PrivateIdentifier',
	'Program', 'Property', 'PropertyDefinition', 'AccessorProperty', 'RestElement', 'ReturnStatement',
	'SequenceExpression', 'SpreadElement', 'StaticBlock', 'Super', 'SwitchCase', 'SwitchStatement',
	'TaggedTemplateExpression', 'TemplateElement', 'TemplateLiteral', 'ThisExpression', 'ThrowStatement',
	'TryStatement', 'UnaryExpression', 'UpdateExpression', 'VariableDeclaration', 'VariableDeclarator',
	'WhileStatement', 'WithStatement', 'YieldExpression', 'JSXFragment', 'JSXOpeningFragment',
	'JSXClosingFragment', 'JSXIdentifier', 'JSXNamespacedName', 'JSXMemberExpression',
	'JSXEmptyExpression', 'JSXExpressionContainer', 'JSXElement', 'JSXClosingElement',
	'JSXOpeningElement', 'JSXAttribute', 'JSXSpreadAttribute', 'JSXText', 'ExportDefaultDeclaration',
	'ExportNamedDeclaration', 'ExportAllDeclaration', 'ExportSpecifier', 'ImportDeclaration',
	'ImportSpecifier', 'ImportDefaultSpecifier', 'ImportNamespaceSpecifier', 'ImportExpression',
	'ImportAttribute', 'TSAbstractKeyword', 'TSAnyKeyword', 'TSBooleanKeyword', 'TSNeverKeyword',
	'TSNumberKeyword', 'TSStringKeyword', 'TSSymbolKeyword', 'TSUndefinedKeyword', 'TSUnknownKeyword',
	'TSVoidKeyword', 'TSNullKeyword', 'TSAbstractPropertyDefinition', 'TSAbstractAccessorProperty',
	'TSAbstractMethodDefinition', 'TSArrayType', 'TSAsExpression', 'TSSatisfiesExpression',
	'TSCallSignatureDeclaration', 'TSConditionalType', 'TSConstructorType',
	'TSConstructSignatureDeclaration', 'TSDeclareFunction', 'TSEmptyBodyFunctionExpression',
	'TSEnumDeclaration', 'TSEnumBody', 'TSEnumMember', 'TSExportAssignment', 'TSExternalModuleReference',
	'TSFunctionType', 'TSImportType', 'TSIndexedAccessType', 'TSIndexSignature', 'TSInferType',
	'TSInterfaceBody', 'TSInterfaceDeclaration', 'TSInterfaceHeritage', 'TSImportEqualsDeclaration',
	'TSLiteralType', 'TSMappedType', 'TSMethodSignature', 'TSModuleBlock', 'TSModuleDeclaration',
	'TSNonNullExpression', 'TSParameterProperty', 'TSPropertySignature', 'TSQualifiedName', 'TSRestType',
	'TSThisType', 'TSTupleType', 'TSTypeAliasDeclaration', 'TSTypeAnnotation', 'TSTypeLiteral',
	'TSTypeOperator', 'TSTypeParameter', 'TSTypeParameterDeclaration', 'TSTypeParameterInstantiation',
	'TSTypeReference', 'Decorator']

// StiOff is the value of an option that is an offset: a number of indent levels, `"first"` or
// `"off"` (ElementListOffset, and the options that are a number or `"off"`).
enum StiOffKind {
	number
	first
	off
}

struct StiOff {
	kind StiOffKind
	num  f64
}

struct StiOptions {
	tab                 bool
	indent_size         int
	switch_case         f64
	var_var             StiOff
	var_let             StiOff
	var_const           StiOff
	var_using           StiOff
	assignment_operator StiOff
	outer_iife_body     StiOff
	member_expression   StiOff
	fd_parameters       StiOff
	fd_body             f64
	fd_return_type      f64
	fe_parameters       StiOff
	fe_body             f64
	fe_return_type      f64
	static_block_body   f64
	call_arguments      StiOff
	array_expression    StiOff
	object_expression   StiOff
	import_declaration  StiOff
	flat_ternary        bool
	// offsetTernaryExpressions: off, or on with the branch types that get two levels.
	offset_ternary  bool
	ternary_call    bool
	ternary_await   bool
	ternary_new     bool
	ignored_nodes   []string
	ignore_comments bool
	tab_length      f64
	jsx_indent_size f64 // jsxIndentSize
	jsx_offset      f64 // jsxOffset: jsxIndentSize / indentSize
}

// sti_is_number: a JSON value that is a number.
fn sti_is_number(v json2.Any) bool {
	return !(v is string || v is json2.Null || v is bool || v is map[string]json2.Any
		|| v is []json2.Any)
}

// sti_get is `object[key]`, none when the key is missing.
fn sti_get(object map[string]json2.Any, key string) ?json2.Any {
	return object[key] or { return none }
}

// sti_off reads an offset option; `fallback` when it is missing or not an offset.
fn sti_off(value ?json2.Any, fallback StiOff) StiOff {
	v := value or { return fallback }
	if v is string {
		return match v {
			'first' { StiOff{.first, 0} }
			'off' { StiOff{.off, 0} }
			else { fallback }
		}
	}
	if !sti_is_number(v) {
		return fallback
	}
	return StiOff{.number, v.f64()}
}

// sti_number reads a numeric option; `fallback` when it is missing or not a number.
fn sti_number(value ?json2.Any, fallback f64) f64 {
	v := value or { return fallback }
	if !sti_is_number(v) {
		return fallback
	}
	return v.f64()
}

fn sti_object(value ?json2.Any) map[string]json2.Any {
	v := value or { return map[string]json2.Any{} }
	if v is map[string]json2.Any {
		return v
	}
	return map[string]json2.Any{}
}

fn sti_options(given []json2.Any) !StiOptions {
	options := sty_options(given, decoded_default_options(stylistic_indent))
	mut tab := false
	mut indent_size := 4
	if options.len > 0 {
		first := options[0]
		if first is string {
			tab = first == 'tab'
			indent_size = 1
		} else if sti_is_number(first) {
			indent_size = int(first.f64())
		}
	}
	user := sty_option_object(options, 1)
	one := StiOff{.number, 1}
	variable := user['VariableDeclarator'] or { json2.Any(f64(1)) }
	mut var_var, mut var_let, mut var_const, mut var_using := one, one, one, one
	if variable is map[string]json2.Any {
		// `options.VariableDeclarator[kind] ?? 1`
		var_var = sti_off(sti_get(variable, 'var'), one)
		var_let = sti_off(sti_get(variable, 'let'), one)
		var_const = sti_off(sti_get(variable, 'const'), one)
		var_using = sti_off(sti_get(variable, 'using'), one)
	} else {
		v := sti_off(variable, one)
		var_var, var_let, var_const, var_using = v, v, v, v
	}
	fd := sti_object(sti_get(user, 'FunctionDeclaration'))
	fe := sti_object(sti_get(user, 'FunctionExpression'))
	ternary := user['offsetTernaryExpressions'] or { json2.Any(false) }
	mut offset_ternary := false
	mut ternary_call, mut ternary_await, mut ternary_new := true, true, true
	if ternary is bool {
		offset_ternary = ternary
	} else if ternary is map[string]json2.Any {
		offset_ternary = true
		ternary_call = sty_option_bool(ternary, 'CallExpression') or { true }
		ternary_await = sty_option_bool(ternary, 'AwaitExpression') or { true }
		ternary_new = sty_option_bool(ternary, 'NewExpression') or { true }
	}
	mut ignored := []string{}
	if list := user['ignoredNodes'] {
		if list is []json2.Any {
			for item in list {
				if item is string {
					ignored << item
				}
			}
		}
	}
	jsx := user['jsx'] or { json2.Any(json2.Null{}) }
	jsx_indent_size := if jsx is string && jsx == 'half' {
		// Math.max(1, Math.round(indentSize / 2))
		math.max(1.0, math.floor(f64(indent_size) / 2 + 0.5))
	} else {
		sti_number(jsx, f64(indent_size))
	}
	return StiOptions{
		tab:                 tab
		indent_size:         indent_size
		switch_case:         sti_number(sti_get(user, 'SwitchCase'), 1)
		var_var:             var_var
		var_let:             var_let
		var_const:           var_const
		var_using:           var_using
		assignment_operator: sti_off(sti_get(user, 'assignmentOperator'), one)
		outer_iife_body:     sti_off(sti_get(user, 'outerIIFEBody'), one)
		member_expression:   sti_off(sti_get(user, 'MemberExpression'), one)
		fd_parameters:       sti_off(sti_get(fd, 'parameters'), one)
		fd_body:             sti_number(sti_get(fd, 'body'), 1)
		fd_return_type:      sti_number(sti_get(fd, 'returnType'), 1)
		fe_parameters:       sti_off(sti_get(fe, 'parameters'), one)
		fe_body:             sti_number(sti_get(fe, 'body'), 1)
		fe_return_type:      sti_number(sti_get(fe, 'returnType'), 1)
		static_block_body:   sti_number(sti_get(sti_object(sti_get(user, 'StaticBlock')), 'body'), 1)
		call_arguments:      sti_off(sti_get(sti_object(sti_get(user, 'CallExpression')), 'arguments'), one)
		array_expression:    sti_off(sti_get(user, 'ArrayExpression'), one)
		object_expression:   sti_off(sti_get(user, 'ObjectExpression'), one)
		import_declaration:  sti_off(sti_get(user, 'ImportDeclaration'), one)
		flat_ternary:        sty_option_bool(user, 'flatTernaryExpressions') or { false }
		offset_ternary:      offset_ternary
		ternary_call:        ternary_call
		ternary_await:       ternary_await
		ternary_new:         ternary_new
		ignored_nodes:       ignored
		ignore_comments:     sty_option_bool(user, 'ignoreComments') or { false }
		tab_length:          sti_number(sti_get(user, 'tabLength'), 4)
		jsx_indent_size:     jsx_indent_size
		jsx_offset:          jsx_indent_size / f64(indent_size)
	}
}

// StiFilter is the filter of a token query (isOpeningParenToken, isNotSemicolonToken…).
enum StiFilter {
	any
	open_paren
	close_paren
	not_open_paren
	not_close_paren
	open_brace
	close_brace
	open_bracket
	close_bracket
	eq
	colon
	question
	semicolon
	not_semicolon
	optional_chain
	value     // token.value === the given text
	from_name // an Identifier token `from`
}

// StiState is the state of the rule on one file: the tokens with their lines (TokenInfo), the
// offset map and its descriptors (OffsetStorage: IndexMap, OffsetDescriptorStorage), and the sets
// the listeners fill.
struct StiState {
	t    &estree.EsTree = unsafe { nil }
	src  string
	opts StiOptions
mut:
	all      []SourceToken // tokens and comments
	toks     []SourceToken // tokens
	tok_all  []i32         // the index in `all` of each token
	all_tok  []i32         // the index in `toks` of each token of `all`, -1 for a comment
	line     []i32         // the line (from 1) where each token or comment of `all` starts
	end_line []i32         // the line where it ends
	// firstTokensByLineNumber, by line from 1: -1 if none.
	first_of_line []i32
	indent_char   string
	// IndexMap: the descriptor of the offsets from each byte on, 0 if none starts there.
	index_map []i32
	// OffsetDescriptorStorage (descriptor 0 is the empty-slot sentinel).
	descriptors []StiDescriptor
	// _lockedFirstTokens (the token each token of `all` is locked to, -1 if none) and
	// _desiredIndentCache.
	locked []i32
	cache  []StiIndent
	// The sti_* flags of each token or comment of `all`: _desiredIndentCache has it, desired is
	// computing it, _ignoredTokens, parameterParens, ignoredNodeFirstTokens.
	flags []u8
	stack []int // the tokens desired is computing, reused from call to call
}

// The flags of a token.
const sti_cached = u8(1)
const sti_in_progress = u8(2)
const sti_ignored = u8(4)
const sti_param_paren = u8(8)
const sti_ignored_first = u8(16)

@[inline]
fn (s &StiState) has(ai int, flag u8) bool {
	return s.flags[ai] & flag != 0
}

@[inline]
fn (mut s StiState) mark(ai int, flag u8) {
	s.flags[ai] |= flag
}

@[inline]
fn (mut s StiState) unmark(ai int, flag u8) {
	s.flags[ai] &= ~flag
}

fn (mut c Checker) lint_stylistic_indent(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	opts := sti_options(c.rule_options(stylistic_indent))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut s := sti_new_state(t, tokens, c.src, opts)
	stats.checked += t.nodes.len
	// The ignored nodes, in the order ESLint adds them to its set: those of an `ignoredNodes`
	// selector when entering them, those of an unknown type when leaving them (`*:exit`).
	mut by_selector := []bool{len: t.nodes.len}
	if opts.ignored_nodes.len > 0 {
		for m in esquery.run(t, opts.ignored_nodes)! {
			by_selector[m.node] = true
		}
	}
	mut known := []i8{len: 256}
	mut is_ignored := []bool{len: t.nodes.len}
	mut ignored_nodes := []int{}
	mut walk := StiWalk{}
	walk.start(t)
	for {
		node, leave := walk.next(t)
		if node < 0 {
			break
		}
		if leave {
			typ := int(t.typ(node))
			if known[typ] == 0 {
				known[typ] = if t.typ(node).type_name() in sti_known_nodes { i8(1) } else { i8(2) }
			}
			if known[typ] == 1 {
				continue
			}
		} else if !by_selector[node] {
			continue
		}
		// addToIgnoredNodes
		first := s.first_token(node)
		if first >= 0 {
			s.mark(first, sti_ignored_first)
		}
		if !is_ignored[node] {
			is_ignored[node] = true
			ignored_nodes << node
		}
	}
	// Program:exit. With ignoreComments, every comment is ignored.
	if opts.ignore_comments {
		for ai, token in s.all {
			if token.is_comment() {
				s.ignore_token(ai)
			}
		}
	}
	// The queued offset listeners of the nodes that are not ignored, in the order of the
	// traversal: on entering a node `*` (the least specific selector), then its type's listener.
	walk.start(t)
	for {
		node, leave := walk.next(t)
		if node < 0 {
			break
		}
		if is_ignored[node] {
			continue
		}
		if leave {
			if t.typ(node) in [.do_while_statement, .for_statement, .for_in_statement,
				.for_of_statement, .if_statement, .while_statement, .with_statement] {
				s.statement_exit(node)
			}
			continue
		}
		s.any_node(node)
		s.enter(node, mut findings)
	}
	// Update the offsets of the ignored nodes so that their tokens are not reported.
	for node in ignored_nodes {
		s.ignore_node(node)
	}
	s.add_parens_indent()
	for i in 1 .. t.line_starts.len + 1 {
		first := int(s.first_of_line[i])
		if first < 0 {
			// Don't check indentation on blank lines.
			continue
		}
		if int(s.line[first]) != i {
			// Don't check the indentation of multi-line tokens twice.
			continue
		}
		if s.all[first].is_comment() {
			// precedingTokens: the token before the comment, comments skipped.
			mut before := first - 1
			for before >= 0 && s.all[before].is_comment() {
				before--
			}
			after := if before >= 0 {
				s.token_after(s.all[before].end, .any, '')
			} else if s.toks.len > 0 {
				int(s.tok_all[0])
			} else {
				-1
			}
			may_align_with_before := before >= 0 && !s.has_blank_lines_between(before, first)
			may_align_with_after := after >= 0 && !s.has_blank_lines_between(first, after)
			// A comment before a line that starts with a semicolon aligns with that semicolon.
			if after >= 0 && s.is(after, .semicolon) && !s.same_line(first, after) {
				s.set_offset(first, after, 0)
			}
			// A comment that matches the indentation of the token before or after is not reported.
			if (may_align_with_before && s.has_indent(first, s.desired(before)!))
				|| (may_align_with_after && s.has_indent(first, s.desired(after)!)) {
				continue
			}
		}
		desired := s.desired(first)!
		if s.has_indent(first, desired) {
			continue
		}
		findings << s.report(first, s.indent_text(desired))
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// StiWalk is the traversal of ESLint (EsTree.steps) without the array of its steps: the nodes
// to enter, and the nodes to leave as -2 - index.
struct StiWalk {
mut:
	stack []int
}

fn (mut w StiWalk) start(t &estree.EsTree) {
	w.stack.clear()
	if t.root >= 0 {
		w.stack << t.root
	}
}

// next is the next step of the traversal (a node, and whether it is left), -1 at the end.
fn (mut w StiWalk) next(t &estree.EsTree) (int, bool) {
	for w.stack.len > 0 {
		top := w.stack.pop()
		if top < -1 {
			node := -2 - top
			if t.visits(node) {
				return node, true
			}
			continue
		}
		w.stack << -2 - top
		// The children in reverse order, as EsTree.push_children_reversed.
		keys := estree.keys_of(t.nodes[top].typ)
		for k := keys.len - 1; k >= 0; k-- {
			p := t.prop(top, keys[k]) or { continue }
			match p.kind {
				.node {
					w.stack << p.idx
				}
				.list {
					items := t.lists[p.idx]
					for j := items.len - 1; j >= 0; j-- {
						if items[j] >= 0 {
							w.stack << items[j]
						}
					}
				}
				else {}
			}
		}
		if t.visits(top) {
			return top, false
		}
	}
	return -1, false
}

fn sti_new_state(t &estree.EsTree, tokens &SourceTokens, src string, opts StiOptions) StiState {
	all := tokens.all
	mut s := StiState{
		t:             unsafe { t }
		src:           src
		opts:          opts
		all:           all
		toks:          tokens.tokens
		tok_all:       []i32{cap: tokens.tokens.len}
		all_tok:       []i32{len: all.len, init: -1}
		line:          []i32{len: all.len}
		end_line:      []i32{len: all.len}
		first_of_line: []i32{len: t.line_starts.len + 2, init: -1}
		indent_char:   if opts.tab { '\t' } else { ' ' }
		index_map:     []i32{len: src.len + 1}
		descriptors:   []StiDescriptor{cap: 1024}
		locked:        []i32{len: all.len, init: -1}
		cache:         []StiIndent{len: all.len}
		flags:         []u8{len: all.len}
	}
	for ai, token in all {
		if !token.is_comment() {
			s.all_tok[ai] = i32(s.tok_all.len)
			s.tok_all << i32(ai)
		}
	}
	// The lines of the tokens, in one sweep (their starts and their ends grow with their index).
	starts := t.line_starts
	mut line := 0
	mut end_line := 0
	for ai, token in all {
		for line + 1 < starts.len && starts[line + 1] <= token.start {
			line++
		}
		if end_line < line {
			end_line = line
		}
		for end_line + 1 < starts.len && starts[end_line + 1] <= token.end {
			end_line++
		}
		s.line[ai] = i32(line + 1)
		s.end_line[ai] = i32(end_line + 1)
	}
	// TokenInfo: the first token of each line; a token that ends on a later line is also the first
	// one of that line when text precedes its end there.
	for ai, token in all {
		if int(s.first_of_line[int(s.line[ai])]) < 0 {
			s.first_of_line[int(s.line[ai])] = i32(ai)
		}
		el := int(int(s.end_line[ai]))
		if int(s.first_of_line[el]) < 0 && !sti_is_blank(src_view(src, starts[el - 1], token.end)) {
			s.first_of_line[el] = i32(ai)
		}
	}
	// Descriptor 0 is the empty-slot sentinel; the start of the file has offset 0 from nothing.
	s.create_descriptor(0, -1, false)
	s.index_map[0] = i32(s.create_descriptor(0, -1, false))
	return s
}

// sti_is_blank: `text.trim()` is empty.
fn sti_is_blank(text string) bool {
	mut i := 0
	for i < text.len {
		if !sti_space_at(text, i) {
			return false
		}
		i += utf8_char_len(text[i])
	}
	return true
}

// ---- Tokens (SourceCode's token queries, on token indexes) ----

// text is the text of a token or comment of `all`.
@[inline]
fn (s &StiState) text(ai int) string {
	return src_view(s.src, s.all[ai].start, s.all[ai].end)
}

// value is token.value: a comment without its delimiters, a PrivateIdentifier without its `#`.
fn (s &StiState) value(ai int) string {
	token := s.all[ai]
	return match token.kind {
		.line_comment, .shebang_comment { src_view(s.src, token.start + 2, token.end) }
		.block_comment { src_view(s.src, token.start + 2, token.end - 2) }
		.private_identifier { src_view(s.src, token.start + 1, token.end) }
		else { src_view(s.src, token.start, token.end) }
	}
}

// pass tests the token `k` of `toks` against a filter.
fn (s &StiState) pass(k int, f StiFilter, v string) bool {
	token := s.toks[k]
	if f == .any {
		return true
	}
	if f == .value {
		return s.value(int(s.tok_all[k])) == v
	}
	text := src_view(s.src, token.start, token.end)
	if f == .from_name {
		return token.kind == .identifier && text == 'from'
	}
	p := token.kind == .punctuator
	return match f {
		.open_paren { p && text == '(' }
		.close_paren { p && text == ')' }
		.not_open_paren { !(p && text == '(') }
		.not_close_paren { !(p && text == ')') }
		.open_brace { p && text == '{' }
		.close_brace { p && text == '}' }
		.open_bracket { p && text == '[' }
		.close_bracket { p && text == ']' }
		.eq { p && text == '=' }
		.colon { p && text == ':' }
		.question { p && text == '?' }
		.semicolon { p && text == ';' }
		.not_semicolon { !(p && text == ';') }
		.optional_chain { p && text == '?.' }
		else { false }
	}
}

// is tests a token of `all` (never a comment) against a filter.
fn (s &StiState) is(ai int, f StiFilter) bool {
	k := int(s.all_tok[ai])
	return k >= 0 && s.pass(k, f, '')
}

// first_token is getFirstToken(node): -1 if the node has no token.
fn (s &StiState) first_token(node int) int {
	return s.first_token_skip(node, 0)
}

// first_token_skip is getFirstToken(node, { skip }).
fn (s &StiState) first_token_skip(node int, skip int) int {
	k := source_tokens_index(s.toks, s.t.nodes[node].start) + skip
	if k < s.toks.len && s.toks[k].start < s.t.nodes[node].end {
		return int(s.tok_all[k])
	}
	return -1
}

// first_token_where is getFirstToken(node, filter).
fn (s &StiState) first_token_where(node int, f StiFilter, v string) int {
	end := s.t.nodes[node].end
	for k := source_tokens_index(s.toks, s.t.nodes[node].start); k < s.toks.len
		&& s.toks[k].start < end; k++ {
		if s.pass(k, f, v) {
			return int(s.tok_all[k])
		}
	}
	return -1
}

// last_token is getLastToken(node).
fn (s &StiState) last_token(node int) int {
	return s.last_token_skip(node, 0)
}

// last_token_skip is getLastToken(node, { skip }).
fn (s &StiState) last_token_skip(node int, skip int) int {
	k := source_tokens_index(s.toks, s.t.nodes[node].end) - 1 - skip
	if k >= 0 && s.toks[k].start >= s.t.nodes[node].start {
		return int(s.tok_all[k])
	}
	return -1
}

// last_token_where is getLastToken(node, filter).
fn (s &StiState) last_token_where(node int, f StiFilter, v string) int {
	start := s.t.nodes[node].start
	for k := source_tokens_index(s.toks, s.t.nodes[node].end) - 1; k >= 0
		&& s.toks[k].start >= start; k-- {
		if s.pass(k, f, v) {
			return int(s.tok_all[k])
		}
	}
	return -1
}

// token_before is getTokenBefore(what starts at `offset`, filter).
fn (s &StiState) token_before(offset int, f StiFilter, v string) int {
	for k := source_tokens_index(s.toks, offset) - 1; k >= 0; k-- {
		if s.pass(k, f, v) {
			return int(s.tok_all[k])
		}
	}
	return -1
}

// token_before_skip is getTokenBefore(what starts at `offset`, { skip }).
fn (s &StiState) token_before_skip(offset int, skip int) int {
	k := source_tokens_index(s.toks, offset) - 1 - skip
	return if k >= 0 { int(s.tok_all[k]) } else { -1 }
}

// token_after is getTokenAfter(what ends at `offset`, filter).
fn (s &StiState) token_after(offset int, f StiFilter, v string) int {
	for k := source_tokens_index(s.toks, offset); k < s.toks.len; k++ {
		if s.pass(k, f, v) {
			return int(s.tok_all[k])
		}
	}
	return -1
}

// first_between is getFirstTokenBetween(what ends at `left_end`, what starts at `right_start`,
// filter).
fn (s &StiState) first_between(left_end int, right_start int, f StiFilter, v string) int {
	for k := source_tokens_index(s.toks, left_end); k < s.toks.len
		&& s.toks[k].start < right_start; k++ {
		if s.pass(k, f, v) {
			return int(s.tok_all[k])
		}
	}
	return -1
}

// count_between is getTokensBetween(left, right, { filter }).length.
fn (s &StiState) count_between(left_end int, right_start int, f StiFilter) int {
	mut n := 0
	for k := source_tokens_index(s.toks, left_end); k < s.toks.len
		&& s.toks[k].start < right_start; k++ {
		if s.pass(k, f, '') {
			n++
		}
	}
	return n
}

// line_of is the line (from 1) of a byte offset.
fn (s &StiState) line_of(offset int) int {
	starts := s.t.line_starts
	mut lo := 0
	mut hi := starts.len
	for lo + 1 < hi {
		mid := (lo + hi) / 2
		if starts[mid] <= offset {
			lo = mid
		} else {
			hi = mid
		}
	}
	return lo + 1
}

// same_line is isTokenOnSameLine(left, right) of two tokens.
@[inline]
fn (s &StiState) same_line(left int, right int) bool {
	return int(s.end_line[left]) == int(s.line[right])
}

// nodes_same_line is isTokenOnSameLine(left, right) of two nodes.
fn (s &StiState) nodes_same_line(left int, right int) bool {
	return s.line_of(s.t.nodes[left].end) == s.line_of(s.t.nodes[right].start)
}

// single_line is isSingleLine(node).
fn (s &StiState) single_line(node int) bool {
	return s.line_of(s.t.nodes[node].start) == s.line_of(s.t.nodes[node].end)
}

// is_first_of_line is tokenInfo.isFirstTokenOfLine(token).
@[inline]
fn (s &StiState) is_first_of_line(ai int) bool {
	return int(s.first_of_line[int(s.line[ai])]) == ai
}

// token_indent is tokenInfo.getTokenIndent(token): the text of its line before it.
fn (s &StiState) token_indent(ai int) string {
	return src_view(s.src, s.t.line_starts[int(s.line[ai]) - 1], s.all[ai].start)
}

// column is token.loc.start.column (UTF-16 units).
fn (s &StiState) column(ai int) int {
	_, column := s.t.line_column(s.all[ai].start)
	return column
}

// has_blank_lines_between ports hasBlankLinesBetween.
fn (s &StiState) has_blank_lines_between(first int, second int) bool {
	first_line := int(s.end_line[first])
	second_line := int(s.line[second])
	if first_line == second_line || first_line == second_line - 1 {
		return false
	}
	for line in first_line + 1 .. second_line {
		if int(s.first_of_line[line]) < 0 {
			return true
		}
	}
	return false
}

// ---- OffsetStorage ----

fn (mut s StiState) create_descriptor(offset f64, from int, force bool) int {
	s.descriptors << StiDescriptor{
		offset: offset
		from:   i32(from)
		force:  force
	}
	return s.descriptors.len - 1
}

// find_last_not_after is IndexMap.findLastNotAfter.
@[direct_array_access]
fn (s &StiState) find_last_not_after(key int) int {
	mut i := if key < s.index_map.len { key } else { s.index_map.len - 1 }
	for ; i >= 0; i-- {
		v := s.index_map[i]
		if v != 0 {
			return int(v)
		}
	}
	return 0
}

// insert is IndexMap.insert (out of the map: ignored, as a typed array does).
@[inline]
fn (mut s StiState) insert(key int, value int) {
	if key >= 0 && key < s.index_map.len {
		s.index_map[key] = i32(value)
	}
}

// match_offset_of is OffsetStorage.matchOffsetOf.
fn (mut s StiState) match_offset_of(base int, offset_token int) {
	if offset_token >= 0 {
		s.locked[offset_token] = i32(base)
	}
}

// set_offset is OffsetStorage.setDesiredOffset.
fn (mut s StiState) set_offset(token int, from int, offset f64) {
	if token >= 0 {
		s.set_offsets(s.all[token].start, s.all[token].end, from, offset, false)
	}
}

// set_offsets is OffsetStorage.setDesiredOffsets([start, end], from, offset, force).
fn (mut s StiState) set_offsets(start int, end int, from int, offset f64, force bool) {
	descriptor := s.create_descriptor(offset, from, force)
	descriptor_after := s.find_last_not_after(end)
	from_in_range := from >= 0 && s.all[from].start >= start && s.all[from].end <= end
	from_descriptor := if from_in_range { s.find_last_not_after(s.all[from].start) } else { 0 }
	// deleteRange(start + 1, end)
	lo := math.max(start + 1, 0)
	hi := math.min(end, s.index_map.len)
	if hi > lo {
		unsafe { vmemset(&s.index_map[lo], 0, (hi - lo) * int(sizeof(i32))) }
	}
	s.insert(start, descriptor)
	if from_in_range {
		s.insert(s.all[from].start, from_descriptor)
		s.insert(s.all[from].end, descriptor)
	}
	s.insert(end, descriptor_after)
}

// first_dependency is OffsetStorage.getFirstDependency.
fn (s &StiState) first_dependency(ai int) int {
	return s.descriptors[s.find_last_not_after(s.all[ai].start)].from
}

// ignore_token is OffsetStorage.ignoreToken.
fn (mut s StiState) ignore_token(ai int) {
	if ai >= 0 && s.is_first_of_line(ai) {
		s.mark(ai, sti_ignored)
	}
}

// sti_starts_with_line_break: /^\s*?\n/u tests the text.
fn sti_starts_with_line_break(text string) bool {
	mut i := 0
	for i < text.len {
		if text[i] == `\n` {
			return true
		}
		if !sti_space_at(text, i) {
			return false
		}
		i += utf8_char_len(text[i])
	}
	return false
}

// sti_round is the count of `repeat(Math.round(count))` (NaN repeats nothing).
fn sti_round(count f64) int {
	if math.is_nan(count) || count < 0.5 {
		return 0
	}
	return int(math.floor(count + 0.5))
}

// sti_repeat is `unit.repeat(Math.round(count))`.
fn sti_repeat(unit string, count f64) string {
	n := sti_round(count)
	return if n > 0 { unit.repeat(n) } else { '' }
}

// StiDescriptor is an offset descriptor: `offset` levels from the token `from` (-1: none).
struct StiDescriptor {
	offset f64
	from   i32
	force  bool
}

// StiIndent is a desired indentation without its text: the indentation of the ignored token
// `root` (none when -1) and `count` indent characters after it. Every desired indentation has
// this form: an ignored token keeps its own indentation, the others add characters to the
// desired indentation of the token they depend on.
struct StiIndent {
	root  i32 = -1
	count int
}

// indent_text is the text of a desired indentation.
fn (s &StiState) indent_text(indent StiIndent) string {
	base := if indent.root >= 0 { s.token_indent(indent.root) } else { '' }
	return base + if indent.count > 0 { s.indent_char.repeat(indent.count) } else { '' }
}

// has_indent is `tokenInfo.getTokenIndent(token) === desiredIndent` (validateTokenIndent).
fn (s &StiState) has_indent(ai int, indent StiIndent) bool {
	actual := s.token_indent(ai)
	base := if indent.root >= 0 { s.token_indent(indent.root) } else { '' }
	if actual.len != base.len + indent.count || !actual.starts_with(base) {
		return false
	}
	c := s.indent_char[0]
	for i in base.len .. actual.len {
		if actual[i] != c {
			return false
		}
	}
	return true
}

// desired is OffsetStorage.getDesiredIndent, without the recursion (a chain of dependencies may
// be as long as the file); a cycle is the stack overflow ESLint would crash with.
fn (mut s StiState) desired(token int) !StiIndent {
	if s.has(token, sti_cached) {
		return s.cache[token]
	}
	s.stack.clear()
	s.stack << token
	s.mark(token, sti_in_progress)
	for s.stack.len > 0 {
		top := s.stack.last()
		if s.has(top, sti_ignored) {
			// An ignored token keeps its indentation.
			s.done(top, StiIndent{ root: i32(top) })
			continue
		}
		if int(s.locked[top]) >= 0 {
			base := int(s.locked[top])
			base_first := int(s.first_of_line[int(s.line[base])])
			if !s.has(base_first, sti_cached) {
				s.push(base_first)!
				continue
			}
			from_indent := s.cache[base_first]
			s.done(top, StiIndent{
				root:  from_indent.root
				count: from_indent.count + sti_round(f64(s.column(base) - s.column(base_first)))
			})
			continue
		}
		descriptor := s.descriptors[s.find_last_not_after(s.all[top].start)]
		from := int(descriptor.from)
		if from >= 0 && !s.has(from, sti_cached) {
			s.push(from)!
			continue
		}
		offset := if from >= 0 && int(s.line[from]) == int(s.line[top])
			&& !sti_starts_with_line_break(s.value(top)) && !descriptor.force {
			0.0
		} else {
			descriptor.offset * f64(s.opts.indent_size)
		}
		from_indent := if from >= 0 { s.cache[from] } else { StiIndent{} }
		s.done(top, StiIndent{
			root:  from_indent.root
			count: from_indent.count + sti_round(offset)
		})
	}
	return s.cache[token]
}

fn (mut s StiState) push(ai int) ! {
	if s.has(ai, sti_in_progress) {
		return error('Maximum call stack size exceeded')
	}
	s.mark(ai, sti_in_progress)
	s.stack << ai
}

fn (mut s StiState) done(ai int, value StiIndent) {
	s.cache[ai] = value
	s.mark(ai, sti_cached)
	s.unmark(ai, sti_in_progress)
	s.stack.delete_last()
}

// ---- Handlers (utils/handlers.ts) ----

// element_first_token is the getFirstToken of addElementListIndent: the first token of the element
// with its opening parentheses, which are not `start`.
fn (s &StiState) element_first_token(element int, start int) int {
	mut k := source_tokens_index(s.toks, s.t.nodes[element].start) - 1
	for k >= 0 && s.pass(k, .open_paren, '') && int(s.tok_all[k]) != start {
		k--
	}
	if k + 1 < s.toks.len {
		return int(s.tok_all[k + 1])
	}
	return -1
}

// sti_count_trailing_linebreaks ports countTrailingLinebreaks.
fn sti_count_trailing_linebreaks(text string) int {
	// Only a text that ends with white space has line breaks after its last character (JSXText).
	if text.len == 0 || !sti_space_at(text, sti_last_char_start(text)) {
		return 0
	}
	runes := text.runes()
	mut i := runes.len
	for i > 0 && is_js_space(runes[i - 1]) {
		i--
	}
	mut n := 0
	mut j := i
	for j < runes.len {
		r := runes[j]
		if r == `\r` && j + 1 < runes.len && runes[j + 1] == `\n` {
			n++
			j += 2
			continue
		}
		if r in [`\r`, `\n`, ` `, ` `] {
			n++
		}
		j++
	}
	return n
}

// sti_last_char_start is the byte offset of the last character of a non-empty text.
fn sti_last_char_start(text string) int {
	mut i := text.len - 1
	for i > 0 && text[i] & 0xc0 == 0x80 {
		i--
	}
	return i
}

// add_element_list_indent ports addElementListIndent.
fn (mut s StiState) add_element_list_indent(elements []int, start int, end int, offset StiOff) {
	if start < 0 || end < 0 || s.same_line(start, end) {
		return
	}
	// Offset every token in the list by one level (mainly for comments; the others are overridden).
	s.set_offsets(s.all[start].end, s.all[end].start, start, if offset.kind == .number {
		offset.num
	} else {
		1
	}, false)
	s.set_offset(end, start, 0)
	// "first" without a first element (a sparse array with a hole first): one level.
	if offset.kind == .first && elements.len > 0 && elements[0] < 0 {
		return
	}
	for index, element in elements {
		if element < 0 {
			// Skip holes in arrays.
			continue
		}
		if offset.kind == .off {
			// Ignore the first token of every element with "off".
			s.ignore_token(s.element_first_token(element, start))
		}
		// Offset the following elements relative to the first element.
		if index == 0 {
			continue
		}
		if offset.kind == .first && s.is_first_of_line_or_none(s.element_first_token(element, start)) {
			s.match_offset_of(s.element_first_token(elements[0], start), s.element_first_token(element,
				start))
		} else {
			previous := elements[index - 1]
			if previous < 0 {
				continue
			}
			first_of_previous := s.element_first_token(previous, start)
			last_of_previous := s.last_token(previous)
			if last_of_previous < 0 {
				continue
			}
			if int(s.end_line[last_of_previous]) - sti_count_trailing_linebreaks(s.value(last_of_previous)) > int(s.end_line[start]) {
				s.set_offsets(s.t.nodes[previous].end, s.t.nodes[element].end, first_of_previous,
					0, false)
			}
		}
	}
}

fn (s &StiState) is_first_of_line_or_none(ai int) bool {
	return ai >= 0 && s.is_first_of_line(ai)
}

// add_blockless_node_indent ports addBlocklessNodeIndent.
fn (mut s StiState) add_blockless_node_indent(node int) {
	if node < 0 || s.t.typ(node) == .block_statement {
		return
	}
	last_parent := s.token_before(s.t.nodes[node].start, .not_open_paren, '')
	mut first_body := s.first_token(node)
	mut last_body := s.last_token(node)
	if first_body < 0 || last_body < 0 {
		return
	}
	for {
		before := s.token_before(s.all[first_body].start, .any, '')
		after := s.token_after(s.all[last_body].end, .any, '')
		if before < 0 || after < 0 || !s.is(before, .open_paren) || !s.is(after, .close_paren) {
			break
		}
		first_body = before
		last_body = after
	}
	s.set_offsets(s.all[first_body].start, s.all[last_body].end, last_parent, 1, false)
}

// add_function_call_indent ports addFunctionCallIndent.
fn (mut s StiState) add_function_call_indent(node int) {
	t := s.t
	args := t.list(node, .arguments) or { []int{} }
	callee := t.node(node, .callee) or { return }
	type_arguments := t.node(node, .type_arguments) or { -1 }
	opening := if args.len > 0 {
		after := if type_arguments >= 0 { type_arguments } else { callee }
		s.token_after(t.nodes[after].end, .open_paren, '')
	} else {
		s.last_token_skip(node, 1)
	}
	closing := s.last_token(node)
	if opening < 0 || closing < 0 {
		return
	}
	s.mark(opening, sti_param_paren)
	s.mark(closing, sti_param_paren)
	// The `?.` of an optional call, as for a MemberExpression.
	if t.typ(node) == .call_expression && (t.flag(node, .optional) or { false }) {
		dot := s.token_after(t.nodes[callee].end, .optional_chain, '')
		if dot >= 0 {
			paren_count := s.count_between(t.nodes[callee].end, s.all[dot].start, .close_paren)
			first_of_callee := if paren_count > 0 {
				s.token_before_skip(t.nodes[callee].start, paren_count - 1)
			} else {
				s.first_token(callee)
			}
			last_of_callee := s.token_before(s.all[dot].start, .any, '')
			base := if last_of_callee >= 0 && s.same_line(last_of_callee, opening) {
				last_of_callee
			} else {
				first_of_callee
			}
			s.set_offset(dot, base, 1)
		}
	}
	offset_after := if t.typ(callee) == .tagged_template_expression {
		quasi := t.node(callee, .quasi) or { -1 }
		first := if quasi >= 0 { s.first_token(quasi) } else { -1 }
		if first >= 0 { s.all[first].start } else { s.all[opening].start }
	} else if type_arguments >= 0 {
		t.nodes[type_arguments].start
	} else {
		s.all[opening].start
	}
	s.set_offset(opening, s.token_before(offset_after, .any, ''), 0)
	s.add_element_list_indent(args, opening, closing, s.opts.call_arguments)
}

// add_parens_indent ports addParensIndent.
fn (mut s StiState) add_parens_indent() {
	mut stack := []int{}
	mut lefts := []int{}
	mut rights := []int{}
	for k in 0 .. s.toks.len {
		if s.pass(k, .open_paren, '') {
			stack << k
		} else if s.pass(k, .close_paren, '') {
			lefts << if stack.len > 0 { stack.pop() } else { -1 }
			rights << k
		}
	}
	for i := lefts.len - 1; i >= 0; i-- {
		if lefts[i] < 0 {
			continue
		}
		left := int(s.tok_all[lefts[i]])
		right := int(s.tok_all[rights[i]])
		if s.same_line(left, right) {
			continue
		}
		// Only parentheses around expressions: not those of parameters and arguments.
		if !s.has(left, sti_param_paren) && !s.has(right, sti_param_paren) {
			for k in lefts[i] + 1 .. rights[i] {
				ai := int(s.tok_all[k])
				dependency := s.first_dependency(ai)
				in_parens := dependency >= 0 && int(s.all_tok[dependency]) > lefts[i]
					&& int(s.all_tok[dependency]) < rights[i]
				if !in_parens {
					s.set_offset(ai, left, 1)
				}
			}
		}
		s.set_offset(right, left, 0)
	}
}

// ignore_node ports ignoreNode: the tokens of an unknown node whose offset does not depend on
// another of its tokens keep their indentation.
fn (mut s StiState) ignore_node(node int) {
	lo := source_tokens_index(s.all, s.t.nodes[node].start)
	hi := source_tokens_index(s.all, s.t.nodes[node].end)
	for ai in lo .. hi {
		dependency := s.first_dependency(ai)
		if dependency < 0 || dependency < lo || dependency >= hi {
			first_of_line := int(s.first_of_line[int(s.line[ai])])
			if ai == first_of_line {
				s.ignore_token(ai)
			} else {
				s.set_offset(ai, first_of_line, 0)
			}
		}
	}
}

// is_on_first_line_of_statement ports isOnFirstLineOfStatement.
fn (s &StiState) is_on_first_line_of_statement(token int, leaf int) bool {
	t := s.t
	mut node := leaf
	for t.nodes[node].parent >= 0 {
		name := t.typ(t.nodes[node].parent).type_name()
		if name.ends_with('Statement') || name.ends_with('Declaration') {
			break
		}
		node = t.nodes[node].parent
	}
	parent := t.nodes[node].parent
	return parent < 0 || s.line_of(t.nodes[parent].start) == int(s.line[token])
}

// check_assignment_operator ports checkAssignmentOperator.
fn (mut s StiState) check_assignment_operator(operator int) {
	if operator < 0 {
		return
	}
	left := s.token_before(s.all[operator].start, .any, '')
	right := s.token_after(s.all[operator].end, .any, '')
	if s.opts.assignment_operator.kind == .number {
		s.set_offset(operator, left, s.opts.assignment_operator.num)
		s.set_offset(right, operator, s.opts.assignment_operator.num)
	} else {
		s.ignore_token(operator)
		s.ignore_token(right)
	}
}

// check_array_like_node ports checkArrayLikeNode.
fn (mut s StiState) check_array_like_node(node int) {
	t := s.t
	key := if t.typ(node) == .ts_tuple_type {
		estree.Key.element_types
	} else {
		estree.Key.elements
	}
	elements := t.list(node, key) or { []int{} }
	opening := s.first_token(node)
	if opening < 0 {
		return
	}
	mut after := s.all[opening].end
	for i := elements.len - 1; i >= 0; i-- {
		if elements[i] >= 0 {
			after = t.nodes[elements[i]].end
			break
		}
	}
	closing := s.token_after(after, .close_bracket, '')
	s.add_element_list_indent(elements, opening, closing, s.opts.array_expression)
}

// check_object_like_node ports checkObjectLikeNode.
fn (mut s StiState) check_object_like_node(node int, properties []int) {
	opening := s.first_token_where(node, .open_brace, '')
	if opening < 0 {
		return
	}
	after := if properties.len > 0 {
		s.t.nodes[properties.last()].end
	} else {
		s.all[opening].end
	}
	closing := s.token_after(after, .close_brace, '')
	s.add_element_list_indent(properties, opening, closing, s.opts.object_expression)
}

// check_conditional_node ports checkConditionalNode.
fn (mut s StiState) check_conditional_node(node int, test int, consequent int, alternate int) {
	t := s.t
	if test < 0 || consequent < 0 || alternate < 0 {
		return
	}
	first := s.first_token(node)
	if s.opts.flat_ternary && s.nodes_same_line(test, consequent)
		&& !s.is_on_first_line_of_statement(first, node) {
		return
	}
	// A conditional type chained in the alternate of another one and written compactly aligns
	// with the enclosing chain.
	parent := t.nodes[node].parent
	aligns := t.typ(node) == .ts_conditional_type && parent >= 0
		&& t.typ(parent) == .ts_conditional_type
		&& (t.node(parent, .false_type) or { -1 }) == node && s.nodes_same_line(test, consequent)
	question := s.first_between(t.nodes[test].end, t.nodes[consequent].start, .question, '')
	colon := s.first_between(t.nodes[consequent].end, t.nodes[alternate].start, .colon, '')
	if question < 0 || colon < 0 {
		return
	}
	first_consequent := s.token_after(s.all[question].end, .any, '')
	last_consequent := s.token_before(s.all[colon].start, .any, '')
	first_alternate := s.token_after(s.all[colon].end, .any, '')
	operator_offset := if aligns { 0.0 } else { 1.0 }
	s.set_offset(question, first, operator_offset)
	s.set_offset(colon, first, operator_offset)
	s.check_branch(consequent, first_consequent, first, aligns)
	// The alternate aligns with the consequent when they share a line.
	if last_consequent >= 0 && first_alternate >= 0 && s.same_line(last_consequent, first_alternate) {
		s.set_offset(first_alternate, first_consequent, 0)
	} else {
		s.check_branch(alternate, first_alternate, first, aligns)
	}
}

// check_branch is checkBranch of checkConditionalNode.
fn (mut s StiState) check_branch(branch int, branch_first int, first int, aligns bool) {
	if branch_first < 0 {
		return
	}
	mut offset := if aligns { 0.0 } else { 1.0 }
	if !aligns && s.opts.offset_ternary {
		mut inner := branch
		if s.t.typ(inner) == .chain_expression {
			inner = s.t.node(inner, .expression) or { inner }
		}
		enabled := match s.t.typ(inner) {
			.call_expression { s.opts.ternary_call }
			.await_expression { s.opts.ternary_await }
			.new_expression { s.opts.ternary_new }
			else { false }
		}
		if s.all[branch_first].kind == .punctuator || enabled {
			offset = 2
		}
	}
	s.set_offset(branch_first, first, offset)
}

// check_operator_token ports checkOperatorToken.
fn (mut s StiState) check_operator_token(left int, right int, operator string) {
	if left < 0 || right < 0 {
		return
	}
	token := s.first_between(s.t.nodes[left].end, s.t.nodes[right].start, .value, operator)
	if token < 0 {
		return
	}
	after := s.token_after(s.all[token].end, .any, '')
	s.ignore_token(token)
	s.ignore_token(after)
	s.set_offset(after, token, 0)
}

// check_member_expression ports checkMemberExpression.
fn (mut s StiState) check_member_expression(node int, object int, property int, computed bool) {
	t := s.t
	if object < 0 || property < 0 {
		return
	}
	first_non_object := s.first_between(t.nodes[object].end, t.nodes[property].start, .not_close_paren,
		'')
	if first_non_object < 0 {
		return
	}
	second_non_object := s.token_after(s.all[first_non_object].end, .any, '')
	paren_count := s.count_between(t.nodes[object].end, t.nodes[property].start, .close_paren)
	first_object := if paren_count > 0 {
		s.token_before_skip(t.nodes[object].start, paren_count - 1)
	} else {
		s.first_token(object)
	}
	last_object := s.token_before(s.all[first_non_object].start, .any, '')
	first_property := if computed { first_non_object } else { second_non_object }
	if computed {
		// The closing bracket matches the opening one.
		s.set_offset(s.last_token(node), first_non_object, 0)
		s.set_offsets(t.nodes[property].start, t.nodes[property].end, first_non_object, 1,
			false)
	}
	// The object ends on the line where the property starts: offset from its last token.
	base := if last_object >= 0 && first_property >= 0 && s.same_line(last_object, first_property) {
		last_object
	} else {
		first_object
	}
	if s.opts.member_expression.kind == .number {
		s.set_offset(first_non_object, base, s.opts.member_expression.num)
		s.set_offset(second_non_object, if computed { first_non_object } else { base },
			s.opts.member_expression.num)
	} else {
		s.ignore_token(first_non_object)
		s.ignore_token(second_non_object)
		s.set_offset(first_non_object, base, 0)
		s.set_offset(second_non_object, first_non_object, 0)
	}
}

// is_outer_iife ports isOuterIIFE.
fn (s &StiState) is_outer_iife(node int) bool {
	t := s.t
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression
		|| (t.node(parent, .callee) or { -1 }) != node {
		return false
	}
	mut statement := t.nodes[parent].parent
	for statement >= 0 {
		typ := t.typ(statement)
		if (typ == .unary_expression
			&& (t.string_of(statement, .operator) or { '' }) in ['!', '~', '+', '-'])
			|| typ in [.assignment_expression, .logical_expression, .sequence_expression,
				.variable_declarator] {
			statement = t.nodes[statement].parent
			continue
		}
		break
	}
	if statement < 0 || t.typ(statement) !in [.expression_statement, .variable_declaration] {
		return false
	}
	grand := t.nodes[statement].parent
	return grand >= 0 && t.typ(grand) == .program
}

// check_block_like_node ports checkBlockLikeNode.
fn (mut s StiState) check_block_like_node(node int) {
	t := s.t
	parent := t.nodes[node].parent
	level := if parent >= 0 && s.is_outer_iife(parent) {
		s.opts.outer_iife_body
	} else if parent >= 0 && t.typ(parent) in [.function_expression, .arrow_function_expression] {
		StiOff{.number, s.opts.fe_body}
	} else if parent >= 0 && t.typ(parent) == .function_declaration {
		StiOff{.number, s.opts.fd_body}
	} else {
		StiOff{.number, 1}
	}
	first := s.first_token(node)
	// A block that is not a lone statement: its opening brace aligns with the parent.
	if parent >= 0 && t.typ(parent) !in [.program, .block_statement, .static_block, .switch_case] {
		s.set_offset(first, s.first_token(parent), 0)
	}
	key := if t.typ(node) == .ts_enum_body { estree.Key.members } else { estree.Key.body }
	elements := t.list(node, key) or { []int{} }
	s.add_element_list_indent(elements, first, s.last_token(node), level)
}

// check_heritages ports checkHeritages.
fn (mut s StiState) check_heritages(node int, first_heritage int) {
	t := s.t
	class_token := s.first_token(node)
	extends_token := s.token_before(t.nodes[first_heritage].start, .not_open_paren, '')
	body := t.node(node, .body) or { return }
	if extends_token < 0 {
		return
	}
	s.set_offsets(s.all[extends_token].start, t.nodes[body].start, class_token, 1, false)
}

// check_class_property ports checkClassProperty.
fn (mut s StiState) check_class_property(node int) {
	t := s.t
	first := s.first_token(node)
	last := s.last_token(node)
	key := t.node(node, .key) or { return }
	mut key_last := -1
	if t.flag(node, .computed) or { false } {
		left := s.token_before(t.nodes[key].start, .open_bracket, '')
		right := s.token_after(t.nodes[key].end, .close_bracket, '')
		if left < 0 || right < 0 {
			return
		}
		key_last = right
		if left != first {
			s.set_offset(left, first, 0)
		}
		s.set_offsets(s.all[left].end, s.all[right].start, left, 1, false)
		s.set_offset(right, left, 0)
	} else {
		id := s.first_token(key)
		key_last = id
		decorators := t.list(node, .decorators) or { []int{} }
		if decorators.len == 0 && id != first {
			s.set_offset(id, first, 1)
		}
	}
	// The initializer.
	if value := t.node(node, .value) {
		operator := s.token_before(t.nodes[value].start, .eq, '')
		s.check_assignment_operator(operator)
		if last >= 0 && s.is(last, .semicolon) {
			s.set_offset(last, operator, 1)
		}
	} else if last >= 0 && s.is(last, .semicolon) {
		s.set_offset(last, key_last, 1)
	}
}

// ---- Listeners (indent.ts) ----

// any_node is the `*` listener: the children of a node are indented at least as much as its first
// token.
fn (mut s StiState) any_node(node int) {
	first := s.first_token(node)
	if first >= 0 && !s.has(first, sti_ignored_first) && !s.single_line(node) {
		s.set_offsets(s.t.nodes[node].start, s.t.nodes[node].end, first, 0, false)
	}
}

// statement_exit is the `:exit` listener of the statements with a body: the `;` of a
// semicolon-first line after a blockless body is not indented.
fn (mut s StiState) statement_exit(node int) {
	t := s.t
	mut bodies := []int{}
	if t.typ(node) == .if_statement {
		bodies << t.node(node, .consequent) or { -1 }
		if alternate := t.node(node, .alternate) {
			bodies << alternate
		}
	} else {
		bodies << t.node(node, .body) or { -1 }
	}
	for body in bodies {
		if body < 0 {
			continue
		}
		last := s.last_token(body)
		if last < 0 || !s.is(last, .semicolon) {
			continue
		}
		before := s.token_before(s.all[last].start, .any, '')
		after := s.token_after(s.all[last].end, .any, '')
		if before >= 0 && !s.same_line(before, last) && after >= 0 && s.same_line(last, after) {
			s.set_offset(last, s.first_token(node), 0)
		}
	}
}

// enter is the listener of the node's type.
fn (mut s StiState) enter(node int, mut findings []Finding) {
	t := s.t
	match t.typ(node) {
		.array_expression, .array_pattern, .ts_tuple_type {
			s.check_array_like_node(node)
		}
		.object_expression, .object_pattern {
			s.check_object_like_node(node, t.list(node, .properties) or { []int{} })
		}
		.arrow_function_expression {
			is_async := t.flag(node, .async) or { false }
			maybe_opening := s.first_token_skip(node, if is_async { 1 } else { 0 })
			body := t.node(node, .body) or { -1 }
			if maybe_opening >= 0 && s.is(maybe_opening, .open_paren) {
				before := t.node(node, .return_type) or { body }
				closing := if before >= 0 {
					s.token_before(t.nodes[before].start, .close_paren, '')
				} else {
					-1
				}
				if closing >= 0 {
					s.mark(maybe_opening, sti_param_paren)
					s.mark(closing, sti_param_paren)
					s.add_element_list_indent(t.list(node, .params) or { []int{} }, maybe_opening,
						closing, s.opts.fe_parameters)
				}
			}
			s.add_blockless_node_indent(body)
		}
		.assignment_expression {
			left := t.node(node, .left) or { return }
			right := t.node(node, .right) or { return }
			operator := t.string_of(node, .operator) or { '' }
			s.check_assignment_operator(s.first_between(t.nodes[left].end, t.nodes[right].start,
				.value, operator))
		}
		.assignment_pattern {
			left := t.node(node, .left) or { return }
			right := t.node(node, .right) or { return }
			s.check_assignment_operator(s.first_between(t.nodes[left].end, t.nodes[right].start,
				.eq, ''))
		}
		.binary_expression, .logical_expression {
			s.check_operator_token(t.node(node, .left) or { -1 }, t.node(node, .right) or { -1 },
				t.string_of(node, .operator) or { '' })
		}
		.block_statement, .class_body, .ts_enum_body, .ts_interface_body, .ts_module_block {
			s.check_block_like_node(node)
		}
		.call_expression {
			s.add_function_call_indent(node)
		}
		.class_declaration, .class_expression {
			if super_class := t.node(node, .super_class) {
				s.check_heritages(node, super_class)
			}
		}
		.conditional_expression {
			s.check_conditional_node(node, t.node(node, .test) or { -1 }, t.node(node, .consequent) or {
				-1
			}, t.node(node, .alternate) or { -1 })
		}
		.do_while_statement, .while_statement, .for_in_statement, .for_of_statement,
		.with_statement {
			s.add_blockless_node_indent(t.node(node, .body) or { -1 })
		}
		.export_named_declaration {
			if _ := t.node(node, .declaration) {
				return
			}
			s.export_specifiers(node)
		}
		.export_all_declaration {
			exported := t.node(node, .exported) or { -1 }
			after := if exported >= 0 {
				t.nodes[exported].end
			} else {
				first := s.first_token(node)
				if first < 0 {
					return
				}
				s.all[first].end
			}
			from := s.token_after(after, .from_name, '')
			last := s.last_token_where(node, .not_semicolon, '')
			if from >= 0 && last >= 0 {
				// Indent everything from the `from` of `export * from 'qux'` on.
				s.set_offsets(s.all[from].start, s.all[last].end, s.first_token(node), 1,
					false)
			}
			s.export_attributes(node)
		}
		.for_statement {
			opening := s.first_token_skip(node, 1)
			for key in [estree.Key.init, .test, .update] {
				if part := t.node(node, key) {
					s.set_offsets(t.nodes[part].start, t.nodes[part].end, opening, 1, false)
				}
			}
			s.add_blockless_node_indent(t.node(node, .body) or { -1 })
		}
		.function_declaration, .function_expression {
			s.function_params(node)
		}
		.if_statement {
			s.add_blockless_node_indent(t.node(node, .consequent) or { -1 })
			if alternate := t.node(node, .alternate) {
				s.add_blockless_node_indent(alternate)
			}
		}
		.import_declaration {
			s.import_declaration(node)
		}
		.import_expression {
			opening := s.first_token_skip(node, 1)
			closing := s.last_token(node)
			if opening < 0 || closing < 0 {
				return
			}
			s.mark(opening, sti_param_paren)
			s.mark(closing, sti_param_paren)
			s.set_offset(opening, s.token_before(s.all[opening].start, .any, ''), 0)
			source := t.node(node, .source) or { return }
			s.add_element_list_indent([source], opening, closing, s.opts.call_arguments)
		}
		.member_expression {
			s.check_member_expression(node, t.node(node, .object) or { -1 }, t.node(node, .property) or {
				-1
			}, t.flag(node, .computed) or { false })
		}
		.meta_property {
			s.check_member_expression(node, t.node(node, .meta) or { -1 }, t.node(node, .property) or {
				-1
			}, false)
		}
		.new_expression {
			// Only with parentheses (`new Foo(bar)`, `new Foo()`, not `new Foo`).
			args := t.list(node, .arguments) or { []int{} }
			last := s.last_token(node)
			before_last := s.last_token_skip(node, 1)
			if args.len > 0 || (last >= 0 && s.is(last, .close_paren) && before_last >= 0
				&& s.is(before_last, .open_paren)) {
				s.add_function_call_indent(node)
			}
		}
		.property {
			if (t.flag(node, .shorthand) or { false }) || (t.flag(node, .method) or { false })
				|| (t.string_of(node, .kind) or { '' }) != 'init' {
				return
			}
			key := t.node(node, .key) or { return }
			value := t.node(node, .value) or { return }
			colon := s.first_between(t.nodes[key].end, t.nodes[value].start, .colon, '')
			if colon < 0 {
				return
			}
			s.set_offset(s.token_after(s.all[colon].end, .any, ''), colon, 1)
		}
		.property_definition, .accessor_property, .ts_abstract_property_definition,
		.ts_abstract_accessor_property {
			s.check_class_property(node)
		}
		.static_block {
			s.add_element_list_indent(t.list(node, .body) or { []int{} }, s.first_token_skip(node,
				1), s.last_token(node), StiOff{.number, s.opts.static_block_body})
		}
		.switch_statement {
			discriminant := t.node(node, .discriminant) or { return }
			opening := s.token_after(t.nodes[discriminant].end, .open_brace, '')
			closing := s.last_token(node)
			if opening < 0 || closing < 0 {
				return
			}
			s.set_offsets(s.all[opening].end, s.all[closing].start, opening, s.opts.switch_case,
				false)
			cases := t.list(node, .cases) or { []int{} }
			if cases.len > 0 {
				lo := source_tokens_index(s.all, t.nodes[cases.last()].end)
				hi := source_tokens_index(s.all, s.all[closing].start)
				for ai in lo .. hi {
					if s.all[ai].is_comment() {
						s.ignore_token(ai)
					}
				}
			}
		}
		.switch_case {
			consequent := t.list(node, .consequent) or { []int{} }
			if consequent.len == 1 && t.typ(consequent[0]) == .block_statement {
				return
			}
			keyword := s.first_token(node)
			after := s.token_after(t.nodes[node].end, .any, '')
			if keyword < 0 || after < 0 {
				return
			}
			s.set_offsets(s.all[keyword].end, s.all[after].start, keyword, 1, false)
		}
		.template_literal {
			s.template_literal(node)
		}
		.variable_declaration {
			s.variable_declaration(node)
		}
		.variable_declarator {
			if init := t.node(node, .init) {
				s.check_assignment_operator(s.token_before(t.nodes[init].start, .not_open_paren,
					''))
			}
			last := s.last_token(node)
			if last >= 0 && s.is(last, .semicolon) {
				s.ignore_token(last)
			}
		}
		.jsx_text {
			s.jsx_text(node, mut findings)
		}
		.jsx_attribute {
			value := t.node(node, .value) or { return }
			name := t.node(node, .name) or { return }
			s.check_assignment_operator(s.first_between(t.nodes[name].end, t.nodes[value].start,
				.eq, ''))
		}
		.jsx_element {
			if closing_element := t.node(node, .closing_element) {
				opening_element := t.node(node, .opening_element) or { return }
				s.add_element_list_indent(t.list(node, .children) or { []int{} }, s.first_token(opening_element),
					s.first_token(closing_element), StiOff{.number, s.opts.jsx_offset})
			}
		}
		.jsx_opening_element {
			first := s.first_token(node)
			mut closing := -1
			if t.flag(node, .self_closing) or { false } {
				closing = s.last_token_skip(node, 1)
				s.set_offset(s.last_token(node), closing, 0)
			} else {
				closing = s.last_token(node)
			}
			if name := t.node(node, .name) {
				s.set_offsets(t.nodes[name].start, t.nodes[name].end, first, 0, false)
			}
			s.add_element_list_indent(t.list(node, .attributes) or { []int{} }, first, closing,
				StiOff{.number, s.opts.jsx_offset})
		}
		.jsx_closing_element {
			if name := t.node(node, .name) {
				s.set_offsets(t.nodes[name].start, t.nodes[name].end, s.first_token(node),
					s.opts.jsx_offset, false)
			}
		}
		.jsx_fragment {
			opening := t.node(node, .opening_fragment) or { return }
			closing := t.node(node, .closing_fragment) or { return }
			s.add_element_list_indent(t.list(node, .children) or { []int{} }, s.first_token(opening),
				s.first_token(closing), StiOff{.number, s.opts.jsx_offset})
		}
		.jsx_opening_fragment {
			first := s.first_token(node)
			s.set_offsets(t.nodes[node].start, t.nodes[node].end, first, s.opts.jsx_offset,
				false)
			s.match_offset_of(first, s.last_token(node))
		}
		.jsx_closing_fragment {
			first := s.first_token(node)
			closing := s.last_token(node)
			s.set_offsets(t.nodes[node].start, t.nodes[node].end, first, s.opts.jsx_offset,
				false)
			slash := s.last_token_where(node, .value, '/')
			if slash >= 0 && closing >= 0 {
				s.match_offset_of(first, if s.same_line(slash, closing) { slash } else { closing })
			}
		}
		.jsx_expression_container, .jsx_spread_attribute {
			opening := s.first_token(node)
			closing := s.last_token(node)
			if opening < 0 || closing < 0 {
				return
			}
			s.set_offsets(s.all[opening].end, s.all[closing].start, opening, s.opts.jsx_offset,
				false)
		}
		.jsx_member_expression {
			s.check_member_expression(node, t.node(node, .object) or { -1 }, t.node(node, .property) or {
				-1
			}, false)
		}
		.ts_type_annotation {
			// The return types of functions are handled by their listener.
			parent := t.nodes[node].parent
			if parent >= 0 && t.typ(parent) in [.function_declaration, .function_expression] {
				return
			}
			colon := s.first_token(node)
			if colon < 0 {
				return
			}
			s.set_offset(s.token_after(s.all[colon].end, .any, ''), colon, 1)
		}
		.ts_type_alias_declaration {
			if annotation := t.node(node, .type_annotation) {
				s.check_assignment_operator(s.token_before(t.nodes[annotation].start, .not_open_paren,
					''))
			}
			s.ignore_last_semicolon(node)
		}
		.ts_enum_member {
			if initializer := t.node(node, .initializer) {
				s.check_assignment_operator(s.token_before(t.nodes[initializer].start, .eq,
					''))
			}
		}
		.ts_type_literal {
			s.check_object_like_node(node, t.list(node, .members) or { []int{} })
		}
		.ts_mapped_type {
			start := s.first_token_where(node, .open_brace, '')
			end := s.last_token_where(node, .close_brace, '')
			if start < 0 || end < 0 {
				return
			}
			s.set_offsets(s.all[start].end, s.all[end].start, start, 1, false)
			s.set_offset(end, start, 0)
		}
		.ts_as_expression {
			s.check_operator_token(t.node(node, .expression) or { -1 }, t.node(node, .type_annotation) or {
				-1
			}, 'as')
		}
		.ts_satisfies_expression {
			s.check_operator_token(t.node(node, .expression) or { -1 }, t.node(node, .type_annotation) or {
				-1
			}, 'satisfies')
		}
		.ts_conditional_type {
			s.check_conditional_node(node, t.node(node, .extends_type) or { -1 }, t.node(node,
				.true_type) or { -1 }, t.node(node, .false_type) or { -1 })
		}
		.ts_import_equals_declaration {
			if reference := t.node(node, .module_reference) {
				s.check_assignment_operator(s.token_before(t.nodes[reference].start, .eq, ''))
			}
			s.ignore_last_semicolon(node)
		}
		.ts_indexed_access_type {
			s.check_member_expression(node, t.node(node, .object_type) or { -1 }, t.node(node,
				.index_type) or { -1 }, true)
		}
		.ts_interface_declaration {
			heritages := t.list(node, .extends_) or { []int{} }
			if heritages.len > 0 {
				s.check_heritages(node, heritages[0])
			}
		}
		.ts_qualified_name {
			s.check_member_expression(node, t.node(node, .left) or { -1 }, t.node(node, .right) or {
				-1
			}, false)
		}
		.ts_type_parameter {
			if default_ := t.node(node, .default_) {
				s.check_assignment_operator(s.token_before(t.nodes[default_].start, .eq, ''))
			}
		}
		.ts_type_parameter_declaration, .ts_type_parameter_instantiation {
			params := t.list(node, .params) or { []int{} }
			if params.len > 0 {
				s.add_element_list_indent(params, s.first_token(node), s.last_token(node),
					StiOff{.number, 1})
			}
		}
		else {}
	}
}

fn (mut s StiState) ignore_last_semicolon(node int) {
	last := s.last_token(node)
	if last >= 0 && s.is(last, .semicolon) {
		s.ignore_token(last)
	}
}

// export_specifiers is the ExportNamedDeclaration listener of `export {foo, bar} from 'qux'`.
fn (mut s StiState) export_specifiers(node int) {
	t := s.t
	source := t.node(node, .source) or { -1 }
	closing := if source >= 0 {
		s.token_before(t.nodes[source].start, .close_brace, '')
	} else {
		s.last_token_where(node, .close_brace, '')
	}
	if closing < 0 {
		return
	}
	s.add_element_list_indent(t.list(node, .specifiers) or { []int{} }, s.first_token_skip(node,
		1), closing, StiOff{.number, 1})
	if source < 0 {
		return
	}
	from := s.token_after(s.all[closing].end, .from_name, '')
	last := s.last_token_where(node, .not_semicolon, '')
	if from >= 0 && last >= 0 {
		// Indent everything from the `from` of `export {foo, bar, baz} from 'qux'` on.
		s.set_offsets(s.all[from].start, s.all[last].end, s.first_token(node), 1, false)
	}
	s.export_attributes(node)
}

// export_attributes indents the attributes of an export with a source (`with { … }`).
fn (mut s StiState) export_attributes(node int) {
	t := s.t
	source := t.node(node, .source) or { return }
	last_closing := s.last_token_where(node, .close_brace, '')
	if last_closing >= 0 && t.nodes[source].end < s.all[last_closing].start {
		opening := s.token_after(t.nodes[source].end, .open_brace, '')
		s.add_element_list_indent(t.list(node, .attributes) or { []int{} }, opening, last_closing,
			StiOff{.number, 1})
	}
}

// function_params is the listener of FunctionDeclaration and FunctionExpression.
fn (mut s StiState) function_params(node int) {
	t := s.t
	return_type := t.node(node, .return_type) or { -1 }
	body := t.node(node, .body) or { -1 }
	before := if return_type >= 0 { return_type } else { body }
	if before < 0 {
		return
	}
	closing := s.token_before(t.nodes[before].start, .close_paren, '')
	if closing < 0 {
		return
	}
	params := t.list(node, .params) or { []int{} }
	opening_before := if params.len > 0 {
		decorators := t.list(params[0], .decorators) or { []int{} }
		if decorators.len > 0 { t.nodes[decorators[0]].start } else { t.nodes[params[0]].start }
	} else {
		s.all[closing].start
	}
	opening := s.token_before(opening_before, .open_paren, '')
	if opening < 0 {
		return
	}
	s.mark(opening, sti_param_paren)
	s.mark(closing, sti_param_paren)
	declaration := t.typ(node) == .function_declaration
	s.add_element_list_indent(params, opening, closing, if declaration {
		s.opts.fd_parameters
	} else {
		s.opts.fe_parameters
	})
	if return_type >= 0 {
		s.set_offsets(t.nodes[return_type].start, t.nodes[return_type].end, closing, if declaration {
			s.opts.fd_return_type
		} else {
			s.opts.fe_return_type
		}, false)
	}
}

// import_declaration is the ImportDeclaration listener.
fn (mut s StiState) import_declaration(node int) {
	t := s.t
	specifiers := t.list(node, .specifiers) or { []int{} }
	source := t.node(node, .source) or { return }
	named := specifiers.filter(t.typ(it) == .import_specifier)
	if named.len > 0 {
		opening := s.first_token_where(node, .open_brace, '')
		closing := s.token_before(t.nodes[source].start, .close_brace, '')
		s.add_element_list_indent(named, opening, closing, s.opts.import_declaration)
	}
	from := if specifiers.len > 0 {
		s.token_after(t.nodes[specifiers.last()].end, .from_name, '')
	} else {
		s.first_token_where(node, .from_name, '')
	}
	last := s.last_token_where(node, .not_semicolon, '')
	if from >= 0 && last >= 0 {
		s.set_offsets(s.all[from].start, s.all[last].end, s.first_token(node), 1, false)
	}
	last_closing := s.last_token_where(node, .close_brace, '')
	if last_closing >= 0 && t.nodes[source].end < s.all[last_closing].start {
		// The attributes (`with { … }`).
		opening := s.token_after(t.nodes[source].end, .open_brace, '')
		if from < 0 && opening >= 0 && last >= 0 {
			with_token := s.token_before(s.all[opening].start, .value, 'with')
			if with_token >= 0 {
				s.set_offsets(s.all[with_token].start, s.all[last].end, s.first_token(node), 1,
					false)
			}
		}
		s.add_element_list_indent(t.list(node, .attributes) or { []int{} }, opening, last_closing,
			StiOff{.number, 1})
	}
}

// template_literal is the TemplateLiteral listener.
fn (mut s StiState) template_literal(node int) {
	t := s.t
	expressions := t.list(node, .expressions) or { []int{} }
	quasis := t.list(node, .quasis) or { []int{} }
	for index, expression in expressions {
		if index + 1 >= quasis.len {
			break
		}
		previous := quasis[index]
		next := quasis[index + 1]
		align := if s.single_line(previous) { s.first_token(previous) } else { -1 }
		starts_on_same_line := s.nodes_same_line(previous, expression)
		ends_on_same_line := s.nodes_same_line(expression, next)
		if align >= 0 || (ends_on_same_line && !starts_on_same_line) {
			s.set_offsets(t.nodes[previous].end, t.nodes[next].start, align, 1, false)
			s.set_offset(s.first_token(next), align, 0)
			continue
		}
		// A block from the indentation of the line of `${` (the text before it, `${` excluded).
		end := t.nodes[previous].end
		line_start := t.line_starts[s.line_of(end) - 1]
		text := if end - 2 > line_start { s.src[line_start..end - 2] } else { '' }
		mut num_indentation := 0
		for num_indentation < text.len && text[num_indentation] in [` `, `\t`] {
			num_indentation++
		}
		mut num_spaces := 0
		for i in 0 .. num_indentation {
			if text[i] == ` ` {
				num_spaces++
			}
		}
		num_tabs := num_indentation - num_spaces
		divisor := if s.opts.tab { s.opts.tab_length } else { f64(s.opts.indent_size) }
		indent_offset := f64(num_tabs) + math.ceil(f64(num_spaces) / divisor)
		inner := if ends_on_same_line { indent_offset } else { indent_offset + 1 }
		s.set_offsets(t.nodes[previous].end, t.nodes[next].start, -1, inner, false)
		s.set_offset(s.first_token(next), -1, indent_offset)
	}
}

// variable_declaration is the VariableDeclaration listener.
fn (mut s StiState) variable_declaration(node int) {
	t := s.t
	declarations := t.list(node, .declarations) or { []int{} }
	if declarations.len == 0 {
		return
	}
	variable_indent := match t.string_of(node, .kind) or { '' } {
		'var' { s.opts.var_var }
		'let' { s.opts.var_let }
		'const' { s.opts.var_const }
		'using', 'await using' { s.opts.var_using }
		else { StiOff{.number, 1} }
	}
	mut numeric := if variable_indent.kind == .number { variable_indent.num } else { 1.0 }
	first := s.first_token(node)
	last := s.last_token(node)
	if first < 0 || last < 0 {
		return
	}
	if s.line_of(t.nodes[declarations.last()].start) > s.line_of(t.nodes[node].start) {
		if variable_indent.kind == .first {
			s.add_element_list_indent(declarations, first, last, variable_indent)
			first_of_first := s.first_token(declarations[0])
			first_of_line := int(s.first_of_line[int(s.line[first])])
			width := utf16_length_of(s.token_indent(first_of_first)) - utf16_length_of(s.token_indent(first_of_line))
			numeric = if s.opts.indent_size == 0 {
				0
			} else {
				f64(width) / f64(s.opts.indent_size)
			}
		}
		// Forced: the tokens on the first line of a declarator followed by others stay indented.
		s.set_offsets(t.nodes[node].start, t.nodes[node].end, first, numeric, true)
	} else {
		s.set_offsets(t.nodes[node].start, t.nodes[node].end, first, numeric, false)
	}
	if s.is(last, .semicolon) {
		s.ignore_token(last)
	}
}

// sti_line_indents are the `match[1].length` of /\n(C*)[\t ]*\S/g on the text (C the indent
// character): the indentation of each line after the first that has text.
fn sti_line_indents(text string, indent u8) []int {
	mut out := []int{}
	for i := 0; i < text.len; i++ {
		if text[i] != `\n` {
			continue
		}
		mut j := i + 1
		for j < text.len && text[j] == indent {
			j++
		}
		run := j - i - 1
		for j < text.len && text[j] in [` `, `\t`] {
			j++
		}
		if j < text.len && !sti_space_at(text, j) {
			out << run
		}
	}
	return out
}

// sti_space_at: the character at the byte offset is white space (\s).
fn sti_space_at(text string, offset int) bool {
	b := text[offset]
	if b < 0x80 {
		return b in [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
	}
	// Decode the character (the text is valid UTF-8).
	n := utf8_char_len(b)
	if offset + n > text.len {
		return false
	}
	mut r := u32(0)
	match n {
		2 { r = (u32(b & 0x1f) << 6) | u32(text[offset + 1] & 0x3f) }
		3 {
			r = (u32(b & 0x0f) << 12) | (u32(text[offset + 1] & 0x3f) << 6) | u32(text[offset + 2] & 0x3f)
		}
		4 {
			r = (u32(b & 0x07) << 18) | (u32(text[offset + 1] & 0x3f) << 12) | (u32(text[offset + 2] & 0x3f) << 6) | u32(text[offset + 3] & 0x3f)
		}
		else { return false }
	}
	return is_js_space(rune(r))
}

// sti_reindent_text is `raw.replace(/\n[\t ]*(\S)/g, (match, p1) => `\n${indent}${p1}`)`.
fn sti_reindent_text(raw string, indent string) string {
	mut out := []u8{cap: raw.len}
	mut i := 0
	for i < raw.len {
		if raw[i] != `\n` {
			out << raw[i]
			i++
			continue
		}
		mut j := i + 1
		for j < raw.len && raw[j] in [` `, `\t`] {
			j++
		}
		if j < raw.len && !sti_space_at(raw, j) {
			out << `\n`
			out << indent.bytes()
			i = j
			continue
		}
		out << raw[i]
		i++
	}
	return out.bytestr()
}

// jsx_text is the JSXText listener: the lines of the text of a JSX element are indented one JSX
// level from the line of the element.
fn (mut s StiState) jsx_text(node int, mut findings []Finding) {
	t := s.t
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) !in [.jsx_element, .jsx_fragment] {
		return
	}
	value := t.string_of(node, .value) or { return }
	indents := sti_line_indents(value, s.indent_char[0])
	if indents.len == 0 {
		return
	}
	parent_start := t.nodes[parent].start
	parent_text := s.src[t.line_starts[s.line_of(parent_start) - 1]..parent_start]
	mut parent_indent := 0
	for parent_indent < parent_text.len && parent_text[parent_indent] == s.indent_char[0] {
		parent_indent++
	}
	target := f64(parent_indent) + s.opts.jsx_indent_size
	raw := t.string_of(node, .raw) or { s.src[t.nodes[node].start..t.nodes[node].end] }
	for indent in indents {
		if f64(indent) == target {
			continue
		}
		data := s.message_data(target, indent, indent)
		findings << Finding{
			stmt:       Ident{
				start_byte: t.nodes[node].start
				end_byte:   t.nodes[node].end
			}
			message_id: 'wrongIndentation'
			data:       data
			has_fix:    true
			fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, sti_reindent_text(raw,
				sti_repeat(s.indent_char, target)))
		}
	}
}

// sti_js_number is a number as JavaScript prints it in a template.
fn sti_js_number(n f64) string {
	if n == math.floor(n) && math.abs(n) < 1e15 {
		return i64(n).str()
	}
	return n.str()
}

// message_data ports createErrorMessageData.
fn (s &StiState) message_data(expected f64, spaces int, tabs int) map[string]string {
	indent_type := if s.opts.tab { 'tab' } else { 'space' }
	expected_statement := '${sti_js_number(expected)} ${indent_type}${if expected == 1 {
		''
	} else {
		's'
	}}'
	found := if spaces > 0 {
		if !s.opts.tab {
			spaces.str()
		} else {
			'${spaces} space${if spaces == 1 { '' } else { 's' }}'
		}
	} else if tabs > 0 {
		if s.opts.tab { tabs.str() } else { '${tabs} tab${if tabs == 1 { '' } else { 's' }}' }
	} else {
		'0'
	}
	return {
		'expected': expected_statement
		'actual':   found
	}
}

// report reports the indentation of the first token or comment of a line.
fn (s &StiState) report(ai int, needed string) Finding {
	actual := s.token_indent(ai)
	mut spaces := 0
	mut tabs := 0
	for b in actual {
		if b == ` ` {
			spaces++
		} else if b == `\t` {
			tabs++
		}
	}
	line_start := s.t.line_starts[int(s.line[ai]) - 1]
	return Finding{
		stmt:       Ident{
			start_byte: line_start
			end_byte:   s.all[ai].start
		}
		message_id: 'wrongIndentation'
		data:       s.message_data(f64(utf16_length_of(needed)), spaces, tabs)
		has_fix:    true
		fix:        fix_replace_range(line_start, s.all[ai].start, needed)
	}
}
