module rules

import estree
import json2
import time

// Port of the `unicorn/prefer-single-call` rule of eslint-plugin-unicorn 79.0.0, with its option
// `ignore`, its fix and its suggestion.

const upsg_messages = {
	'error/array-push': 'Do not call `{{description}}` multiple times.'
	'suggestion':       'Merge with previous one.'
}

fn upsg_options(options []json2.Any) ![]string {
	o := option_object(unicorn_prefer_single_call, options, ['ignore'])!
	return o.string_list('ignore')!
}

// UpsgCase is one of the calls the rule merges.
struct UpsgCase {
	description          string
	ignore               []string
	keep_second_call     bool
	check_array_receiver bool
}

const upsg_cases = [
	UpsgCase{
		description:          'Array#push()'
		check_array_receiver: true
		ignore:               ['stream.push', 'this.push', 'this.stream.push', 'process.stdin.push',
			'process.stdout.push', 'process.stderr.push']
	},
	UpsgCase{
		description:          'Array#unshift()'
		check_array_receiver: true
		keep_second_call:     true
		ignore:               ['stream.unshift', 'this.unshift', 'this.stream.unshift',
			'process.stdin.unshift', 'process.stdout.unshift', 'process.stderr.unshift']
	},
	UpsgCase{
		description: 'Element#classList.add()'
	},
	UpsgCase{
		description: 'Element#classList.remove()'
	},
	UpsgCase{
		description: 'importScripts()'
	},
]

// upsg_test is the `test` of each case.
fn upsg_test(t &estree.EsTree, index int, call int) bool {
	return match index {
		0 {
			un_is_method_call(t, call, methods: ['push'], optional_call: false)
		}
		1 {
			un_is_method_call(t, call, methods: ['unshift'], optional_call: false)
		}
		2, 3 {
			un_is_method_call(t, call,
				methods:         [if index == 2 { 'add' } else { 'remove' }]
				optional_call:   false
				optional_member: false
			) && un_is_member(t, t.node(t.node(call, .callee) or { -1 }, .object) or { -1 }, UnMember{
				properties: ['classList']
				computed:   false
			})
		}
		else {
			un_is_call(t, call, names: ['importScripts'])
		}
	}
}

fn (mut c Checker) lint_unicorn_prefer_single_call(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignored_in_options := upsg_options(c.rule_options(unicorn_prefer_single_call))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for second in 0 .. t.nodes.len {
		if t.typ(second) != .call_expression {
			continue
		}
		stats.checked++
		for index, case in upsg_cases {
			if !upsg_test(t, index, second) {
				continue
			}
			mut ignored := case.ignore.clone()
			ignored << ignored_in_options
			if f := c.upsg_problem(mut ctx, index, case, ignored, second) {
				findings << f
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upsg_expression_statement ports getExpressionStatement.
fn upsg_expression_statement(t &estree.EsTree, call int) int {
	mut statement := t.nodes[call].parent
	if statement >= 0 && t.typ(statement) == .chain_expression
		&& (t.node(statement, .expression) or { -1 }) == call {
		statement = t.nodes[statement].parent
	}
	return if statement >= 0 && t.typ(statement) == .expression_statement { statement } else { -1 }
}

// upsg_problem finds the mergeable previous call (getMergeableFirstCall) and makes the problem.
fn (mut c Checker) upsg_problem(mut ctx UnCtx, index int, case UpsgCase, ignored []string, second int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	callee := t.node(second, .callee)?
	if un_is_node_matches(t, callee, ignored) {
		return none
	}
	second_statement := upsg_expression_statement(t, second)
	if second_statement < 0 {
		return none
	}
	first_statement := unb_sibling(t, second_statement, -1)
	if first_statement < 0 || t.typ(first_statement) != .expression_statement {
		return none
	}
	mut first := t.node(first_statement, .expression)?
	if t.typ(first) == .chain_expression {
		first = t.node(first, .expression)?
	}
	if !upsg_test(t, index, first) || !c.un_is_same_reference(t, t.node(first, .callee)?, callee) {
		return none
	}
	if case.check_array_receiver
		&& c.un_should_skip_known_non_array_receiver(mut ctx, t.node(callee, .object)?) {
		return none
	}
	// getMergePlan
	keep_second := case.keep_second_call && (!un_has_optional_chain_element(t, callee)
		|| un_has_optional_chain_element(t, t.node(first, .callee)?))
	prepend_source := case.keep_second_call && !keep_second
	target := if keep_second { second } else { first }
	source := if keep_second { first } else { second }
	first_start, first_end := t.nodes[first_statement].start, t.nodes[first_statement].end
	second_start, second_end := t.nodes[second_statement].start, t.nodes[second_statement].end
	removal := if keep_second {
		UnRange{first_start, second_start}
	} else {
		UnRange{first_end, second_end}
	}
	first_last := un_last_token(t, tokens, first_statement)?
	second_last := un_last_token(t, tokens, second_statement)?
	keep_semicolon := !keep_second && !c.token_is(first_last, ';') && c.token_is(second_last, ';')
	add_semicolon := keep_second
		&& c.un_needs_semicolon(t, tokens, tokens.before(first_start, false), c.src[second_start..second_start + 1])
	report := if t.typ(callee) == .identifier { callee } else { t.node(callee, .property)? }
	mut finding := Finding{
		stmt:       c.es_tree_position(t, report)
		message_id: 'error/array-push'
		data:       {
			'description': case.description
		}
	}
	if un_has_comment_in_range(tokens, removal.start, removal.end) {
		return finding
	}
	mut fixes := []Fix{}
	source_arguments := t.list(source, .arguments) or { []int{} }
	if source_arguments.len > 0 {
		text := c.unb_call_arguments_text(t, tokens, source, !prepend_source)?
		call_tokens := c.un_call_tokens(t, tokens, target)?
		target_arguments := t.list(target, .arguments) or { []int{} }
		if prepend_source {
			fixes << fix_insert_at(call_tokens.opening.end, if target_arguments.len > 0 {
				'${text}, '
			} else {
				text
			})
		} else if trailing := call_tokens.trailing {
			fixes << fix_insert_at(trailing.end, ' ${text}')
		} else {
			fixes << fix_insert_at(call_tokens.closing.start, if target_arguments.len > 0 {
				', ${text}'
			} else {
				text
			})
		}
	}
	fixes << fix_replace_range(removal.start, removal.end, if keep_semicolon || add_semicolon {
		';'
	} else {
		''
	})
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	if !has_fix {
		return finding
	}
	if (case.check_array_receiver && !c.un_is_array(mut ctx, t.node(callee, .object)?))
		|| c.upsg_should_use_suggestion(mut ctx, first, second, case.check_array_receiver) {
		return Finding{
			...finding
			suggestions: [Suggestion{
				message_id: 'suggestion'
				fix:        fix
			}]
		}
	}
	return Finding{
		...finding
		has_fix: true
		fix:     fix
	}
}

// upsg_should_use_suggestion ports shouldUseSuggestionForMerge: merging evaluates the second
// call's arguments before the first mutation.
fn (mut c Checker) upsg_should_use_suggestion(mut ctx UnCtx, first int, second int, check_array_receiver bool) bool {
	t := ctx.t
	if check_array_receiver {
		mut arguments := t.list(first, .arguments) or { []int{} }
		arguments << t.list(second, .arguments) or { []int{} }
		for argument in arguments {
			if c.un_static_value_if_no_side_effects(mut ctx, argument) == none {
				return true
			}
		}
		return false
	}
	return (t.list(second, .arguments) or { []int{} }).any(un_has_side_effect(t, it, UnSideEffect{}))
}
