module rules

import json2
import time

// Port of the `unicode-bom` rule of ESLint 10.6.0, with its option and its fix.

const ubom_messages = {
	'expected':   'Expected Unicode BOM (Byte Order Mark).'
	'unexpected': 'Unexpected Unicode BOM (Byte Order Mark).'
}

// ubom_always reads "always" or "never".
fn ubom_always(options []json2.Any) !bool {
	option := if options.len > 0 { options[0] } else { json2.Any('never') }
	if option is string && option in ['always', 'never'] {
		return option == 'always'
	}
	return error('the option of `${unicode_bom}` must be "always" or "never"')
}

fn (mut c Checker) lint_unicode_bom(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	always := ubom_always(c.rule_options(unicode_bom))!
	mut findings := []Finding{}
	stats.checked++
	// The text has no BOM (veslint takes it away, as ESLint does): the fix of "never" removes the
	// one before it (the range [-1, 0]).
	if !c.has_bom && always {
		findings << Finding{
			stmt:       c.position_at(0)
			message_id: 'expected'
			has_fix:    true
			fix:        fix_insert_at(0, '﻿')
		}
	} else if c.has_bom && !always {
		findings << Finding{
			stmt:       c.position_at(0)
			message_id: 'unexpected'
			has_fix:    true
			fix:        Fix{
				start: -1
				end:   0
				text:  ''
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
