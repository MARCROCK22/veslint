module rules

import estree
import time

// Port of the `unicorn/no-unnecessary-array-splice-count` and `unicorn/no-unnecessary-slice-end`
// rules of eslint-plugin-unicorn 64.0.0 (rules/shared/no-unnecessary-length-or-infinity-rule.js;
// they have no options), with their fix.

const unuasc_messages = {
	'no-unnecessary-array-splice-count': 'Passing `{{description}}` as the `{{argumentName}}` argument is unnecessary.'
}

const unuse_messages = {
	'no-unnecessary-slice-end': 'Passing `{{description}}` as the `end` argument is unnecessary.'
}

fn (mut c Checker) lint_unicorn_no_unnecessary_array_splice_count(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return c.un_length_or_infinity(root, abs_path, mut stats, ['splice', 'toSpliced'], 'no-unnecessary-array-splice-count')
}

fn (mut c Checker) lint_unicorn_no_unnecessary_slice_end(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return c.un_length_or_infinity(root, abs_path, mut stats, ['slice'], 'no-unnecessary-slice-end')
}

// un_length_or_infinity_description ports getObjectLengthOrInfinityDescription.
fn (c &Checker) un_length_or_infinity_description(t &estree.EsTree, node int, object int) ?string {
	// `Infinity`
	if t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == 'Infinity' {
		return 'Infinity'
	}
	// `Number.POSITIVE_INFINITY`
	if un_is_member(t, node, objects: ['Number'], properties: ['POSITIVE_INFINITY'], computed: false, optional: false) {
		return 'Number.POSITIVE_INFINITY'
	}
	// `object?.length`
	optional := t.typ(node) == .chain_expression
	member := if optional { t.node(node, .expression)? } else { node }
	// `object.length`
	if !(un_is_member(t, member, properties: ['length'], computed: false)
		&& c.un_is_same_reference(t, object, t.node(member, .object)?)) {
		return none
	}
	name := if t.typ(object) == .identifier { t.string_of(object, .name) or { '' } } else { '…' }
	return '${name}${if optional { '?.' } else { '.' }}length'
}

fn (mut c Checker) un_length_or_infinity(root C.TSNode, abs_path string, mut stats Stats, methods []string, message_id string) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: methods, arguments_length: 2, optional_call: false) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		second := (t.list(node, .arguments) or { continue })[1]
		description := c.un_length_or_infinity_description(t, second, t.node(callee, .object) or {
			continue
		}) or { continue }
		mut data := {
			'description': description
		}
		match t.string_of(t.node(callee, .property) or { continue }, .name) or { '' } {
			'splice' { data['argumentName'] = 'deleteCount' }
			'toSpliced' { data['argumentName'] = 'skipCount' }
			else {}
		}
		fix := c.un_remove_argument(t, tokens, second) or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, second)
			message_id: message_id
			data:       data
			has_fix:    true
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
