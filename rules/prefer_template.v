module rules

import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `prefer-template` rule of ESLint 10.6.0, with its fix (it has no options).

const ptpl_messages = {
	'unexpectedStringConcatenation': 'Unexpected string concatenation.'
}

fn (mut c Checker) lint_prefer_template(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut done := map[int]bool{}
	for node in c.nodes_of_kinds(root, ['string', 'template_string'], []) {
		parent := cti_estree_parent(node) or { continue }
		if !ptpl_is_concatenation(parent) {
			continue
		}
		stats.checked++
		mut top := parent
		for {
			up := cti_estree_parent(top) or { break }
			if !ptpl_is_concatenation(up) {
				break
			}
			top = up
		}
		if node_start(top) in done {
			continue
		}
		done[node_start(top)] = true
		if !c.ptpl_has_non_string(top) {
			continue
		}
		mut has_fix := false
		mut fix := Fix{}
		if !c.ptpl_has_octal_escape(top) {
			has_fix = true
			fix = fix_replace_range(node_start(top), c.es_end(top), c.ptpl_template(top, none,
				none))
		}
		findings << Finding{
			stmt:       position_of(top)
			message_id: 'unexpectedStringConcatenation'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn ptpl_is_concatenation(n C.TSNode) bool {
	return node_kind(n) == 'binary_expression' && operator_of(n) == '+'
}

fn ptpl_operands(n C.TSNode) (C.TSNode, C.TSNode) {
	left := unwrap_parens(node_field(n, 'left') or { n })
	right := unwrap_parens(node_field(n, 'right') or { n })
	return left, right
}

// ptpl_has_octal_escape ports hasOctalOrNonOctalDecimalEscapeSequence on the strings of the
// concatenation: an escape `\1`…`\9`, or `\0` before a digit.
fn (c &Checker) ptpl_has_octal_escape(n C.TSNode) bool {
	if ptpl_is_concatenation(n) {
		left, right := ptpl_operands(n)
		return c.ptpl_has_octal_escape(left) || c.ptpl_has_octal_escape(right)
	}
	if node_kind(n) != 'string' {
		return false
	}
	raw := c.text(n)
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

fn (c &Checker) ptpl_has_string(n C.TSNode) bool {
	if ptpl_is_concatenation(n) {
		left, right := ptpl_operands(n)
		return c.ptpl_has_string(right) || c.ptpl_has_string(left)
	}
	return node_kind(n) in ['string', 'template_string']
}

fn (c &Checker) ptpl_has_non_string(n C.TSNode) bool {
	if ptpl_is_concatenation(n) {
		left, right := ptpl_operands(n)
		return c.ptpl_has_non_string(right) || c.ptpl_has_non_string(left)
	}
	return node_kind(n) !in ['string', 'template_string']
}

// ptpl_starts_with_curly ports startsWithTemplateCurly: never for a string or a template (the
// first quasi of a template is never empty, its range has the delimiters), always for anything
// else.
fn ptpl_starts_with_curly(n C.TSNode) bool {
	if estree_binary_kind(n) == 'BinaryExpression' {
		left, _ := ptpl_operands(n)
		return ptpl_starts_with_curly(left)
	}
	return node_kind(n) !in ['string', 'template_string']
}

fn ptpl_ends_with_curly(n C.TSNode) bool {
	if estree_binary_kind(n) == 'BinaryExpression' {
		_, right := ptpl_operands(n)
		return ptpl_starts_with_curly(right)
	}
	return node_kind(n) !in ['string', 'template_string']
}

// ptpl_text_between ports getTextBetween: what is between the tokens from `start` to `end`.
fn (mut c Checker) ptpl_text_between(n C.TSNode, start int, end int) string {
	tokens := c.source_tokens(n)
	mut out := ''
	mut previous := start
	for token in tokens.inside(start, end, false) {
		out += c.src[previous..token.start]
		previous = token.end
	}
	return out + c.src[previous..end]
}

// ptpl_string_template ports the conversion of a string literal into a template.
fn (c &Checker) ptpl_string_template(n C.TSNode) string {
	raw := c.text(n)
	quote := raw[0]
	body := raw[1..raw.len - 1]
	// `${` and backquotes after an even number of backslashes get one more.
	mut escaped := []u8{}
	mut i := 0
	for i < body.len {
		mut j := i
		for j < body.len && body[j] == `\\` {
			j++
		}
		backslashes := j - i
		if j < body.len && (body[j] == `\`` || (body[j] == `$` && j + 1 < body.len && body[j + 1] == `{`)) {
			escaped << body[i..j].bytes()
			if backslashes % 2 == 0 {
				escaped << `\\`
			}
			if body[j] == `$` {
				escaped << `$`
				escaped << `{`
				i = j + 2
			} else {
				escaped << `\``
				i = j + 1
			}
			continue
		}
		if backslashes > 0 {
			escaped << body[i..j].bytes()
			i = j
			continue
		}
		escaped << body[i]
		i++
	}
	// Then `\` before the quote of the string is the quote alone.
	text := escaped.bytestr()
	mut out := []u8{}
	mut k := 0
	for k < text.len {
		if text[k] == `\\` && k + 1 < text.len && text[k + 1] == quote {
			out << quote
			k += 2
			continue
		}
		out << text[k]
		k++
	}
	return '`${out.bytestr()}`'
}

// ptpl_template ports getTemplateLiteral.
fn (mut c Checker) ptpl_template(n C.TSNode, before ?string, after ?string) string {
	kind := node_kind(n)
	if kind == 'string' {
		return c.ptpl_string_template(n)
	}
	if kind == 'template_string' {
		return c.es_text(n)
	}
	if ptpl_is_concatenation(n) && c.ptpl_has_string(n) {
		left, right := ptpl_operands(n)
		tokens := c.source_tokens(n)
		mut plus := tokens.after(c.es_end(left), false) or { return c.es_text(n) }
		for c.src[plus.start..plus.end] != '+' {
			plus = tokens.after(plus.end, false) or { return c.es_text(n) }
		}
		before_plus := c.ptpl_text_between(n, c.es_end(left), plus.start)
		after_plus := c.ptpl_text_between(n, plus.end, node_start(right))
		if ptpl_ends_with_curly(left) {
			l := c.ptpl_template(left, before, before_plus + after_plus)
			r := c.ptpl_template(right, none, after)
			return l[..l.len - 1] + r[1..]
		}
		if ptpl_starts_with_curly(right) {
			l := c.ptpl_template(left, before, none)
			r := c.ptpl_template(right, before_plus + after_plus, after)
			return l[..l.len - 1] + r[1..]
		}
		return '${c.ptpl_template(left, before, none)}${before_plus}+${after_plus}${c.ptpl_template(right, after, none)}'
	}
	return '`\${${before or { '' }}${c.es_text(n)}${after or { '' }}}`'
}
