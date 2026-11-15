module rules

import estree
import time
import x.json2

// Port of the `@stylistic/lines-between-class-members` rule of @stylistic/eslint-plugin 5.10.0,
// with its options (`"always"`, the default, `"never"` or `{ enforce: [...] }`, and
// `exceptAfterSingleLine` and `exceptAfterOverload`) and its fixes.

const slbcm_messages = {
	'never':  'Unexpected blank line between class members.'
	'always': 'Expected blank line between class members.'
}

struct SlbcmConfigure {
	blank_line string
	prev       string
	next       string
}

struct SlbcmOptions {
	configure_list           []SlbcmConfigure
	except_after_single_line bool
	except_after_overload    bool
}

fn slbcm_options(given []json2.Any) !SlbcmOptions {
	options := sty_options(given, decoded_default_options(stylistic_lines_between_class_members))
	first := if options.len > 0 { options[0] } else { json2.Any('always') }
	mut configure_list := []SlbcmConfigure{}
	mut first_is_string := false
	if first is map[string]json2.Any {
		enforce := first['enforce'] or { json2.Any([]json2.Any{}) }
		if enforce is []json2.Any {
			for item in enforce {
				if item is map[string]json2.Any {
					configure_list << SlbcmConfigure{
						blank_line: sty_option_string([item['blankLine'] or { json2.Any('') }],
							0, '')
						prev:       sty_option_string([item['prev'] or { json2.Any('') }], 0, '')
						next:       sty_option_string([item['next'] or { json2.Any('') }], 0, '')
					}
				}
			}
		}
	} else {
		first_is_string = true
		configure_list << SlbcmConfigure{
			blank_line: sty_option_string(options, 0, '')
			prev:       '*'
			next:       '*'
		}
	}
	second := sty_option_object(options, 1)
	except_after_overload := (sty_option_bool(second, 'exceptAfterOverload') or { false })
		&& ((first_is_string && sty_option_string(options, 0, '') == 'always')
			|| (!first_is_string && configure_list.any(it.blank_line == 'always' && it.prev != 'field'
				&& it.next != 'field')))
	return SlbcmOptions{
		configure_list:           configure_list
		except_after_single_line: sty_option_bool(second, 'exceptAfterSingleLine') or { false }
		except_after_overload:    except_after_overload
	}
}

fn (mut c Checker) lint_stylistic_lines_between_class_members(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := slbcm_options(c.rule_options(stylistic_lines_between_class_members))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .class_body {
			continue
		}
		stats.checked++
		c.slbcm_check(t, tokens, step.node, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// slbcm_match ports match: whether the class member is of the type (`*`, `field` or `method`).
fn slbcm_match(t &estree.EsTree, node int, typ string) bool {
	return match typ {
		'*' { true }
		'field' { t.typ(node) == .property_definition }
		'method' { t.typ(node) == .method_definition }
		else { false }
	}
}

fn slbcm_is_overload(t &estree.EsTree, node int) bool {
	if t.typ(node) !in [.ts_abstract_method_definition, .method_definition] {
		return false
	}
	value := t.node(node, .value) or { return false }
	return t.typ(value) == .ts_empty_body_function_expression
}

fn slbcm_line_start(t &estree.EsTree, offset int) int {
	line, _ := t.line_column(offset)
	return line
}

// slbcm_last_consecutive_after ports findLastConsecutiveTokenAfter.
fn slbcm_last_consecutive_after(t &estree.EsTree, tokens &SourceTokens, prev_last SourceToken, next_first SourceToken, max_line int) SourceToken {
	mut current := prev_last
	for {
		after := tokens.after(current.end, true) or { return current }
		if after.start != next_first.start
			&& slbcm_line_start(t, after.start) - slbcm_line_start(t, current.end) <= max_line {
			current = after
			continue
		}
		return current
	}
	return current
}

// slbcm_first_consecutive_before ports findFirstConsecutiveTokenBefore.
fn slbcm_first_consecutive_before(t &estree.EsTree, tokens &SourceTokens, next_first SourceToken, prev_last SourceToken, max_line int) SourceToken {
	mut current := next_first
	for {
		before := tokens.before(current.start, true) or { return current }
		if before.start != prev_last.start
			&& slbcm_line_start(t, current.start) - slbcm_line_start(t, before.end) <= max_line {
			current = before
			continue
		}
		return current
	}
	return current
}

fn (c &Checker) slbcm_check(t &estree.EsTree, tokens &SourceTokens, class_body int, options SlbcmOptions, mut findings []Finding) {
	all_members := t.list(class_body, .body) or { return }
	body := if options.except_after_overload {
		all_members.filter(!slbcm_is_overload(t, it))
	} else {
		all_members
	}
	for i := 0; i < body.len - 1; i++ {
		cur_first := un_first_token(t, tokens, body[i], 0) or { continue }
		// getBoundaryTokens
		last_token := un_last_token(t, tokens, body[i]) or { continue }
		prev_token := tokens.before(last_token.start, false) or { continue }
		next_token := un_first_token(t, tokens, body[i + 1], 0) or { continue }
		semicolon_less_style := c.token_is(last_token, ';')
			&& !sty_same_line(t, prev_token, last_token) && sty_same_line(t, last_token, next_token)
		cur_last := if semicolon_less_style { prev_token } else { last_token }
		next_first := if semicolon_less_style { last_token } else { next_token }

		is_multi := !sty_same_line(t, cur_first, cur_last)
		skip := !is_multi && options.except_after_single_line
		before_padding := slbcm_last_consecutive_after(t, tokens, cur_last, next_first, 1)
		after_padding := slbcm_first_consecutive_before(t, tokens, next_first, cur_last, 1)
		is_padded := slbcm_line_start(t, after_padding.start) - slbcm_line_start(t, before_padding.end) > 1
		has_token_in_padding := tokens.inside(before_padding.end, after_padding.start, true).len != 0
		cur_line_last_token := slbcm_last_consecutive_after(t, tokens, cur_last, next_first,
			0)
		// getPaddingType: the last matching configuration.
		mut padding_type := ''
		for k := options.configure_list.len - 1; k >= 0; k-- {
			configure := options.configure_list[k]
			if slbcm_match(t, body[i], configure.prev) && slbcm_match(t, body[i + 1], configure.next) {
				padding_type = configure.blank_line
				break
			}
		}
		next := body[i + 1]
		if padding_type == 'never' && is_padded {
			findings << Finding{
				stmt:       c.position_range(t.nodes[next].start, t.nodes[next].end)
				message_id: 'never'
				has_fix:    !has_token_in_padding
				fix:        fix_replace_range(before_padding.end, after_padding.start, '\n')
			}
		} else if padding_type == 'always' && !skip && !is_padded {
			findings << Finding{
				stmt:       c.position_range(t.nodes[next].start, t.nodes[next].end)
				message_id: 'always'
				has_fix:    !has_token_in_padding
				fix:        fix_insert_at(cur_line_last_token.end, '\n')
			}
		}
	}
}
