module rules

import estree
import regexpp
import time

// Port of the `unicorn/prefer-string-replace-all` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes. Patterns are read with regexpp/ where the plugin uses regjsparser
// 0.13.4: upsra_parse turns regexpp's tree into the one regjsparser gives (its node types and
// value kinds, its greedy three-digit octal escapes, `\k<name>` as a reference without named
// groups, and the patterns it rejects: modifiers, `\k` otherwise, `\B` in a class).

const upsra_messages = {
	'method':     'Prefer `String#replaceAll()` over `String#replace()`.'
	'pattern':    'This pattern can be replaced with {{replacement}}.'
	'split-join': 'Prefer `String#replaceAll()` over `String#split().join()`.'
}

// UpsraType is the `type` of a regjsparser node (`group` split by its `behavior`).
enum UpsraType {
	value
	character_class
	quantifier
	group_ignore // `(?:…)`
	group_normal // a capturing group
	lookaround   // a lookahead or lookbehind group
	alternative
	disjunction
	anchor
	reference
	dot
	class_escape // characterClassEscape, unicodePropertyEscape
	other        // what only appears inside a class (ranges, class strings, set operations)
}

// UpsraValueKind is what getValueReplacement does with a value of a regjsparser `kind`.
enum UpsraValueKind {
	raw            // symbol, singleEscape, hexadecimalEscape, unicodeEscape, …: the raw text
	strip          // identifier, or a symbol `\8`: the raw text without its backslash
	control_letter // controlLetter
	code_point     // null, octal: `\u{…}`
	empty          // an identifier of regjsparser whose raw has no backslash (`[\&]` with `v`)
}

struct UpsraNode {
mut:
	typ        UpsraType
	kind       UpsraValueKind
	code_point int
	raw        []u16
	negative   bool
	body       []int
	min        f64
	max        f64
}

struct UpsraTree {
mut:
	nodes []UpsraNode
	root  int
}

struct UpsraParser {
	ast          regexpp.Ast
	unicode      bool // `u` or `v`
	unicode_sets bool
mut:
	tree UpsraTree
}

fn (mut p UpsraParser) add(n UpsraNode) int {
	p.tree.nodes << n
	return p.tree.nodes.len - 1
}

// upsra_is_octal_digit: a UTF-16 unit `0`–`7`.
fn upsra_is_octal_digit(u u16) bool {
	return u >= `0` && u <= `7`
}

// upsra_octal_digits is the number of digits of a legacy octal escape (`\12`), 0 for another
// raw text.
fn upsra_octal_digits(raw []u16) int {
	if raw.len < 2 || raw[0] != `\\` || !raw[1..].all(upsra_is_octal_digit(it)) {
		return 0
	}
	return raw.len - 1
}

// upsra_is_name_unit: a unit of a group name for regjsparser (approximated for non-ASCII units).
fn upsra_is_name_unit(u u16, first bool) bool {
	return (u >= `a` && u <= `z`) || (u >= `A` && u <= `Z`) || u in [u16(`$`), `_`] || u >= 0x80
		|| (!first && u >= `0` && u <= `9`)
}

// reference_end is the index after the elements that regjsparser reads as the reference
// `\k<name>` without named groups, starting at the `\k` character at `i`; none where it fails.
fn (p &UpsraParser) reference_end(elements []int, i int) ?int {
	mut j := i + 1
	if j >= elements.len || p.ast.nodes[elements[j]].kind != .character
		|| p.ast.raw16(elements[j]) != [u16(`<`)] {
		return none
	}
	j++
	mut name_length := 0
	for j < elements.len {
		mut n := p.ast.nodes[elements[j]]
		if n.kind == .quantifier && p.ast.nodes[n.element].kind == .character
			&& p.ast.raw16(n.element) == [u16(`>`)] && name_length > 0 {
			// `\k<a>+`: the quantifier is of the whole reference.
			return j
		}
		if n.kind != .character {
			return none
		}
		raw := p.ast.raw16(elements[j])
		if raw == [u16(`>`)] {
			return if name_length > 0 { j + 1 } else { none }
		}
		if raw.len != 1 || !upsra_is_name_unit(raw[0], name_length == 0) {
			return none
		}
		name_length++
		j++
	}
	return none
}

// value_kind classifies a regexpp Character as regjsparser does its value.
fn (p &UpsraParser) value_kind(raw []u16, in_class bool) UpsraValueKind {
	if raw.len < 2 || raw[0] != `\\` {
		return .raw
	}
	e := raw[1]
	if e == `c` && raw.len == 3 {
		return .control_letter
	}
	if raw.len == 2 && e == `0` {
		return .code_point
	}
	if !p.unicode && upsra_octal_digits(raw) > 0 {
		return .code_point
	}
	return match e {
		`t`, `n`, `v`, `f`, `r`, `b` {
			.raw
		}
		`-` {
			if p.unicode && in_class { .raw } else { .strip }
		}
		`x`, `u` {
			if raw.len > 2 { .raw } else { .strip }
		}
		`&`, `!`, `#`, `%`, `,`, `:`, `;`, `<`, `=`, `>`, `@`, `\``, `~` {
			if p.unicode_sets && in_class { .empty } else { .strip }
		}
		else {
			.strip
		}
	}
}

// elements converts a list of regexpp elements (of an alternative or a class).
fn (mut p UpsraParser) elements(elements []int, in_class bool) ?[]int {
	mut out := []int{}
	mut i := 0
	for i < elements.len {
		element := elements[i]
		n := p.ast.nodes[element]
		if n.kind != .character {
			out << p.node(element)?
			i++
			continue
		}
		mut raw := p.ast.raw16(element).clone()
		if !p.unicode && raw == [u16(`\\`), `k`] {
			if in_class {
				return none
			}
			end := p.reference_end(elements, i)?
			out << p.add(UpsraNode{
				typ: .reference
			})
			i = end
			continue
		}
		if in_class && raw == [u16(`\\`), `B`] {
			return none
		}
		mut code_point := n.value
		i++
		// regjsparser reads up to three octal digits: `\400` is one escape, `\40` and `0` for
		// regexpp.
		mut digits := upsra_octal_digits(raw)
		if !p.unicode && digits > 0 && !(raw.len == 2 && raw[1] == `0`) {
			for digits < 3 && i < elements.len && p.ast.nodes[elements[i]].kind == .character {
				next := p.ast.raw16(elements[i])
				if next.len != 1 || !upsra_is_octal_digit(next[0]) {
					break
				}
				raw << next[0]
				code_point = code_point * 8 + int(next[0] - `0`)
				digits++
				i++
			}
		}
		out << p.add(UpsraNode{
			typ:        .value
			kind:       p.value_kind(raw, in_class)
			code_point: code_point
			raw:        raw
		})
	}
	return out
}

// alternatives converts the alternatives of a pattern or a group: the body of regjsparser's
// group (the terms, or one disjunction).
fn (mut p UpsraParser) alternatives(alternatives []int) ?[]int {
	if alternatives.len == 1 {
		return p.elements(p.ast.nodes[alternatives[0]].elements, false)
	}
	mut body := []int{}
	for alternative in alternatives {
		body << p.term(p.elements(p.ast.nodes[alternative].elements, false)?)
	}
	return [p.add(UpsraNode{ typ: .disjunction, body: body })]
}

// term is a list of terms as regjsparser gives it: the term itself when there is one.
fn (mut p UpsraParser) term(body []int) int {
	if body.len == 1 {
		return body[0]
	}
	return p.add(UpsraNode{ typ: .alternative, body: body })
}

fn (mut p UpsraParser) node(i int) ?int {
	n := p.ast.nodes[i]
	match n.kind {
		.group {
			if n.modifiers >= 0 {
				// regjsparser does not read modifiers.
				return none
			}
			return p.add(UpsraNode{ typ: .group_ignore, body: p.alternatives(n.alternatives)? })
		}
		.capturing_group {
			return p.add(UpsraNode{ typ: .group_normal, body: p.alternatives(n.alternatives)? })
		}
		.assertion {
			if n.assertion_kind in [.lookahead, .lookbehind] {
				return p.add(UpsraNode{ typ: .lookaround, body: p.alternatives(n.alternatives)? })
			}
			return p.add(UpsraNode{ typ: .anchor })
		}
		.quantifier {
			return p.add(UpsraNode{
				typ:  .quantifier
				min:  n.min
				max:  n.max
				body: [p.node(n.element)?]
			})
		}
		.character_class {
			return p.add(UpsraNode{
				typ:      .character_class
				negative: n.negate
				body:     p.elements(n.elements, true)?
			})
		}
		.expression_character_class {
			return p.add(UpsraNode{ typ: .character_class, negative: n.negate })
		}
		.character {
			body := p.elements([i], p.ast.nodes[n.parent].kind !in [.alternative, .quantifier])?
			return body[0]
		}
		.character_set {
			return p.add(UpsraNode{ typ: if n.set_kind == .any { .dot } else { .class_escape } })
		}
		.backreference {
			return p.add(UpsraNode{ typ: .reference })
		}
		else {
			return p.add(UpsraNode{ typ: .other })
		}
	}
}

// upsra_parse ports parseRegExpLiteral: the tree regjsparser gives for the pattern of a regular
// expression literal, none where it fails.
fn upsra_parse(info estree.RegexInfo) ?UpsraTree {
	unicode := info.flags.contains('u') || info.flags.contains('v')
	source := regexpp.to_utf16(info.pattern)
	ast := regexpp.parse_pattern(source, 0, source.len, regexpp.PatternFlags{
		unicode:      info.flags.contains('u')
		unicode_sets: info.flags.contains('v')
	}, regexpp.Options{}) or { return none }
	mut p := UpsraParser{
		ast:          ast
		unicode:      unicode
		unicode_sets: info.flags.contains('v')
	}
	pattern := ast.nodes[ast.root]
	body := p.alternatives(pattern.alternatives)?
	p.tree.root = if pattern.alternatives.len == 1 { p.term(body) } else { body[0] }
	return p.tree
}

fn upsra_unicode_escape(code_point int) []u16 {
	return regexpp.to_utf16('\\u{${code_point.hex().to_upper()}}')
}

// upsra_value_replacement ports getValueReplacement.
fn upsra_value_replacement(n UpsraNode) []u16 {
	mut character := match n.kind {
		.control_letter {
			return match n.code_point {
				13 { regexpp.to_utf16('\\r') }
				10 { regexpp.to_utf16('\\n') }
				9 { regexpp.to_utf16('\\t') }
				else { upsra_unicode_escape(n.code_point) }
			}
		}
		.code_point {
			return upsra_unicode_escape(n.code_point)
		}
		.strip {
			n.raw[1..]
		}
		.empty {
			[]u16{}
		}
		.raw {
			n.raw
		}
	}
	if character == [u16(`'`)] || character == [u16(`\\`)] {
		character = [u16(`\\`), character[0]]
	}
	return character
}

// upsra_node_replacement ports getNodeReplacement.
fn upsra_node_replacement(tree &UpsraTree, node int) ?[]u16 {
	n := tree.nodes[node]
	if n.typ == .value {
		return upsra_value_replacement(n)
	}
	if n.typ == .character_class && !n.negative && n.body.len == 1
		&& tree.nodes[n.body[0]].typ == .value {
		return upsra_value_replacement(tree.nodes[n.body[0]])
	}
	if (n.typ == .quantifier && n.min == 1 && n.max == 1) || n.typ == .group_ignore {
		return upsra_body_replacement(tree, n.body)
	}
	return none
}

// upsra_body_replacement ports getBodyReplacement.
fn upsra_body_replacement(tree &UpsraTree, body []int) ?[]u16 {
	mut parts := []u16{}
	for node in body {
		parts << upsra_node_replacement(tree, node)?
	}
	return parts
}

// upsra_has_surrogate_character ports hasSurrogateCharacter.
fn upsra_has_surrogate_character(tree &UpsraTree, node int) bool {
	n := tree.nodes[node]
	return (n.typ == .value && n.code_point >= 0xD800 && n.code_point <= 0xDFFF)
		|| n.body.any(upsra_has_surrogate_character(tree, it))
}

// upsra_pattern_replacement ports getPatternReplacement: the string literal a regular expression
// with the `g` flag stands for.
fn upsra_pattern_replacement(t &estree.EsTree, node int) ?string {
	if !un_is_regex_literal(t, node) {
		return none
	}
	info := t.get(node, .regex) as estree.RegexInfo
	tree := upsra_parse(info)?
	if info.flags.contains('i') || info.flags.contains('y')
		|| ((info.flags.contains('u') || info.flags.contains('v'))
			&& upsra_has_surrogate_character(&tree, tree.root)) {
		return none
	}
	root := tree.nodes[tree.root]
	replacement := if root.typ == .alternative {
		upsra_body_replacement(&tree, root.body)?
	} else {
		upsra_node_replacement(&tree, tree.root)?
	}
	if replacement.len == 0 {
		return none
	}
	return regexpp.utf16_to_wtf8([u16(`'`)]) + regexpp.utf16_to_wtf8(replacement) + "'"
}

// upsra_minimum_consumed_length ports getMinimumConsumedLength.
fn upsra_minimum_consumed_length(tree &UpsraTree, node int) f64 {
	n := tree.nodes[node]
	return match n.typ {
		.anchor, .reference {
			0
		}
		.value, .dot, .character_class, .class_escape {
			1
		}
		.alternative {
			upsra_body_minimum_length(tree, n.body)
		}
		.disjunction {
			mut minimum := upsra_minimum_consumed_length(tree, n.body[0])
			for child in n.body[1..] {
				length := upsra_minimum_consumed_length(tree, child)
				if length < minimum {
					minimum = length
				}
			}
			minimum
		}
		.quantifier {
			n.min * upsra_body_minimum_length(tree, n.body)
		}
		.group_ignore {
			upsra_body_minimum_length(tree, n.body)
		}
		else {
			// A lookaround consumes nothing.
			0
		}
	}
}

// upsra_body_minimum_length ports getBodyMinimumLength.
fn upsra_body_minimum_length(tree &UpsraTree, body []int) f64 {
	mut length := f64(0)
	for node in body {
		length += upsra_minimum_consumed_length(tree, node)
	}
	return length
}

// upsra_regexp_literal_with_global_flag ports getRegExpLiteralWithGlobalFlag: the text of a
// regular expression literal with the `g` flag, for a separator of `split()` that replaceAll()
// can take as it is.
fn upsra_regexp_literal_with_global_flag(t &estree.EsTree, node int) ?string {
	if !un_is_regex_literal(t, node) {
		return none
	}
	info := t.get(node, .regex) as estree.RegexInfo
	if info.flags.contains('y') {
		return none
	}
	tree := upsra_parse(info)?
	if tree.nodes.any(it.typ == .group_normal)
		|| upsra_minimum_consumed_length(&tree, tree.root) == 0 {
		return none
	}
	flags := if info.flags.contains('g') { info.flags } else { 'g${info.flags}' }
	return '/${info.pattern}/${flags}'
}

// upsra_split_join_replacement ports getSplitJoinReplacement: the replaceAll() call of
// `string.split(separator).join(replacement)`.
fn (mut c Checker) upsra_split_join_replacement(t &estree.EsTree, tokens &SourceTokens, node int, mut ctx UnbTypeContext) ?string {
	if !un_is_method_call(t, node,
		methods:          ['join']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) {
		return none
	}
	split_call := t.node(t.node(node, .callee)?, .object)?
	if !un_is_method_call(t, split_call,
		methods:          ['split']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) {
		return none
	}
	object := t.node(t.node(split_call, .callee)?, .object)?
	if c.unb_is_known_non_string(t, object, mut ctx) {
		return none
	}
	separator := (t.list(split_call, .arguments)?)[0]
	replacement := (t.list(node, .arguments)?)[0]
	mut search_text := ''
	if separator_value := unb_static_string_value(t, separator) {
		if separator_value.len == 0 {
			return none
		}
		search_text = unb_escape_string(separator_value, "'")
	} else {
		search_text = upsra_regexp_literal_with_global_flag(t, separator)?
	}
	replacement_value := unb_static_string_value(t, replacement)?
	object_text := c.unb_member_object_text(t, tokens, object, node)
	replacement_text := unb_escape_string(replacement_value.replace('$', '$$'), "'")
	return '${object_text}.replaceAll(${search_text}, ${replacement_text})'
}

fn (mut c Checker) lint_unicorn_prefer_string_replace_all(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if text := c.upsra_split_join_replacement(t, tokens, node, mut ctx) {
			property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
			mut finding := Finding{
				stmt:       c.es_tree_position(t, property)
				message_id: 'split-join'
			}
			// getCommentSafeProblem
			if !c.unb_would_remove_comments(tokens, unb_node_range(t, node), [], false) {
				finding = Finding{
					...finding
					has_fix: true
					fix:     fix_replace_range(t.nodes[node].start, t.nodes[node].end, text)
				}
			}
			findings << finding
			continue
		}
		if !un_is_method_call(t, node,
			methods:          ['replace', 'replaceAll']
			arguments_length: 2
			optional_call:    false
		) {
			continue
		}
		if unb_is_regexp_escape_replace_call(t, node) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		if c.unb_is_known_non_string(t, t.node(callee, .object) or { continue }, mut ctx) {
			continue
		}
		pattern := (t.list(node, .arguments) or { continue })[0]
		regexp := c.unb_static_regexp(root, t, pattern) or { continue }
		if !regexp.flags.contains('g') {
			continue
		}
		property := t.node(callee, .property) or { continue }
		replacement := upsra_pattern_replacement(t, pattern)
		if (t.string_of(property, .name) or { '' }) == 'replaceAll' {
			text := replacement or { continue }
			findings << Finding{
				stmt:       c.es_tree_position(t, pattern)
				message_id: 'pattern'
				data:       {
					// `This pattern can be replaced with a string literal.` for long strings
					'replacement': if regexpp.to_utf16(text).len < 20 {
						text
					} else {
						'a string literal'
					}
				}
				has_fix:    true
				fix:        fix_replace_range(t.nodes[pattern].start, t.nodes[pattern].end, text)
			}
			continue
		}
		mut fixes := [fix_insert_at(t.nodes[property].end, 'All')]
		if text := replacement {
			fixes << fix_replace_range(t.nodes[pattern].start, t.nodes[pattern].end, text)
		}
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'method'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
