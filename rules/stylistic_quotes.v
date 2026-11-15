module rules

import estree
import time
import x.json2

// Port of the `@stylistic/quotes` rule of @stylistic/eslint-plugin 5.10.0, with its options
// (`"double"`, the default, `"single"` or `"backtick"`, and `avoidEscape`,
// `allowTemplateLiterals` — `"never"`, `"avoidEscape"`, `"always"` or the deprecated booleans —,
// `ignoreStringLiterals`, or the deprecated `"avoid-escape"`) and its fixes.

const squo_messages = {
	'wrongQuotes': 'Strings must use {{description}}.'
}

struct SquoOptions {
	quote_option                           string
	quote                                  string
	alternate_quote                        string
	description                            string
	avoid_escape                           bool
	ignore_string_literals                 bool
	allow_template_literals_always         bool
	allow_template_literals_to_avoid_escape bool
}

fn squo_options(given []json2.Any) !SquoOptions {
	options := sty_options(given, [json2.Any('double'), json2.Any({
		'allowTemplateLiterals': json2.Any('never')
		'avoidEscape':           json2.Any(false)
		'ignoreStringLiterals':  json2.Any(false)
	})])
	mut quote_option := sty_option_string(options, 0, '')
	if quote_option == '' {
		quote_option = 'double'
	}
	quote, alternate_quote, description := match quote_option {
		'single' { "'", '"', 'singlequote' }
		'backtick' { '`', '"', 'backtick' }
		else { '"', "'", 'doublequote' }
	}
	mut avoid_escape := false
	mut ignore_string_literals := false
	mut always := false
	mut to_avoid_escape := false
	second := if options.len > 1 { options[1] } else { json2.Any(json2.Null{}) }
	if second is map[string]json2.Any {
		avoid_escape = sty_option_bool(second, 'avoidEscape') or { false }
		ignore_string_literals = sty_option_bool(second, 'ignoreStringLiterals') or { false }
		allow := second['allowTemplateLiterals'] or { json2.Any(json2.Null{}) }
		if allow is string {
			always = allow == 'always'
			to_avoid_escape = always || allow == 'avoidEscape'
		} else if allow is bool {
			// Deprecated.
			always = allow
			to_avoid_escape = allow
		}
	} else if second is string && second == 'avoid-escape' {
		// Deprecated.
		avoid_escape = true
	}
	return SquoOptions{
		quote_option:                            quote_option
		quote:                                   quote
		alternate_quote:                         alternate_quote
		description:                             description
		avoid_escape:                            avoid_escape
		ignore_string_literals:                  ignore_string_literals
		allow_template_literals_always:          always
		allow_template_literals_to_avoid_escape: to_avoid_escape
	}
}

fn (mut c Checker) lint_stylistic_quotes(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := squo_options(c.rule_options(stylistic_quotes))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.literal {
				if options.ignore_string_literals || t.get(node, .value) !is string {
					continue
				}
				stats.checked++
				c.squo_check_literal(t, tokens, node, options, mut findings)
			}
			.template_literal {
				stats.checked++
				c.squo_check_template(t, tokens, node, options, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) squo_check_literal(t &estree.EsTree, tokens &SourceTokens, node int, options SquoOptions, mut findings []Finding) {
	raw := c.src[t.nodes[node].start..t.nodes[node].end]
	mut is_valid := (options.quote_option == 'backtick'
		&& c.squo_is_allowed_as_non_backtick(t, tokens, node)) || squo_is_jsx_literal(t, node)
		|| squo_is_surrounded_by(raw, options.quote)
	if !is_valid && options.avoid_escape {
		is_valid = squo_is_surrounded_by(raw, options.alternate_quote) && raw.contains(options.quote)
	}
	if is_valid {
		return
	}
	// An octal or non-octal decimal escape sequence is a syntax error in a template literal.
	has_fix := !(options.quote_option == 'backtick'
		&& squo_has_octal_or_non_octal_decimal_escape(raw))
	findings << Finding{
		stmt:       c.position_range(t.nodes[node].start, t.nodes[node].end)
		message_id: 'wrongQuotes'
		data:       {
			'description': options.description
		}
		has_fix:    has_fix
		fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, squo_switch_quote(options.quote,
			raw))
	}
}

fn (c &Checker) squo_check_template(t &estree.EsTree, tokens &SourceTokens, node int, options SquoOptions, mut findings []Finding) {
	// No problem when backticks are expected or a feature of template literals is used.
	if options.allow_template_literals_always || options.quote_option == 'backtick'
		|| c.squo_is_using_feature_of_template_literal(t, node) {
		return
	}
	text := c.src[t.nodes[node].start..t.nodes[node].end]
	if options.allow_template_literals_to_avoid_escape && options.avoid_escape
		&& text.contains(options.quote) {
		return
	}
	// A template literal is not a directive, but the fix could make it one.
	parent := t.nodes[node].parent
	has_fix := !(squo_is_top_level_expression_statement(t, parent)
		&& !c.squo_is_parenthesised(t, tokens, node))
	findings << Finding{
		stmt:       c.position_range(t.nodes[node].start, t.nodes[node].end)
		message_id: 'wrongQuotes'
		data:       {
			'description': options.description
		}
		has_fix:    has_fix
		fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, squo_switch_quote(options.quote,
			text))
	}
}

// squo_is_surrounded_by ports isSurroundedBy.
fn squo_is_surrounded_by(value string, character string) bool {
	return value.len > 0 && value[0..1] == character && value[value.len - 1..] == character
}

// squo_is_jsx_literal ports isJSXLiteral: an attribute value or a text of JSX.
fn squo_is_jsx_literal(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) in [.jsx_attribute, .jsx_element, .jsx_fragment]
}

// squo_is_parenthesised ports isParenthesised of shared/utils/ast: the tokens around the node
// are `(` and `)`.
fn (c &Checker) squo_is_parenthesised(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	previous := tokens.before(t.nodes[node].start, false) or { return false }
	next := tokens.after(t.nodes[node].end, false) or { return false }
	return c.token_is(previous, '(') && previous.end <= t.nodes[node].start
		&& c.token_is(next, ')') && next.start >= t.nodes[node].end
}

// squo_is_top_level_expression_statement ports isTopLevelExpressionStatement.
fn squo_is_top_level_expression_statement(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .expression_statement {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	if t.typ(parent) == .program {
		return true
	}
	if t.typ(parent) != .block_statement {
		return false
	}
	grand := t.nodes[parent].parent
	// isFunction of @typescript-eslint/utils.
	return grand >= 0 && t.typ(grand) in [.arrow_function_expression, .function_declaration,
		.function_expression, .ts_declare_function, .ts_empty_body_function_expression]
}

// squo_is_directive ports isDirective.
fn (c &Checker) squo_is_directive(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	expression := t.node(node, .expression) or { return false }
	return un_is_string_literal(t, expression) && !c.squo_is_parenthesised(t, tokens, expression)
}

// squo_is_in_or_just_after_directive_prologue ports isExpressionInOrJustAfterDirectivePrologue.
fn (c &Checker) squo_is_in_or_just_after_directive_prologue(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || !squo_is_top_level_expression_statement(t, parent) {
		return false
	}
	block := t.nodes[parent].parent
	body := t.list(block, .body) or { return false }
	for statement in body {
		if statement == parent {
			return true
		}
		if !c.squo_is_directive(t, tokens, statement) {
			break
		}
	}
	return false
}

// squo_is_allowed_as_non_backtick ports isAllowedAsNonBacktick.
fn (c &Checker) squo_is_allowed_as_non_backtick(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	at := fn [t, parent, node] (key estree.Key) bool {
		return (t.node(parent, key) or { -1 }) == node
	}
	not_computed := !(t.flag(parent, .computed) or { false })
	return match t.typ(parent) {
		// Directive prologues.
		.expression_statement {
			!c.squo_is_parenthesised(t, tokens, node)
				&& c.squo_is_in_or_just_after_directive_prologue(t, tokens, node)
		}
		// LiteralPropertyName.
		.property, .method_definition, .ts_abstract_property_definition, .property_definition,
		.accessor_property {
			at(.key) && not_computed
		}
		// ModuleSpecifier.
		.import_declaration, .export_named_declaration {
			at(.source)
		}
		// ModuleExportName or ModuleSpecifier.
		.export_all_declaration {
			at(.exported) || at(.source)
		}
		.import_specifier {
			at(.imported)
		}
		.export_specifier {
			at(.local) || at(.exported)
		}
		.import_attribute {
			at(.value)
		}
		.ts_import_type, .ts_abstract_method_definition, .ts_method_signature,
		.ts_property_signature, .ts_module_declaration, .ts_external_module_reference {
			true
		}
		.ts_enum_member {
			at(.id)
		}
		.ts_literal_type {
			grand := t.nodes[parent].parent
			grand >= 0 && t.typ(grand) == .ts_import_type
		}
		else {
			false
		}
	}
}

// squo_is_using_feature_of_template_literal ports isUsingFeatureOfTemplateLiteral: a tag, an
// interpolation or an unescaped line break.
fn (c &Checker) squo_is_using_feature_of_template_literal(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) == .tagged_template_expression
		&& (t.node(parent, .quasi) or { -1 }) == node {
		return true
	}
	expressions := t.list(node, .expressions) or { []int{} }
	if expressions.len > 0 {
		return true
	}
	quasis := t.list(node, .quasis) or { []int{} }
	if quasis.len == 0 {
		return false
	}
	// The raw text of the only quasi: what is between the backticks.
	return squo_has_unescaped_line_break(c.src[t.nodes[node].start + 1..t.nodes[node].end - 1])
}

// squo_has_unescaped_line_break is UNESCAPED_LINEBREAK_PATTERN.test(text): a line break (`\r`,
// `\n`, U+2028, U+2029) after an even number of backslashes.
fn squo_has_unescaped_line_break(text string) bool {
	for i := 0; i < text.len; i++ {
		is_break := text[i] in [`\r`, `\n`] || (text[i] == 0xe2 && i + 2 < text.len
			&& text[i + 1] == 0x80 && text[i + 2] in [u8(0xa8), 0xa9])
		if !is_break {
			continue
		}
		mut backslashes := 0
		for j := i - 1; j >= 0 && text[j] == `\\`; j-- {
			backslashes++
		}
		if backslashes % 2 == 0 {
			return true
		}
	}
	return false
}

// squo_has_octal_or_non_octal_decimal_escape ports hasOctalOrNonOctalDecimalEscapeSequence:
// /^(?:[^\\]|\\.)*\\(?:[1-9]|0\d)/su.
fn squo_has_octal_or_non_octal_decimal_escape(raw string) bool {
	mut i := 0
	for i < raw.len {
		if raw[i] != `\\` {
			i++
			continue
		}
		if i + 1 < raw.len {
			next := raw[i + 1]
			if next >= `1` && next <= `9` {
				return true
			}
			if next == `0` && i + 2 < raw.len && raw[i + 2].is_digit() {
				return true
			}
		}
		i += 2
	}
	return false
}

// squo_is_line_terminator_at tells whether a line terminator of JavaScript (`.` does not match
// it) starts at `i`, and its length in bytes.
fn squo_is_line_terminator_at(s string, i int) (bool, int) {
	if s[i] in [`\r`, `\n`] {
		return true, 1
	}
	if s[i] == 0xe2 && i + 2 < s.len && s[i + 1] == 0x80 && s[i + 2] in [u8(0xa8), 0xa9] {
		return true, 3
	}
	return false, 0
}

// squo_switch_quote ports switchQuote: the string with the quotes `new_quote`, escaping and
// unescaping what that needs (the replacement of
// /\\(\$\{|\r\n?|\n|.)|["'`]|\$\{|(\r\n?|\n)/gu).
fn squo_switch_quote(new_quote string, str string) string {
	old_quote := str[0..1]
	if new_quote == old_quote {
		return str
	}
	body := str[1..str.len - 1]
	mut out := []u8{cap: str.len + 4}
	out << new_quote.bytes()
	mut i := 0
	for i < body.len {
		ch := body[i]
		mut matched := ''
		mut escaped := ''
		mut newline := ''
		if ch == `\\` && i + 1 < body.len {
			next := body[i + 1]
			if next == `$` && i + 2 < body.len && body[i + 2] == `{` {
				escaped = '\${'
			} else if next == `\r` {
				escaped = if i + 2 < body.len && body[i + 2] == `\n` { '\r\n' } else { '\r' }
			} else if next == `\n` {
				escaped = '\n'
			} else {
				is_terminator, _ := squo_is_line_terminator_at(body, i + 1)
				if !is_terminator {
					// `.`: one code point.
					length := utf8_char_len(next)
					escaped = body[i + 1..i + 1 + length]
				}
			}
			if escaped == '' {
				out << ch
				i++
				continue
			}
			matched = '\\' + escaped
		} else if ch in [`"`, `'`, `\``] {
			matched = body[i..i + 1]
		} else if ch == `$` && i + 1 < body.len && body[i + 1] == `{` {
			matched = '\${'
		} else if ch == `\r` {
			newline = if i + 1 < body.len && body[i + 1] == `\n` { '\r\n' } else { '\r' }
			matched = newline
		} else if ch == `\n` {
			newline = '\n'
			matched = newline
		} else {
			out << ch
			i++
			continue
		}
		i += matched.len
		if escaped != '' && (escaped == old_quote || (old_quote == '`' && escaped == '\${')) {
			// Unescape.
			out << escaped.bytes()
		} else if matched == new_quote || (new_quote == '`' && matched == '\${') {
			// Escape.
			out << `\\`
			out << matched.bytes()
		} else if newline != '' && old_quote == '`' {
			// Escape line breaks.
			out << '\\n'.bytes()
		} else {
			out << matched.bytes()
		}
	}
	out << new_quote.bytes()
	return out.bytestr()
}
