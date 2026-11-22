module rules

import json2
import regexpp
import time

// Port of the `regexp/no-useless-character-class` rule of eslint-plugin-regexp 3.3.3 with its option
// (`ignores`, ["="] by default) and its fix: a character class of a single element that can be
// written without brackets, or a nested class of several (or no) elements.

const regexp_no_useless_character_class_messages = {
	'unexpectedCharacterClassWith':               'Unexpected character class with one {{type}}. Can remove brackets{{additional}}.'
	'unexpectedUnnecessaryNestingCharacterClass': 'Unexpected unnecessary nesting character class. Can remove brackets.'
}

// rxnucc_options is `ignores`.
fn rxnucc_options(options []json2.Any) ![]string {
	o := option_object(regexp_no_useless_character_class, options, ['ignores'])!
	if 'ignores' !in o.values {
		return ['=']
	}
	return o.string_list('ignores')!
}

fn (mut c Checker) lint_regexp_no_useless_character_class(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignores := rxnucc_options(c.rule_options(regexp_no_useless_character_class))!
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if re.kind !in [.literal, .source] {
			continue
		}
		stats.checked++
		ast := &re.ast
		mut stack := 0
		for event in ast.visit_events() {
			n := ast.nodes[event.node]
			if n.kind == .expression_character_class {
				stack += if event.enter { 1 } else { -1 }
				continue
			}
			if n.kind != .character_class {
				continue
			}
			if event.enter {
				stack++
				continue
			}
			stack--
			if n.negate {
				continue
			}
			ctx := RxnuccClass{
				ast:     ast
				pattern: re.source.value
				cc:      event.node
				nested:  stack > 0
				unicode: re.flags.unicode
			}
			mut unwrapped := []string{}
			for index, element in n.elements {
				mut text := ?string(none)
				if index == 0 {
					text = ctx.escaped_first(element)
				}
				if text == none && index == n.elements.len - 1 {
					text = ctx.escaped_last(element)
				}
				unwrapped << text or { rx_raw(ast, element) }
			}
			mut message_id := 'unexpectedCharacterClassWith'
			mut typ := ''
			mut additional := ''
			parent := ast.nodes[n.parent]
			if n.elements.len != 1 && parent.kind == .character_class {
				message_id = 'unexpectedUnnecessaryNestingCharacterClass'
				typ = 'unnecessary nesting character class'
				if n.elements.len == 0 {
					position := parent.elements.index(event.node)
					if position + 1 < parent.elements.len
						&& ctx.need_escape_first(parent.elements[position + 1]) {
						unwrapped << '\\'
					}
				}
			} else {
				if n.elements.len != 1 {
					continue
				}
				element := n.elements[0]
				e := ast.nodes[element]
				raw := rx_raw(ast, element)
				if ignores.len > 0 && raw in ignores {
					continue
				}
				match e.kind {
					.character {
						if raw == '\\b' {
							continue
						}
						if raw.len > 1 && raw[0] == `\\` && raw[1..].bytes().all(it.is_digit())
							&& !raw.starts_with('\\0') {
							continue
						}
						if ignores.len > 0
							&& regexpp.utf16_to_wtf8(rx_from_code_point(u32(e.value))) in ignores {
							continue
						}
						if !rx_can_unwrapped(ast, event.node, raw) {
							continue
						}
						typ = 'character'
					}
					.character_class_range {
						if ast.nodes[e.min_char].value != ast.nodes[e.max_char].value {
							continue
						}
						typ = 'character class range'
						additional = ' and range'
						unwrapped[0] = ctx.escaped_first(e.min_char) or {
							ctx.escaped_last(e.min_char) or { rx_raw(ast, e.min_char) }
						}
					}
					.class_string_disjunction {
						if stack == 0 {
							continue
						}
						typ = 'string literal'
					}
					.character_set {
						typ = 'character class escape'
					}
					.character_class, .expression_character_class {
						typ = 'character class'
					}
					else {
						continue
					}
				}
			}
			range := rx_node_range(ast, event.node)
			findings << rx_with_fix(c.rx_report(t, &re, range, message_id, {
				'type':       typ
				'additional': additional
			}), c.rx_fix_replace_node(t, &re, range, unwrapped.join('')))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// RxnuccClass is what the escape helpers of the rule read: the class being left, whether it is
// inside another one (characterClassStack.length), the pattern and the `u` flag.
struct RxnuccClass {
	ast     &regexpp.Ast
	pattern []u16
	cc      int
	nested  bool
	unicode bool
}

// rxnucc_char is the raw text the escape helpers look at: a character's, or a range's bound.
fn (x &RxnuccClass) char_of(element int, first bool) ?string {
	n := x.ast.nodes[element]
	if n.kind == .character {
		return rx_raw(x.ast, element)
	}
	if n.kind == .character_class_range {
		return rx_raw(x.ast, if first { n.min_char } else { n.max_char })
	}
	return none
}

// pattern_at is `pattern[i]` (a unit, or '' past the ends).
fn (x &RxnuccClass) pattern_at(i int) string {
	if i < 0 || i >= x.pattern.len {
		return ''
	}
	return regexpp.utf16_to_wtf8([x.pattern[i]])
}

// need_escape_first ports isNeedEscapedForFirstElement.
fn (x &RxnuccClass) need_escape_first(element int) bool {
	ch := x.char_of(element, true) or { return false }
	cc := x.ast.nodes[x.cc]
	if x.nested {
		if ch.len == 1 && rx_reserved_double_punctuators.contains(ch)
			&& x.pattern_at(cc.start - 1) == ch {
			return true
		}
		parent := x.ast.nodes[cc.parent]
		return ch == '^' && parent.kind == .character_class && parent.elements.len > 0
			&& parent.elements[0] == x.cc
	}
	escapes := if x.unicode { '$()*+./?[{|}' } else { '$()*+./?[{|' }
	return ch.len == 1 && escapes.contains(ch)
}

// need_escape_last ports needEscapedForLastElement.
fn (x &RxnuccClass) need_escape_last(element int) bool {
	ch := x.char_of(element, false) or { return false }
	if x.nested {
		cc := x.ast.nodes[x.cc]
		return ch.len == 1 && rx_reserved_double_punctuators.contains(ch)
			&& x.pattern_at(cc.end) == ch
	}
	return false
}

// escaped_first ports getEscapedFirstRawIfNeeded.
fn (x &RxnuccClass) escaped_first(element int) ?string {
	if x.need_escape_first(element) {
		return '\\${rx_raw(x.ast, element)}'
	}
	return none
}

// escaped_last ports getEscapedLastRawIfNeeded.
fn (x &RxnuccClass) escaped_last(element int) ?string {
	if !x.need_escape_last(element) {
		return none
	}
	last_raw := x.char_of(element, false) or { '' }
	raw := rx_raw(x.ast, element)
	return '${raw[..raw.len - last_raw.len]}\\${last_raw}'
}
