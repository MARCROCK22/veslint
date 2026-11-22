module rules

import codepath
import estree
import json2
import jsregexp
import time
import treesitter { node_kind, node_parent, node_start }

// Port of the `no-fallthrough` rule of ESLint 10.15.0, on the code path events of the codepath
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
	pattern, flags := nft_comment_pattern(options)!
	return nft_options_with(options, jsregexp.js_regex_new(pattern, flags)!)!
}

// nft_lint_options are nft_options with the comment pattern compiled once per Checker.
fn (mut c Checker) nft_lint_options(options []json2.Any) !NftOptions {
	pattern, flags := nft_comment_pattern(options)!
	return nft_options_with(options, c.cached_js_regex(pattern, flags)!)!
}

fn nft_options_with(options []json2.Any, comment_pattern jsregexp.JsRegex) !NftOptions {
	o := option_object(no_fallthrough, options, ['commentPattern', 'allowEmptyCase',
		'reportUnusedFallthroughComment'])!
	return NftOptions{
		allow_empty_case:                  o.bool_value('allowEmptyCase') or { false }
		report_unused_fallthrough_comment: o.bool_value('reportUnusedFallthroughComment') or {
			false
		}
		comment_pattern:                   comment_pattern
	}
}

// nft_comment_pattern is the source and the flags of the comment pattern: DEFAULT_FALLTHROUGH_COMMENT,
// or `new RegExp(commentPattern, "u")`.
fn nft_comment_pattern(options []json2.Any) !(string, string) {
	o := option_object(no_fallthrough, options, ['commentPattern', 'allowEmptyCase',
		'reportUnusedFallthroughComment'])!
	value := o.values['commentPattern'] or { json2.Any('') }
	pattern := if value is string { value } else { '' }
	if pattern != '' {
		return pattern, 'u'
	}
	return 'falls?\\s?through', 'iu'
}

struct NftPreviousCase {
	node                     int
	is_switch_exit_reachable bool
	is_fallthrough           bool
}

fn (mut c Checker) lint_no_fallthrough(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	opts := c.nft_lint_options(c.rule_options(no_fallthrough))!
	mut findings := []Finding{}
	// Only the SwitchCase nodes matter: a TypeScript file without a `switch` needs neither its
	// ESTree nor its code paths (built on first use, they were a fifth of a lint without types).
	// The template of a .vue or .svelte file is not in this tree.
	mut partial := false
	mut partial_tree := estree.EsTree{}
	mut partial_paths := codepath.Analysis{}
	if !c.is_vue() && !c.is_svelte() {
		switches := c.nodes_of_kind(root, c'switch_statement')
		if switches.len == 0 {
			stats.eval_ms += ms(sw.elapsed())
			return findings
		}
		// What the rule sees of a `switch` happens in the code path of the function around it,
		// which starts afresh at the function: the functions with a `switch` are enough, unless
		// one is outside every function or the whole file's tree is built already (another rule
		// asked for it).
		if c.file_es_state == .unknown {
			if functions := nft_switch_functions(switches) {
				mut top := root
				for {
					top = node_parent(top) or { break }
				}
				partial_tree = estree.convert_functions(top, c.src, abs_path.to_lower().ends_with('.tsx'),
					c.es_options(), functions) or { return findings }
				partial_paths = codepath.analyze(&partial_tree)
				partial = true
			}
		}
	}
	an := if partial {
		&partial_paths
	} else {
		c.code_path_analysis(root, abs_path) or { return findings }
	}
	t := if partial {
		&partial_tree
	} else {
		c.es_tree(root, abs_path) or { return findings }
	}
	findings = c.nft_check(an, t, opts, mut stats)
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nft_check reports the cases of the switch statements of the tree, from its code path events.
fn (mut c Checker) nft_check(an &codepath.Analysis, t &estree.EsTree, opts NftOptions, mut stats Stats) []Finding {
	mut findings := []Finding{}
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
								stmt:       c.es_tree_position(t, ev.node)
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
									stmt:       c.position_range(found.start, found.end)
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
	return findings
}

// nft_switch_functions are the outermost functions (function_part of estree.convert_functions)
// that the `switch` statements are in, in the order of the file; none when one of them is in no
// function (its code path is the program's).
fn nft_switch_functions(switches []C.vt_node) ?[]C.vt_node {
	mut innermost := map[u64]bool{}
	mut found := []C.vt_node{}
	for s in switches {
		mut node := node_parent(s) or { return none }
		for !nft_starts_code_path(node) {
			node = node_parent(node) or { return none }
		}
		if node_kind(node) == 'program' {
			return none
		}
		key := node_key(node)
		if key !in innermost {
			innermost[key] = true
			found << node
		}
	}
	// A function inside another one of them is converted with it. The functions are told apart
	// by their range, which no two functions share (other nodes may share a function's: the
	// statement or the program that is only that function).
	mut out := []C.vt_node{cap: found.len}
	for f in found {
		mut nested := false
		mut node := f
		for {
			node = node_parent(node) or { break }
			if nft_starts_code_path(node) && node_kind(node) != 'program'
				&& node_key(node) in innermost {
				nested = true
				break
			}
		}
		if !nested {
			out << f
		}
	}
	out.sort_with_compare(fn (a &C.vt_node, b &C.vt_node) int {
		return int(node_start(*a)) - int(node_start(*b))
	})
	return out
}

// nft_starts_code_path: the node is the program, or a function, method or class static block,
// whose code path a `switch` in it is in (a `switch` is a statement: a class field's value has it
// in a function).
fn nft_starts_code_path(node C.vt_node) bool {
	return node_kind(node) in ['program', 'function_declaration', 'generator_function_declaration',
		'function_expression', 'generator_function', 'arrow_function', 'method_definition',
		'class_static_block']
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
