module rules

import json2
import regexpp
import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-invalid-regexp` rule of ESLint 10.6.0.

const nir_messages = {
	'regexMessage': '{{message}}.'
}

const nir_valid_flags = 'dgimsuvy'

// nir_options are the flags allowConstructorFlags adds to the valid ones, without repeats.
fn nir_options(options []json2.Any) ![]string {
	o := option_object(no_invalid_regexp, options, ['allowConstructorFlags'])!
	mut allowed := []string{}
	for flag in o.string_list('allowConstructorFlags')!.join('').runes() {
		text := flag.str()
		if !nir_valid_flags.contains(text) && text !in allowed {
			allowed << text
		}
	}
	return allowed
}

fn (mut c Checker) lint_no_invalid_regexp(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allowed := nir_options(c.rule_options(no_invalid_regexp))!
	mut all_flags := nir_valid_flags.split('')
	all_flags << allowed
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['call_expression', 'new_expression'], []) {
		stats.checked++
		callee := node_field(node, if node_kind(node) == 'call_expression' {
			'function'
		} else {
			'constructor'
		}) or { continue }
		if node_kind(callee) != 'identifier' || c.text(callee) != 'RegExp' {
			continue
		}
		mut args := []C.TSNode{}
		if arguments := node_field(node, 'arguments') {
			if node_kind(arguments) != 'arguments' {
				continue
			}
			args = named_children(arguments).filter(node_kind(it) != 'comment').map(unwrap_parens(it))
		}
		// getFlags: '' without a second argument, none when it is not a string.
		mut flags := ?string('')
		if args.len >= 2 {
			flags = if units := c.es_string_units(args[1]) {
				?string(stv_units_string(units))
			} else {
				?string(none)
			}
		}
		mut message := ''
		if f := flags {
			mut to_check := f
			if f != '' {
				for flag in all_flags {
					to_check = to_check.replace_once(flag, '')
				}
			}
			message = nir_flags_message(f, to_check, all_flags)
		}
		if message != '' {
			findings << nir_report(node, message)
			continue
		}
		if args.len == 0 {
			continue
		}
		pattern := c.es_string_units(args[0]) or { continue }
		if f := flags {
			message = nir_pattern_message(pattern, es_regex_pattern_flags(f))
		} else {
			// Without known flags, invalid in every mode; the message is that of no flags.
			if nir_pattern_message(pattern, regexpp.PatternFlags{ unicode: true }) != ''
				&& nir_pattern_message(pattern, regexpp.PatternFlags{ unicode_sets: true }) != '' {
				message = nir_pattern_message(pattern, regexpp.PatternFlags{})
			}
		}
		if message != '' {
			findings << nir_report(node, message)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn nir_report(node C.TSNode, message string) Finding {
	return Finding{
		stmt:       position_of(node)
		message_id: 'regexMessage'
		data:       {
			'message': message
		}
	}
}

// nir_pattern_message ports validateRegExpPattern: regexpp's message, '' for a valid pattern.
fn nir_pattern_message(pattern []u16, flags regexpp.PatternFlags) string {
	regexpp.validate_pattern(pattern, 0, pattern.len, flags, regexpp.Options{}) or {
		if err is regexpp.SyntaxError {
			return err.message
		}
		return err.msg()
	}
	return ''
}

// nir_flags_message ports validateRegExpFlags.
fn nir_flags_message(flags string, to_check string, all_flags []string) string {
	mut duplicates := []string{}
	for flag in to_check.runes() {
		if flag.str() in all_flags {
			duplicates << flag.str()
		}
	}
	if flags.contains('u') && flags.contains('v') {
		return "Regex 'u' and 'v' flags cannot be used together"
	}
	if duplicates.len > 0 {
		return "Duplicate flags ('${duplicates.join('')}') supplied to RegExp constructor"
	}
	if to_check == '' {
		return ''
	}
	return "Invalid flags supplied to RegExp constructor '${to_check}'"
}
