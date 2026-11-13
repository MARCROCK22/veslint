module rules

import jsregexp
import time
import treesitter { named_children, node_field, node_kind, nodes_of_kind, position_of }

// Port of the `prefer-regexp-exec` rule of typescript-eslint 8.62.0, with its fix.
//
// For a string literal argument with a surrogate that has no pair (`text.match('\ud800')`), the
// text of the fix has U+FFFD in its place: that is how Node writes such a string in UTF-8, so it
// is what `eslint --fix` leaves in the file.

const prx_messages = {
	'regExpExecOverStringMatch': 'Use the `RegExp#exec()` method instead.'
}

// PrxCandidate is a `.match` member of a call with one argument whose types decide the report.
struct PrxCandidate {
	call           C.TSNode
	member         C.TSNode
	object         C.TSNode
	argument       C.TSNode
	string_literal bool   // the argument is a string literal that RegExp accepts
	regexp         string // and what `RegExp(argument).toString()` gives for it
}

fn (mut c Checker) lint_prefer_regexp_exec(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut candidates := []PrxCandidate{}
	mut spans := []Span{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		args := call_arguments(call) or { continue }
		if args.len != 1 {
			continue
		}
		// 'CallExpression[arguments.length=1] > MemberExpression': the callee or the argument.
		mut members := []C.TSNode{}
		if callee := node_field(call, 'function') {
			members << unwrap_parens(callee)
		}
		members << unwrap_parens(args[0])
		for member in members {
			if !is_member(member) || is_estree_chain_root(member) {
				continue
			}
			candidate := c.prx_candidate(call, member, unwrap_parens(args[0])) or { continue }
			spans << node_span(candidate.object)
			if !candidate.string_literal {
				spans << node_span(candidate.argument)
			}
			candidates << candidate
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for candidate in candidates {
		object := c.node_type(candidate.object) or { continue }
		if c.type_name(object, 0)! != 'string' {
			continue
		}
		mut string_argument := false
		if !candidate.string_literal {
			argument := c.node_type(candidate.argument) or { continue }
			mut regexp := false
			mut text := false
			for part in c.constituents(argument)! {
				name := c.type_name(part, 0)!
				if name == 'RegExp' {
					regexp = true
				} else if name == 'string' {
					text = true
				}
			}
			if regexp == text {
				continue
			}
			string_argument = text
		}
		findings << Finding{
			stmt:       position_of(member_property(candidate.member) or { continue })
			message_id: 'regExpExecOverStringMatch'
			has_fix:    true
			fix:        c.prx_fix(candidate, string_argument)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

// prx_fix ports the three fixers (getWrappingFixer on the call): `/source/.exec(object)` for a
// string literal, `RegExp(argument).exec(object)` for another string and
// `argument.exec(object)` for a RegExp.
fn (mut c Checker) prx_fix(candidate PrxCandidate, string_argument bool) Fix {
	call := es_inner(candidate.call)
	object := c.wrapping_inner_code(call, es_child(candidate.object))
	if candidate.string_literal {
		return c.wrapping_fix(call, '${candidate.regexp}.exec(${object})')
	}
	argument := c.wrapping_inner_code(call, es_child(candidate.argument))
	if string_argument {
		return c.wrapping_fix(call, 'RegExp(${argument}).exec(${object})')
	}
	return c.wrapping_fix(call, '${argument}.exec(${object})')
}

// prx_candidate applies the checks that do not need types: a static `match` member, an argument
// that is not a RegExp with the global flag (or could be one), and a string literal argument
// RegExp accepts.
fn (mut c Checker) prx_candidate(call C.TSNode, member C.TSNode, argument C.TSNode) ?PrxCandidate {
	if !c.is_static_member_access_of_value(member, ['match']) {
		return none
	}
	object := unwrap_parens(node_field(member, 'object')?)
	value := c.get_static_value(argument)
	if !value.found && !c.prx_definitely_no_global_flag(argument) {
		return none
	}
	if value.found && value.value.kind == .regexp_ && value.value.regexp.flags.contains('g') {
		return none
	}
	mut string_literal := false
	mut regexp := ''
	if node_kind(argument) == 'string' {
		// Literal.value, in UTF-16 units.
		quoted := c.text(argument)
		units := cooked_units(quoted[1..quoted.len - 1], false) or { return none }
		value_regexp := jsregexp.regexp_new(units, '')?
		string_literal = true
		regexp = '/${stv_units_string(value_regexp.source)}/${value_regexp.flags}'
	}
	return PrxCandidate{
		call:           call
		member:         member
		object:         object
		argument:       argument
		string_literal: string_literal
		regexp:         regexp
	}
}

// prx_definitely_no_global_flag ports definitelyDoesNotContainGlobalFlag: `RegExp(…)` or
// `new RegExp(…)` without flags or with static flags without `g`.
fn (mut c Checker) prx_definitely_no_global_flag(n C.TSNode) bool {
	kind := node_kind(n)
	if kind != 'call_expression' && kind != 'new_expression' {
		return false
	}
	callee := unwrap_parens(node_field(n, if kind == 'call_expression' {
		'function'
	} else {
		'constructor'
	}) or { return false })
	if node_kind(callee) != 'identifier' || c.identifier_name(callee) != 'RegExp' {
		return false
	}
	args_node := node_field(n, 'arguments') or { return kind == 'new_expression' }
	if node_kind(args_node) != 'arguments' {
		return false
	}
	args := named_children(args_node)
	if args.len < 2 {
		return true
	}
	flags := c.get_static_value(args[1])
	if !flags.found {
		return false
	}
	return flags.value.kind != .string_ || !stv_units_string(flags.value.units).contains('g')
}
