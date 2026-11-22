module rules

import estree
import json2
import time

// Port of the `regexp/letter-case` rule of eslint-plugin-regexp 3.3.3 with its options
// (caseInsensitive, unicodeEscape, hexadecimalEscape and controlEscape: "lowercase", "uppercase" or
// "ignore") and its fix: the letters of a pattern with the `i` flag (characters and ranges of
// letters), and the hexadecimal digits of unicode and hexadecimal escapes and the letter of control
// escapes, in the case of the option.

const regexp_letter_case_messages = {
	'unexpected': "'{{char}}' is not in {{case}}"
}

struct RxlcOptions {
	case_insensitive   string = 'lowercase'
	unicode_escape     string = 'lowercase'
	hexadecimal_escape string = 'lowercase'
	control_escape     string = 'uppercase'
}

// rxlc_options ports parseOptions: a missing (or empty) option takes its default.
fn rxlc_options(options []json2.Any) !RxlcOptions {
	o := option_object(regexp_letter_case, options, ['caseInsensitive', 'unicodeEscape',
		'hexadecimalEscape', 'controlEscape'])!
	cases := ['lowercase', 'uppercase', 'ignore']
	d := RxlcOptions{}
	pick := fn (value string, default_value string) string {
		return if value == '' { default_value } else { value }
	}
	return RxlcOptions{
		case_insensitive:   pick(o.string_value('caseInsensitive', cases)!, d.case_insensitive)
		unicode_escape:     pick(o.string_value('unicodeEscape', cases)!, d.unicode_escape)
		hexadecimal_escape: pick(o.string_value('hexadecimalEscape', cases)!, d.hexadecimal_escape)
		control_escape:     pick(o.string_value('controlEscape', cases)!, d.control_escape)
	}
}

// rxlc_is_case ports CODE_POINT_CASE_CHECKER.
fn rxlc_is_case(letter_case string, cp int) bool {
	return if letter_case == 'lowercase' {
		rx_is_lowercase_letter(cp)
	} else {
		rx_is_uppercase_letter(cp)
	}
}

// rxlc_string_is_case ports STRING_CASE_CHECKER (the texts are ASCII).
fn rxlc_string_is_case(letter_case string, s string) bool {
	return if letter_case == 'lowercase' { s.to_lower() == s } else { s.to_upper() == s }
}

// rxlc_convert ports CONVERTER.
fn rxlc_convert(letter_case string, s string) string {
	return if letter_case == 'lowercase' { s.to_lower() } else { s.to_upper() }
}

fn (mut c Checker) lint_regexp_letter_case(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := rxlc_options(c.rule_options(regexp_letter_case))!
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if re.kind !in [.literal, .source] {
			continue
		}
		stats.checked++
		ast := &re.ast
		for event in ast.visit_events() {
			n := ast.nodes[event.node]
			if !event.enter {
				continue
			}
			range := rx_node_range(ast, event.node)
			raw := rx_raw(ast, event.node)
			if n.kind == .character {
				if re.flags.ignore_case && ast.nodes[n.parent].kind != .character_class_range
					&& options.case_insensitive != 'ignore'
					&& !rxlc_is_case(options.case_insensitive, n.value) && rx_is_letter(n.value) {
					findings << c.rxlc_report(t, &re, range, raw, options.case_insensitive,
						rxlc_convert(options.case_insensitive, rune(n.value).str()))
				}
				kind := rx_escape_sequence_kind(raw)
				if kind in [.unicode, .unicode_code_point] && options.unicode_escape != 'ignore' {
					// /^(\\u\{?)(.*?)(\}?)$/
					prefix := if kind == .unicode_code_point { '\\u{' } else { '\\u' }
					suffix := if kind == .unicode_code_point { '}' } else { '' }
					code := raw[prefix.len..raw.len - suffix.len]
					if !rxlc_string_is_case(options.unicode_escape, code) {
						findings << c.rxlc_report(t, &re, range, raw, options.unicode_escape,
							'${prefix}${rxlc_convert(options.unicode_escape, code)}${suffix}')
					}
				}
				if kind == .hexadecimal && options.hexadecimal_escape != 'ignore' {
					code := raw[2..]
					if !rxlc_string_is_case(options.hexadecimal_escape, code) {
						findings << c.rxlc_report(t, &re, range, raw, options.hexadecimal_escape,
							'\\x${rxlc_convert(options.hexadecimal_escape, code)}')
					}
				}
				if kind == .control && options.control_escape != 'ignore' {
					code := raw[2..]
					if !rxlc_string_is_case(options.control_escape, code) {
						findings << c.rxlc_report(t, &re, range, raw, options.control_escape,
							'\\c${rxlc_convert(options.control_escape, code)}')
					}
				}
			} else if n.kind == .character_class_range && re.flags.ignore_case
				&& options.case_insensitive != 'ignore' {
				min := ast.nodes[n.min_char].value
				max := ast.nodes[n.max_char].value
				letter_case := options.case_insensitive
				if rxlc_is_case(letter_case, min) || !rx_is_letter(min) || rxlc_is_case(letter_case, max)
					|| !rx_is_letter(max) {
					continue
				}
				findings << c.rxlc_report(t, &re, range, raw, letter_case, '${rxlc_convert(letter_case,
					rune(min).str())}-${rxlc_convert(letter_case, rune(max).str())}')
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxlc_report ports `report`.
fn (c &Checker) rxlc_report(t &estree.EsTree, re &RxRegExp, range RxRange, raw string, letter_case string, text string) Finding {
	return rx_with_fix(c.rx_report(t, re, range, 'unexpected', {
		'char': raw
		'case': letter_case
	}), c.rx_fix_replace_node(t, re, range, text))
}
