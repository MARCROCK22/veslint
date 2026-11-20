module rules

import json2
import regexpp
import time

// Port of the `regexp/no-lazy-ends` rule of eslint-plugin-regexp 3.3.3 with its option
// (ignorePartial, true by default: only patterns used whole) and its suggestions: a lazy quantifier
// of a variable count at the end of the pattern (also inside groups, and inside quantifiers of at
// most one repetition, at the end).

const regexp_no_lazy_ends_messages = {
	'uselessElement':          'The quantifier and the quantified element can be removed because the quantifier is lazy and has a minimum of 0.'
	'uselessQuantifier':       'The quantifier can be removed because the quantifier is lazy and has a minimum of 1.'
	'uselessRange':            "The quantifier can be replaced with '{{{min}}}' because the quantifier is lazy and has a minimum of {{min}}."
	'suggestMakeGreedy':       'Make the quantifier greedy. (This changes the behavior of the regex.)'
	'suggestRemoveElement':    'Remove the quantified element. (This does not changes the behavior of the regex.)'
	'suggestRemoveQuantifier': 'Remove the quantifier. (This does not changes the behavior of the regex.)'
	'suggestRange':            "Replace the quantifier with '{{{min}}}'. (This does not changes the behavior of the regex.)"
}

// rxnle_options is ignorePartial.
fn rxnle_options(options []json2.Any) !bool {
	o := option_object(regexp_no_lazy_ends, options, ['ignorePartial'])!
	if 'ignorePartial' !in o.values {
		return true
	}
	return o.bool_value('ignorePartial')!
}

fn (mut c Checker) lint_regexp_no_lazy_ends(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignore_partial := rxnle_options(c.rule_options(regexp_no_lazy_ends))!
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if re.kind !in [.literal, .source] {
			continue
		}
		stats.checked++
		if ignore_partial && c.rx_usage_of_pattern(root, t, re.regexp_node) != .whole {
			continue
		}
		ast := &re.ast
		pattern := ast.root
		alternatives := ast.nodes[pattern].alternatives
		for lazy in rxnle_lazy_end_quantifiers(ast, alternatives) {
			q := ast.nodes[lazy]
			range := rx_node_range(ast, lazy)
			raw := rx_raw(ast, lazy)
			element_raw := rx_raw(ast, q.element)
			make_greedy := rx_suggestion('suggestMakeGreedy', {}, c.rx_fix_replace_node(t, &re,
				range, raw[..raw.len - 1]))
			mut message_id := ''
			mut data := map[string]string{}
			mut first := ?Suggestion(none)
			if q.min == 0 {
				replacement := if alternatives.len == 1
					&& ast.nodes[alternatives[0]].elements.len == 1
					&& ast.nodes[alternatives[0]].elements[0] == lazy {
					'(?:)'
				} else {
					''
				}
				message_id = 'uselessElement'
				first = rx_suggestion('suggestRemoveElement', {}, c.rx_fix_replace_node(t, &re,
					range, replacement))
			} else if q.min == 1 {
				message_id = 'uselessQuantifier'
				first = rx_suggestion('suggestRemoveQuantifier', {}, c.rx_fix_replace_node(t,
					&re, range, element_raw))
			} else {
				min := '${i64(q.min)}'
				message_id = 'uselessRange'
				data = {
					'min': min
				}
				first = rx_suggestion('suggestRange', data, c.rx_fix_replace_node(t, &re, range,
					'${element_raw}{${min}}'))
			}
			mut suggestions := []Suggestion{}
			if s := first {
				suggestions << s
			}
			if s := make_greedy {
				suggestions << s
			}
			findings << Finding{
				...c.rx_report(t, &re, range, message_id, data)
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxnle_lazy_end_quantifiers ports extractLazyEndQuantifiers.
fn rxnle_lazy_end_quantifiers(ast &regexpp.Ast, alternatives []int) []int {
	mut out := []int{}
	for alternative in alternatives {
		elements := ast.nodes[alternative].elements
		if elements.len == 0 {
			continue
		}
		last := elements.last()
		n := ast.nodes[last]
		match n.kind {
			.quantifier {
				if !n.greedy && n.min != n.max {
					out << last
				} else if n.max == 1 {
					element := ast.nodes[n.element]
					if element.kind in [.group, .capturing_group] {
						out << rxnle_lazy_end_quantifiers(ast, element.alternatives)
					}
				}
			}
			.capturing_group, .group {
				out << rxnle_lazy_end_quantifiers(ast, n.alternatives)
			}
			else {}
		}
	}
	return out
}
