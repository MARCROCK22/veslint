module rules

import json2
import time

// Port of the `regexp/no-missing-g-flag` rule of eslint-plugin-regexp 3.3.3 with its option
// (strictTypes, true by default) and its fix: a regular expression without the `g` flag given as
// the first argument of matchAll or replaceAll of a string (TypeScript's type of the object, from the
// program; without one the object is never a string).

const regexp_no_missing_g_flag_messages = {
	'missingGlobalFlag': "The pattern given to the argument of `String#{{method}}()` requires the `g` flag, but is missing it."
}

// rxnmgf_options is strictTypes.
fn rxnmgf_options(options []json2.Any) !bool {
	o := option_object(regexp_no_missing_g_flag, options, ['strictTypes'])!
	value := o.values['strictTypes'] or { return true }
	if value is json2.Null {
		return true
	}
	return o.bool_value('strictTypes')!
}

fn (mut c Checker) lint_regexp_no_missing_g_flag(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	strict_types := rxnmgf_options(c.rule_options(regexp_no_missing_g_flag))!
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	methods := {
		'matchAll':   1
		'replaceAll': 2
	}
	for re in regexps {
		if !re.visited() {
			continue
		}
		stats.checked++
		if re.flags.global || !re.has_flags_string {
			continue
		}
		for ref in c.rx_expression_references(root, t, re.regexp_node) {
			if ref.kind != .argument {
				continue
			}
			call := ref.other
			args := t.list(call, .arguments) or { []int{} }
			if args.len == 0 || args[0] != ref.node || !rx_is_known_method_call(t, call, methods) {
				continue
			}
			object := t.node(t.node(call, .callee) or { -1 }, .object) or { -1 }
			is_string := if strict_types {
				c.rx_is_string(root, t, abs_path, object)
			} else {
				c.rx_maybe_string(root, t, abs_path, object)
			}
			if !is_string {
				continue
			}
			mut finding := Finding{
				stmt:       c.es_tree_position(t, ref.node)
				message_id: 'missingGlobalFlag'
				data:       {
					'method': rx_method_name(t, call)
				}
			}
			// The fix only when the regular expression is the argument itself.
			mut fixable := args[0] == re.regexp_node
			if fixable && t.typ(re.regexp_node) in [.new_expression, .call_expression] {
				call_args := t.list(re.regexp_node, .arguments) or { []int{} }
				if call_args.len > 1 && t.typ(call_args[1]) != .literal {
					fixable = false
				}
			}
			if fixable {
				finding = rx_with_fix(finding, c.rx_fix_replace_flags(t, &re, '${re.flags_string}g',
					false))
			}
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
