module rules

import json2
import time

// Port of the `@eslint-community/eslint-comments/require-description` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: a directive comment (ESLint's, and the
// `additionalDirectives`) whose kind `ignore` does not list, without a description after ` -- `
// (the text up to the next ` -- `), as the plugin's own parser reads it, reported before the
// comment.

const ec_rd_messages = {
	'missingDescription': 'Unexpected undescribed directive comment. Include descriptions to explain why the comment is necessary.'
}

fn ec_rd_options(options []json2.Any) !EcNuOptions {
	return EcNuOptions{
		allow:      ec_strings_option(options, 'ignore')
		additional: ec_strings_option(options, 'additionalDirectives')
	}
}

fn (mut c Checker) lint_eslint_comments_require_description(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := ec_rd_options(c.rule_options(eslint_comments_require_description))!
	mut findings := []Finding{}
	for directive in c.ec_directive_comments(root, o.additional) {
		stats.checked++
		if directive.kind in o.allow {
			continue
		}
		description := directive.description or { '' }
		if description == '' {
			findings << ec_finding(ec_force_location(directive.comment), 'missingDescription',
				{})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
