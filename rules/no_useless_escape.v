module rules

import json2
import regexpp
import time
import treesitter { children, named_children, node_end, node_field, node_kind, node_parent, node_start }

// Port of the `no-useless-escape` rule of ESLint 10.6.0.

const nue_messages = {
	'unnecessaryEscape':              'Unnecessary escape character: \\{{character}}.'
	'removeEscape':                   'Remove the `\\`. This maintains the current functionality.'
	'removeEscapeDoNotKeepSemantics': 'Remove the `\\` if it was inserted by mistake.'
	'escapeBackslash':                'Replace the `\\` with `\\\\` to include the actual backslash character.'
}

// The escapes each place allows, as in ESLint (sets of characters).
const nue_valid_string_escapes = '\\nrvtbfux\r\n\u2028\u2029'
const nue_regex_general_escapes = '\\bcdDfnpPrsStvwWxu0123456789]'
const nue_regex_non_charclass_escapes = nue_regex_general_escapes + '^/.$*+?[{}|()Bk'
const nue_regex_classset_escapes = nue_regex_general_escapes + 'q/[{}|()-'
const nue_class_set_reserved_double_punctuator = '!#$%&*+,.:;<=>?@^`~'

fn nue_options(options []json2.Any) ![]string {
	o := option_object(no_useless_escape, options, ['allowRegexCharacters'])!
	return o.string_list('allowRegexCharacters')!
}

fn (mut c Checker) lint_no_useless_escape(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allowed := nue_options(c.rule_options(no_useless_escape))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['string', 'template_string', 'regex'], []) {
		stats.checked++
		match node_kind(node) {
			'regex' {
				c.nue_regexp(node, allowed, mut findings)
			}
			'string' {
				// JSX attribute values are not checked.
				if parent := node_parent(node) {
					if node_kind(parent) in ['jsx_attribute', 'jsx_element', 'jsx_fragment'] {
						continue
					}
				}
				c.nue_string(node, node_start(node), c.text(node), false, mut findings)
			}
			else {
				// A tagged template is not checked.
				if parent := node_parent(node) {
					if node_kind(parent) == 'call_expression' {
						if arguments := node_field(parent, 'arguments') {
							if node_key(arguments) == node_key(node) {
								continue
							}
						}
					}
				}
				// Each TemplateElement: from the backtick or `}` to the `${` or backtick.
				mut start := node_start(node)
				for child in children(node) {
					if node_kind(child) == 'template_substitution' {
						end := node_start(child) + 2
						c.nue_string(node, start, c.src[start..end], true, mut findings)
						start = node_end(child) - 1
					}
				}
				end := c.es_end(node)
				c.nue_string(node, start, c.src[start..end], true, mut findings)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nue_report ports report: the backslash at `offset`, with the suggestions to remove it and (unless
// `no_backslash`) to escape it.
fn (c &Checker) nue_report(node C.TSNode, offset int, character string, no_backslash bool) Finding {
	mut suggestions := [
		Suggestion{
			message_id: if c.nue_is_directive(node) {
				'removeEscapeDoNotKeepSemantics'
			} else {
				'removeEscape'
			}
			fix:        Fix{offset, offset + 1, ''}
		},
	]
	if !no_backslash {
		suggestions << Suggestion{
			message_id: 'escapeBackslash'
			fix:        Fix{offset, offset, '\\'}
		}
	}
	return Finding{
		stmt:        c.position_at(offset)
		message_id:  'unnecessaryEscape'
		data:        {
			'character': character
		}
		suggestions: suggestions
	}
}

// nue_is_directive: the string is a directive of a program or function body (isDirective of its
// parent).
fn (c &Checker) nue_is_directive(node C.TSNode) bool {
	if node_kind(node) != 'string' {
		return false
	}
	statement := node_parent(node) or { return false }
	if node_kind(statement) != 'expression_statement' {
		return false
	}
	body := node_parent(statement) or { return false }
	if node_kind(body) == 'statement_block' {
		owner := node_parent(body) or { return false }
		if node_kind(owner) !in function_kinds {
			return false
		}
	} else if node_kind(body) != 'program' {
		return false
	}
	return nue_directive_prologue(body).any(node_key(it) == node_key(statement))
}

// nue_directive_prologue are the leading statements of a body that are a string alone (ESTree's
// directives).
fn nue_directive_prologue(body C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	for statement in named_children(body) {
		kind := node_kind(statement)
		if kind in ['comment', 'hash_bang_line', 'html_comment'] {
			continue
		}
		if kind != 'expression_statement' {
			break
		}
		expressions := named_children(statement).filter(node_kind(it) != 'comment')
		if expressions.len != 1 || node_kind(expressions[0]) != 'string' {
			break
		}
		out << statement
	}
	return out
}

// nue_string ports validateString over the text of a string literal or template element that
// starts at `start`: each `\` followed by something other than a digit.
fn (c &Checker) nue_string(node C.TSNode, start int, value string, template bool, mut findings []Finding) {
	mut i := 0
	for i < value.len {
		if value[i] != `\\` || i + 1 >= value.len {
			i++
			continue
		}
		len := utf8_char_len(value[i + 1])
		next := value[i + 1..i + 1 + len]
		if next[0].is_digit() {
			i++
			continue
		}
		mut unnecessary := !nue_valid_string_escapes.contains(next)
		mut quote := false
		if template {
			quote = next == '`'
			if next == '$' {
				unnecessary = !(i + 2 < value.len && value[i + 2] == `{`)
			} else if next == '{' {
				unnecessary = !(i > 0 && value[i - 1] == `$`)
			}
		} else {
			quote = next == value[0..1]
		}
		if unnecessary && !quote {
			findings << c.nue_report(node, start + i, next, false)
		}
		i += 1 + len
	}
}

// nue_regexp ports validateRegExp.
fn (c &Checker) nue_regexp(node C.TSNode, allowed []string, mut findings []Finding) {
	pattern, flags := c.es_regex_literal(node) or { return }
	unicode_sets := flags.contains('v')
	ast := regexpp.parse_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags),
		regexpp.Options{}) or { return }
	text := stv_units_string(pattern)
	mut classes := []int{} // the stack of character classes, innermost last
	for event in ast.visit_events() {
		n := ast.nodes[event.node]
		if n.kind in [.character_class, .expression_character_class] {
			if event.enter {
				classes << event.node
			} else {
				classes.pop()
			}
			continue
		}
		if !event.enter || n.kind != .character {
			continue
		}
		raw := ast.raw16(event.node)
		if raw.len < 2 || raw[0] != `\\` {
			continue
		}
		escaped := stv_units_string(raw[1..])
		if escaped != rune(n.value).str() || escaped in allowed {
			continue
		}
		allowed_escapes := if classes.len > 0 {
			if unicode_sets { nue_regex_classset_escapes } else { nue_regex_general_escapes }
		} else {
			nue_regex_non_charclass_escapes
		}
		if allowed_escapes.contains(escaped) {
			continue
		}
		mut no_backslash := false
		if classes.len > 0 {
			class := ast.nodes[classes.last()]
			if escaped == '^' && class.start + 1 == n.start {
				continue
			}
			if !unicode_sets {
				if escaped == '-' && class.start + 1 != n.start && n.end != class.end - 1 {
					continue
				}
			} else {
				if nue_class_set_reserved_double_punctuator.contains(escaped) {
					if n.end < pattern.len && rune(pattern[n.end]).str() == escaped {
						continue
					}
					if n.start > 0 && rune(pattern[n.start - 1]).str() == escaped {
						if escaped != '^' {
							continue
						}
						if !class.negate {
							continue
						}
						if class.start + 1 < n.start - 1 {
							continue
						}
					}
				}
				if n.parent >= 0
					&& ast.nodes[n.parent].kind in [.class_intersection, .class_subtraction] {
					no_backslash = true
				}
			}
		}
		offset := node_start(node) + 1 + es_units_byte_offset(text, n.start)
		findings << c.nue_report(node, offset, escaped, no_backslash)
	}
}
