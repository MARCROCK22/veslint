module rules

import estree
import time
import x.json2

// Port of the `@stylistic/comma-style` rule of @stylistic/eslint-plugin 6.0.1, with its options
// (`"last"`, the default, or `"first"`, and `exceptions`, the node types not to check) and its
// fixes.

const scst_messages = {
	'unexpectedLineBeforeAndAfterComma': "Bad line breaking before and after ','."
	'expectedCommaFirst':                "',' should be placed first."
	'expectedCommaLast':                 "',' should be placed last."
}

struct ScstOptions {
	style      string
	exceptions map[string]bool
}

// scst_core_exceptions are the default exceptions of ESLint core's comma-style, which
// vue/comma-style runs without @stylistic/eslint-plugin (vue_wrap.v); ESLint Stylistic has none.
const scst_core_exceptions = ['ArrayPattern', 'ArrowFunctionExpression', 'CallExpression',
	'FunctionDeclaration', 'FunctionExpression', 'ImportDeclaration', 'ObjectPattern', 'NewExpression']

// scst_core_types are the node types ESLint core's comma-style checks.
const scst_core_types = ['VariableDeclaration', 'ObjectExpression', 'ObjectPattern', 'ArrayExpression',
	'ArrayPattern', 'FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression',
	'CallExpression', 'ImportDeclaration', 'NewExpression']

fn scst_options(given []json2.Any, core bool) !ScstOptions {
	options := sty_options(given, [json2.Any('last')])
	mut exceptions := map[string]bool{}
	if core {
		for name in scst_core_exceptions {
			exceptions[name] = true
		}
	}
	object := sty_option_object(options, 1)
	if given_exceptions := object['exceptions'] {
		if given_exceptions is map[string]json2.Any {
			for key, value in given_exceptions {
				if value is bool {
					exceptions[key] = value
				}
			}
		}
	}
	return ScstOptions{
		style:      sty_option_string(options, 0, 'last')
		exceptions: exceptions
	}
}

fn (mut c Checker) lint_stylistic_comma_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := scst_options(c.rule_options(stylistic_comma_style), c.vue_wrap_core)!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		typ := t.typ(node)
		key := match typ {
			.variable_declaration { estree.Key.declarations }
			.object_expression, .object_pattern { .properties }
			.array_expression, .array_pattern { .elements }
			.function_declaration, .function_expression, .arrow_function_expression,
			.ts_declare_function, .ts_function_type, .ts_constructor_type,
			.ts_empty_body_function_expression, .ts_method_signature,
			.ts_call_signature_declaration, .ts_construct_signature_declaration,
			.ts_type_parameter_declaration, .ts_type_parameter_instantiation {
				.params
			}
			.call_expression, .new_expression { .arguments }
			.import_declaration, .export_named_declaration { .specifiers }
			.export_all_declaration { .attributes }
			.import_expression { .source }
			.sequence_expression { .expressions }
			.class_declaration, .class_expression { .implements_ }
			.ts_enum_body, .ts_type_literal { .members }
			.ts_index_signature { .parameters }
			.ts_interface_declaration { .extends_ }
			.ts_interface_body { .body }
			.ts_tuple_type { .element_types }
			else { continue }
		}
		if options.exceptions[typ.type_name()]
			|| (c.vue_wrap_core && typ.type_name() !in scst_core_types) {
			continue
		}
		stats.checked++
		if typ == .import_expression {
			// [node.source, node.options ?? null]
			source := t.node(node, .source) or { -1 }
			opts := t.node(node, .options) or { -1 }
			c.scst_validate_comma(t, tokens, node, [source, opts], options, mut findings)
			continue
		}
		c.scst_validate_comma(t, tokens, node, t.list(node, key) or { []int{} }, options, mut
			findings)
		if typ in [.import_declaration, .export_named_declaration] {
			// visitImportAttributes
			if attributes := t.list(node, .attributes) {
				c.scst_validate_comma(t, tokens, node, attributes, options, mut findings)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// scst_extract_comma_tokens ports extractCommaTokens (`items` holds -1 for a null item).
fn (c &Checker) scst_extract_comma_tokens(t &estree.EsTree, tokens &SourceTokens, node int, items []int) []SourceToken {
	if items.len == 0 {
		return []SourceToken{}
	}
	defined := items.filter(it >= 0)
	node_start := t.nodes[node].start
	node_end := t.nodes[node].end
	if defined.len == 0 {
		return tokens.inside(node_start, node_end, false).filter(c.token_is(it, ','))
	}
	mut before := []SourceToken{}
	mut previous := tokens.before(t.nodes[defined[0]].start, false)
	for {
		token := previous or { break }
		if node_start > token.start {
			break
		}
		if c.token_is(token, ',') {
			before << token
		} else if !c.token_is(token, '(') {
			break
		}
		previous = tokens.before(token.start, false)
	}
	mut commas := before.reverse()
	mut previous_item := -1
	for item in defined {
		if previous_item >= 0 {
			for token in tokens.inside(t.nodes[previous_item].end, t.nodes[item].start, false) {
				if c.token_is(token, ',') {
					commas << token
				}
			}
		}
		if last := un_last_token(t, tokens, item) {
			// A type element such as a TSPropertySignature may end with a comma.
			if c.token_is(last, ',') {
				commas << last
			}
		}
		previous_item = item
	}
	mut next := tokens.after(t.nodes[previous_item].end, false)
	for {
		token := next or { break }
		if token.end > node_end {
			break
		}
		if c.token_is(token, ',') {
			commas << token
		} else if !c.token_is(token, ')') {
			break
		}
		next = tokens.after(token.end, false)
	}
	return commas
}

// scst_validate_comma ports validateComma.
fn (c &Checker) scst_validate_comma(t &estree.EsTree, tokens &SourceTokens, node int, items []int, options ScstOptions, mut findings []Finding) {
	for comma in c.scst_extract_comma_tokens(t, tokens, node, items) {
		before := tokens.before(comma.start, false) or { continue }
		after := tokens.after(comma.end, false) or { continue }
		if c.token_is(before, '[') {
			// Ignore the first comma in an array.
			continue
		}
		if c.token_is(before, ',') {
			// getTokenBefore(tokenBeforeComma, isNotCommaToken)
			mut index := source_tokens_index(tokens.tokens, before.start) - 1
			for index >= 0 && c.token_is(tokens.tokens[index], ',') {
				index--
			}
			if index >= 0 && c.token_is(tokens.tokens[index], '[') {
				// Ignore commas at the beginning of an array.
				continue
			}
		}
		if c.token_is(after, ',') && !sty_same_line(t, comma, after) {
			// Ignore consecutive commas.
			continue
		}
		c.scst_validate_item_spacing(t, tokens, before, comma, after, options, mut findings)
	}
}

// scst_validate_item_spacing ports validateCommaItemSpacing.
fn (c &Checker) scst_validate_item_spacing(t &estree.EsTree, tokens &SourceTokens, before SourceToken, comma SourceToken, after SourceToken, options ScstOptions, mut findings []Finding) {
	same_after := sty_same_line(t, comma, after)
	same_before := sty_same_line(t, before, comma)
	if same_after && same_before {
		return
	}
	if !same_after && !same_before {
		comments := tokens.comments_after(comma.end)
		style_type := if comments.len > 0 && comments[0].kind == .block_comment
			&& sty_same_line(t, comma, comments[0]) {
			options.style
		} else {
			'between'
		}
		// A lone comma.
		c.scst_report(comma, 'unexpectedLineBeforeAndAfterComma', c.scst_fix(style_type,
			before, comma, after), mut findings)
	} else if options.style == 'first' && !same_after {
		c.scst_report(comma, 'expectedCommaFirst', c.scst_fix(options.style, before, comma,
			after), mut findings)
	} else if options.style == 'last' && same_after {
		c.scst_report(comma, 'expectedCommaLast', c.scst_fix(options.style, before, comma,
			after), mut findings)
	}
}

// scst_fix ports getFixerFunction and getReplacedText.
fn (c &Checker) scst_fix(style_type string, before SourceToken, comma SourceToken, after SourceToken) Fix {
	text := c.src[before.end..comma.start] + c.src[comma.end..after.start]
	replaced := match style_type {
		// LINEBREAK_MATCHER has no `g` flag: only the first line break goes.
		'between' { ',' + scst_remove_first_line_break(text) }
		'first' { text + ',' }
		'last' { ',' + text }
		else { '' }
	}
	return fix_replace_range(before.end, after.start, replaced)
}

fn (c &Checker) scst_report(comma SourceToken, message_id string, fix Fix, mut findings []Finding) {
	findings << Finding{
		stmt:       c.position_range(comma.start, comma.end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}

// scst_remove_first_line_break is `text.replace(LINEBREAK_MATCHER, '')`: the first `\r\n`, `\r`,
// `\n`, U+2028 or U+2029 removed.
fn scst_remove_first_line_break(text string) string {
	for i := 0; i < text.len; i++ {
		if text[i] == `\r` {
			end := if i + 1 < text.len && text[i + 1] == `\n` { i + 2 } else { i + 1 }
			return text[..i] + text[end..]
		}
		if text[i] == `\n` {
			return text[..i] + text[i + 1..]
		}
		// U+2028 and U+2029 are E2 80 A8 and E2 80 A9 in UTF-8.
		if text[i] == 0xe2 && i + 2 < text.len && text[i + 1] == 0x80
			&& (text[i + 2] == 0xa8 || text[i + 2] == 0xa9) {
			return text[..i] + text[i + 3..]
		}
	}
	return text
}
