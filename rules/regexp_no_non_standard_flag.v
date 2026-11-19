module rules

import time

// Port of the `regexp/no-non-standard-flag` rule of eslint-plugin-regexp 3.3.3 (it has no options):
// the first flag that is none of `dgimsuvy`, on every regular expression whose flags are known.

const regexp_no_non_standard_flag_messages = {
	'unexpected': "Unexpected non-standard flag '{{flag}}'."
}

fn (mut c Checker) lint_regexp_no_non_standard_flag(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if !re.visited() {
			continue
		}
		stats.checked++
		if re.flags_string == '' {
			continue
		}
		for flag in re.flags_string.runes() {
			if !'dgimsuvy'.contains(flag.str()) {
				findings << c.rx_flags_report(t, re.regexp_node, re.flags_node, 'unexpected',
					{
					'flag': flag.str()
				})
				break
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
