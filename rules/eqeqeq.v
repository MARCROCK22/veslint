module rules

import json2
import time
import treesitter { node_field, node_kind }

// Port of the `eqeqeq` rule of ESLint 10.6.0, with its options, its fix and its suggestion.

const eqe_messages = {
	'unexpected':      "Expected '{{expectedOperator}}' and instead saw '{{actualOperator}}'."
	'replaceOperator': "Use '{{expectedOperator}}' instead of '{{actualOperator}}'."
}

struct EqeOptions {
	config string // always, smart or allow-null
	null   string // always, never or ignore
}

// eqe_options reads "always" (with `null`), "smart" or "allow-null".
fn eqe_options(options []json2.Any) !EqeOptions {
	config := if options.len > 0 { options[0] } else { json2.Any('always') }
	if config !is string || config.str() !in ['always', 'smart', 'allow-null'] {
		return error('the first option of `${eqeqeq}` must be "always", "smart" or "allow-null"')
	}
	o := option_object(eqeqeq, if options.len > 1 { options[1..] } else { []json2.Any{} },
		['null'])!
	null_value := o.values['null'] or { json2.Any('always') }
	return EqeOptions{
		config: config.str()
		null:   if config.str() == 'always' { null_value.str() } else { 'ignore' }
	}
}

fn (mut c Checker) lint_eqeqeq(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := eqe_options(c.rule_options(eqeqeq))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		stats.checked++
		left := unwrap_parens(node_field(node, 'left') or { continue })
		right := unwrap_parens(node_field(node, 'right') or { continue })
		operator := operator_of(node)
		is_null := node_kind(left) == 'null' || node_kind(right) == 'null'
		if operator !in ['==', '!='] {
			if o.null == 'never' && is_null {
				c.eqe_report(root, node, left, right, operator, operator[..operator.len - 1], mut
					findings)!
			}
			continue
		}
		if o.config == 'smart' && (c.eqe_typeof_binary(left, right)
			|| c.eqe_same_type_literals(left, right) || is_null) {
			continue
		}
		if o.null != 'always' && is_null {
			continue
		}
		c.eqe_report(root, node, left, right, operator, '${operator}=', mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) eqe_typeof_binary(left C.TSNode, right C.TSNode) bool {
	return (node_kind(left) == 'unary_expression' && operator_of(left) == 'typeof')
		|| (node_kind(right) == 'unary_expression' && operator_of(right) == 'typeof')
}

// eqe_literal_type is `typeof value` of a Literal.
fn (c &Checker) eqe_literal_type(n C.TSNode) string {
	return match node_kind(n) {
		'string' { 'string' }
		'number' {
			if c.text(n).ends_with('n') { 'bigint' } else { 'number' }
		}
		'true', 'false' { 'boolean' }
		'null', 'regex' { 'object' }
		else { '' }
	}
}

fn (c &Checker) eqe_same_type_literals(left C.TSNode, right C.TSNode) bool {
	a := c.eqe_literal_type(left)
	return a != '' && a == c.eqe_literal_type(right)
}

// eqe_report reports at the operator, with a fix when both sides have the same type and a
// suggestion otherwise.
fn (mut c Checker) eqe_report(root C.TSNode, node C.TSNode, left C.TSNode, right C.TSNode, operator string, expected string, mut findings []Finding) ! {
	tokens := c.source_tokens(root)
	mut token := tokens.after(c.es_end(left), false) or { return }
	for c.src[token.start..token.end] != operator {
		token = tokens.after(token.end, false) or { return }
	}
	data := {
		'expectedOperator': expected
		'actualOperator':   operator
	}
	fix := fix_replace_range(token.start, token.end, expected)
	if c.eqe_typeof_binary(left, right) || c.eqe_same_type_literals(left, right) {
		findings << Finding{
			stmt:       c.position_range(token.start, token.end)
			message_id: 'unexpected'
			data:       data
			has_fix:    true
			fix:        fix
		}
		return
	}
	_, suggestion := c.suggestion('replaceOperator', data, [fix])!
	findings << Finding{
		stmt:        c.position_range(token.start, token.end)
		message_id:  'unexpected'
		data:        data
		suggestions: [suggestion]
	}
}
