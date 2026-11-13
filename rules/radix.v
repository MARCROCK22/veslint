module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `radix` rule of ESLint 10.6.0, with its suggestion (its option, "always" or
// "as-needed", changes nothing).

const radix_messages = {
	'missingParameters':   'Missing parameters.'
	'missingRadix':        'Missing radix parameter.'
	'invalidRadix':        'Invalid radix parameter, must be an integer between 2 and 36.'
	'addRadixParameter10': 'Add radix parameter `10` for parsing decimal numbers.'
}

// radix_options checks the option: "always" or "as-needed".
fn radix_options(options []json2.Any) !bool {
	if options.len > 0 && (options[0] !is string || options[0].str() !in ['always', 'as-needed']) {
		return error('the option of `${radix_rule}` must be "always" or "as-needed"')
	}
	return true
}

fn (mut c Checker) lint_radix(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	radix_options(c.rule_options(radix_rule))!
	mut findings := []Finding{}
	tree := c.scope_tree(root)
	// getVariableByName from the global scope: `parseInt` and `Number` not declared there.
	parse_int := tree.find_variable(0, 'parseInt', -1)
	if parse_int >= 0 && tree.variables[parse_int].defs.len == 0 {
		for r in tree.variables[parse_int].references {
			id := tree.references[r].identifier
			stats.checked++
			if call := es_callee_of(id) {
				if node_kind(call) == 'call_expression' {
					c.radix_check(root, call, mut findings)!
				}
			}
		}
	}
	number := tree.find_variable(0, 'Number', -1)
	if number >= 0 && tree.variables[number].defs.len == 0 {
		for r in tree.variables[number].references {
			id := tree.references[r].identifier
			stats.checked++
			member := cti_estree_parent(id) or { continue }
			if node_kind(member) != 'member_expression' {
				continue
			}
			property := node_field(member, 'property') or { continue }
			if node_kind(property) != 'property_identifier' || c.text(property) != 'parseInt' {
				continue
			}
			if call := es_callee_of(member) {
				if node_kind(call) == 'call_expression' {
					c.radix_check(root, call, mut findings)!
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) radix_check(root C.TSNode, call C.TSNode, mut findings []Finding) ! {
	args := (call_arguments(call) or { return }).filter(node_kind(it) != 'comment')
	match args.len {
		0 {
			findings << Finding{
				stmt:       position_of(call)
				message_id: 'missingParameters'
			}
		}
		1 {
			tokens := c.source_tokens(root)
			last := tokens.before(c.es_end(call), false) or { return }
			second := tokens.before(last.start, false) or { return }
			trailing := second.kind == .punctuator && c.src[second.start..second.end] == ','
			_, suggestion := c.suggestion('addRadixParameter10', map[string]string{}, [
				fix_insert_at(last.start, if trailing { ' 10,' } else { ', 10' }),
			])!
			findings << Finding{
				stmt:        position_of(call)
				message_id:  'missingRadix'
				suggestions: [suggestion]
			}
		}
		else {
			radix_arg := unwrap_parens(args[1])
			mut invalid := false
			if es_is_literal(radix_arg) {
				invalid = true
				if node_kind(radix_arg) == 'number' && !c.text(radix_arg).ends_with('n') {
					value := number_literal_value(c.text(radix_arg)) or { 0 }
					invalid = !(value >= 2 && value <= 36 && value == f64(i64(value)))
				}
			} else if node_kind(radix_arg) in ['identifier', 'undefined']
				&& c.identifier_name(radix_arg) == 'undefined' {
				invalid = c.es_is_global_reference(root, radix_arg)
			}
			if invalid {
				findings << Finding{
					stmt:       position_of(call)
					message_id: 'invalidRadix'
				}
			}
		}
	}
}
