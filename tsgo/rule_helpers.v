module tsgo

import json2
import strings

// Requests that run a type walk of a rule in TypeScript's process (tsgo/inproc/api_rules.go):
// methods `veslint/…`, answered only by TypeScript linked into veslint. With `tsc --api` in a
// process of its own the rules walk the types themselves, through the requests of TypeScript's
// API; both give the same answers.

// in_process tells whether TypeScript runs in this process, where the `veslint/…` methods are
// answered.
pub fn (c &Client) in_process() bool {
	return c.inproc != 0
}

// UnboundMethodStep is a check of unbound-method: the property `name` of the type `typ`, of each
// of its parts (`walk`, checkUnionConstituentsAndReport) or of the type itself.
pub struct UnboundMethodStep {
pub:
	typ  int
	name string
	walk bool
}

// unbound_method_checks runs groups of checks of unbound-method in one request: `groups[i]` steps
// of `steps` after those of the groups before it, stopping at the first that reports. For each
// group: 0 when none reports, else the number of the step that reports (1 for the first) times 4
// plus the message: 1 for `unbound`, 2 for `unboundWithoutThisAnnotation`.
pub fn (mut c Client) unbound_method_checks(snapshot int, project string, ignore_static bool, groups []int, steps []UnboundMethodStep) ![]int {
	mut b := strings.new_builder(128 + steps.len * 40)
	b.write_string('{"snapshot":')
	b.write_decimal(snapshot)
	b.write_string(',"project":')
	b.write_string(json_text(project))
	b.write_string(',"ignoreStatic":')
	b.write_string(if ignore_static { 'true' } else { 'false' })
	b.write_string(',"groups":[')
	for i, count in groups {
		if i > 0 {
			b.write_u8(`,`)
		}
		b.write_decimal(count)
	}
	b.write_string('],"types":[')
	for i, step in steps {
		if i > 0 {
			b.write_u8(`,`)
		}
		b.write_decimal(step.typ)
	}
	b.write_string('],"names":[')
	for i, step in steps {
		if i > 0 {
			b.write_u8(`,`)
		}
		b.write_string(json_text(step.name))
	}
	b.write_string('],"walk":[')
	for i, step in steps {
		if i > 0 {
			b.write_u8(`,`)
		}
		b.write_string(if step.walk { 'true' } else { 'false' })
	}
	b.write_string(']}')
	answer := json2.decode[[]int](c.request('veslint/unboundMethodChecks', b.str())!) or {
		return error('invalid response from `veslint/unboundMethodChecks`: ${err.msg()}')
	}
	if answer.len != groups.len {
		return error('invalid response from `veslint/unboundMethodChecks`: ${answer.len} answers for ${groups.len} groups')
	}
	return answer
}
