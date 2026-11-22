module rules

import json2
import time

// Port of the `@eslint-community/eslint-comments/no-restricted-disable` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: the disable areas of the rules the options
// name, as patterns of the `ignore` package (gitignore's, without case: EcIgnore), and those for
// every rule; reported where the rule id is written (or before the comment, for every rule).
// Deviation: a rule id the package rejects as a path (empty, or starting with `/`, `./` or `../`)
// makes ESLint stop with its error; veslint stops with the same message.

const ec_nrd_messages = {
	'disallow': "Disabling '{{ruleId}}' is not allowed."
}

fn ec_nrd_options(options []json2.Any) ![]string {
	return options.map(it.str())
}

fn (mut c Checker) lint_eslint_comments_no_restricted_disable(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	d := c.ec_disabled_area(root)
	mut findings := []Finding{}
	patterns := ec_nrd_options(c.rule_options(eslint_comments_no_restricted_disable))!
	if patterns.len == 0 {
		return findings
	}
	mut ig := EcIgnore{}
	for pattern in patterns {
		ig.add(pattern)!
	}
	for area in d.areas {
		stats.checked++
		mut rule_id := ''
		mut report := false
		if id := area.rule_id {
			rule_id = id
			report = ig.ignores(id)!
		} else {
			report = true
		}
		if !report {
			continue
		}
		findings << ec_finding(ec_rule_id_location(d.comments[area.comment], area.rule_id),
			'disallow', {
			// `area.ruleId || String(context.options)`
			'ruleId': if rule_id != '' { rule_id } else { patterns.join(',') }
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
