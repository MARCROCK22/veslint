module rules

import time
import treesitter { node_kind, position_of }

// Port of the `no-new-native-nonconstructor` rule of ESLint 10.6.0 (it has no options).

const nnnn_messages = {
	'noNewNonconstructor': '`{{name}}` cannot be called as a constructor.'
}

fn (mut c Checker) lint_no_new_native_nonconstructor(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for name in ['Symbol', 'BigInt'] {
		for id in c.es_global_variable_references(root, name) {
			stats.checked++
			if call := es_callee_of(id) {
				if node_kind(call) == 'new_expression' {
					findings << Finding{
						stmt:       position_of(id)
						message_id: 'noNewNonconstructor'
						data:       {
							'name': name
						}
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
