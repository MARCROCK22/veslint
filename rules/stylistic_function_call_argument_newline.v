module rules

import estree
import time
import x.json2

// Port of the `@stylistic/function-call-argument-newline` rule of @stylistic/eslint-plugin 6.0.1,
// with its option (`"always"`, the default, `"never"` or `"consistent"`) and its fixes.

const sfcan_messages = {
	'unexpectedLineBreak': 'There should be no line break here.'
	'missingLineBreak':    'There should be a line break after this argument.'
}

fn sfcan_options(given []json2.Any) !string {
	options := sty_options(given, [json2.Any('always')])
	return sty_option_string(options, 0, 'always')
}

fn (mut c Checker) lint_stylistic_function_call_argument_newline(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	option := sfcan_options(c.rule_options(stylistic_function_call_argument_newline))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.call_expression, .new_expression {
				stats.checked++
				c.sfcan_check(t, tokens, t.list(node, .arguments) or { []int{} }, option, mut
					findings)
			}
			.import_expression {
				options := t.node(node, .options) or { continue }
				source := t.node(node, .source) or { continue }
				stats.checked++
				c.sfcan_check(t, tokens, [source, options], option, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sfcan_check ports check.
fn (c &Checker) sfcan_check(t &estree.EsTree, tokens &SourceTokens, arguments []int, option string, mut findings []Finding) {
	if arguments.len < 2 {
		return
	}
	match option {
		'never' {
			c.sfcan_check_arguments(t, tokens, arguments, false, mut findings)
		}
		'always' {
			c.sfcan_check_arguments(t, tokens, arguments, true, mut findings)
		}
		'consistent' {
			first := un_last_token(t, tokens, arguments[0]) or { return }
			second := un_first_token(t, tokens, arguments[1], 0) or { return }
			c.sfcan_check_arguments(t, tokens, arguments, !sty_same_line(t, first, second), mut
				findings)
		}
		else {}
	}
}

// sfcan_check_arguments ports checkArguments, with the checker `missing` (a line break is
// required) or `unexpected`.
fn (c &Checker) sfcan_check_arguments(t &estree.EsTree, tokens &SourceTokens, arguments []int, missing bool, mut findings []Finding) {
	for i := 1; i < arguments.len; i++ {
		previous := un_last_token(t, tokens, arguments[i - 1]) or { continue }
		current := un_first_token(t, tokens, arguments[i], 0) or { continue }
		if sty_same_line(t, previous, current) != missing {
			continue
		}
		before := tokens.before(current.start, true) or { continue }
		has_line_comment_before := before.kind == .line_comment
		findings << Finding{
			stmt:       c.position_range(before.end, current.start)
			message_id: if missing { 'missingLineBreak' } else { 'unexpectedLineBreak' }
			has_fix:    !has_line_comment_before
			fix:        fix_replace_range(before.end, current.start, if missing {
				'\n'
			} else {
				' '
			})
		}
	}
}
