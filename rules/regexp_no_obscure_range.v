module rules

import json2
import time

// Port of the `regexp/no-obscure-range` rule of eslint-plugin-regexp 3.3.3 with its option
// (`allowed`, else the setting regexp.allowedCharacterRanges, else "alphanumeric"): a character
// class range whose characters are not obvious.

const regexp_no_obscure_range_messages = {
	'unexpected': 'Unexpected obscure character range. The characters of {{range}} are not obvious.'
}

// rx_string_or_list is a value that is a string or a list of strings, as a list.
fn rx_string_or_list(value json2.Any) []string {
	if value is string {
		return if value == '' { []string{} } else { [value] }
	}
	if value is []json2.Any {
		return value.filter(it is string).map(it as string)
	}
	return []
}

// rxnor_allowed_option is the `allowed` option.
fn rxnor_allowed_option(options []json2.Any) ![]string {
	o := option_object(regexp_no_obscure_range, options, ['allowed'])!
	return rx_string_or_list(o.values['allowed'] or { return []string{} })
}

// rx_allowed_character_ranges_setting is the setting regexp.allowedCharacterRanges.
fn (c &Checker) rx_allowed_character_ranges_setting() []string {
	regexp := c.settings['regexp'] or { return [] }
	if regexp is map[string]json2.Any {
		return rx_string_or_list(regexp['allowedCharacterRanges'] or { return [] })
	}
	return []
}

fn (mut c Checker) lint_regexp_no_obscure_range(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allowed := rx_allowed_char_ranges(rxnor_allowed_option(c.rule_options(regexp_no_obscure_range))!,
		c.rx_allowed_character_ranges_setting())!
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
			if !event.enter || n.kind != .character_class_range {
				continue
			}
			min := ast.nodes[n.min_char]
			max := ast.nodes[n.max_char]
			if min.value == max.value {
				continue
			}
			min_raw := rx_raw(ast, n.min_char)
			max_raw := rx_raw(ast, n.max_char)
			if rx_is_control_escape(min_raw) && rx_is_control_escape(max_raw) {
				continue
			}
			if rx_is_octal_escape(min_raw) && rx_is_octal_escape(max_raw) {
				continue
			}
			if (rx_is_hex_like_escape(min_raw) || min.value == 0) && rx_is_hex_like_escape(max_raw) {
				continue
			}
			if !rx_is_escape_sequence(min_raw) && !rx_is_escape_sequence(max_raw)
				&& rx_in_range(allowed, min.value, max.value) {
				continue
			}
			findings << c.rx_report(t, &re, rx_node_range(ast, event.node), 'unexpected', {
				'range': rx_mention_char(ast, event.node)
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
