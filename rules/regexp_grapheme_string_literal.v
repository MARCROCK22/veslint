module rules

import regexpp
import time

// Port of the `regexp/grapheme-string-literal` rule of eslint-plugin-regexp 3.3.3 (it has no
// options): a string alternative of a string disjunction (`\q{…}`) of more than one grapheme, as
// Intl.Segmenter counts them (sty_string_length of @stylistic's port).

const regexp_grapheme_string_literal_messages = {
	'onlySingleCharacters': 'Only single characters and graphemes are allowed inside character classes. Use regular alternatives (e.g. `{{alternatives}}`) for strings instead.'
}

// rxgsl_is_multiple_graphemes ports isMultipleGraphemes.
fn rxgsl_is_multiple_graphemes(ast &regexpp.Ast, alternative int) bool {
	elements := ast.nodes[alternative].elements
	if elements.len <= 1 {
		return false
	}
	text := elements.map(rune(ast.nodes[it].value)).string()
	return sty_string_length(text) > 1
}

fn (mut c Checker) lint_regexp_grapheme_string_literal(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			n := ast.nodes[event.node]
			if !event.enter || n.kind != .string_alternative
				|| !rxgsl_is_multiple_graphemes(ast, event.node) {
				continue
			}
			raws := ast.nodes[n.parent].alternatives.filter(rxgsl_is_multiple_graphemes(ast,
				it)).map(rx_raw(ast, it))
			findings << c.rx_report(t, &re, rx_node_range(ast, event.node), 'onlySingleCharacters',
				{
				'alternatives': '(?:${raws.join('|')}|[...])'
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
