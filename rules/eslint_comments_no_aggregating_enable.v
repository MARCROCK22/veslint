module rules

import time

// Port of the `@eslint-community/eslint-comments/no-aggregating-enable` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: an `eslint-enable` that closes the areas of
// two or more `eslint-disable` comments, reported before the comment.

const ec_nae_messages = {
	'aggregatingEnable': 'This `eslint-enable` comment affects {{count}} `eslint-disable` comments. An `eslint-enable` comment should be for an `eslint-disable` comment.'
}

fn (mut c Checker) lint_eslint_comments_no_aggregating_enable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	d := c.ec_disabled_area(root)
	mut findings := []Finding{}
	for i, comment in d.related_comments {
		stats.checked++
		count := d.related_counts[i]
		if count >= 2 {
			findings << ec_finding(ec_force_location(d.comments[comment]), 'aggregatingEnable',
				{
				'count': count.str()
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
