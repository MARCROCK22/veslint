module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { node_field, nodes_of_kind, position_of }

// Port of the `require-array-sort-compare` rule of typescript-eslint 8.62.0, with its
// `ignoreStringArrays` option.

const rasc_messages = {
	'requireCompare': "Require 'compare' argument."
}

struct RascOptions {
	ignore_string_arrays bool
}

fn rasc_options(options []json2.Any) !RascOptions {
	o := option_object(require_array_sort_compare, options, ['ignoreStringArrays'])!
	return RascOptions{
		ignore_string_arrays: o.bool_value('ignoreStringArrays')!
	}
}

fn (mut c Checker) lint_require_array_sort_compare(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := rasc_options(c.rule_options(require_array_sort_compare))!
	mut sw := time.new_stopwatch()
	// 'CallExpression[arguments.length=0] > MemberExpression': the callee of a call without
	// arguments, when it is a member access named `sort` or `toSorted`.
	mut calls := []C.TSNode{}
	mut objects := []C.TSNode{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		args := call_arguments(call) or { continue }
		if args.len != 0 {
			continue
		}
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		if !is_member(callee) || is_estree_chain_root(callee) {
			continue
		}
		if !c.is_static_member_access_of_value(callee, ['sort', 'toSorted']) {
			continue
		}
		object := node_field(callee, 'object') or { continue }
		calls << call
		objects << unwrap_parens(object)
	}
	c.resolve_spans(objects.map(node_span(it)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, call in calls {
		t := c.node_type(objects[i]) or { continue }
		if options.ignore_string_arrays && c.rasc_is_string_array(t)! {
			continue
		}
		if c.rasc_is_array_or_union_of_arrays(c.constrained(t)!)! {
			findings << Finding{
				stmt:       position_of(call)
				message_id: 'requireCompare'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}

// rasc_is_string_array ports isStringArrayNode: an array or a tuple all of whose type arguments
// are text (getTypeName), on the type of the node itself, not on its constraint.
fn (mut c Checker) rasc_is_string_array(t TypeResponse) !bool {
	if !c.is_array(t)! && !c.is_tuple(t)! {
		return false
	}
	for arg in c.type_args(t)! {
		if c.type_name(arg, 0)! != 'string' {
			return false
		}
	}
	return true
}

// rasc_is_array_or_union_of_arrays ports isTypeArrayTypeOrUnionOfArrayTypes: an array (not a
// tuple), or a union of arrays.
fn (mut c Checker) rasc_is_array_or_union_of_arrays(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if !c.is_array(part)! {
				return false
			}
		}
		return true
	}
	return c.is_array(t)!
}
