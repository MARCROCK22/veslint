module rules

import estree
import regexpp
import time

// Port of the `regexp/no-empty-alternative` rule of eslint-plugin-regexp 3.3.3 (it has no options),
// with its suggestion: the first empty alternative of a pattern, group, capturing group or string
// disjunction with two alternatives or more.

const regexp_no_empty_alternative_messages = {
	'empty':   'This empty alternative might be a mistake. If not, use a quantifier instead.'
	'suggest': 'Use a quantifier instead.'
}

fn (mut c Checker) lint_regexp_no_empty_alternative(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
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
			kind := ast.nodes[event.node].kind
			if event.enter && kind in [.group, .capturing_group, .pattern, .class_string_disjunction] {
				if f := c.rxnea_verify(t, &re, event.node) {
					findings << f
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxnea_verify ports verifyAlternatives.
fn (c &Checker) rxnea_verify(t &estree.EsTree, re &RxRegExp, node int) ?Finding {
	ast := &re.ast
	alternatives := ast.nodes[node].alternatives
	if alternatives.len < 2 {
		return none
	}
	for i, alt in alternatives {
		if ast.nodes[alt].elements.len != 0 {
			continue
		}
		index := ast.nodes[alt].start
		range := if i == alternatives.len - 1 {
			RxRange{index - 1, index}
		} else {
			RxRange{index, index + 1}
		}
		mut suggestions := []Suggestion{}
		if ast.nodes[node].kind != .class_string_disjunction {
			if fixed := rxnea_fixed_node(ast, node, alt) {
				if s := rx_suggestion('suggest', {}, c.rx_fix_replace_node(t, re, rx_node_range(ast,
					node), fixed))
				{
					suggestions << s
				}
			}
		}
		return Finding{
			...c.rx_report(t, re, range, 'empty', {})
			suggestions: suggestions
		}
	}
	return none
}

// rxnea_fixed_node ports getFixedNode: the node with the other alternatives in a group made optional
// (`??` for the first alternative, `?` for the last); none for an alternative in the middle.
fn rxnea_fixed_node(ast &regexpp.Ast, node int, alt int) ?string {
	n := ast.nodes[node]
	quant := if n.alternatives[0] == alt {
		'??'
	} else if n.alternatives[n.alternatives.len - 1] == alt {
		'?'
	} else {
		return none
	}
	inner := n.alternatives.filter(it != alt).map(rx_raw(ast, it)).join('|')
	mut replacement := '(?:${inner})${quant}'
	if n.kind == .capturing_group {
		first := ast.nodes[n.alternatives[0]]
		last := ast.nodes[n.alternatives[n.alternatives.len - 1]]
		before := rx_slice(ast, node, 0, first.start - n.start)
		after := rx_slice(ast, node, last.end - n.start, n.end - n.start)
		replacement = '${before}${replacement}${after}'
	} else if n.parent >= 0 && ast.nodes[n.parent].kind == .quantifier {
		replacement = '(?:${replacement})'
	}
	return replacement
}
