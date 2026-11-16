module rules

import estree
import time
import x.json2

// Port of the `@stylistic/space-unary-ops` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`words`, `nonwords` and `overrides`) and its fixes: the spaces after the word operators
// (`typeof`, `void`, `delete`, `new`, `yield`, `await`) and around the other unary and update
// operators and the `!` of non-null assertions.

const ssuo_messages = {
	'unexpectedBefore':    "Unexpected space before unary operator '{{operator}}'."
	'unexpectedAfter':     "Unexpected space after unary operator '{{operator}}'."
	'unexpectedAfterWord': "Unexpected space after unary word operator '{{word}}'."
	'requireAfterWord':    "Unary word operator '{{word}}' must be followed by whitespace."
	'requireAfter':        "Unary operator '{{operator}}' must be followed by whitespace."
	'requireBefore':       "Space is required before unary operator '{{operator}}'."
}

struct SsuoOptions {
	words     bool
	nonwords  bool
	overrides map[string]bool
}

fn ssuo_options(given []json2.Any) !SsuoOptions {
	options := sty_options(given, [
		json2.Any({
			'words':    json2.Any(true)
			'nonwords': json2.Any(false)
		}),
	])
	object := sty_option_object(options, 0)
	mut overrides := map[string]bool{}
	if value := object['overrides'] {
		if value is map[string]json2.Any {
			for key, item in value {
				if item is bool {
					overrides[key] = item
				}
			}
		}
	}
	return SsuoOptions{
		words:     sty_option_bool(object, 'words') or { true }
		nonwords:  sty_option_bool(object, 'nonwords') or { false }
		overrides: overrides
	}
}

fn (mut c Checker) lint_stylistic_space_unary_ops(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := ssuo_options(c.rule_options(stylistic_space_unary_ops))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.unary_expression, .update_expression, .new_expression {
				stats.checked++
				c.ssuo_check_for_spaces(t, tokens, node, options, mut findings)
			}
			.yield_expression {
				stats.checked++
				if t.node(node, .argument) == none || (t.flag(node, .delegate) or { false }) {
					continue
				}
				first := un_first_token(t, tokens, node, 0) or { continue }
				second := un_first_token(t, tokens, node, 1) or { continue }
				c.ssuo_check_word(t, node, first, second, 'yield', options, mut findings)
			}
			.await_expression {
				stats.checked++
				first := un_first_token(t, tokens, node, 0) or { continue }
				second := un_first_token(t, tokens, node, 1) or { continue }
				c.ssuo_check_word(t, node, first, second, 'await', options, mut findings)
			}
			.ts_non_null_expression {
				stats.checked++
				c.ssuo_check_non_null(t, tokens, node, options, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) ssuo_report(t &estree.EsTree, node int, message_id string, key string, value string, fix ?Fix, mut findings []Finding) {
	findings << Finding{
		stmt:       c.position_range(t.nodes[node].start, t.nodes[node].end)
		message_id: message_id
		data:       {
			key: value
		}
		has_fix:    fix != none
		fix:        fix or { Fix{} }
	}
}

// ssuo_check_word ports checkUnaryWordOperatorForSpaces.
fn (c &Checker) ssuo_check_word(t &estree.EsTree, node int, first SourceToken, second SourceToken, word string, options SsuoOptions, mut findings []Finding) {
	should_have_space := options.overrides[word] or { options.words }
	if should_have_space {
		// verifyWordHasSpaces
		if second.start == first.end {
			c.ssuo_report(t, node, 'requireAfterWord', 'word', word, fix_insert_at(first.end, ' '), mut
				findings)
		}
	} else {
		// verifyWordDoesntHaveSpaces
		if c.es_can_tokens_be_adjacent(first, second) && second.start > first.end {
			c.ssuo_report(t, node, 'unexpectedAfterWord', 'word', word, fix_remove_range(first.end,
				second.start), mut findings)
		}
	}
}

// ssuo_is_first_bang_in_bang_bang ports isFirstBangInBangBangExpression.
fn ssuo_is_first_bang_in_bang_bang(t &estree.EsTree, node int) bool {
	if t.typ(node) != .unary_expression {
		return false
	}
	argument := t.node(node, .argument) or { return false }
	return t.typ(argument) == .unary_expression
		&& (t.string_of(argument, .operator) or { '' }) == '!'
}

// ssuo_verify_non_words ports verifyNonWordsHaveSpaces (`spaced`) and
// verifyNonWordsDontHaveSpaces.
fn (c &Checker) ssuo_verify_non_words(t &estree.EsTree, node int, first SourceToken, second SourceToken, spaced bool, mut findings []Finding) {
	prefix := t.flag(node, .prefix) or { false }
	if spaced {
		if prefix {
			if ssuo_is_first_bang_in_bang_bang(t, node) {
				return
			}
			if first.end == second.start {
				c.ssuo_report(t, node, 'requireAfter', 'operator', c.token_text(first),
					fix_insert_at(first.end, ' '), mut findings)
			}
		} else if first.end == second.start {
			c.ssuo_report(t, node, 'requireBefore', 'operator', c.token_text(second),
				fix_insert_at(second.start, ' '), mut findings)
		}
		return
	}
	if second.start <= first.end {
		return
	}
	if prefix {
		fix := if c.es_can_tokens_be_adjacent(first, second) {
			?Fix(fix_remove_range(first.end, second.start))
		} else {
			?Fix(none)
		}
		c.ssuo_report(t, node, 'unexpectedAfter', 'operator', c.token_text(first), fix, mut
			findings)
	} else {
		c.ssuo_report(t, node, 'unexpectedBefore', 'operator', c.token_text(second),
			fix_remove_range(first.end, second.start), mut findings)
	}
}

// ssuo_check_non_null ports checkForSpacesAroundNonNull.
fn (c &Checker) ssuo_check_non_null(t &estree.EsTree, tokens &SourceTokens, node int, options SsuoOptions, mut findings []Finding) {
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	mut index := inside.len - 1
	for index >= 0 && c.token_text(inside[index]) != '!' {
		index--
	}
	if index < 0 {
		return
	}
	operator := inside[index]
	prefix_token := tokens.before(operator.start, false) or { return }
	should_have_space := options.overrides['ts-non-null'] or {
		options.overrides['!'] or { options.nonwords }
	}
	c.ssuo_verify_non_words(t, node, prefix_token, operator, should_have_space, mut findings)
}

// ssuo_check_for_spaces ports checkForSpaces.
fn (c &Checker) ssuo_check_for_spaces(t &estree.EsTree, tokens &SourceTokens, node int, options SsuoOptions, mut findings []Finding) {
	typ := t.typ(node)
	prefix := t.flag(node, .prefix) or { false }
	mut first := SourceToken{}
	mut second := SourceToken{}
	if typ == .update_expression && !prefix {
		// getLastTokens(node, 2)
		second = un_last_token(t, tokens, node) or { return }
		first = tokens.before(second.start, false) or { return }
		if first.start < t.nodes[node].start {
			return
		}
	} else {
		first = un_first_token(t, tokens, node, 0) or { return }
		second = un_first_token(t, tokens, node, 1) or { return }
	}
	if (typ == .new_expression || prefix) && first.kind == .keyword {
		c.ssuo_check_word(t, node, first, second, c.token_text(first), options, mut findings)
		return
	}
	operator := if prefix { c.token_text(first) } else { c.token_text(second) }
	should_have_space := options.overrides[operator] or { options.nonwords }
	c.ssuo_verify_non_words(t, node, first, second, should_have_space, mut findings)
}
