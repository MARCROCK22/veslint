module rules

import estree
import time
import x.json2

// Port of the `@stylistic/rest-spread-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// option (`"always"` or `"never"`, the default) and its fixes.

const srsp_messages = {
	'unexpectedWhitespace': 'Unexpected whitespace after {{type}} operator.'
	'expectedWhitespace':   'Expected whitespace after {{type}} operator.'
}

struct SrspOptions {
	always_space bool
}

fn srsp_options(given []json2.Any) !SrspOptions {
	options := sty_options(given, [json2.Any('never')])
	return SrspOptions{
		always_space: sty_option_string(options, 0, '') == 'always'
	}
}

fn (mut c Checker) lint_stylistic_rest_spread_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := srsp_options(c.rule_options(stylistic_rest_spread_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) !in [.spread_element, .rest_element] {
			continue
		}
		stats.checked++
		c.srsp_check_white_space(t, tokens, node, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// srsp_check_white_space ports checkWhiteSpace.
fn (c &Checker) srsp_check_white_space(t &estree.EsTree, tokens &SourceTokens, node int, options SrspOptions, mut findings []Finding) {
	operator := un_first_token(t, tokens, node, 0) or { return }
	next_token := tokens.after(operator.end, true) or { return }
	has_whitespace := tokens.is_space_between(operator.end, next_token.start)
	parent := t.nodes[node].parent
	mut typ := ''
	if t.typ(node) == .spread_element {
		typ = 'spread'
		if parent >= 0 && t.typ(parent) == .object_expression {
			typ += ' property'
		}
	} else {
		typ = 'rest'
		if parent >= 0 && t.typ(parent) == .object_pattern {
			typ += ' property'
		}
	}
	if options.always_space && !has_whitespace {
		findings << Finding{
			stmt:       c.position_range(operator.start, operator.end)
			message_id: 'expectedWhitespace'
			data:       {
				'type': typ
			}
			has_fix:    true
			fix:        fix_replace_range(operator.end, next_token.start, ' ')
		}
	} else if !options.always_space && has_whitespace {
		findings << Finding{
			stmt:       c.position_range(operator.end, next_token.start)
			message_id: 'unexpectedWhitespace'
			data:       {
				'type': typ
			}
			has_fix:    true
			fix:        fix_remove_range(operator.end, next_token.start)
		}
	}
}
