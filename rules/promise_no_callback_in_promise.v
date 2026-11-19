module rules

import estree
import json2
import time

// Port of the `promise/no-callback-in-promise` rule of eslint-plugin-promise 7.3.0, with its
// options.

const prm_no_callback_in_promise_messages = {
	'callback': 'Avoid calling back inside of a promise.'
}

const prm_cb_blacklist = ['callback', 'cb', 'next', 'done']
const prm_timeout_whitelist = ['setImmediate', 'setTimeout', 'requestAnimationFrame', 'nextTick']

struct PrmNoCallbackInPromise {
	exceptions   []string
	timeouts_err bool
}

fn prm_no_callback_in_promise_options(options []json2.Any) !PrmNoCallbackInPromise {
	o := option_object(promise_no_callback_in_promise, options, ['exceptions', 'timeoutsErr'])!
	return PrmNoCallbackInPromise{
		exceptions:   o.string_list('exceptions')!
		timeouts_err: o.bool_value('timeoutsErr')!
	}
}

// prm_is_inside_timeout ports isInsideTimeout: a function expression given to setTimeout,
// setImmediate, requestAnimationFrame or nextTick (by the name of the callee, or of the property
// it calls).
fn prm_is_inside_timeout(t &estree.EsTree, node int) bool {
	if !prm_is_function_expression(t, node) {
		return false
	}
	callee := prm_child(t, t.nodes[node].parent, .callee)
	mut name := prm_name(t, prm_child(t, callee, .property))
	if name == '' {
		name = prm_name(t, callee)
	}
	return name in prm_timeout_whitelist
}

fn (mut c Checker) lint_promise_no_callback_in_promise(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := prm_no_callback_in_promise_options(c.rule_options(promise_no_callback_in_promise))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !c.prm_is_callback(t, node, o.exceptions) {
			args := t.list(node, .arguments) or { []int{} }
			name := if args.len > 0 { prm_name(t, args[0]) } else { '' }
			if prm_has_promise_callback(t, node) {
				callee := prm_child(t, node, .callee)
				mut calling_name := prm_name(t, callee)
				if calling_name == '' {
					calling_name = prm_name(t, prm_child(t, callee, .property))
				}
				if name !in o.exceptions && name in prm_cb_blacklist
					&& (o.timeouts_err || calling_name !in prm_timeout_whitelist) {
					findings << Finding{
						stmt:       c.es_tree_position(t, args[0])
						message_id: 'callback'
					}
				}
				continue
			}
			if !o.timeouts_err || name == '' {
				continue
			}
		}
		ancestors := prm_ancestors(t, node)
		if ancestors.any(prm_is_inside_promise(t, it))
			&& (o.timeouts_err || !ancestors.any(prm_is_inside_timeout(t, it))) {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'callback'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
