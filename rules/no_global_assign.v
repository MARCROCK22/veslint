module rules

import json2
import time
import treesitter { position_of }

// Port of the `no-global-assign` rule of ESLint 10.6.0, with its option.

const nga_messages = {
	'globalShouldNotBeModified': "Read-only global '{{name}}' should not be modified."
}

// nga_exceptions reads `exceptions`.
fn nga_exceptions(options []json2.Any) ![]string {
	o := option_object(no_global_assign, options, ['exceptions'])!
	value := o.values['exceptions'] or { json2.Any([]json2.Any{}) }
	return value.as_array().map(it.str())
}

fn (mut c Checker) lint_no_global_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	exceptions := nga_exceptions(c.rule_options(no_global_assign))!
	mut findings := []Finding{}
	tree := c.scope_tree(root)
	for v in tree.scopes[0].variables {
		variable := tree.variables[v]
		// A global ESLint declares (from the configuration or a comment) as read-only.
		declared := variable.eslint_implicit_global_setting != '' || variable.eslint_explicit_global
		if !declared || variable.writeable || variable.name in exceptions {
			continue
		}
		stats.checked++
		for r in es_modifying_references(tree, v) {
			id := tree.references[r].identifier
			findings << Finding{
				stmt:       position_of(id)
				message_id: 'globalShouldNotBeModified'
				data:       {
					'name': c.text(id)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
