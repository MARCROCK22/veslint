module rules

import estree
import time
import x.json2

// Port of the `@stylistic/computed-property-spacing` rule of @stylistic/eslint-plugin 5.10.0, with
// its options (`"always"` or `"never"`, the default, and `enforceForClassMembers`, true by default)
// and its fixes.

const scpsp_messages = {
	'unexpectedSpaceBefore': "There should be no space before '{{tokenValue}}'."
	'unexpectedSpaceAfter':  "There should be no space after '{{tokenValue}}'."
	'missingSpaceBefore':    "A space is required before '{{tokenValue}}'."
	'missingSpaceAfter':     "A space is required after '{{tokenValue}}'."
}

struct ScpspOptions {
	spaced                    bool
	enforce_for_class_members bool
}

fn scpsp_options(given []json2.Any) !ScpspOptions {
	options := sty_options(given, [json2.Any('never'), json2.Any({
		'enforceForClassMembers': json2.Any(true)
	})])
	return ScpspOptions{
		spaced:                    sty_option_string(options, 0, '') == 'always'
		enforce_for_class_members: sty_option_bool(sty_option_object(options, 1), 'enforceForClassMembers') or {
			false
		}
	}
}

fn (mut c Checker) lint_stylistic_computed_property_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := scpsp_options(c.rule_options(stylistic_computed_property_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		key := match t.typ(node) {
			.property {
				estree.Key.key
			}
			.member_expression {
				estree.Key.property
			}
			.ts_indexed_access_type {
				estree.Key.index_type
			}
			.method_definition, .property_definition, .accessor_property {
				if !options.enforce_for_class_members {
					continue
				}
				estree.Key.key
			}
			else {
				continue
			}
		}
		stats.checked++
		c.scpsp_check(t, tokens, node, key, options.spaced, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// scpsp_check ports the listener checkSpacing(propertyName) returns.
fn (c &Checker) scpsp_check(t &estree.EsTree, tokens &SourceTokens, node int, key estree.Key, spaced bool, mut findings []Finding) {
	if t.typ(node) != .ts_indexed_access_type && !(t.flag(node, .computed) or { false }) {
		return
	}
	property := t.node(node, key) or { return }
	before := c.scpsp_token_before(tokens, t.nodes[property].start, '[') or { return }
	first := tokens.after(before.end, true) or { return }
	after := c.un_token_after_punctuator(tokens, t.nodes[property].end, ']') or { return }
	last := tokens.before(after.start, true) or { return }
	if sty_same_line(t, before, first) {
		if spaced {
			if !tokens.is_space_between(before.end, first.start) {
				findings << c.scpsp_report(before.start, before.end, 'missingSpaceAfter',
					c.token_text(before), fix_insert_at(before.end, ' '))
			}
		} else if tokens.is_space_between(before.end, first.start) {
			findings << c.scpsp_report(before.end, first.start, 'unexpectedSpaceAfter',
				c.token_text(before), fix_remove_range(before.end, first.start))
		}
	}
	if sty_same_line(t, last, after) {
		if spaced {
			if !tokens.is_space_between(last.end, after.start) {
				findings << c.scpsp_report(after.start, after.end, 'missingSpaceBefore',
					c.token_text(after), fix_insert_at(after.start, ' '))
			}
		} else if tokens.is_space_between(last.end, after.start) {
			findings << c.scpsp_report(last.end, after.start, 'unexpectedSpaceBefore',
				c.token_text(after), fix_remove_range(last.end, after.start))
		}
	}
}

// scpsp_token_before ports getTokenBefore(node, isOpeningBracketToken) and the like: the last token
// before `offset` that is that punctuator.
fn (c &Checker) scpsp_token_before(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset) - 1; i >= 0; i-- {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

fn (c &Checker) scpsp_report(start int, end int, message_id string, token_value string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       {
			'tokenValue': token_value
		}
		has_fix:    true
		fix:        fix
	}
}
