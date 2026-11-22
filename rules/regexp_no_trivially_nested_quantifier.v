module rules

import math
import regexpp
import time

// Port of the `regexp/no-trivially-nested-quantifier` rule of eslint-plugin-regexp 3.3.3 (it has no
// options), with its fix: a quantified group whose only alternative is a quantifier that can be
// merged with it, or, with more alternatives, a quantifier of one of them that can be simplified or
// removed.

const regexp_no_trivially_nested_quantifier_messages = {
	'nested':       "These two quantifiers are trivially nested and can be replaced with '{{quant}}'."
	'childOne':     'This nested quantifier can be removed.'
	'childSimpler': "This nested quantifier can be simplified to '{{quant}}'."
}

fn (mut c Checker) lint_regexp_no_trivially_nested_quantifier(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
			q := ast.nodes[event.node]
			if !event.enter || q.kind != .quantifier || rxntnq_is_trivial(q) {
				continue
			}
			element := ast.nodes[q.element]
			if element.kind != .group {
				continue
			}
			for alternative in element.alternatives {
				elements := ast.nodes[alternative].elements
				if elements.len != 1 || ast.nodes[elements[0]].kind != .quantifier {
					continue
				}
				child_index := elements[0]
				child := ast.nodes[child_index]
				if rxntnq_is_trivial(child) {
					continue
				}
				if element.alternatives.len == 1 {
					quant := rxntnq_combined(q, child) or { continue }
					quant_str := rx_quant_to_string(quant) or { continue }
					replacement := rx_raw(ast, child.element) + quant_str
					range := rx_node_range(ast, event.node)
					findings << rx_with_fix(c.rx_report(t, &re, range, 'nested', {
						'quant': quant_str
					}), c.rx_fix_replace_node(t, &re, range, replacement))
				} else {
					quant := rxntnq_simplified_child(q, child) or { continue }
					if quant.min == child.min && quant.max == child.max {
						continue
					}
					range := rx_node_range(ast, child_index)
					if quant.min == 1 && quant.max == 1 {
						findings << rx_with_fix(c.rx_report(t, &re, range, 'childOne', {}),
							c.rx_fix_replace_node(t, &re, range, rx_raw(ast, child.element)))
					} else {
						without_greedy := RxQuant{
							min: quant.min
							max: quant.max
						}
						findings << rx_with_fix(c.rx_report(t, &re, range, 'childSimpler', {
							'quant': rx_quant_to_string(without_greedy) or { continue }
						}), c.rx_fix_replace_quant(t, &re, child_index, '', without_greedy))
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxntnq_is_trivial ports isTrivialQuantifier: {0} or {1}.
fn rxntnq_is_trivial(q regexpp.Node) bool {
	return q.min == q.max && (q.min == 0 || q.min == 1)
}

// rxntnq_combined ports getCombinedQuant: `(R{a,b}){c,d}` as `R{a*c,b*d}` when they are the same.
fn rxntnq_combined(parent regexpp.Node, child regexpp.Node) ?RxQuant {
	if parent.max == 0 || child.max == 0 || parent.greedy != child.greedy {
		return none
	}
	a := child.min
	b := child.max
	c := parent.min
	d := parent.max
	condition := if math.is_inf(b, 1) && c == 0 {
		a <= 1
	} else {
		c == d || b * c + 1 >= a * (c + 1)
	}
	if !condition {
		return none
	}
	return RxQuant{
		min:        a * c
		max:        b * d
		greedy:     parent.greedy
		has_greedy: true
	}
}

// rxntnq_simplified_child ports getSimplifiedChildQuant.
fn rxntnq_simplified_child(parent regexpp.Node, child regexpp.Node) ?RxQuant {
	if parent.max == 0 || child.max == 0 || parent.greedy != child.greedy {
		return none
	}
	mut min := child.min
	mut max := child.max
	if min == 0 && parent.min == 0 {
		min = 1
	}
	if math.is_inf(parent.max, 1) && (min == 0 || min == 1) && max > 1 {
		max = 1
	}
	return RxQuant{
		min:        min
		max:        max
		greedy:     child.greedy
		has_greedy: true
	}
}
