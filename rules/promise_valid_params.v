module rules

import json2
import time

// Port of the `promise/valid-params` rule of eslint-plugin-promise 7.3.0, with its options.

const prm_valid_params_messages = {
	'requireOneOptionalArgument':  'Promise.{{ name }}() requires 0 or 1 arguments, but received {{ numArgs }}'
	'requireOneArgument':          'Promise.{{ name }}() requires 1 argument, but received {{ numArgs }}'
	'requireTwoOptionalArguments': 'Promise.{{ name }}() requires 1 or 2 arguments, but received {{ numArgs }}'
}

fn prm_valid_params_options(options []json2.Any) ![]string {
	o := option_object(promise_valid_params, options, ['exclude'])!
	return o.string_list('exclude')!
}

fn (mut c Checker) lint_promise_valid_params(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	exclude := prm_valid_params_options(c.rule_options(promise_valid_params))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		if !prm_is_promise(t, node) {
			continue
		}
		name := prm_callee_property_name(t, node)
		num_args := (t.list(node, .arguments) or { []int{} }).len
		if name != '' && name in exclude {
			continue
		}
		message_id := match name {
			'resolve', 'reject' {
				if num_args > 1 { 'requireOneOptionalArgument' } else { '' }
			}
			'then' {
				if num_args < 1 || num_args > 2 { 'requireTwoOptionalArguments' } else { '' }
			}
			'race', 'all', 'allSettled', 'any', 'catch', 'finally' {
				if num_args != 1 { 'requireOneArgument' } else { '' }
			}
			else {
				''
			}
		}
		if message_id != '' {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: message_id
				data:       {
					'name':    name
					'numArgs': num_args.str()
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
