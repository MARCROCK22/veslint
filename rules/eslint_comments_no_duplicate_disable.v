module rules

import time

// Port of the `@eslint-community/eslint-comments/no-duplicate-disable` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: a disable directive for a rule (or for every
// rule) that an area already disables there, reported where the rule id is written (or before the
// comment, for every rule).

const ec_ndd_messages = {
	'duplicate':     'ESLint rules have been disabled already.'
	'duplicateRule': "'{{ruleId}}' rule has been disabled already."
}

fn (mut c Checker) lint_eslint_comments_no_duplicate_disable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	d := c.ec_disabled_area(root)
	mut findings := []Finding{}
	for item in d.duplicate_disable_directives {
		stats.checked++
		findings << ec_rule_comment_finding(d, item, 'duplicateRule', 'duplicate')
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ec_rule_comment_finding is the report of a directive about a rule id: `with_rule` when it has a
// rule id that is not empty, `without` otherwise.
fn ec_rule_comment_finding(d EcDisabledArea, item EcRuleComment, with_rule string, without string) Finding {
	loc := ec_rule_id_location(d.comments[item.comment], item.rule_id)
	if id := item.rule_id {
		return ec_finding(loc, if id != '' { with_rule } else { without }, {
			'ruleId': id
		})
	}
	return ec_finding(loc, without, {})
}
