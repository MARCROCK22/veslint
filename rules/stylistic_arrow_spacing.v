module rules

import estree
import time
import x.json2

// Port of the `@stylistic/arrow-spacing` rule of @stylistic/eslint-plugin 5.10.0, with its options
// (`before` and `after`, true by default) and its fixes.

const sarws_messages = {
	'expectedBefore':   'Missing space before =>.'
	'unexpectedBefore': 'Unexpected space before =>.'
	'expectedAfter':    'Missing space after =>.'
	'unexpectedAfter':  'Unexpected space after =>.'
}

struct SarwsOptions {
	before bool
	after  bool
}

fn sarws_options(given []json2.Any) !SarwsOptions {
	options := sty_options(given, [
		json2.Any({
			'before': json2.Any(true)
			'after':  json2.Any(true)
		}),
	])
	object := sty_option_object(options, 0)
	return SarwsOptions{
		before: sty_option_bool(object, 'before') or { false }
		after:  sty_option_bool(object, 'after') or { false }
	}
}

fn (mut c Checker) lint_stylistic_arrow_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sarws_options(c.rule_options(stylistic_arrow_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if t.typ(node) !in [.arrow_function_expression, .ts_function_type, .ts_constructor_type] {
			continue
		}
		stats.checked++
		c.sarws_spaces(t, tokens, node, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sarws_arrow ports getArrow: the `=>` before the body of an arrow function, the first one of the
// return type of a function or constructor type.
fn (c &Checker) sarws_arrow(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	if t.typ(node) == .arrow_function_expression {
		body := t.node(node, .body)?
		for i := source_tokens_index(tokens.tokens, t.nodes[body].start) - 1; i >= 0; i-- {
			if c.token_is(tokens.tokens[i], '=>') {
				return tokens.tokens[i]
			}
		}
		return none
	}
	return_type := t.node(node, .return_type)?
	for token in tokens.inside(t.nodes[return_type].start, t.nodes[return_type].end, false) {
		if c.token_is(token, '=>') {
			return token
		}
	}
	return none
}

// sarws_spaces ports spaces.
fn (c &Checker) sarws_spaces(t &estree.EsTree, tokens &SourceTokens, node int, options SarwsOptions, mut findings []Finding) {
	arrow := c.sarws_arrow(t, tokens, node) or { return }
	if before := tokens.before(arrow.start, true) {
		spaced := tokens.is_space_between(before.end, arrow.start)
		if options.before && !spaced {
			findings << Finding{
				stmt:       c.position_range(before.start, before.end)
				message_id: 'expectedBefore'
				has_fix:    true
				fix:        fix_insert_at(arrow.start, ' ')
			}
		} else if !options.before && spaced {
			findings << Finding{
				stmt:       c.position_range(before.start, before.end)
				message_id: 'unexpectedBefore'
				has_fix:    true
				fix:        fix_remove_range(before.end, arrow.start)
			}
		}
	}
	if after := tokens.after(arrow.end, true) {
		spaced := tokens.is_space_between(arrow.end, after.start)
		if options.after && !spaced {
			findings << Finding{
				stmt:       c.position_range(after.start, after.end)
				message_id: 'expectedAfter'
				has_fix:    true
				fix:        fix_insert_at(arrow.end, ' ')
			}
		} else if !options.after && spaced {
			findings << Finding{
				stmt:       c.position_range(after.start, after.end)
				message_id: 'unexpectedAfter'
				has_fix:    true
				fix:        fix_remove_range(arrow.end, after.start)
			}
		}
	}
}
