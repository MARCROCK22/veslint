module rules

import estree
import time
import x.json2

// Port of the `@stylistic/quote-props` rule of @stylistic/eslint-plugin 5.10.0, with its options
// (`"always"`, the default, `"as-needed"`, `"consistent"` and `"consistent-as-needed"`, and
// `keywords`, `unnecessary` and `numbers`) and its fixes: the quotes around the keys of objects,
// object patterns, property signatures, enum members and import attributes.

const sqp_messages = {
	'requireQuotesDueToReservedWord': "Properties should be quoted as '{{property}}' is a reserved word."
	'inconsistentlyQuotedProperty':   "Inconsistently quoted property '{{key}}' found."
	'unnecessarilyQuotedProperty':    "Unnecessarily quoted property '{{property}}' found."
	'unquotedReservedProperty':       "Unquoted reserved word '{{property}}' used as key."
	'unquotedNumericProperty':        "Unquoted number literal '{{property}}' used as key."
	'unquotedPropertyFound':          "Unquoted property '{{property}}' found."
	'redundantQuoting':               "Properties shouldn't be quoted as all quotes are redundant."
}

// ES3_KEYWORDS of shared/utils/ast.
const sqp_es3_keywords = ['abstract', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class',
	'const', 'continue', 'debugger', 'default', 'delete', 'do', 'double', 'else', 'enum', 'export',
	'extends', 'false', 'final', 'finally', 'float', 'for', 'function', 'goto', 'if', 'implements',
	'import', 'in', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'null', 'package',
	'private', 'protected', 'public', 'return', 'short', 'static', 'super', 'switch', 'synchronized',
	'this', 'throw', 'throws', 'transient', 'true', 'try', 'typeof', 'var', 'void', 'volatile',
	'while', 'with']

// The keywords of acorn for ecmaVersion 5 (espree's default), which `tokenize` gives the types
// Keyword, Null and Boolean.
const sqp_es5_keywords = ['break', 'case', 'catch', 'continue', 'debugger', 'default', 'do', 'else',
	'finally', 'for', 'function', 'if', 'return', 'switch', 'throw', 'try', 'var', 'while', 'with',
	'null', 'true', 'false', 'instanceof', 'typeof', 'void', 'delete', 'new', 'in', 'this']

struct SqpOptions {
	mode              string
	keywords          bool
	check_unnecessary bool
	numbers           bool
}

fn sqp_options(given []json2.Any) !SqpOptions {
	options := sty_options(given, [json2.Any('always')])
	second := sty_option_object(options, 1)
	return SqpOptions{
		mode:              sty_option_string(options, 0, '')
		keywords:          sty_option_bool(second, 'keywords') or { false }
		check_unnecessary: sty_option_bool(second, 'unnecessary') or { true }
		numbers:           sty_option_bool(second, 'numbers') or { false }
	}
}

struct SqpCtx {
	t       &estree.EsTree
	options SqpOptions
}

fn (mut c Checker) lint_stylistic_quote_props(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sqp_options(c.rule_options(stylistic_quote_props))!
	t := c.es_tree(root, abs_path) or { return findings }
	ctx := SqpCtx{
		t:       t
		options: options
	}
	mode := if options.mode == '' { 'always' } else { options.mode }
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.property, .import_attribute, .ts_property_signature, .ts_enum_member {
				if mode == 'always' {
					c.sqp_check_omitted_quotes(ctx, node, mut findings)
				}
				if mode == 'as-needed' {
					c.sqp_check_unnecessary_quotes(ctx, node, mut findings)
				}
			}
			.object_expression {
				c.sqp_check_consistency_for_object(ctx, mode, t.list(node, .properties) or {
					[]int{}
				}, false, mut findings)
			}
			.ts_type_literal {
				c.sqp_check_consistency_for_object(ctx, mode, t.list(node, .members) or { []int{} },
					false, mut findings)
			}
			.ts_interface_body {
				c.sqp_check_consistency_for_object(ctx, mode, t.list(node, .body) or { []int{} },
					false, mut findings)
			}
			.ts_enum_declaration {
				members := if body := t.node(node, .body) {
					t.list(body, .members) or { []int{} }
				} else {
					t.list(node, .members) or { []int{} }
				}
				c.sqp_check_consistency_for_object(ctx, mode, members, true, mut findings)
			}
			.import_declaration, .export_all_declaration, .export_named_declaration {
				// checkImportAttributes.
				if attributes := t.list(node, .attributes) {
					if mode == 'consistent' {
						c.sqp_check_consistency(ctx, attributes, false, mut findings)
					}
					if mode == 'consistent-as-needed' {
						c.sqp_check_consistency(ctx, attributes, true, mut findings)
					}
				}
			}
			else {
				continue
			}
		}
		stats.checked++
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sqp_key is the key of a property (`node.id` of an enum member).
fn sqp_key(t &estree.EsTree, node int) int {
	return if t.typ(node) == .ts_enum_member {
		t.node(node, .id) or { -1 }
	} else {
		t.node(node, .key) or { -1 }
	}
}

fn sqp_is_string_key(t &estree.EsTree, key int) bool {
	return t.typ(key) == .literal && t.get(key, .value) is string
}

fn sqp_is_numeric_key(t &estree.EsTree, key int) bool {
	if t.typ(key) != .literal {
		return false
	}
	value := t.get(key, .value)
	return value is f64 || value is estree.BigIntValue
}

// sqp_key_value is `key.name || key.value` as a string: the name of an identifier, the value of a
// string literal, String(value) of a numeric literal.
fn sqp_key_value(t &estree.EsTree, key int) string {
	// An Identifier or a PrivateIdentifier (`#secret`): its name, without the `#`.
	if t.typ(key) in [.identifier, .private_identifier] {
		return t.string_of(key, .name) or { '' }
	}
	value := t.get(key, .value)
	match value {
		string {
			return value
		}
		estree.BigIntValue {
			return value.digits
		}
		f64 {
			return js_number_string(t.string_of(key, .raw) or { '' }) or { '' }
		}
		else {
			return ''
		}
	}
}

// sqp_quoted_key ports getQuotedKey.
fn (c &Checker) sqp_quoted_key(t &estree.EsTree, key int) string {
	if sqp_is_string_key(t, key) || t.typ(key) == .template_literal {
		return c.src[t.nodes[key].start..t.nodes[key].end]
	}
	// `key.type === 'Identifier' ? key.name : key.value`: a PrivateIdentifier has no `value`.
	if t.typ(key) == .private_identifier {
		return '"undefined"'
	}
	return '"${sqp_key_value(t, key)}"'
}

// SqpToken is the only token of `tokenize(value)` when it is the whole string (an Identifier, a
// Keyword, Null or Boolean token, or a Numeric one); `canonical` tells whether
// `String(+token.value) === token.value`.
struct SqpToken {
	value     string
	numeric   bool
	canonical bool
}

// sqp_whole_token is what areQuotesRedundant needs of espree's `tokenize(value)` (ecmaVersion 5,
// a script): the token when the string is exactly one token of those types, none otherwise (an
// error, other tokens, white space or comments around it, or a token of another type). The
// rule's outcome is the same in all those cases.
fn sqp_whole_token(s string) ?SqpToken {
	if s.len == 0 {
		return none
	}
	if s[0] >= `0` && s[0] <= `9` {
		value := js_atof64(s) or { return none }
		return SqpToken{
			value:     s
			numeric:   true
			canonical: js_number_to_string(value) == s
		}
	}
	// An IdentifierName with \uXXXX escapes, in the BMP (acorn's ES5 rules).
	mut word := []rune{}
	mut escaped := false
	runes := s.runes()
	mut i := 0
	for i < runes.len {
		mut r := runes[i]
		if r == `\\` {
			if i + 6 > runes.len || runes[i + 1] != `u` {
				return none
			}
			hex := runes[i + 2..i + 6].string()
			if !hex.bytes().all(it.is_hex_digit()) {
				return none
			}
			r = rune(u32(hex.parse_uint(16, 32) or { return none }))
			escaped = true
			i += 6
		} else {
			i++
		}
		if u32(r) > 0xFFFF {
			return none
		}
		ok := if word.len == 0 { un_is_id_start_rune(r) } else { un_is_id_part_rune(r) }
		if !ok {
			return none
		}
		word << r
	}
	value := word.string()
	if value in sqp_es5_keywords && escaped {
		// "Escape sequence in keyword".
		return none
	}
	return SqpToken{
		value: value
	}
}

// sqp_quotes_redundant ports areQuotesRedundant.
fn sqp_quotes_redundant(token ?SqpToken, skip_number_literals bool) bool {
	whole := token or { return false }
	return !whole.numeric || (!skip_number_literals && whole.canonical)
}

// sqp_skipped: a method, computed or shorthand property, which the checks leave out.
fn sqp_skipped(t &estree.EsTree, node int) bool {
	if t.typ(node) == .property && (t.flag(node, .method) or { false }
		|| t.flag(node, .computed) or { false } || t.flag(node, .shorthand) or { false }) {
		return true
	}
	return t.typ(node) != .import_attribute && (t.flag(node, .computed) or { false })
}

fn (c &Checker) sqp_report(t &estree.EsTree, node int, message_id string, data map[string]string, key int, text string) Finding {
	return Finding{
		stmt:       c.position_range(t.nodes[node].start, t.nodes[node].end)
		message_id: message_id
		data:       data
		has_fix:    true
		fix:        fix_replace_range(t.nodes[key].start, t.nodes[key].end, text)
	}
}

// sqp_check_unnecessary_quotes ports checkUnnecessaryQuotes.
fn (c &Checker) sqp_check_unnecessary_quotes(ctx SqpCtx, node int, mut findings []Finding) {
	t := ctx.t
	if sqp_skipped(t, node) {
		return
	}
	key := sqp_key(t, node)
	if key < 0 {
		return
	}
	options := ctx.options
	if sqp_is_string_key(t, key) {
		value := sqp_key_value(t, key)
		token := sqp_whole_token(value) or { return }
		if token.value in sqp_es3_keywords && options.keywords {
			return
		}
		if options.check_unnecessary && sqp_quotes_redundant(token, options.numbers) {
			findings << c.sqp_report(t, node, 'unnecessarilyQuotedProperty', {
				'property': value
			}, key, value)
		}
	} else if options.keywords && t.typ(key) == .identifier
		&& sqp_key_value(t, key) in sqp_es3_keywords {
		findings << c.sqp_report(t, node, 'unquotedReservedProperty', {
			'property': sqp_key_value(t, key)
		}, key, c.sqp_quoted_key(t, key))
	} else if options.numbers && sqp_is_numeric_key(t, key) {
		findings << c.sqp_report(t, node, 'unquotedNumericProperty', {
			'property': sqp_key_value(t, key)
		}, key, c.sqp_quoted_key(t, key))
	}
}

// sqp_check_omitted_quotes ports checkOmittedQuotes.
fn (c &Checker) sqp_check_omitted_quotes(ctx SqpCtx, node int, mut findings []Finding) {
	t := ctx.t
	if sqp_skipped(t, node) {
		return
	}
	key := sqp_key(t, node)
	if key < 0 || sqp_is_string_key(t, key) {
		return
	}
	findings << c.sqp_report(t, node, 'unquotedPropertyFound', {
		'property': sqp_key_value(t, key)
	}, key, c.sqp_quoted_key(t, key))
}

// sqp_check_consistency_for_object ports checkConsistencyForObject (for an enum, the members with
// their `id` as `key`), in the consistent modes.
fn (c &Checker) sqp_check_consistency_for_object(ctx SqpCtx, mode string, properties []int, enum_members bool, mut findings []Finding) {
	if mode != 'consistent' && mode != 'consistent-as-needed' {
		return
	}
	t := ctx.t
	filtered := properties.filter(t.typ(it) != .spread_element
		&& (if enum_members { t.node(it, .id) != none } else { t.node(it, .key) != none })
		&& !(t.flag(it, .method) or { false }) && !(t.flag(it, .computed) or { false })
		&& !(t.flag(it, .shorthand) or { false }))
	c.sqp_check_consistency(ctx, filtered, mode == 'consistent-as-needed', mut findings)
}

// sqp_check_consistency ports checkConsistency.
fn (c &Checker) sqp_check_consistency(ctx SqpCtx, properties []int, check_quotes_redundancy bool, mut findings []Finding) {
	t := ctx.t
	options := ctx.options
	mut quoted := []int{}
	mut unquoted := []int{}
	mut keyword_key_name := ''
	mut necessary_quotes := false
	for property in properties {
		key := sqp_key(t, property)
		if key < 0 {
			continue
		}
		if sqp_is_string_key(t, key) {
			quoted << property
			if check_quotes_redundancy {
				token := sqp_whole_token(sqp_key_value(t, key))
				necessary_quotes = necessary_quotes || !sqp_quotes_redundant(token, false)
					|| (options.keywords && (token or { SqpToken{} }).value in sqp_es3_keywords)
			}
		} else if options.keywords && check_quotes_redundancy && t.typ(key) == .identifier
			&& sqp_key_value(t, key) in sqp_es3_keywords {
			unquoted << property
			necessary_quotes = true
			keyword_key_name = sqp_key_value(t, key)
		} else {
			unquoted << property
		}
	}
	if check_quotes_redundancy && quoted.len > 0 && !necessary_quotes {
		for property in quoted {
			key := sqp_key(t, property)
			findings << c.sqp_report(t, property, 'redundantQuoting', map[string]string{},
				key, sqp_key_value(t, key))
		}
	} else if unquoted.len > 0 && keyword_key_name != '' {
		for property in unquoted {
			key := sqp_key(t, property)
			findings << c.sqp_report(t, property, 'requireQuotesDueToReservedWord', {
				'property': keyword_key_name
			}, key, c.sqp_quoted_key(t, key))
		}
	} else if quoted.len > 0 && unquoted.len > 0 {
		for property in unquoted {
			key := sqp_key(t, property)
			findings << c.sqp_report(t, property, 'inconsistentlyQuotedProperty', {
				'key': sqp_key_value(t, key)
			}, key, c.sqp_quoted_key(t, key))
		}
	}
}
