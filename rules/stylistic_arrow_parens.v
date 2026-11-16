module rules

import estree
import time
import x.json2

// Port of the `@stylistic/arrow-parens` rule of @stylistic/eslint-plugin 6.0.1, with its options
// (`"always"`, the default, or `"as-needed"` with `requireForBlockBody`) and its fixes: the
// parentheses around the single parameter of an arrow function.

const sap_messages = {
	'unexpectedParens':       'Unexpected parentheses around single function argument.'
	'expectedParens':         'Expected parentheses around arrow function argument.'
	'unexpectedParensInline': 'Unexpected parentheses around single function argument having a body with no curly braces.'
	'expectedParensBlock':    'Expected parentheses around arrow function argument having a body with curly braces.'
}

struct SapOptions {
	as_needed              bool
	require_for_block_body bool
}

fn sap_options(given []json2.Any) !SapOptions {
	options := sty_options(given, [json2.Any('always')])
	as_needed := sty_option_string(options, 0, '') == 'as-needed'
	require := sty_option_bool(sty_option_object(options, 1), 'requireForBlockBody') or { false }
	return SapOptions{
		as_needed:              as_needed
		require_for_block_body: as_needed && require
	}
}

fn (mut c Checker) lint_stylistic_arrow_parens(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sap_options(c.rule_options(stylistic_arrow_parens))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .arrow_function_expression {
			continue
		}
		params := t.list(step.node, .params) or { continue }
		if params.len != 1 {
			continue
		}
		stats.checked++
		c.sap_check(t, tokens, step.node, params[0], options, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sap_check ports the `ArrowFunctionExpression[params.length=1]` listener.
fn (c &Checker) sap_check(t &estree.EsTree, tokens &SourceTokens, node int, param int, options SapOptions, mut findings []Finding) ! {
	has_block_body := if body := t.node(node, .body) {
		t.typ(body) == .block_statement
	} else {
		false
	}
	should_have_parens := !options.as_needed || (options.require_for_block_body && has_block_body)
	// findOpeningParenOfParams.
	mut opening := SourceToken{}
	mut has_parens := false
	if before := tokens.before(t.nodes[param].start, false) {
		if c.token_is(before, '(') && t.nodes[node].start <= before.start {
			opening = before
			has_parens = true
		}
	}
	param_start := t.nodes[param].start
	param_end := t.nodes[param].end
	if should_have_parens && !has_parens {
		has_fix, fix := c.merge_fixes([fix_insert_at(param_start, '('),
			fix_insert_at(param_end, ')')])!
		findings << Finding{
			stmt:       c.position_range(param_start, param_end)
			message_id: if options.require_for_block_body {
				'expectedParensBlock'
			} else {
				'expectedParens'
			}
			has_fix:    has_fix
			fix:        fix
		}
	}
	if should_have_parens || !has_parens || t.typ(param) != .identifier {
		return
	}
	if t.flag(param, .optional) or { false } || t.node(param, .type_annotation) != none
		|| t.node(node, .return_type) != none {
		return
	}
	// getClosingParenOfParams: getTokenAfter(param, isClosingParenToken).
	closing := c.un_token_after_punctuator(tokens, param_end, ')') or { return }
	if tokens.comments_exist_between(opening.end, closing.start) {
		return
	}
	// hasUnexpectedTokensBeforeOpeningParen.
	skip := if t.flag(node, .async) or { false } { 1 } else { 0 }
	first := un_first_token(t, tokens, node, skip) or { return }
	if first.start != opening.start {
		return
	}
	mut fixes := []Fix{}
	if before_opening := tokens.before(opening.start, false) {
		first_of_param := un_first_token(t, tokens, param, 0) or { return }
		if before_opening.end == opening.start
			&& !c.es_can_tokens_be_adjacent(before_opening, first_of_param) {
			fixes << fix_insert_at(opening.start, ' ')
		}
	}
	fixes << fix_remove_range(opening.start, param_start)
	fixes << fix_remove_range(param_end, closing.end)
	has_fix, fix := c.merge_fixes(fixes)!
	findings << Finding{
		stmt:       c.position_range(param_start, param_end)
		message_id: if options.require_for_block_body {
			'unexpectedParensInline'
		} else {
			'unexpectedParens'
		}
		has_fix:    has_fix
		fix:        fix
	}
}
