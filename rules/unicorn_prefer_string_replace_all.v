module rules

import estree
import regexpp
import time

// Port of the `unicorn/prefer-string-replace-all` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix. The pattern is read with regexpp/ where the plugin uses regjsparser:
// both give a pattern of plain characters as a list of characters.

const upsra_messages = {
	'method':  'Prefer `String#replaceAll()` over `String#replace()`.'
	'pattern': 'This pattern can be replaced with {{replacement}}.'
}

// upsra_pattern_replacement ports getPatternReplacement: the string literal a `/…/g` regular
// expression of plain characters stands for.
fn upsra_pattern_replacement(t &estree.EsTree, node int) ?string {
	if !un_is_regex_literal(t, node) {
		return none
	}
	info := t.get(node, .regex) as estree.RegexInfo
	if info.flags.replace_once('u', '').replace_once('v', '') != 'g' {
		return none
	}
	source := regexpp.to_utf16(info.pattern)
	ast := regexpp.parse_pattern(source, 0, source.len, regexpp.PatternFlags{
		unicode:      info.flags.contains('u')
		unicode_sets: info.flags.contains('v')
	}, regexpp.Options{}) or { return none }
	alternatives := ast.nodes[ast.root].alternatives
	if alternatives.len != 1 {
		return none
	}
	mut out := "'"
	for element in ast.nodes[alternatives[0]].elements {
		n := ast.nodes[element]
		if n.kind != .character {
			return none
		}
		raw := ast.raw(element)
		if raw.len == 3 && raw.starts_with('\\c') {
			// controlLetter
			out += match n.value {
				13 { '\\r' }
				10 { '\\n' }
				9 { '\\t' }
				else { '\\u{${n.value.hex()}}' }
			}
			continue
		}
		if raw.len >= 2 && raw[0] == `\\` && raw[1] >= `0` && raw[1] <= `7` && raw != '\\0' {
			// octal
			out += '\\u{${n.value.hex()}}'
			continue
		}
		mut character := raw
		// An identity escape (`\.`) is its character.
		if raw.len >= 2 && raw[0] == `\\` && raw[1] !in [`n`, `r`, `t`, `f`, `v`, `0`, `x`, `u`, `c`] {
			character = raw[1..]
		}
		if character in ["'", '\\'] {
			out += '\\${character}'
		} else {
			out += character
		}
	}
	return out + "'"
}

// upsra_global_regexp ports isRegExpWithGlobalFlag.
fn (mut c Checker) upsra_global_regexp(t &estree.EsTree, node int) bool {
	if un_is_regex_literal(t, node) {
		info := t.get(node, .regex) as estree.RegexInfo
		return info.flags.contains('g')
	}
	if un_is_new(t, node, names: ['RegExp']) {
		args := t.list(node, .arguments) or { []int{} }
		if (args.len == 0 || t.typ(args[0]) != .spread_element) && args.len > 1
			&& t.typ(args[1]) == .literal {
			flags := t.get(args[1], .value)
			if flags is string {
				return flags.contains('g')
			}
		}
	}
	result := c.un_static_value(t, node)
	return result.found && result.value.kind == .regexp_ && result.value.regexp.flags.contains('g')
}

fn (mut c Checker) lint_unicorn_prefer_string_replace_all(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node,
			methods:          ['replace', 'replaceAll']
			arguments_length: 2
			optional_call:    false
		) {
			continue
		}
		pattern := (t.list(node, .arguments) or { continue })[0]
		if !c.upsra_global_regexp(t, pattern) {
			continue
		}
		property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
		replacement := upsra_pattern_replacement(t, pattern)
		if (t.string_of(property, .name) or { '' }) == 'replaceAll' {
			text := replacement or { continue }
			findings << Finding{
				stmt:       c.es_tree_position(t, pattern)
				message_id: 'pattern'
				data:       {
					'replacement': if text.runes().len < 20 { text } else { 'a string literal' }
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
