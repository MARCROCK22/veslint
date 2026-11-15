module rules

import estree
import time
import treesitter { node_kind, node_parent }
import x.json2

// Port of the `@stylistic/keyword-spacing` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`before` and `after`, true by default, and `overrides` per keyword) and its fixes.

const skwsp_messages = {
	'expectedBefore':   'Expected space(s) before "{{value}}".'
	'expectedAfter':    'Expected space(s) after "{{value}}".'
	'unexpectedBefore': 'Unexpected space(s) before "{{value}}".'
	'unexpectedAfter':  'Unexpected space(s) after "{{value}}".'
}

// The patterns of the tokens next to a keyword that are checked (PREV_TOKEN, NEXT_TOKEN,
// PREV_TOKEN_M and NEXT_TOKEN_M).
const skwsp_prev_token = [')', ']', '}', '>']
const skwsp_next_token = ['(', '[', '{', '<', '~', '!', '+', '++', '-', '--']
const skwsp_prev_token_m = [')', ']', '}', '>', '*']
const skwsp_next_token_m = ['{', '*']

struct SkwspSpacing {
	before bool
	after  bool
}

struct SkwspOptions {
	default_  SkwspSpacing
	overrides map[string]SkwspSpacing
}

fn skwsp_options(given []json2.Any) !SkwspOptions {
	options := sty_options(given, [
		json2.Any({
			'before':    json2.Any(true)
			'after':     json2.Any(true)
			'overrides': json2.Any(map[string]json2.Any{})
		}),
	])
	object := sty_option_object(options, 0)
	before := sty_option_bool(object, 'before') or { false }
	after := sty_option_bool(object, 'after') or { false }
	mut overrides := map[string]SkwspSpacing{}
	overrides_value := object['overrides'] or { json2.Any(json2.Null{}) }
	if overrides_value is map[string]json2.Any {
		for key, value in overrides_value {
			if value is map[string]json2.Any {
				// parseOptions: `('before' in override) ? override.before : before`
				overrides[key] = SkwspSpacing{
					before: if 'before' in value { sty_option_bool(value, 'before') or { false } } else { before }
					after:  if 'after' in value { sty_option_bool(value, 'after') or { false } } else { after }
				}
			}
		}
	}
	return SkwspOptions{
		default_:  SkwspSpacing{before, after}
		overrides: overrides
	}
}

// SkwspCtx is the state of the rule on one file.
struct SkwspCtx {
	t       &estree.EsTree
	tokens  &SourceTokens
	options SkwspOptions
mut:
	// tokensToIgnore: the starts of the `>` operators of binary expressions.
	ignored  map[int]bool
	findings []Finding
}

fn (mut c Checker) lint_stylistic_keyword_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := skwsp_options(c.rule_options(stylistic_keyword_spacing))!
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut x := SkwspCtx{
		t:       t
		tokens:  c.un_tokens(t)
		options: options
	}
	// In the order of ESLint's traversal: tokensToIgnore grows as it goes, and reports that start
	// at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		stats.checked++
		c.skwsp_visit(mut x, step.node)
	}
	stats.eval_ms += ms(sw.elapsed())
	return x.findings
}

// skwsp_visit runs the listener of the node's type.
fn (c &Checker) skwsp_visit(mut x SkwspCtx, node int) {
	t := x.t
	match t.typ(node) {
		.debugger_statement, .with_statement, .break_statement, .continue_statement,
		.return_statement, .throw_statement, .switch_statement, .switch_case, .for_statement,
		.while_statement, .variable_declaration, .static_block {
			c.skwsp_around_first_token(mut x, node)
		}
		.try_statement {
			c.skwsp_around_first_token(mut x, node)
			if handler := t.node(node, .handler) {
				// The space after `catch` is handled by `space-before-function-paren`.
				if _ := t.node(handler, .param) {
					c.skwsp_before_first_token(mut x, handler)
				} else {
					c.skwsp_around_first_token(mut x, handler)
				}
			}
			c.skwsp_around_token_before(mut x, t.node(node, .finalizer))
		}
		.if_statement {
			c.skwsp_around_first_token(mut x, node)
			c.skwsp_around_token_before(mut x, t.node(node, .alternate))
		}
		.do_while_statement {
			c.skwsp_around_first_token(mut x, node)
			c.skwsp_around_token_before(mut x, t.node(node, .test))
		}
		.for_in_statement, .for_of_statement {
			if t.typ(node) == .for_of_statement && (t.flag(node, .await_) or { false }) {
				if first := un_first_token(t, x.tokens, node, 0) {
					c.skwsp_before(mut x, first, skwsp_prev_token)
				}
				if second := un_first_token(t, x.tokens, node, 1) {
					c.skwsp_after(mut x, second, skwsp_next_token)
				}
			} else {
				c.skwsp_around_first_token(mut x, node)
			}
			right := t.node(node, .right) or { return }
			// getTokenBefore(node.right, isNotOpeningParenToken)
			mut index := source_tokens_index(x.tokens.tokens, t.nodes[right].start) - 1
			for index >= 0 && c.token_is(x.tokens.tokens[index], '(') {
				index--
			}
			if index < 0 {
				return
			}
			in_token := x.tokens.tokens[index]
			if index == 0 || x.tokens.tokens[index - 1].kind != .private_identifier {
				c.skwsp_before(mut x, in_token, skwsp_prev_token)
			}
			c.skwsp_after(mut x, in_token, skwsp_next_token)
		}
		.class_declaration, .class_expression {
			// checkSpacingForClass
			c.skwsp_around_first_token(mut x, node)
			c.skwsp_around_token_before(mut x, t.node(node, .super_class))
		}
		.export_named_declaration, .export_default_declaration, .export_all_declaration,
		.import_declaration {
			c.skwsp_module_declaration(mut x, node)
		}
		.function_declaration, .arrow_function_expression, .function_expression {
			// checkSpacingForFunction
			first := un_first_token(t, x.tokens, node, 0) or { return }
			value := c.token_text(first)
			if (first.kind == .keyword && value == 'function') || value == 'async' {
				c.skwsp_before(mut x, first, skwsp_prev_token)
			}
		}
		.await_expression {
			first := un_first_token(t, x.tokens, node, 0) or { return }
			c.skwsp_before(mut x, first, skwsp_prev_token)
		}
		.new_expression, .super, .this_expression, .unary_expression, .yield_expression {
			c.skwsp_before_first_token(mut x, node)
		}
		.import_specifier {
			imported := t.node(node, .imported) or { return }
			local := t.node(node, .local) or { return }
			if t.nodes[imported].start != t.nodes[local].start {
				as_token := x.tokens.before(t.nodes[local].start, false) or { return }
				c.skwsp_before(mut x, as_token, skwsp_prev_token_m)
			}
		}
		.export_specifier {
			local := t.node(node, .local) or { return }
			exported := t.node(node, .exported) or { return }
			if t.nodes[local].start != t.nodes[exported].start {
				as_token := x.tokens.before(t.nodes[exported].start, false) or { return }
				c.skwsp_before(mut x, as_token, skwsp_prev_token_m)
				c.skwsp_after(mut x, as_token, skwsp_next_token_m)
			}
		}
		.import_namespace_specifier {
			as_token := un_first_token(t, x.tokens, node, 1) or { return }
			c.skwsp_before(mut x, as_token, skwsp_prev_token_m)
		}
		.method_definition, .property_definition, .accessor_property, .property {
			c.skwsp_property(mut x, node)
		}
		.binary_expression {
			// To avoid conflicts with `space-infix-ops`, e.g. `a > this.b`.
			if (t.string_of(node, .operator) or { '' }) != '>' {
				return
			}
			right := t.node(node, .right) or { return }
			mut index := source_tokens_index(x.tokens.tokens, t.nodes[right].start) - 1
			for index >= 0 && c.token_is(x.tokens.tokens[index], '(') {
				index--
			}
			if index >= 0 {
				x.ignored[x.tokens.tokens[index].start] = true
			}
		}
		.ts_as_expression, .ts_satisfies_expression {
			keyword := if t.typ(node) == .ts_as_expression { 'as' } else { 'satisfies' }
			expression := t.node(node, .expression) or { return }
			for i := source_tokens_index(x.tokens.tokens, t.nodes[expression].end); i < x.tokens.tokens.len; i++ {
				if c.token_text(x.tokens.tokens[i]) == keyword {
					c.skwsp_around(mut x, x.tokens.tokens[i])
					break
				}
			}
		}
		else {}
	}
}

// skwsp_spacing is checkMethodMap[keyword]: the spacing the options ask around it.
fn (x &SkwspCtx) skwsp_spacing(keyword string) SkwspSpacing {
	return x.options.overrides[keyword] or { x.options.default_ }
}

// skwsp_is_check_type tells whether a token is of a type always checked (CHECK_TYPE): a regular
// expression, a string (not that of a JSX attribute, JSXText for ESLint), a template or a private
// identifier.
fn skwsp_is_check_type(token SourceToken) bool {
	return match token.kind {
		.regular_expression, .template, .private_identifier {
			true
		}
		.string_ {
			parent := node_parent(token.node) or { return true }
			node_kind(parent) !in ['jsx_attribute', 'jsx_element']
		}
		else {
			false
		}
	}
}

// skwsp_before ports checkSpacingBefore: expectSpaceBefore or unexpectSpaceBefore.
fn (c &Checker) skwsp_before(mut x SkwspCtx, token SourceToken, pattern []string) {
	value := c.token_text(token)
	expect := x.skwsp_spacing(value).before
	prev := x.tokens.before(token.start, false) or { return }
	prev_value := c.token_text(prev)
	// isOpenParenOfTemplate
	if !(skwsp_is_check_type(prev) || prev_value in pattern)
		|| (prev.kind == .template && prev_value.ends_with('\${')) || prev.start in x.ignored
		|| !sty_same_line(x.t, prev, token) {
		return
	}
	spaced := x.tokens.is_space_between(prev.end, token.start)
	if expect && !spaced {
		x.findings << c.skwsp_report(token.start, token.end, 'expectedBefore', value,
			fix_insert_at(token.start, ' '))
	} else if !expect && spaced {
		x.findings << c.skwsp_report(prev.end, token.start, 'unexpectedBefore', value,
			fix_remove_range(prev.end, token.start))
	}
}

// skwsp_after ports checkSpacingAfter: expectSpaceAfter or unexpectSpaceAfter.
fn (c &Checker) skwsp_after(mut x SkwspCtx, token SourceToken, pattern []string) {
	value := c.token_text(token)
	expect := x.skwsp_spacing(value).after
	next := x.tokens.after(token.end, false) or { return }
	next_value := c.token_text(next)
	// isCloseParenOfTemplate
	if !(skwsp_is_check_type(next) || next_value in pattern)
		|| (next.kind == .template && next_value.starts_with('}')) || next.start in x.ignored
		|| !sty_same_line(x.t, token, next) {
		return
	}
	spaced := x.tokens.is_space_between(token.end, next.start)
	if expect && !spaced {
		x.findings << c.skwsp_report(token.start, token.end, 'expectedAfter', value, fix_insert_at(token.end,
			' '))
	} else if !expect && spaced {
		x.findings << c.skwsp_report(token.end, next.start, 'unexpectedAfter', value, fix_remove_range(token.end,
			next.start))
	}
}

// skwsp_around ports checkSpacingAround.
fn (c &Checker) skwsp_around(mut x SkwspCtx, token SourceToken) {
	c.skwsp_before(mut x, token, skwsp_prev_token)
	c.skwsp_after(mut x, token, skwsp_next_token)
}

// skwsp_around_first_token ports checkSpacingAroundFirstToken.
fn (c &Checker) skwsp_around_first_token(mut x SkwspCtx, node int) {
	t := x.t
	first := un_first_token(t, x.tokens, node, 0) or { return }
	if first.kind != .keyword {
		// `using` and `await using` declarations start with an identifier.
		if t.typ(node) != .variable_declaration {
			return
		}
		kind := t.string_of(node, .kind) or { '' }
		if (kind != 'using' && kind != 'await using') || first.kind != .identifier {
			return
		}
	}
	c.skwsp_around(mut x, first)
}

// skwsp_before_first_token ports checkSpacingBeforeFirstToken.
fn (c &Checker) skwsp_before_first_token(mut x SkwspCtx, node int) {
	first := un_first_token(x.t, x.tokens, node, 0) or { return }
	if first.kind == .keyword {
		c.skwsp_before(mut x, first, skwsp_prev_token)
	}
}

// skwsp_around_token_before ports checkSpacingAroundTokenBefore: the last keyword before the node.
fn (c &Checker) skwsp_around_token_before(mut x SkwspCtx, node ?int) {
	n := node or { return }
	for i := source_tokens_index(x.tokens.tokens, x.t.nodes[n].start) - 1; i >= 0; i-- {
		if x.tokens.tokens[i].kind == .keyword {
			c.skwsp_around(mut x, x.tokens.tokens[i])
			return
		}
	}
}

// skwsp_module_declaration ports checkSpacingForModuleDeclaration.
fn (c &Checker) skwsp_module_declaration(mut x SkwspCtx, node int) {
	t := x.t
	first := un_first_token(t, x.tokens, node, 0) or { return }
	c.skwsp_before(mut x, first, skwsp_prev_token_m)
	c.skwsp_after(mut x, first, skwsp_next_token_m)
	typ := t.typ(node)
	if typ == .export_default_declaration {
		if default_token := x.tokens.after(first.end, false) {
			c.skwsp_around(mut x, default_token)
		}
	}
	if typ == .export_all_declaration {
		if exported := t.node(node, .exported) {
			as_token := x.tokens.before(t.nodes[exported].start, false) or { return }
			c.skwsp_before(mut x, as_token, skwsp_prev_token_m)
			c.skwsp_after(mut x, as_token, skwsp_next_token_m)
		}
	}
	if typ != .export_default_declaration {
		if source := t.node(node, .source) {
			from_token := x.tokens.before(t.nodes[source].start, false) or { return }
			c.skwsp_before(mut x, from_token, skwsp_prev_token_m)
			c.skwsp_after(mut x, from_token, skwsp_next_token_m)
			// ImportAttribute must be after source.
			if _ := t.list(node, .attributes) {
				if with_token := x.tokens.after(t.nodes[source].end, false) {
					if with_token.kind == .keyword {
						c.skwsp_around(mut x, with_token)
					}
				}
			}
		}
		// checkSpacingForTypeKeywordInImportExport
		kind := t.string_of(node, if typ == .import_declaration { .import_kind } else { .export_kind }) or {
			''
		}
		if kind != 'type' {
			return
		}
		type_token := un_first_token(t, x.tokens, node, 1) or { return }
		// isTypeKeyword
		if type_token.kind != .identifier || c.token_text(type_token) != 'type' {
			return
		}
		c.skwsp_before(mut x, type_token, skwsp_prev_token_m)
		c.skwsp_after(mut x, type_token, skwsp_next_token_m)
	}
}

// skwsp_property ports checkSpacingForProperty.
fn (c &Checker) skwsp_property(mut x SkwspCtx, node int) {
	t := x.t
	typ := t.typ(node)
	if typ != .property && (t.flag(node, .static_) or { false }) {
		c.skwsp_around_first_token(mut x, node)
	}
	kind := t.string_of(node, .kind) or { '' }
	mut checked := kind in ['get', 'set'] || typ == .accessor_property
	if !checked && ((typ == .property && (t.flag(node, .method) or { false }))
		|| typ == .method_definition) {
		if value := t.node(node, .value) {
			checked = t.flag(value, .async) or { false }
		}
	}
	if !checked {
		return
	}
	key := t.node(node, .key) or { return }
	for i := source_tokens_index(x.tokens.tokens, t.nodes[key].start) - 1; i >= 0; i-- {
		if c.token_text(x.tokens.tokens[i]) in ['get', 'set', 'async', 'accessor'] {
			c.skwsp_around(mut x, x.tokens.tokens[i])
			return
		}
	}
}

fn (c &Checker) skwsp_report(start int, end int, message_id string, value string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       {
			'value': value
		}
		has_fix:    true
		fix:        fix
	}
}
