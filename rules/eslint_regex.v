module rules

import regexpp
import treesitter { node_field, node_kind, node_parent }

// Helpers of the rules of ESLint core about regular expressions (regexpp is the port of
// @eslint-community/regexpp 4.12.2 in regexpp/). Patterns are UTF-16 units, like JavaScript
// strings, and regexpp's offsets are indexes of units.

// es_regex_literal is node.regex of a regular expression literal: its pattern, as written between
// the slashes, and its flags.
fn (c &Checker) es_regex_literal(n C.TSNode) ?([]u16, string) {
	if node_kind(n) != 'regex' {
		return none
	}
	pattern := node_field(n, 'pattern') or { return utf16_units(''), c.es_regex_flags(n) }
	return utf16_units(c.text(pattern)), c.es_regex_flags(n)
}

fn (c &Checker) es_regex_flags(n C.TSNode) string {
	flags := node_field(n, 'flags') or { return '' }
	return c.text(flags)
}

// es_string_units is the value of a string Literal in UTF-16 units (none for any other node).
fn (c &Checker) es_string_units(n C.TSNode) ?[]u16 {
	if node_kind(n) != 'string' {
		return none
	}
	raw := c.text(n)
	if raw.len < 2 {
		return none
	}
	return cooked_units(raw[1..raw.len - 1], false)
}

// es_units_byte_offset is the byte offset of the UTF-16 index `index` in `text`; the second unit
// of a surrogate pair is the byte after the first one of its character (offsets.utf16_offsets
// reads it back as that unit).
fn es_units_byte_offset(text string, index int) int {
	mut units := 0
	mut offset := 0
	for offset < text.len && units < index {
		len := utf8_char_len(text[offset])
		if len == 4 && units + 1 == index {
			return offset + 1
		}
		units += if len == 4 { 2 } else { 1 }
		offset += len
	}
	return offset
}

// es_regex_flags_of is `{unicode, unicodeSets}` of a flags string.
fn es_regex_pattern_flags(flags string) regexpp.PatternFlags {
	return regexpp.PatternFlags{
		unicode:      flags.contains('u')
		unicode_sets: flags.contains('v')
	}
}

// es_estree_parent is the parent of an expression in ESTree, past its parentheses.
fn es_estree_parent(n C.TSNode) ?(C.TSNode, C.TSNode) {
	mut child := n
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		child = parent
		parent = node_parent(parent)?
	}
	return parent, child
}
