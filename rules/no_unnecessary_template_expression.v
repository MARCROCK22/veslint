module rules

import time
import tsgo { TypeResponse, handle_kind }
import treesitter { Ident, children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kind, nodes_of_kinds, position_of }

// Port of the `no-unnecessary-template-expression` rule of typescript-eslint 8.62.0 (it has no
// options), with its fixes.

const nute_messages = {
	'noUnnecessaryTemplateExpression': 'Template literal expression is unnecessary and can be simplified.'
}

// SyntaxKind.EnumMember of TypeScript 7.1.0-beta.
const nute_syntax_kind_enum_member = u32(307)

// NuteTemplate is a TemplateLiteral (not tagged) or a TSTemplateLiteralType with interpolations.
struct NuteTemplate {
	node           C.TSNode
	is_type        bool       // a TSTemplateLiteralType
	substitutions  []C.TSNode // `template_substitution` or `template_type` (`${…}`) nodes
	interpolations []C.TSNode // the ESTree expression or type of each one, without parentheses
	quasis         []string   // raw text of each quasi: substitutions.len + 1
mut:
	awaited    bool // the template follows an `await`, which TypeScript may read as a tag
	await_node C.TSNode
}

fn (mut c Checker) lint_no_unnecessary_template_expression(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut templates := []NuteTemplate{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['template_string', 'template_literal_type'], []string{}) {
		is_type := node_kind(node) == 'template_literal_type'
		mut template := c.nute_template(node, is_type) or { continue }
		if !is_type {
			parent := node_parent(node) or { continue }
			parent_kind := node_kind(parent)
			if parent_kind == 'call_expression' {
				// A tagged template is not checked.
				if args := node_field(parent, 'arguments') {
					if node_key(args) == node_key(node) {
						continue
					}
				}
			} else if parent_kind == 'await_expression' {
				template.awaited = true
				template.await_node = parent
				spans << node_span(parent)
			}
		}
		if c.nute_is_trivial(template) {
			first := template.interpolations[0]
			spans << if is_type { c.type_node_span(first) } else { node_span(first) }
		}
		templates << template
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for template in templates {
		if template.awaited && c.await_reading(template.await_node) == .tagged_template {
			continue
		}
		if c.nute_is_trivial(template) && c.nute_single_string(template)! {
			// reportSingleInterpolation: from two code units before the interpolation.
			// Its fix moves the interpolation to where the template is (getMovedNodeCode).
			code := c.moved_node_code(es_child(template.interpolations[0]), es_child(template.node))
			findings << Finding{
				stmt:       c.nute_position_before(template.interpolations[0], 2)
				message_id: 'noUnnecessaryTemplateExpression'
				has_fix:    true
				fix:        fix_replace(template.node, code)
			}
			continue
		}
		mut unnecessary := []int{}
		for i, _ in template.substitutions {
			if c.nute_is_unnecessary(template, i) {
				unnecessary << i
			}
		}
		fixes := c.nute_fixes(template, unnecessary)!
		for k, i in unnecessary {
			// From the `${` of the substitution (prevQuasi.range[1] - 2).
			findings << Finding{
				stmt:       position_of(template.substitutions[i])
				message_id: 'noUnnecessaryTemplateExpression'
				has_fix:    true
				fix:        fixes[k]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += templates.len
	return findings
}

// nute_template reads the quasis and interpolations of a template; none if it has no
// interpolations (a template type without them is a TSLiteralType in ESTree).
fn (c &Checker) nute_template(node C.TSNode, is_type bool) ?NuteTemplate {
	substitution_kind := if is_type { 'template_type' } else { 'template_substitution' }
	mut substitutions := []C.TSNode{}
	mut interpolations := []C.TSNode{}
	mut quasis := []string{}
	mut quasi_start := node_start(node) + 1
	mut closed := false
	for child in children(node) {
		kind := node_kind(child)
		if kind == substitution_kind {
			inner := first_named(child)?
			quasis << c.src[quasi_start..node_start(child)]
			substitutions << child
			interpolations << if is_type { unwrap_type_parens(inner) } else { unwrap_parens(inner) }
			quasi_start = node_end(child)
		} else if kind == '`' && node_start(child) >= quasi_start && node_start(child) > node_start(node) {
			quasis << c.src[quasi_start..node_start(child)]
			closed = true
		}
	}
	if !closed || substitutions.len == 0 {
		return none
	}
	return NuteTemplate{
		node:           node
		is_type:        is_type
		substitutions:  substitutions
		interpolations: interpolations
		quasis:         quasis
	}
}

// nute_is_trivial ports isTrivialInterpolation without comments between the quasis: the template
// is exactly `${…}`.
fn (c &Checker) nute_is_trivial(t NuteTemplate) bool {
	return t.substitutions.len == 1 && t.quasis[0] == '' && t.quasis[1] == ''
		&& !nute_has_comments(t.substitutions[0])
}

// nute_has_comments ports hasCommentsBetweenQuasi: a comment inside the `${…}`.
fn nute_has_comments(substitution C.TSNode) bool {
	return nodes_of_kind(substitution, c'comment').len > 0
}

// nute_single_string decides reportSingleInterpolation: the type of the only interpolation (its
// constraint, getConstraintInfo) is a string. In a template type, not a type parameter nor an enum
// member.
fn (mut c Checker) nute_single_string(t NuteTemplate) !bool {
	ty := c.node_type(t.interpolations[0]) or { return false }
	is_type_parameter := ty.flags & type_flag_type_parameter != 0
	constraint := if is_type_parameter { c.base_constraint(ty)! } else { ty }
	if constraint.is_null() || !c.nute_is_underlying_type_string(constraint)! {
		return false
	}
	if t.is_type && (is_type_parameter || c.nute_is_enum_member_type(constraint)!) {
		return false
	}
	return true
}

// nute_is_underlying_type_string ports isUnderlyingTypeString, whose isStringLike is the
// union-aware isTypeFlagSet.
fn (mut c Checker) nute_is_underlying_type_string(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if c.type_flags(part)! & type_flag_string_like == 0 {
				return false
			}
		}
		return true
	}
	if t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.type_flags(part)! & type_flag_string_like != 0 {
				return true
			}
		}
		return false
	}
	return c.type_flags(t)! & type_flag_string_like != 0
}

// nute_is_enum_member_type ports isEnumMemberType: a part whose symbol is declared by an enum
// member.
fn (mut c Checker) nute_is_enum_member_type(t TypeResponse) !bool {
	for part in c.type_constituents(t)! {
		if part.symbol == 0 {
			continue
		}
		symbol := c.symbol_of(part)!
		if symbol.value_declaration != ''
			&& handle_kind(symbol.value_declaration) == nute_syntax_kind_enum_member {
			return true
		}
	}
	return false
}

// nute_is_unnecessary ports isUnnecessaryValueInterpolation and isUnncessaryTypeInterpolation for
// the interpolation `i`.
fn (c &Checker) nute_is_unnecessary(t NuteTemplate, i int) bool {
	if nute_has_comments(t.substitutions[i]) {
		return false
	}
	n := t.interpolations[i]
	next := t.quasis[i + 1]
	kind := node_kind(n)
	if !t.is_type {
		// isFixableIdentifier: undefined, Infinity or NaN.
		if (kind == 'undefined' || kind == 'identifier')
			&& c.text(n) in ['undefined', 'Infinity', 'NaN'] {
			return true
		}
		if kind in ['string', 'number', 'true', 'false', 'null', 'regex'] {
			return c.nute_literal_allowed(n, next)
		}
		if kind == 'template_string' {
			return c.nute_template_allowed(n, next)
		}
		return false
	}
	if kind == 'literal_type' {
		literal := first_named(n) or { return false }
		return match node_kind(literal) {
			'string', 'number', 'true', 'false' { c.nute_literal_allowed(literal, next) }
			'null', 'undefined' { true } // TSNullKeyword and TSUndefinedKeyword
			else { false } // `-1` is a TSLiteralType of a UnaryExpression
		}
	}
	if kind == 'template_literal_type' {
		// Without interpolations: a TSLiteralType of a TemplateLiteral.
		for child in children(n) {
			if node_kind(child) == 'template_type' {
				return false
			}
		}
		return c.nute_template_allowed(n, next)
	}
	return false
}

// nute_fixes ports the fixes of getReportDescriptors for the unnecessary interpolations of a
// template (their indexes, in order): each one loses its `${` and `}`, a literal becomes its text
// and a template its content, with what would then read as a `${` or end the template escaped.
// Like the original it goes from the last interpolation to the first, remembering whether what
// follows starts with `{`.
fn (mut c Checker) nute_fixes(t NuteTemplate, unnecessary []int) ![]Fix {
	mut out := []Fix{len: unnecessary.len}
	mut next_is_brace := false
	for k := unnecessary.len - 1; k >= 0; k-- {
		i := unnecessary[k]
		substitution := t.substitutions[i]
		interpolation := t.interpolations[i]
		// Remove the quasis' parts that are related to the current expression.
		mut fixes := [
			fix_remove_range(node_start(substitution), node_start(interpolation)),
			fix_remove_range(node_end(interpolation), node_end(substitution)),
		]
		if t.quasis[i + 1] != '' {
			next_is_brace = t.quasis[i + 1].starts_with('{')
		}
		if literal := nute_literal(interpolation) {
			mut escaped := nute_escape(c.nute_literal_text(literal))
			// `...${'...$'}{...`
			if next_is_brace && nute_ends_with_unescaped_dollar(escaped) {
				escaped = escaped[..escaped.len - 1] + '\\$'
			}
			if escaped != '' {
				next_is_brace = escaped.starts_with('{')
			}
			fixes << fix_replace(literal, escaped)
		} else if nute_is_template(interpolation) {
			quasis := c.nute_quasis(interpolation)
			// `... ${`... $`}${'{...'} ...`
			if next_is_brace && nute_ends_with_unescaped_dollar(quasis.last()) {
				fixes << fix_insert_at(node_end(interpolation) - 2, '\\')
			}
			if quasis.len == 1 && quasis[0] != '' {
				next_is_brace = quasis[0].starts_with('{')
			}
			// Remove the beginning and trailing backtick characters.
			fixes << fix_remove_range(node_start(interpolation), node_start(interpolation) + 1)
			fixes << fix_remove_range(node_end(interpolation) - 1, node_end(interpolation))
		} else {
			next_is_brace = false
		}
		// `... $${'{...'} ...`
		if next_is_brace && nute_ends_with_unescaped_dollar(t.quasis[i]) {
			fixes << fix_replace_range(node_start(substitution) - 1, node_start(substitution),
				'\\$')
		}
		_, fix := c.merge_fixes(fixes)!
		out[k] = fix
	}
	return out
}

// nute_literal ports getLiteral: the Literal an interpolation is, or the one of its TSLiteralType.
fn nute_literal(interpolation C.TSNode) ?C.TSNode {
	mut node := interpolation
	if node_kind(node) == 'literal_type' {
		node = first_named(node)?
		// `null` and `undefined` are keyword types, not literals.
		if node_kind(node) == 'null' {
			return none
		}
	}
	if node_kind(node) in ['string', 'number', 'true', 'false', 'null', 'regex'] {
		return node
	}
	return none
}

// nute_is_template ports getTemplateLiteral: a TemplateLiteral, or the TSLiteralType of one (a
// template type without interpolations).
fn nute_is_template(interpolation C.TSNode) bool {
	if node_kind(interpolation) == 'template_string' {
		return true
	}
	return node_kind(interpolation) == 'template_literal_type'
		&& children(interpolation).all(node_kind(it) != 'template_type')
}

// nute_quasis are the raw texts of the quasis of a template.
fn (c &Checker) nute_quasis(template C.TSNode) []string {
	mut quasis := []string{}
	mut start := node_start(template) + 1
	for child in children(template) {
		if node_kind(child) in ['template_substitution', 'template_type'] {
			quasis << c.src[start..node_start(child)]
			start = node_end(child)
		}
	}
	end := node_end(template) - 1
	quasis << if end > start { c.src[start..end] } else { '' }
	return quasis
}

// nute_literal_text is what a literal contributes to the template: the raw text of a string
// without its quotes, or `String(value)` with every backslash doubled (a number, a BigInt, a
// boolean, `null`, or a RegExp, which is null if it is not valid).
fn (mut c Checker) nute_literal_text(literal C.TSNode) string {
	text := c.text(literal)
	return match node_kind(literal) {
		'string' {
			text[1..text.len - 1]
		}
		'number' {
			js_number_string(text) or { text }
		}
		'regex' {
			value := c.get_static_value(literal)
			if value.found && value.value.kind == .regexp_ {
				'/${stv_units_string(value.value.regexp.source)}/${value.value.regexp.flags}'.replace('\\',
					'\\\\')
			} else {
				'null'
			}
		}
		else {
			text
		}
	}
}

// nute_backslashes_before counts the backslashes right before the byte `i` of `s`.
fn nute_backslashes_before(s string, i int) int {
	mut count := 0
	for i - count > 0 && s[i - count - 1] == `\\` {
		count++
	}
	return count
}

// nute_escape escapes every backtick and `${` of the text that is not escaped already (one after
// an even number of backslashes).
fn nute_escape(s string) string {
	mut out := []u8{cap: s.len + 2}
	mut i := 0
	for i < s.len {
		length := if s[i] == `\`` {
			1
		} else if s[i] == `$` && i + 1 < s.len && s[i + 1] == `{` {
			2
		} else {
			0
		}
		if length == 0 {
			out << s[i]
			i++
			continue
		}
		if nute_backslashes_before(s, i) % 2 == 0 {
			out << `\\`
		}
		out << s[i..i + length].bytes()
		i += length
	}
	return out.bytestr()
}

// nute_ends_with_unescaped_dollar ports endsWithUnescapedDollarSign.
fn nute_ends_with_unescaped_dollar(s string) bool {
	return s.ends_with('$') && nute_backslashes_before(s, s.len - 1) % 2 == 0
}

// nute_literal_allowed: a literal is unnecessary unless it is a whitespace string followed by a
// line break (allow trailing whitespace literal).
fn (c &Checker) nute_literal_allowed(literal C.TSNode, next string) bool {
	if !nute_starts_with_line_break(next) {
		return true
	}
	if node_kind(literal) != 'string' {
		return true
	}
	text := c.text(literal)
	value := cooked_string(text[1..text.len - 1], false) or { return true }
	return !nute_is_whitespace(value)
}

// nute_template_allowed: the same for a template without interpolations, on its raw text.
fn (c &Checker) nute_template_allowed(template C.TSNode, next string) bool {
	if !nute_starts_with_line_break(next) {
		return true
	}
	for child in children(template) {
		if node_kind(child) in ['template_substitution', 'template_type'] {
			return true
		}
	}
	text := c.text(template)
	return !nute_is_whitespace(text[1..text.len - 1])
}

// nute_is_whitespace ports isWhitespace: /^\s*$/.
fn nute_is_whitespace(s string) bool {
	for r in s.runes() {
		if !is_js_space(r) {
			return false
		}
	}
	return true
}

// nute_starts_with_line_break ports startsWithNewLine: \r, \n, U+2028 or U+2029 first.
fn nute_starts_with_line_break(s string) bool {
	return s.starts_with('\n') || s.starts_with('\r') || s.starts_with(' ')
		|| s.starts_with(' ')
}

// nute_position_before is the position `units` UTF-16 code units before the start of `n`, like
// sourceCode.getLocFromIndex(range[0] - units).
fn (c &Checker) nute_position_before(n C.TSNode, units int) Ident {
	mut offset := node_start(n)
	mut left := units
	for left > 0 && offset > 0 {
		mut prev := offset - 1
		for prev > 0 && c.src[prev] & 0xc0 == 0x80 {
			prev--
		}
		// A character of 4 UTF-8 bytes is 2 UTF-16 code units.
		left -= if offset - prev == 4 { 2 } else { 1 }
		offset = prev
	}
	return c.position_at(offset)
}
