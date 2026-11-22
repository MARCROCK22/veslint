module rules

import time

// Port of the `regexp/no-invalid-regexp` rule of eslint-plugin-regexp 3.3.3 (it has no options): a
// pattern regexpp rejects (at its error index, from the unit before it to the one after it), and,
// for a pattern whose value is not known, duplicate flags or both `u` and `v`.

const regexp_no_invalid_regexp_messages = {
	'error':         '{{message}}'
	'duplicateFlag': 'Duplicate {{flag}} flag.'
	'uvFlag':        "Regex 'u' and 'v' flags cannot be used together."
}

fn (mut c Checker) lint_regexp_no_invalid_regexp(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if !re.visited() {
			continue
		}
		stats.checked++
		if re.kind == .invalid {
			data := {
				'message': re.error.message
			}
			index := re.error.index
			if index >= 0 && index <= re.source.value.len {
				start := if index - 1 > 0 { index - 1 } else { 0 }
				end := if index + 1 < re.source.value.len { index + 1 } else { re.source.value.len }
				findings << c.rx_report(t, &re, RxRange{start, end}, 'error', data)
			} else {
				findings << Finding{
					stmt:       c.es_tree_position(t, re.node)
					message_id: 'error'
					data:       data
				}
			}
		} else if re.kind == .unknown {
			mut seen := []rune{}
			mut duplicate := false
			for flag in re.flags_string.runes() {
				if flag in seen {
					findings << c.rx_flags_report(t, re.regexp_node, re.flags_node, 'duplicateFlag',
						{
						'flag': flag.str()
					})
					duplicate = true
					break
				}
				seen << flag
			}
			if !duplicate && re.flags.unicode && re.flags.unicode_sets {
				findings << c.rx_flags_report(t, re.regexp_node, re.flags_node, 'uvFlag', {})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
