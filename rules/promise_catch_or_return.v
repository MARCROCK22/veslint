module rules

import estree
import json2
import time

// Port of the `promise/catch-or-return` rule of eslint-plugin-promise 7.3.0, with its options.

const prm_catch_or_return_messages = {
	'terminationMethod': 'Expected {{ terminationMethod }}() or return'
}

struct PrmCatchOrReturn {
	allow_then         bool
	allow_then_strict  bool
	allow_finally      bool
	termination_method []string
}

fn prm_catch_or_return_options(options []json2.Any) !PrmCatchOrReturn {
	o := option_object(promise_catch_or_return, options, ['allowFinally', 'allowThen', 'allowThenStrict',
		'terminationMethod'])!
	// `options.terminationMethod || 'catch'`, a text making a list of one.
	mut methods := ['catch']
	if value := o.values['terminationMethod'] {
		if value is string {
			if value != '' {
				methods = [value]
			}
		} else {
			methods = o.string_list('terminationMethod')!
		}
	}
	return PrmCatchOrReturn{
		allow_then:         o.bool_value('allowThen')!
		allow_then_strict:  o.bool_value('allowThenStrict')!
		allow_finally:      o.bool_value('allowFinally')!
		termination_method: methods
	}
}

// prm_is_allowed_promise_termination ports isAllowedPromiseTermination.
fn prm_is_allowed_promise_termination(t &estree.EsTree, o &PrmCatchOrReturn, expression int) bool {
	if !prm_is_member_call(t, expression) {
		return false
	}
	callee := prm_child(t, expression, .callee)
	property := prm_child(t, callee, .property)
	name := prm_name(t, property)
	args := t.list(expression, .arguments) or { []int{} }
	// somePromise.then(a, b), somePromise.then(null, b)
	if (o.allow_then || o.allow_then_strict) && name == 'then' && args.len == 2
		&& ((o.allow_then && !o.allow_then_strict)
			|| (t.typ(args[0]) == .literal && t.get(args[0], .value) is estree.Null)) {
		return true
	}
	// somePromise.catch().finally(fn)
	object := prm_child(t, callee, .object)
	if o.allow_finally && name == 'finally' && prm_is_promise(t, object)
		&& prm_is_allowed_promise_termination(t, o, object) {
		return true
	}
	// somePromise.catch()
	if name != '' && name in o.termination_method {
		return true
	}
	// somePromise['catch']()
	if t.typ(property) == .literal {
		value := t.get(property, .value)
		if value is string && value == 'catch' {
			return true
		}
	}
	// cy.get().then(a, b)
	return prm_is_member_call_with_object_name(t, 'cy', expression)
}

fn (mut c Checker) lint_promise_catch_or_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := prm_catch_or_return_options(c.rule_options(promise_catch_or_return))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .expression_statement || !t.visits(node) {
			continue
		}
		stats.checked++
		expression := prm_child(t, node, .expression)
		if !prm_is_promise(t, expression) || prm_is_allowed_promise_termination(t, &o, expression) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'terminationMethod'
			data:       {
				// An array in the message is its elements joined with commas.
				'terminationMethod': o.termination_method.join(',')
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
