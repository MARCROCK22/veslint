module rules

import time

// Port of the `@eslint-community/eslint-comments/no-unlimited-disable` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: an `eslint-disable`,
// `eslint-disable-line` or `eslint-disable-next-line` comment without rule ids, as the plugin's
// own parser reads it, reported before the comment.

const ec_nud_messages = {
	'unexpected': "Unexpected unlimited '{{kind}}' comment. Specify some rule names to disable."
}

fn (mut c Checker) lint_eslint_comments_no_unlimited_disable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for directive in c.ec_directive_comments(root, []) {
		stats.checked++
		if directive.kind !in ['eslint-disable', 'eslint-disable-line', 'eslint-disable-next-line'] {
			continue
		}
		if directive.value == '' {
			findings << ec_finding(ec_force_location(directive.comment), 'unexpected', {
				'kind': directive.kind
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
