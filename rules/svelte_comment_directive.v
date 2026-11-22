module rules

import json2
import jsregexp
import offsets

// Ports of the `svelte/comment-directive` and `svelte/system` rules of eslint-plugin-svelte 3.24.1
// together with the postprocess of its processor (`svelte/svelte`, src/processor and
// src/shared/comment-directives.ts). comment-directive reads the `<!-- eslint-disable -->`,
// `<!-- eslint-enable -->`, `<!-- eslint-disable-line -->` and `<!-- eslint-disable-next-line -->`
// comments of the template (with or without rule names and a `-- description`); system disables
// the rules settings.svelte.ignoreWarnings names outside the scripts. The postprocess drops the
// problems those directives cover, and with comment-directive's reportUnusedDisableDirectives its
// reports of the directives that suppressed nothing stay (the others go).
//
// Upstream, each rule makes a CommentDirectives object shared with the processor of the file; the
// processor's postprocess filters the problems through each, in the order the rules were created.
// veslint has no `processor` setting: either rule on means the processor on (eslint-plugin-svelte's
// configurations set the three together). lint_file calls svelte_comment_directive_postprocess
// after the script's own directive comments. Without the processor (RuleTester) the rules do
// nothing: eslint-plugin-svelte's tests of them are lints with ESLint.

const svelte_rule_prefix = 'svelte/'

const svcd_messages = {
	'unused':           'Unused {{kind}} directive (no problems were reported).'
	'unusedRule':       "Unused {{kind}} directive (no problems were reported from '{{rule}}')."
	'unusedEnable':     'Unused {{kind}} directive (reporting is not suppressed).'
	'unusedEnableRule': "Unused {{kind}} directive (reporting from '{{rule}}' is not suppressed)."
}

fn svcd_options(options []json2.Any) !bool {
	o := option_object(svelte_comment_directive, options, ['reportUnusedDisableDirectives'])!
	return o.bool_value('reportUnusedDisableDirectives')!
}

// SvcdMatch is which rules a directive applies to: one (`rule`), all of them, or those
// settings.svelte.ignoreWarnings names (system's isIgnoreRule).
enum SvcdMatch {
	one
	all
	ignored
}

// SvcdPos is an AST.Position: a line from 1 and a column from 0.
struct SvcdPos {
	line   int
	column int
}

fn svcd_compare(a SvcdPos, b SvcdPos) int {
	return if a.line != b.line { a.line - b.line } else { a.column - b.column }
}

// SvcdDirective is a Block or a Line of CommentDirectives (`line` for a Line, `pos` for a
// Block), with its `define` location (the key of its unused report).
struct SvcdDirective {
	id      int
	pos     SvcdPos
	line    int
	matches SvcdMatch
	rule    string
	enable  bool
	define  SvcdPos
}

// SvcdSet is a CommentDirectives object: its directives, keyed by their rule (`''` is COMPUTED:
// the directives of all rules and of the ignored ones), in the order they were added.
struct SvcdSet {
mut:
	rule_id        string
	report_unused  bool
	lines          map[string][]SvcdDirective
	blocks         map[string][]SvcdDirective
	ignore_exact   []string
	ignore_regexps []jsregexp.JsRegex
	next_id        int
}

fn (mut s SvcdSet) add(d SvcdDirective, block bool) {
	key := if d.matches == .one { d.rule } else { '' }
	directive := SvcdDirective{
		...d
		id: s.next_id
	}
	s.next_id++
	if block {
		s.blocks[key] << directive
	} else {
		s.lines[key] << directive
	}
}

// matches_rule is the directive's `rule(ruleId)`.
fn (s &SvcdSet) matches_rule(d SvcdDirective, rule_id string) bool {
	return match d.matches {
		.one { d.rule == rule_id }
		.all { true }
		.ignored { s.is_ignored(rule_id) }
	}
}

// is_ignored is system's isIgnoreRule.
fn (s &SvcdSet) is_ignored(rule_id string) bool {
	if rule_id in s.ignore_exact {
		return true
	}
	for r in s.ignore_regexps {
		if r.test(utf16_units(rule_id)) or { false } {
			return true
		}
	}
	return false
}

// SvcdMessage is what filterMessages reads of a problem: its rule ('' for none) and position
// (line from 1, column from 1).
struct SvcdMessage {
	rule_id string
	line    int
	column  int
}

// filter is CommentDirectives.filterMessages: which messages stay.
fn (s &SvcdSet) filter(messages []SvcdMessage, keep []bool) []bool {
	mut used := map[int]SvcdPos{} // directive id -> define
	if s.report_unused {
		mut all_blocks := []SvcdDirective{}
		for _, bs in s.blocks {
			all_blocks << bs
		}
		// Sorted by position, last first (a stable sort, as Array.prototype.sort).
		sorted := svcd_sorted_desc(all_blocks)
		mut enables := []SvcdDirective{}
		for b in sorted {
			if b.enable {
				if b.matches != .one {
					enables.clear()
				}
				enables << b
			} else {
				if b.matches != .one {
					for e in enables {
						used[e.id] = e.define
					}
					enables.clear()
				} else {
					mut rest := []SvcdDirective{}
					for e in enables {
						if b.rule == e.rule || e.matches != .one {
							used[e.id] = e.define
						} else {
							rest << e
						}
					}
					enables = rest.clone()
				}
			}
		}
	}
	mut out := keep.clone()
	for k, m in messages {
		if !out[k] {
			continue
		}
		if !s.is_enabled(m, mut used) {
			out[k] = false
		}
	}
	if s.report_unused {
		mut used_keys := map[string]bool{}
		for _, define in used {
			used_keys[svcd_key(define.line, define.column)] = true
		}
		for k, m in messages {
			if out[k] && m.rule_id == s.rule_id && svcd_key(m.line, m.column - 1) in used_keys {
				out[k] = false
			}
		}
	}
	return out
}

fn svcd_key(line int, column int) string {
	return 'line:${line},column${column}'
}

fn svcd_sorted_desc(directives []SvcdDirective) []SvcdDirective {
	mut order := []int{len: directives.len, init: index}
	order.sort_with_compare(fn [directives] (a &int, b &int) int {
		c := svcd_compare(directives[*b].pos, directives[*a].pos)
		return if c != 0 { c } else { *a - *b }
	})
	return order.map(directives[it])
}

// is_enabled is filterMessages' isEnable.
fn (s &SvcdSet) is_enabled(m SvcdMessage, mut used map[int]SvcdPos) bool {
	if m.rule_id == '' {
		return true
	}
	for key in [m.rule_id, ''] {
		for d in s.lines[key] or { continue } {
			if d.line == m.line && s.matches_rule(d, m.rule_id) {
				used[d.id] = d.define
				return false
			}
		}
	}
	mut blocks := []SvcdDirective{}
	blocks << s.blocks[m.rule_id] or { []SvcdDirective{} }
	blocks << s.blocks[''] or { []SvcdDirective{} }
	message_pos := SvcdPos{m.line, m.column}
	for b in svcd_sorted_desc(blocks) {
		if svcd_compare(message_pos, b.pos) < 0 || !s.matches_rule(b, m.rule_id) {
			continue
		}
		if b.enable {
			return true
		}
		used[b.id] = b.define
		return false
	}
	return true
}

// SvcdParsed is parse(): the directive and its rules, each with where its search started (UTF-16
// index in the comment's value without the description) and its UTF-16 length.
struct SvcdParsed {
	typ   string
	rules []VcdRule
}

// svcd_parse is parse(pattern, comment), eslint-plugin-vue's (vcd_parse) but for the start of
// the rules: the end of the match (`\s+` included) where vue's skips the spaces itself.
fn svcd_parse(value string, line bool) ?SvcdParsed {
	parsed := vcd_parse(value, line)?
	return SvcdParsed{
		typ:   parsed.typ
		rules: parsed.rules
	}
}

// svcd_pos is svelte-eslint-parser's location of a byte offset of the file.
fn (c &Checker) svcd_pos(offset int) SvcdPos {
	loc := c.svelte.doc.loc(offset)
	return SvcdPos{loc.line, loc.column}
}

// svcd_text_pos is sourceCode.getLocFromIndex of a UTF-16 offset of the file (ESLint's line
// breaks).
fn (c &Checker) svcd_text_pos(unit int) SvcdPos {
	doc := c.svelte.doc
	_, positions := offsets.utf16_positions(doc.src, [c.position_at(doc.byte_offset(unit))])
	return SvcdPos{positions[0].line, positions[0].col - 1}
}

// SvcdRun is what comment-directive's listeners make for a file: its directives and its reports.
struct SvcdRun {
mut:
	set     SvcdSet
	reports []Finding
}

// svcd_rule_locs are the locations of the rules of a directive comment (from `<!--`, 4 units
// before the value): their start and end bytes and their start position.
fn (c &Checker) svcd_rule_report(comment int, rule VcdRule, kind string, message_id string, mut run SvcdRun) SvcdPos {
	doc := c.svelte.doc
	value_start := doc.utf16(doc.nodes[comment].start) + 4
	start := doc.byte_offset(value_start + rule.index)
	end := doc.byte_offset(value_start + rule.index + utf16_units(rule.id).len)
	if run.set.report_unused {
		run.reports << Finding{
			...c.sv_report_text(start, end, message_id, {
				'rule': rule.id
				'kind': kind
			})
		}
	}
	return c.svcd_text_pos(value_start + rule.index)
}

// svcd_process_comment is processBlock and processLine of an HTML comment.
fn (c &Checker) svcd_process_comment(comment int, mut run SvcdRun) {
	doc := c.svelte.doc
	n := &doc.nodes[comment]
	start := c.svcd_pos(n.start)
	end := c.svcd_pos(if n.loc_end >= 0 { n.loc_end } else { n.end })
	if parsed := svcd_parse(n.value, false) {
		disable := parsed.typ == 'eslint-disable'
		if parsed.rules.len > 0 {
			for rule in parsed.rules {
				define := c.svcd_rule_report(comment, rule, parsed.typ, if disable {
					'unusedRule'
				} else {
					'unusedEnableRule'
				}, mut run)
				run.set.add(SvcdDirective{
					pos:     if disable { end } else { start }
					matches: .one
					rule:    rule.id
					enable:  !disable
					define:  define
				}, true)
			}
		} else {
			if run.set.report_unused {
				run.reports << c.sv_report_snode(comment, if disable {
					'unused'
				} else {
					'unusedEnable'
				}, {
					'kind': parsed.typ
				})
			}
			run.set.add(SvcdDirective{
				pos:     if disable { end } else { start }
				matches: .all
				enable:  !disable
				define:  start
			}, true)
		}
	}
	parsed := svcd_parse(n.value, true) or { return }
	if start.line != end.line {
		return
	}
	line := start.line + if parsed.typ == 'eslint-disable-line' { 0 } else { 1 }
	if parsed.rules.len > 0 {
		for rule in parsed.rules {
			define := c.svcd_rule_report(comment, rule, parsed.typ, 'unusedRule', mut run)
			run.set.add(SvcdDirective{
				line:    line
				matches: .one
				rule:    rule.id
				define:  define
			}, false)
		}
	} else {
		if run.set.report_unused {
			run.reports << c.sv_report_snode(comment, 'unused', {
				'kind': parsed.typ
			})
		}
		run.set.add(SvcdDirective{
			line:    line
			matches: .all
			define:  start
		}, false)
	}
}

// svcd_comment_directive_run is comment-directive's listeners over the document: SvelteHTMLComment
// and SvelteScriptElement, in traversal order.
fn (mut c Checker) svcd_comment_directive_run(report_unused bool) SvcdRun {
	mut run := SvcdRun{
		set: SvcdSet{
			rule_id:       svelte_comment_directive
			report_unused: report_unused
		}
	}
	doc := c.svelte.doc
	for i in c.sv_snodes() {
		match doc.nodes[i].typ {
			.html_comment {
				c.svcd_process_comment(i, mut run)
			}
			.script_element {
				tag := doc.nodes[doc.nodes[i].start_tag]
				run.set.add(SvcdDirective{
					pos:     c.svcd_pos(tag.end)
					matches: .all
					enable:  true
					define:  c.svcd_pos(doc.nodes[i].start)
				}, true)
			}
			else {}
		}
	}
	return run
}

// The rule's reports (the unused directives, with reportUnusedDisableDirectives): those of the
// directives that suppress something are dropped by the postprocess.
fn (mut c Checker) lint_svelte_comment_directive(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	report_unused := svcd_options(c.rule_options(svelte_comment_directive))!
	if !c.is_svelte() {
		return []
	}
	return c.svcd_comment_directive_run(report_unused).reports
}

// svcd_regexp_str is RE_REGEXP_STR (/^\/(.+)\/([A-Za-z]*)$/u) of src/utils/regexp.ts: the source
// and the flags of a string written as a regular expression.
fn svcd_regexp_str(s string) ?(string, string) {
	if s.len < 3 || s[0] != `/` {
		return none
	}
	last := s.last_index('/') or { return none }
	if last < 2 {
		return none
	}
	for ch in s[last + 1..] {
		if !ch.is_letter() {
			return none
		}
	}
	for r in s[1..last].runes() {
		if r in [`\n`, `\r`, rune(0x2028), rune(0x2029)] {
			return none
		}
	}
	return s[1..last], s[last + 1..]
}

// svcd_system_set is system's CommentDirectives (and its reports): the rules
// settings.svelte.ignoreWarnings names are disabled from the start of the file, enabled inside the
// scripts.
fn (mut c Checker) svcd_system_set() (SvcdSet, []Finding) {
	mut set := SvcdSet{
		rule_id: svelte_system
	}
	ignore := if s := c.settings['svelte'] {
		sv_json_path(s, ['ignoreWarnings']) or { json2.Any(json2.Null{}) }
	} else {
		json2.Any(json2.Null{})
	}
	at_start := Finding{
		stmt:         c.position_range(0, 0)
		fixed_line:   1
		fixed_column: 1
		no_end:       true
	}
	match ignore {
		json2.Null {}
		[]json2.Any {
			for item in ignore {
				if item !is string {
					return SvcdSet{}, [
						Finding{
							...at_start
							text: 'The array element in the `settings.svelte.ignoreWarnings` must be a string.'
						},
					]
				}
				text := item as string
				if source, flags := svcd_regexp_str(text) {
					if r := jsregexp.js_regex_new(source, flags) {
						set.ignore_regexps << r
					}
				} else {
					set.ignore_exact << text
				}
			}
		}
		else {
			return SvcdSet{}, [
				Finding{
					...at_start
					text: 'The `settings.svelte.ignoreWarnings` must be an array.'
				},
			]
		}
	}
	set.add(SvcdDirective{
		pos:     SvcdPos{1, 0}
		matches: .ignored
		define:  SvcdPos{1, 0}
	}, true)
	doc := c.svelte.doc
	for i in c.sv_snodes_of(.script_element) {
		tag_end := c.svcd_pos(doc.nodes[doc.nodes[i].start_tag].end)
		set.add(SvcdDirective{
			pos:     tag_end
			matches: .ignored
			enable:  true
			define:  tag_end
		}, true)
		end_tag := doc.nodes[i].end_tag
		if end_tag >= 0 {
			end_start := c.svcd_pos(doc.nodes[end_tag].start)
			set.add(SvcdDirective{
				pos:     end_start
				matches: .ignored
				define:  end_start
			}, true)
		}
	}
	return set, []Finding{}
}

// svelte/system reports only its settings' errors (the postprocess applies its directives).
fn (mut c Checker) lint_svelte_system(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	_, reports := c.svcd_system_set()
	return reports
}

// sv_finding_positions are the line and column ESLint gives each finding of the .svelte file
// (as svelte_report_positions prints them).
fn (c &Checker) sv_finding_positions(findings []Finding) []offsets.DisplayPos {
	doc := c.svelte.doc
	mut out := []offsets.DisplayPos{cap: findings.len}
	for f in findings {
		if f.fixed_line != 0 {
			out << offsets.DisplayPos{
				line: f.fixed_line
				col:  f.fixed_column
			}
		} else if f.text_loc || f.text_loc_start {
			_, pos := offsets.utf16_positions(doc.src, [f.stmt])
			out << pos[0]
		} else {
			loc := doc.loc(f.stmt.start_byte)
			out << offsets.DisplayPos{
				line: if f.stmt.row < 0 { 0 } else { loc.line }
				col:  loc.column + 1
			}
		}
	}
	return out
}

// svelte_comment_directive_postprocess is the processor's postprocess on the findings of a
// .svelte file (sorted, after the script's own directive comments): each CommentDirectives of the
// rules that are on (comment-directive's, system's), in the order of the rules, filters them.
fn (mut c Checker) svelte_comment_directive_postprocess(findings []Finding, settings []RuleSetting) ![]Finding {
	if !c.is_svelte() {
		return findings
	}
	mut sets := []SvcdSet{}
	for setting in settings {
		if setting.name == svelte_comment_directive {
			sets << c.svcd_comment_directive_run(svcd_options(setting.options)!).set
		} else if setting.name == svelte_system {
			set, reports := c.svcd_system_set()
			if reports.len == 0 {
				sets << set
			}
		}
	}
	if sets.len == 0 {
		return findings
	}
	positions := c.sv_finding_positions(findings)
	mut messages := []SvcdMessage{cap: findings.len}
	for k, f in findings {
		messages << SvcdMessage{
			rule_id: f.eslint_id()
			line:    positions[k].line
			column:  positions[k].col
		}
	}
	mut keep := []bool{len: findings.len, init: true}
	for set in sets {
		keep = set.filter(messages, keep)
	}
	mut out := []Finding{cap: findings.len}
	for k, f in findings {
		if keep[k] {
			out << f
		}
	}
	return out
}
