module rules

import regexpp
import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-control-regex` rule of ESLint 10.6.0 (it has no options).

const ncrx_messages = {
	'unexpected': 'Unexpected control character(s) in regular expression: {{controlChars}}.'
}

fn (mut c Checker) lint_no_control_regex(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['regex', 'string'], []) {
		stats.checked++
		pattern, flags := c.ncrx_regexp(node) or { continue }
		chars := ncrx_control_chars(pattern, flags)
		if chars.len > 0 {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpected'
				data:       {
					'controlChars': chars.join(', ')
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ncrx_regexp ports getRegExp: the pattern and flags of a regular expression literal, or of a
// string that is the first argument of `RegExp(…)` or `new RegExp(…)` (the flags of a second
// string argument, '' standing for none).
fn (c &Checker) ncrx_regexp(node C.TSNode) ?([]u16, ?string) {
	if pattern, flags := c.es_regex_literal(node) {
		return pattern, ?string(flags)
	}
	value := c.es_string_units(node)?
	arguments, child := es_estree_parent(node)?
	if node_kind(arguments) != 'arguments' {
		return none
	}
	call := treesitter.node_parent(arguments)?
	if node_kind(call) !in ['call_expression', 'new_expression'] {
		return none
	}
	callee := node_field(call, if node_kind(call) == 'call_expression' {
		'function'
	} else {
		'constructor'
	})?
	if node_kind(callee) != 'identifier' || c.text(callee) != 'RegExp' {
		return none
	}
	args := named_children(arguments).filter(node_kind(it) != 'comment')
	if args.len == 0 || node_key(args[0]) != node_key(child) {
		return none
	}
	mut flags := ?string(none)
	if args.len > 1 {
		if units := c.es_string_units(unwrap_parens(args[1])) {
			flags = stv_units_string(units)
		}
	}
	return value, flags
}

// ncrx_control_chars ports collectControlChars: the control characters regexpp's validator meets
// (written as themselves or with `\x` or `\u`), in the last pass over the pattern.
fn ncrx_control_chars(pattern []u16, flags ?string) []string {
	f := flags or { '' }
	result := regexpp.validate_pattern_events(pattern, 0, pattern.len, es_regex_pattern_flags(f),
		regexpp.Options{})
	mut out := []string{}
	for event in result.events {
		match event.kind {
			.pattern_enter {
				out = []string{}
			}
			.character {
				cp := event.value
				if cp < 0 || cp > 0x1f {
					continue
				}
				raw := pattern[event.start..event.end]
				literal := event.start < pattern.len && int(pattern[event.start]) == cp
				escaped := raw.len >= 2 && raw[0] == `\\` && (raw[1] == `x` || raw[1] == `u`)
				if literal || escaped {
					out << '\\x${cp:02x}'
				}
			}
			else {}
		}
	}
	return out
}
