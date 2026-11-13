module rules

import json2
import regexpp
import time
import treesitter { children, named_children, node_field, node_kind, node_start, position_of }

// Port of the `prefer-regex-literals` rule of ESLint 10.6.0.

const prl_messages = {
	'unexpectedRegExp':                   "Use a regular expression literal instead of the 'RegExp' constructor."
	'replaceWithLiteral':                 'Replace with an equivalent regular expression literal.'
	'replaceWithLiteralAndFlags':         "Replace with an equivalent regular expression literal with flags '{{ flags }}'."
	'replaceWithIntendedLiteralAndFlags': "Replace with a regular expression literal with flags '{{ flags }}'."
	'unexpectedRedundantRegExp':          "Regular expression literal is unnecessarily wrapped within a 'RegExp' constructor."
	'unexpectedRedundantRegExpWithFlags': "Use regular expression literal with flags instead of the 'RegExp' constructor."
}

// prl_preceding_tokens are the tokens after which a regular expression literal may start.
const prl_preceding_tokens = ['(', ';', '[', ',', '=', '+', '*', '-', '?', '~', '%', '**', '!',
	'typeof', 'instanceof', '&&', '||', '??', 'return', '...', 'delete', 'void', 'in', '<', '>',
	'<=', '>=', '==', '===', '!=', '!==', '<<', '>>', '>>>', '&', '|', '^', ':', '{', '=>', '*=',
	'<<=', '>>=', '>>>=', '^=', '|=', '&=', '??=', '||=', '&&=', '**=', '+=', '-=', '/=', '%=',
	'/', 'do', 'break', 'continue', 'debugger', 'case', 'throw']

// prl_fixable_chars are the characters of /^[-\w\\[\](){} \t\r\n\v\f!@#$%^&*+=/~`.><?,'"|:;]*$/u.
const prl_fixable_chars = '-\\[](){} \t\r\n\v\f!@#$%^&*+=/~`.><?,\'"|:;_'

fn prl_options(options []json2.Any) !bool {
	o := option_object(prefer_regex_literals, options, ['disallowRedundantWrapping'])!
	return o.bool_value('disallowRedundantWrapping') or { false }
}

fn (mut c Checker) lint_prefer_regex_literals(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	redundant := prl_options(c.rule_options(prefer_regex_literals))!
	ecma_version := if c.ecma_version <= 5 {
		5
	} else {
		if c.ecma_version < 2025 {
			c.ecma_version
		} else {
			2025
		}
	}
	mut findings := []Finding{}
	trace := {
		'RegExp': EsTrace{
			call:      true
			construct: true
		}
	}
	for traced in c.es_global_references(root, trace) {
		stats.checked++
		node := traced.node
		mut args := []C.TSNode{}
		if arguments := node_field(node, 'arguments') {
			if node_kind(arguments) == 'arguments' {
				args = named_children(arguments).filter(node_kind(it) != 'comment').map(unwrap_parens(it))
			}
		}
		if redundant && args.len in [1, 2] && node_kind(args[0]) == 'regex'
			&& (args.len == 1 || c.prl_is_static_string(root, args[1])) {
			pattern, literal_flags := c.es_regex_literal(args[0]) or { continue }
			if args.len == 2 {
				arg_flags := if value := c.prl_string_value(root, args[1]) {
					stv_units_string(value)
				} else {
					''
				}
				mut suggestions := []Suggestion{}
				if c.prl_can_fix_to(root, node, pattern, arg_flags, ecma_version) {
					suggestions << Suggestion{
						message_id: 'replaceWithLiteralAndFlags'
						data:       {
							'flags': arg_flags
						}
						fix:        c.prl_fix(root, node, '/${stv_units_string(pattern)}/${arg_flags}')
					}
				}
				mut merged := []rune{}
				for r in (literal_flags + arg_flags).runes() {
					if r !in merged {
						merged << r
					}
				}
				merged_flags := merged.string()
				if prl_sorted(merged_flags) != prl_sorted(arg_flags)
					&& c.prl_can_fix_to(root, node, pattern, merged_flags, ecma_version) {
					suggestions << Suggestion{
						message_id: 'replaceWithIntendedLiteralAndFlags'
						data:       {
							'flags': merged_flags
						}
						fix:        c.prl_fix(root, node, '/${stv_units_string(pattern)}/${merged_flags}')
					}
				}
				findings << Finding{
					stmt:        position_of(node)
					message_id:  'unexpectedRedundantRegExpWithFlags'
					suggestions: suggestions
				}
			} else {
				mut suggestions := []Suggestion{}
				if c.prl_can_fix_to(root, node, pattern, literal_flags, ecma_version) {
					suggestions << Suggestion{
						message_id: 'replaceWithLiteral'
						fix:        c.prl_fix(root, node, c.text(args[0]))
					}
				}
				findings << Finding{
					stmt:        position_of(node)
					message_id:  'unexpectedRedundantRegExp'
					suggestions: suggestions
				}
			}
			continue
		}
		if args.len !in [1, 2] || !args.all(c.prl_is_static_string(root, it)) {
			continue
		}
		content := c.prl_string_value(root, args[0])
		mut flags := ?string(none)
		if args.len > 1 {
			if value := c.prl_string_value(root, args[1]) {
				flags = stv_units_string(value)
			}
		}
		mut no_fix := false
		if pattern := content {
			if !c.prl_can_fix_to(root, node, pattern, flags or { '' }, ecma_version) {
				no_fix = true
			}
			if !stv_units_string(pattern).runes().all(prl_is_fixable_char(it)) {
				no_fix = true
			}
		} else {
			no_fix = true
		}
		mut text := ''
		if pattern := content {
			text = stv_units_string(pattern)
			if text != '' && !no_fix {
				text = prl_escape(pattern, flags or { '' }, ecma_version) or { text }
			}
		}
		literal := '/${if text == '' { '(?:)' } else { text }}/${flags or { '' }}'
		findings << Finding{
			stmt:        position_of(node)
			message_id:  'unexpectedRegExp'
			suggestions: if no_fix {
				[]Suggestion{}
			} else {
				[
					Suggestion{
						message_id: 'replaceWithLiteral'
						fix:        c.prl_fix(root, node, literal)
					},
				]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn prl_sorted(flags string) string {
	mut runes := flags.runes()
	runes.sort()
	return runes.string()
}

// prl_escape writes the line terminators, tabs and `/` of the pattern as escapes (resolveEscapes
// of each Character).
fn prl_escape(pattern []u16, flags string, ecma_version int) ?string {
	ast := regexpp.parse_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags),
		regexpp.Options{ ecma_version: ecma_version }) or { return none }
	mut out := []u16{}
	mut last := 0
	for event in ast.visit_events() {
		n := ast.nodes[event.node]
		if !event.enter || n.kind != .character {
			continue
		}
		raw := stv_units_string(ast.raw16(event.node))
		escaped := match raw {
			'\n', '\\\n' { '\\n' }
			'\r', '\\\r' { '\\r' }
			'\t', '\\\t' { '\\t' }
			'\v', '\\\v' { '\\v' }
			'\f', '\\\f' { '\\f' }
			'/' { '\\/' }
			else { '' }
		}
		if escaped == '' {
			continue
		}
		out << pattern[last..n.start]
		out << utf16_units(escaped)
		last = n.end
	}
	out << pattern[last..]
	return stv_units_string(out)
}

// prl_is_static_string ports isStaticString: a string literal, a template without substitutions
// or String.raw with one.
fn (mut c Checker) prl_is_static_string(root C.TSNode, n C.TSNode) bool {
	return match node_kind(n) {
		'string' { true }
		'template_string' { !children(n).any(node_kind(it) == 'template_substitution') }
		'call_expression' { c.prl_string_raw_template(root, n) != none }
		else { false }
	}
}

// prl_string_raw_template is the template of a String.raw tagged template without substitutions
// (isStringRawTaggedStaticTemplateLiteral), when `String` is the global one.
fn (mut c Checker) prl_string_raw_template(root C.TSNode, n C.TSNode) ?C.TSNode {
	template := node_field(n, 'arguments')?
	if node_kind(template) != 'template_string'
		|| children(template).any(node_kind(it) == 'template_substitution') {
		return none
	}
	tag := unwrap_parens(node_field(n, 'function')?)
	if !c.es_is_specific_member_access(tag, 'String', 'raw') {
		return none
	}
	object := unwrap_parens(node_field(tag, 'object')?)
	if !c.es_is_global_reference(root, object) {
		return none
	}
	return template
}

// prl_string_value ports getStringValue.
fn (mut c Checker) prl_string_value(root C.TSNode, n C.TSNode) ?[]u16 {
	match node_kind(n) {
		'string' {
			return c.es_string_units(n)
		}
		'template_string' {
			if children(n).any(node_kind(it) == 'template_substitution') {
				return none
			}
			raw := c.text(n)
			return cooked_units(raw[1..raw.len - 1], true)
		}
		'call_expression' {
			template := c.prl_string_raw_template(root, n)?
			raw := c.text(template)
			return utf16_units(raw[1..raw.len - 1].replace('\r\n', '\n').replace('\r', '\n'))
		}
		else {
			return none
		}
	}
}

// prl_can_fix_to ports canFixTo.
fn (mut c Checker) prl_can_fix_to(root C.TSNode, node C.TSNode, pattern []u16, flags string, ecma_version int) bool {
	tokens := c.source_tokens(root)
	start := node_start(node)
	end := c.es_end(node)
	if tokens.inside(start, end, true).any(it.is_comment()) {
		return false
	}
	if before := tokens.before(start, false) {
		if c.src[before.start..before.end] !in prl_preceding_tokens {
			return false
		}
	}
	options := regexpp.Options{
		ecma_version: ecma_version
	}
	regexpp.validate_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags), options) or {
		return false
	}
	if flags != '' {
		units := utf16_units(flags)
		regexpp.validate_flags(units, 0, units.len, options) or { return false }
	}
	return true
}

// prl_fix ports the fix that replaces the call with the literal (getSafeOutput: a space where the
// literal would join the token before or after it).
fn (mut c Checker) prl_fix(root C.TSNode, node C.TSNode, literal string) Fix {
	tokens := c.source_tokens(root)
	start := node_start(node)
	end := c.es_end(node)
	mut text := literal
	if before := tokens.before(start, false) {
		if before.end == start && !es_can_adjacent(before.kind, c.src[before.start..before.end],
			.regular_expression, literal) {
			text = ' ' + text
		}
	}
	if after := tokens.after(end, false) {
		if after.start == end && !es_can_adjacent(.regular_expression, literal, after.kind,
			c.src[after.start..after.end]) {
			text += ' '
		}
	}
	return Fix{start, end, text}
}

// prl_is_fixable_char: a character of [-\w\\[\](){} \t\r\n\v\f!@#$%^&*+=/~`.><?,'"|:;].
fn prl_is_fixable_char(r rune) bool {
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`)
		|| prl_fixable_chars.contains(r.str())
}
