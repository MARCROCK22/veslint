module rules

import time

// Port of the `@eslint-community/eslint-comments/no-unused-enable` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: an enable directive for a rule (or for every
// rule) that closes no area, reported where the rule id is written (or before the comment, for
// every rule).

const ec_nue_messages = {
	'unused':     'ESLint rules are re-enabled but those have not been disabled.'
	'unusedRule': "'{{ruleId}}' rule is re-enabled but it has not been disabled."
}

fn (mut c Checker) lint_eslint_comments_no_unused_enable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	d := c.ec_disabled_area(root)
	mut findings := []Finding{}
	for item in d.unused_enable_directives {
		stats.checked++
		findings << ec_rule_comment_finding(d, item, 'unusedRule', 'unused')
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
