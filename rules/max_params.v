module rules

import json2
import time

// Port of the `max-params` rule of typescript-eslint 8.72.2, which extends the rule of ESLint
// 10.15.0 with the same name (ported here too): unless `countVoidThis`, a first parameter
// `this: void` is not counted. The wrapper has no meta.defaultOptions, so the core rule reads the
// options as written (`max`, or `maximum`, 3 without them).

const tsmp_messages = {
	'exceed': '{{name}} has too many parameters ({{count}}). Maximum allowed is {{max}}.'
}

struct TsmpOptions {
	count_void_this bool
	max             ?f64 // the core rule's numParams; none when it is `undefined`
}

// tsmp_options reads the merged options and, after them, the written ones (effective_options).
fn tsmp_options(options []json2.Any) !TsmpOptions {
	o := option_object(max_params, options, ['countVoidThis', 'max', 'maximum'])!
	mut max := ?f64(3.0)
	if options.len > 1 && options[1] is []json2.Any {
		written := options[1].as_array()
		if written.len > 0 && written[0] is map[string]json2.Any {
			raw := written[0].as_map()
			if 'maximum' in raw || 'max' in raw {
				// `option.maximum || option.max`.
				maximum := raw['maximum'] or { json2.Any(json2.null) }
				value := if json_kind(maximum) == .number && json_number(maximum) != 0 {
					maximum
				} else {
					raw['max'] or { json2.Any(json2.null) }
				}
				max = if json_kind(value) == .number { json_number(value) } else { none }
			}
		}
	}
	return TsmpOptions{
		count_void_this: o.bool_value('countVoidThis')!
		max:             max
	}
}

fn (mut c Checker) lint_max_params(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := tsmp_options(c.rule_options(max_params))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut checked := 0
	for i, node in t.nodes {
		if node.typ !in [.arrow_function_expression, .function_declaration, .function_expression,
			.ts_declare_function, .ts_function_type] {
			continue
		}
		checked++
		params := t.list(i, .params) or { []int{} }
		mut count := params.len
		// removeVoidThisParam, or the core rule's countThis 'except-void' (with `countVoidThis`,
		// 'always').
		if !o.count_void_this && params.len > 0 && t.typ(params[0]) == .identifier
			&& (t.string_of(params[0], .name) or { '' }) == 'this' {
			if annotation := t.node(params[0], .type_annotation) {
				if inner := t.node(annotation, .type_annotation) {
					if t.typ(inner) == .ts_void_keyword {
						count--
					}
				}
			}
		}
		max := o.max or { continue }
		if f64(count) > max {
			findings << Finding{
				stmt:       c.es_tree_function_head(t, i)
				message_id: 'exceed'
				data:       {
					'name':  upper_case_first(c.es_tree_function_name(t, i))
					'count': count.str()
					'max':   js_number_to_string(max)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
