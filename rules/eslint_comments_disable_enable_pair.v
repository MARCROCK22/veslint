module rules

import json2
import offsets
import time

// Port of the `@eslint-community/eslint-comments/disable-enable-pair` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: an `eslint-disable` area that no
// `eslint-enable` closes, reported where its rule id is written (or before the comment, for every
// rule); with `allowWholeFile`, not one that starts before the first token of the file.

const ec_dep_messages = {
	'missingPair':     "Requires 'eslint-enable' directive."
	'missingRulePair': "Requires 'eslint-enable' directive for '{{ruleId}}'."
}

fn ec_dep_options(options []json2.Any) !bool {
	if options.len == 0 {
		return false
	}
	value := options[0].as_map()['allowWholeFile'] or { return false }
	return value is bool && value
}

fn (mut c Checker) lint_eslint_comments_disable_enable_pair(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_whole_file := ec_dep_options(c.rule_options(eslint_comments_disable_enable_pair))!
	d := c.ec_disabled_area(root)
	mut findings := []Finding{}
	// sourceCode.ast.tokens[0]: the first token, comments aside.
	tokens := c.source_tokens(root).tokens
	if allow_whole_file && tokens.len == 0 {
		return findings
	}
	mut first := EcPos{}
	if allow_whole_file {
		line, column := c.line_column(offsets.line_starts(c.src), tokens[0].start)
		first = EcPos{line, column - 1}
	}
	for area in d.areas {
		stats.checked++
		if area.end != none {
			continue
		}
		if allow_whole_file && ec_lte(area.start, first) {
			continue
		}
		loc := ec_rule_id_location(d.comments[area.comment], area.rule_id)
		if id := area.rule_id {
			findings << ec_finding(loc, if id != '' { 'missingRulePair' } else { 'missingPair' },
				{
				'ruleId': id
			})
		} else {
			findings << ec_finding(loc, 'missingPair', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
