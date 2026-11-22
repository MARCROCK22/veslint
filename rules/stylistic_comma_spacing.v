module rules

import estree
import treesitter { node_kind }
import time
import x.json2

// Port of the `@stylistic/comma-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its options
// (`before`, false by default, and `after`, true by default) and its fixes.

const scmsp_messages = {
	'unexpected': "There should be no space {{loc}} ','."
	'missing':    "A space is required {{loc}} ','."
}

struct ScmspOptions {
	space_before bool
	space_after  bool
}

fn scmsp_options(given []json2.Any) !ScmspOptions {
	options := sty_options(given, [
		json2.Any({
			'before': json2.Any(false)
			'after':  json2.Any(true)
		}),
	])
	object := sty_option_object(options, 0)
	return ScmspOptions{
		space_before: sty_option_bool(object, 'before') or { false }
		space_after:  sty_option_bool(object, 'after') or { false }
	}
}

fn (mut c Checker) lint_stylistic_comma_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := scmsp_options(c.rule_options(stylistic_comma_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// The starts of the commas whose space before (ignoredBeforeTokens) or after
	// (ignoredAfterTokens) is not checked.
	mut ignored_before := map[int]bool{}
	mut ignored_after := map[int]bool{}
	for node in 0 .. t.nodes.len {
		if !t.visits(node) {
			continue
		}
		match t.typ(node) {
			.array_expression, .array_pattern {
				c.scmsp_ignore_null_elements(t, tokens, node, mut ignored_before, mut ignored_after)
			}
			.ts_type_parameter_declaration {
				// addTypeParametersTrailingCommaToIgnoreList
				params := t.list(node, .params) or { []int{} }
				if params.len > 0 {
					if after := tokens.after(t.nodes[params.last()].end, false) {
						if c.token_is(after, ',') {
							ignored_before[after.start] = true
							ignored_after[after.start] = true
						}
					}
				}
			}
			else {}
		}
	}
	// Program:exit
	all := tokens.all
	for i, token in all {
		if !c.scmsp_is_comma(token) {
			continue
		}
		stats.checked++
		prev := if i > 0 && !c.scmsp_is_comma(all[i - 1]) && token.start !in ignored_before {
			?SourceToken(all[i - 1])
		} else {
			none
		}
		next := if i + 1 < all.len && !c.scmsp_is_comma(all[i + 1]) && token.start !in ignored_after {
			?SourceToken(all[i + 1])
		} else {
			none
		}
		c.scmsp_validate(t, tokens, token, prev, next, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// scmsp_is_comma ports isCommaToken: a `,` punctuator, not the text of a JSX element.
fn (c &Checker) scmsp_is_comma(token SourceToken) bool {
	return c.token_is(token, ',') && node_kind(token.node) != 'jsx_text'
}

// scmsp_ignore_null_elements ports addNullElementsToIgnoreList: the comma after a hole is not
// checked before, nor after when the next element is a hole too (or there is none).
fn (c &Checker) scmsp_ignore_null_elements(t &estree.EsTree, tokens &SourceTokens, node int, mut ignored_before map[int]bool, mut ignored_after map[int]bool) {
	mut previous := un_first_token(t, tokens, node, 0) or { return }
	mut has_previous := true
	elements := t.list(node, .elements) or { []int{} }
	for i, element in elements {
		mut token := SourceToken{}
		mut found := false
		if element < 0 {
			if has_previous {
				if after := tokens.after(previous.end, false) {
					token = after
					found = true
					if c.token_is(after, ',') {
						ignored_before[after.start] = true
						if i + 1 >= elements.len || elements[i + 1] < 0 {
							ignored_after[after.start] = true
						}
					}
				}
			}
		} else if after := tokens.after(t.nodes[element].end, false) {
			token = after
			found = true
		}
		previous = token
		has_previous = found
	}
}

// scmsp_validate ports validateCommaSpacing.
fn (c &Checker) scmsp_validate(t &estree.EsTree, tokens &SourceTokens, comma SourceToken, prev ?SourceToken, next ?SourceToken, options ScmspOptions, mut findings []Finding) {
	if p := prev {
		if sty_same_line(t, p, comma)
			&& options.space_before != tokens.is_space_between(p.end, comma.start) {
			findings << c.scmsp_report(comma, 'before', if options.space_before {
				'missing'
			} else {
				'unexpected'
			}, if options.space_before {
				fix_insert_at(comma.start, ' ')
			} else {
				fix_replace_range(p.end, comma.start, '')
			})
		}
	}
	if n := next {
		if sty_same_line(t, comma, n) && !c.token_is(n, ')') && !c.token_is(n, ']')
			&& !c.token_is(n, '}') && !(!options.space_after && n.kind == .line_comment)
			&& options.space_after != tokens.is_space_between(comma.end, n.start) {
			findings << c.scmsp_report(comma, 'after', if options.space_after {
				'missing'
			} else {
				'unexpected'
			}, if options.space_after {
				fix_insert_at(comma.end, ' ')
			} else {
				fix_replace_range(comma.end, n.start, '')
			})
		}
	}
}

fn (c &Checker) scmsp_report(comma SourceToken, location string, message_id string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(comma.start, comma.end)
		message_id: message_id
		data:       {
			'loc': location
		}
		has_fix:    true
		fix:        fix
	}
}
