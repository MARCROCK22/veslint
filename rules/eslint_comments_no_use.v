module rules

import json2
import time

// Port of the `@eslint-community/eslint-comments/no-use` rule of
// @eslint-community/eslint-plugin-eslint-comments 4.8.1: every directive comment (ESLint's, and the
// `additionalDirectives`) whose kind `allow` does not list, as the plugin's own parser reads it,
// reported before the comment.

const ec_nu_messages = {
	'disallowEslint': 'Unexpected ESLint directive comment.'
	'disallow':       'Unexpected directive comment.'
}

// EcNuOptions are the `allow` and `additionalDirectives` options of no-use and require-description
// (`ignore` there).
struct EcNuOptions {
	allow      []string
	additional []string
}

fn ec_strings_option(options []json2.Any, key string) []string {
	if options.len == 0 {
		return []
	}
	value := options[0].as_map()[key] or { return [] }
	return value.as_array().map(it.str())
}

fn ec_nu_options(options []json2.Any) !EcNuOptions {
	return EcNuOptions{
		allow:      ec_strings_option(options, 'allow')
		additional: ec_strings_option(options, 'additionalDirectives')
	}
}

fn (mut c Checker) lint_eslint_comments_no_use(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := ec_nu_options(c.rule_options(eslint_comments_no_use))!
	mut findings := []Finding{}
	for directive in c.ec_directive_comments(root, o.additional) {
		stats.checked++
		if directive.kind in o.allow {
			continue
		}
		findings << ec_finding(ec_force_location(directive.comment), if directive.eslint {
			'disallowEslint'
		} else {
			'disallow'
		}, {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
