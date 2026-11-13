module rules

import estree
import json2
import jsregexp
import time

// Port of the `no-fallthrough` rule of ESLint 10.6.0, on the code path events of the codepath
// module.

const nft_messages = {
	'unusedFallthroughComment': 'Found a comment that would permit fallthrough, but case cannot fall through.'
	'case':                     "Expected a 'break' statement before 'case'."
	'default':                  "Expected a 'break' statement before 'default'."
}

struct NftOptions {
	allow_empty_case                  bool
	comment_pattern                   jsregexp.JsRegex
	report_unused_fallthrough_comment bool
}

fn nft_options(options []json2.Any) !NftOptions {
	o := option_object(no_fallthrough, options, ['commentPattern', 'allowEmptyCase',
		'reportUnusedFallthroughComment'])!
	value := o.values['commentPattern'] or { json2.Any('') }
	pattern := if value is string { value } else { '' }
	return NftOptions{
		allow_empty_case:                  o.bool_value('allowEmptyCase') or { false }
		report_unused_fallthrough_comment: o.bool_value('reportUnusedFallthroughComment') or {
			false
		}
		// DEFAULT_FALLTHROUGH_COMMENT, or `new RegExp(commentPattern, "u")`
		comment_pattern:                   if pattern != '' {
			jsregexp.js_regex_new(pattern, 'u')!
		} else {
			jsregexp.js_regex_new('falls?\\s?through', 'iu')!
		}
	}
}

struct NftPreviousCase {
	node                     int
	is_switch_exit_reachable bool
	is_fallthrough           bool
}

fn (mut c Checker) lint_no_fallthrough(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	opts := nft_options(c.rule_options(no_fallthrough))!
	mut findings := []Finding{}
	an := c.code_path_analysis(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.source_tokens(t.nodes[t.root].ts)
	mut previous := ?NftPreviousCase(none)
	mut code_path_segments := [][]int{}
	mut current := []int{}
	for ev in an.events {
		match ev.kind {
			.code_path_start {
				code_path_segments << current
				current = []int{}
			}
			.code_path_end {
				current = code_path_segments.pop()
			}
			.segment_start, .unreachable_segment_start {
				if ev.segment !in current {
					current << ev.segment
				}
			}
			.segment_end, .unreachable_segment_end {
				k := current.index(ev.segment)
				if k >= 0 {
					current.delete(k)
				}
			}
			.enter_node {
				if t.typ(ev.node) != .switch_case {
					continue
				}
				stats.checked++
				if prev := previous {
					if t.nodes[prev.node].parent == t.nodes[ev.node].parent {
						comment := c.nft_fallthrough_comment(t, tokens, prev.node, ev.node,
							opts.comment_pattern)
						if prev.is_fallthrough && comment == none {
							findings << Finding{
								stmt:       c.position_at(t.nodes[ev.node].start)
								message_id: if t.node(ev.node, .test) != none {
									'case'
								} else {
									'default'
								}
							}
						} else if opts.report_unused_fallthrough_comment
							&& !prev.is_switch_exit_reachable {
							if found := comment {
								findings << Finding{
									stmt:       c.position_at(found.start)
									message_id: 'unusedFallthroughComment'
								}
							}
						}
					}
				}
				previous = none
			}
			.leave_node {
				if t.typ(ev.node) != .switch_case {
					continue
				}
				node := ev.node
				is_switch_exit_reachable := an.is_any_reachable(current)
				consequent := t.list(node, .consequent) or { []int{} }
				cases := t.list(t.nodes[node].parent, .cases) or { []int{} }
				mut blank_lines := false
				if !opts.allow_empty_case && consequent.len == 0 {
					// hasBlankLinesBetween(node, sourceCode.getTokenAfter(node))
					if next := tokens.after(t.nodes[node].end, false) {
						next_line, _ := t.line_column(next.start)
						end_line, _ := t.line_column(t.nodes[node].end)
						blank_lines = next_line > end_line + 1
					}
				}
				previous = NftPreviousCase{
					node:                     node
					is_switch_exit_reachable: is_switch_exit_reachable
					is_fallthrough:           is_switch_exit_reachable
						&& (consequent.len > 0 || blank_lines) && cases.len > 0
						&& cases.last() != node
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nft_fallthrough_comment ports getFallthroughComment: the comment that allows the case to fall
// through, at the end of its only block or right before the next case.
fn (c &Checker) nft_fallthrough_comment(t &estree.EsTree, tokens &SourceTokens, falls int, subsequent int, pattern jsregexp.JsRegex) ?SourceToken {
	consequent := t.list(falls, .consequent) or { []int{} }
	if consequent.len == 1 && t.typ(consequent[0]) == .block_statement {
		// The comments before the trailing `}` of the block.
		comments := tokens.comments_before(t.nodes[consequent[0]].end - 1)
		if comments.len > 0 && c.nft_is_fallthrough_comment(comments.last(), pattern) {
			return comments.last()
		}
	}
	comments := tokens.comments_before(t.nodes[subsequent].start)
	if comments.len > 0 && c.nft_is_fallthrough_comment(comments.last(), pattern) {
		return comments.last()
	}
	return none
}

// nft_is_fallthrough_comment ports isFallThroughComment on the value of the comment.
fn (c &Checker) nft_is_fallthrough_comment(comment SourceToken, pattern jsregexp.JsRegex) bool {
	value := es_comment_value(c.src[comment.start..comment.end])
	return (pattern.test(utf16_units(value)) or { false }) && !nft_is_directive(js_trim(value))
}

// es_comment_value is the `value` of a comment: its text without `//`, or `/*` and `*/`.
fn es_comment_value(text string) string {
	if text.starts_with('/*') {
		return text[2..text.len - 2]
	}
	if text.starts_with('//') {
		return text[2..]
	}
	return text
}

// nft_is_directive ports directivesPattern of ESLint's shared/directives:
// /^(eslint(?:-env|-enable|-disable(?:(?:-next)?-line)?)?|exported|globals?)(?:\s|$)/u.
fn nft_is_directive(text string) bool {
	for word in ['eslint-disable-next-line', 'eslint-disable-line', 'eslint-disable', 'eslint-enable',
		'eslint-env', 'eslint', 'exported', 'globals', 'global'] {
		if text.starts_with(word) {
			rest := text[word.len..]
			if rest == '' || is_js_space(rest.runes()[0]) {
				return true
			}
		}
	}
	return false
}
