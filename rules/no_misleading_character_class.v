module rules

import json2
import jsregexp
import regexpp
import time
import treesitter { children, named_children, node_field, node_kind, node_start, position_of }

// Port of the `no-misleading-character-class` rule of ESLint 10.6.0.

const nmcc_messages = {
	'surrogatePairWithoutUFlag': "Unexpected surrogate pair in character class. Use 'u' flag."
	'surrogatePair':             'Unexpected surrogate pair in character class.'
	'combiningClass':            'Unexpected combined character in character class.'
	'emojiModifier':             'Unexpected modified Emoji in character class.'
	'regionalIndicatorSymbol':   'Unexpected national flag in character class.'
	'zwj':                       'Unexpected joined character sequence in character class.'
	'suggestUnicodeFlag':        "Add unicode 'u' flag to regex."
}

const nmcc_kinds = ['surrogatePairWithoutUFlag', 'surrogatePair', 'combiningClass', 'emojiModifier',
	'regionalIndicatorSymbol', 'zwj']

fn nmcc_options(options []json2.Any) !bool {
	o := option_object(no_misleading_character_class, options, ['allowEscape'])!
	return o.bool_value('allowEscape') or { false }
}

// NmccCodeUnit is a CodeUnit of char-source.js: where the source of a UTF-16 unit of a string's
// value starts and ends, in UTF-16 units of the literal's text.
struct NmccCodeUnit {
	start int
	end   int
}

struct NmccState {
	allow_escape bool
	ecma_version int
	marks        jsregexp.RegexpProgram // /^\p{M}$/u
mut:
	findings []Finding
}

fn (mut c Checker) lint_no_misleading_character_class(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut st := NmccState{
		allow_escape: nmcc_options(c.rule_options(no_misleading_character_class))!
		ecma_version: c.ecma_version
		marks:        jsregexp.regexp_compile('^\\p{M}$')!
	}
	mut checked := map[u64]bool{}
	// The patterns given to the global RegExp.
	trace := {
		'RegExp': EsTrace{
			call:      true
			construct: true
		}
	}
	for traced in c.es_global_references(root, trace) {
		stats.checked++
		mut args := []C.TSNode{}
		if arguments := node_field(traced.node, 'arguments') {
			if node_kind(arguments) == 'arguments' {
				args = named_children(arguments).filter(node_kind(it) != 'comment').map(unwrap_parens(it))
			}
		}
		if args.len == 0 {
			continue
		}
		pattern_node := args[0]
		mut pattern := []u16{}
		mut flags := ?string(none)
		is_regex := node_kind(pattern_node) == 'regex'
		mut value := JsAny{}
		if !is_regex {
			evaluated := c.get_static_value(pattern_node)
			if !evaluated.found || evaluated.value.kind == .regexp_ {
				continue
			}
			value = evaluated.value
		}
		if args.len > 1 {
			if is_regex {
				pattern, _ = c.es_regex_literal(pattern_node) or { continue }
				checked[node_key(pattern_node)] = true
			} else {
				pattern = stv_to_string(value) or { continue }
			}
			flags = c.string_if_constant(args[1])
		} else {
			if is_regex {
				continue
			}
			pattern = stv_to_string(value) or { continue }
			flags = ''
		}
		f := flags or { continue }
		fix := c.nmcc_constructor_fix(root, traced.node, args, pattern, st.ecma_version)
		c.nmcc_verify(pattern_node, pattern, f, fix, mut st)
	}
	for node in c.nodes_of_kinds(root, ['regex'], []) {
		stats.checked++
		if checked[node_key(node)] {
			continue
		}
		pattern, flags := c.es_regex_literal(node) or { continue }
		mut fix := ?Fix(none)
		if nmcc_valid_with_unicode_flag(st.ecma_version, pattern) {
			end := c.es_end(node)
			fix = Fix{end, end, 'u'}
		}
		c.nmcc_verify(node, pattern, flags, fix, mut st)
	}
	stats.eval_ms += ms(sw.elapsed())
	return st.findings
}

// nmcc_valid_with_unicode_flag ports isValidWithUnicodeFlag for the `u` flag.
fn nmcc_valid_with_unicode_flag(ecma_version int, pattern []u16) bool {
	if ecma_version <= 5 {
		return false
	}
	regexpp.validate_pattern(pattern, 0, pattern.len, regexpp.PatternFlags{ unicode: true },
		regexpp.Options{ ecma_version: if ecma_version < 2025 { ecma_version } else { 2025 } }) or {
		return false
	}
	return true
}

// nmcc_constructor_fix is the unicode fixer of `RegExp(…)`: a `"u"` argument, or a `u` at the
// end of a string or template of flags.
fn (mut c Checker) nmcc_constructor_fix(root C.TSNode, call C.TSNode, args []C.TSNode, pattern []u16, ecma_version int) ?Fix {
	if !nmcc_valid_with_unicode_flag(ecma_version, pattern) {
		return none
	}
	if args.len == 1 {
		tokens := c.source_tokens(root)
		close := tokens.before(c.es_end(call), false)?
		penultimate := tokens.before(close.start, false)?
		text := if c.src[penultimate.start..penultimate.end] == ',' { ' "u",' } else { ', "u"' }
		return Fix{penultimate.end, penultimate.end, text}
	}
	flags := args[1]
	if node_kind(flags) in ['string', 'template_string'] {
		at := c.es_end(flags) - 1
		return Fix{at, at, 'u'}
	}
	return none
}

fn nmcc_is_surrogate_pair(lead int, tail int) bool {
	return lead >= 0xd800 && lead < 0xdc00 && tail >= 0xdc00 && tail < 0xe000
}

fn nmcc_is_emoji_modifier(code int) bool {
	return code >= 0x1f3fb && code <= 0x1f3ff
}

fn nmcc_is_regional_indicator(code int) bool {
	return code >= 0x1f1e6 && code <= 0x1f1ff
}

fn (st &NmccState) is_combining(code int) bool {
	if code < 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) {
		return false
	}
	return jsregexp.regexp_test(st.marks, rune(code).str()) or { false }
}

// nmcc_is_code_point_escape: the raw is `\u{…}`.
fn nmcc_is_code_point_escape(raw string) bool {
	if raw.len < 5 || !raw.starts_with('\\u{') || !raw.ends_with('}') {
		return false
	}
	return raw[3..raw.len - 1].bytes().all(it.is_hex_digit())
}

// nmcc_acceptable_escape ports checkForAcceptableEscape on the UTF-16 units of the source of a
// character: an escape, unless it is backslashes before the character itself.
fn nmcc_acceptable_escape(value int, source []u16) bool {
	if source.len == 0 || source[0] != `\\` {
		return false
	}
	mut i := 0
	for i < source.len && source[i] == `\\` {
		i++
	}
	rest := source[i..]
	mut code := -1
	if rest.len == 1 {
		code = int(rest[0])
	} else if rest.len == 2 && rest[0] >= 0xd800 && rest[0] < 0xdc00 && rest[1] >= 0xdc00
		&& rest[1] < 0xe000 {
		code = 0x10000 + ((int(rest[0]) - 0xd800) << 10) + (int(rest[1]) - 0xdc00)
	}
	return code != value
}

// nmcc_code_units ports parseStringLiteral (template: parseTemplateToken) on the text of a
// literal, in UTF-16 units.
fn nmcc_code_units(source []u16, template bool) []NmccCodeUnit {
	mut out := []NmccCodeUnit{}
	quote := source[0]
	mut pos := 1
	for pos < source.len {
		ch := source[pos]
		if (!template && ch == quote) || (template && (ch == `\``
			|| (ch == `$` && pos + 1 < source.len && source[pos + 1] == `{`))) {
			break
		}
		if ch == `\\` {
			start := pos
			end, length := nmcc_escape(source, pos)
			pos = end
			if length == 1 {
				out << NmccCodeUnit{start, pos}
			} else if length > 1 {
				out << NmccCodeUnit{start, pos}
				out << NmccCodeUnit{start, pos}
			}
			continue
		}
		if template && ch == `\r` && pos + 1 < source.len && source[pos + 1] == `\n` {
			out << NmccCodeUnit{pos, pos + 2}
			pos += 2
			continue
		}
		out << NmccCodeUnit{pos, pos + 1}
		pos++
	}
	return out
}

// nmcc_escape ports readEscapeSequenceOrLineContinuation from the backslash at `start`: where
// the sequence ends and the number of UTF-16 units of its value.
fn nmcc_escape(source []u16, start int) (int, int) {
	if start + 1 >= source.len {
		return start + 1, 0
	}
	ch := source[start + 1]
	mut pos := start + 2
	match ch {
		`b`, `f`, `n`, `r`, `t`, `v` {
			return pos, 1
		}
		`x` {
			return pos + 2, 1
		}
		`u` {
			if pos < source.len && source[pos] == `{` {
				mut end := pos + 1
				for end < source.len && u8(source[end]).is_hex_digit() {
					end++
				}
				if end > pos + 1 && end < source.len && source[end] == `}` {
					digits := stv_units_string(source[pos + 1..end])
					value := digits.parse_uint(16, 32) or { 0 }
					return end + 1, if value > 0xffff { 2 } else { 1 }
				}
			}
			return pos + 4, 1
		}
		`\r` {
			if pos < source.len && source[pos] == `\n` {
				pos++
			}
			return pos, 0
		}
		`\n`, 0x2028, 0x2029 {
			return pos, 0
		}
		`0`, `1`, `2`, `3`, `4`, `5`, `6`, `7` {
			// readOctalSequence: up to three digits (two from 4).
			max := if ch <= `3` { 3 } else { 2 }
			mut count := 1
			for count < max && pos < source.len && source[pos] >= `0` && source[pos] <= `7` {
				count++
				pos++
			}
			return pos, 1
		}
		else {
			// The character itself (one UTF-16 unit).
			return pos, 1
		}
	}
}

// nmcc_sequences ports iterateCharacterSequence over the elements of a class.
fn nmcc_sequences(ast &regexpp.Ast, elements []int) [][]int {
	mut out := [][]int{}
	mut seq := []int{}
	for e in elements {
		n := ast.nodes[e]
		match n.kind {
			.character {
				seq << e
			}
			.character_class_range {
				seq << n.min_char
				out << seq
				seq = [n.max_char]
			}
			.character_set, .character_class, .class_string_disjunction,
			.expression_character_class {
				if seq.len > 0 {
					out << seq
					seq = []int{}
				}
			}
			else {}
		}
	}
	if seq.len > 0 {
		out << seq
	}
	return out
}

// nmcc_find ports findCharacterSequences[kind]: `chars` has -1 for an acceptable escape.
fn (st &NmccState) find(ast &regexpp.Ast, kind string, chars []int, unfiltered []int) [][]int {
	mut out := [][]int{}
	value := fn [ast] (i int) int {
		return ast.nodes[i].value
	}
	raw := fn [ast] (i int) string {
		return ast.raw(i)
	}
	match kind {
		'surrogatePairWithoutUFlag', 'surrogatePair' {
			for i, ch in chars {
				if i == 0 || chars[i - 1] < 0 || ch < 0 {
					continue
				}
				previous := chars[i - 1]
				if !nmcc_is_surrogate_pair(value(previous), value(ch)) {
					continue
				}
				escape := nmcc_is_code_point_escape(raw(previous)) || nmcc_is_code_point_escape(raw(ch))
				if escape == (kind == 'surrogatePair') {
					out << [previous, ch]
				}
			}
		}
		'combiningClass' {
			for i, ch in chars {
				if i == 0 || ch < 0 {
					continue
				}
				previous := unfiltered[i - 1]
				if st.is_combining(value(ch)) && !st.is_combining(value(previous)) {
					out << [previous, ch]
				}
			}
		}
		'emojiModifier' {
			for i, ch in chars {
				if i == 0 || chars[i - 1] < 0 || ch < 0 {
					continue
				}
				if nmcc_is_emoji_modifier(value(ch)) && !nmcc_is_emoji_modifier(value(chars[i - 1])) {
					out << [chars[i - 1], ch]
				}
			}
		}
		'regionalIndicatorSymbol' {
			for i, ch in chars {
				if i == 0 || chars[i - 1] < 0 || ch < 0 {
					continue
				}
				if nmcc_is_regional_indicator(value(ch))
					&& nmcc_is_regional_indicator(value(chars[i - 1])) {
					out << [chars[i - 1], ch]
				}
			}
		}
		else {
			// zwj
			mut sequence := []int{}
			for i, ch in chars {
				if i == 0 || i + 1 >= chars.len || chars[i - 1] < 0 || ch < 0 || chars[i + 1] < 0 {
					continue
				}
				previous := chars[i - 1]
				next := chars[i + 1]
				if value(ch) == 0x200d && value(previous) != 0x200d && value(next) != 0x200d {
					if sequence.len > 0 {
						if sequence.last() == previous {
							sequence << ch
							sequence << next
						} else {
							out << sequence
							sequence = chars[i - 1..i + 2].clone()
						}
					} else {
						sequence = chars[i - 1..i + 2].clone()
					}
				}
			}
			if sequence.len > 0 {
				out << sequence
			}
		}
	}
	return out
}

// nmcc_verify ports verify.
fn (mut c Checker) nmcc_verify(node C.TSNode, pattern []u16, flags string, fix ?Fix, mut st NmccState) {
	ast := regexpp.parse_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags),
		regexpp.Options{}) or { return }
	kind := node_kind(node)
	is_static_template := kind == 'template_string'
		&& !children(node).any(node_kind(it) == 'template_substitution')
	text16 := utf16_units(c.text(node))
	units := if kind == 'string' {
		nmcc_code_units(text16, false)
	} else if is_static_template {
		nmcc_code_units(text16, true)
	} else {
		[]NmccCodeUnit{}
	}
	mut found := map[string][][]int{}
	for event in ast.visit_events() {
		if !event.enter || ast.nodes[event.node].kind != .character_class {
			continue
		}
		for unfiltered in nmcc_sequences(ast, ast.nodes[event.node].elements) {
			mut chars := unfiltered.clone()
			if st.allow_escape {
				chars = unfiltered.map(if c.nmcc_acceptable(ast, it, kind, text16, units) {
					-1
				} else {
					it
				})
			}
			for k in nmcc_kinds {
				found[k] << st.find(ast, k, chars, unfiltered)
			}
		}
	}
	literal := kind in ['string', 'regex'] || is_static_template
	for k in nmcc_kinds {
		matches := found[k] or { continue }
		if matches.len == 0 {
			continue
		}
		mut suggestions := []Suggestion{}
		if k == 'surrogatePairWithoutUFlag' {
			if f := fix {
				suggestions << Suggestion{
					message_id: 'suggestUnicodeFlag'
					fix:        f
				}
			}
		}
		if !literal {
			st.findings << Finding{
				stmt:        position_of(node)
				message_id:  k
				suggestions: suggestions
			}
			continue
		}
		for m in matches {
			first := ast.nodes[m[0]].start
			mut start := 0
			if kind == 'regex' {
				start = 1 + first
			} else {
				start = units[first].start
			}
			offset := node_start(node) + es_units_byte_offset(c.text(node), start)
			st.findings << Finding{
				stmt:        c.position_at(offset)
				message_id:  k
				suggestions: suggestions
			}
		}
	}
}

// nmcc_acceptable ports isAcceptableEscapeSequence.
fn (c &Checker) nmcc_acceptable(ast &regexpp.Ast, ch int, kind string, text16 []u16, units []NmccCodeUnit) bool {
	n := ast.nodes[ch]
	if kind == 'regex' {
		return nmcc_acceptable_escape(n.value, ast.raw16(ch))
	}
	if units.len == 0 || n.end - 1 >= units.len {
		return false
	}
	return nmcc_acceptable_escape(n.value, text16[units[n.start].start..units[n.end - 1].end])
}
