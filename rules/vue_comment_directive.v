module rules

import json2
import offsets
import vue

// Port of the `vue/comment-directive` rule of eslint-plugin-vue 10.12.1 together with the
// postprocess of its processor (`vue/vue`): the `<!-- eslint-disable -->`, `<!-- eslint-enable -->`,
// `<!-- eslint-disable-line -->` and `<!-- eslint-disable-next-line -->` comments of a .vue file
// (and those comments in the JavaScript comments of template expressions), with or without rule
// names and a `-- description`, suppress the problems of the other rules, as ESLint gives them when
// the configuration has the processor (eslint-plugin-vue's configurations set it with the rule).
// With the option reportUnusedDisableDirectives, the disable directives that suppressed nothing are
// reported.
//
// Upstream, the rule reports each directive as a problem (`--block <key>`, `+line <rule>`,
// `clear`…) and the processor walks all the problems in the order of their positions, keeping the
// state of the directives and dropping the problems inside a disabled area and the rule's own;
// veslint makes the same events (vcd_events) and walks them with the other findings of the file
// (vue_comment_directive_postprocess, which lint_file calls when the rule is on).

const vcd_messages = {
	'disableBlock':     '--block {{key}}'
	'enableBlock':      '++block'
	'disableLine':      '--line {{key}}'
	'enableLine':       '++line'
	'disableBlockRule': '-block {{rule}} {{key}}'
	'enableBlockRule':  '+block {{rule}}'
	'disableLineRule':  '-line {{rule}} {{key}}'
	'enableLineRule':   '+line {{rule}}'
	'clear':            'clear'
	'unused':           'Unused {{kind}} directive (no problems were reported).'
	'unusedRule':       "Unused {{kind}} directive (no problems were reported from '{{rule}}')."
}

fn vcd_options(options []json2.Any) !bool {
	o := option_object(vue_comment_directive, options, ['reportUnusedDisableDirectives'])!
	return o.bool_value('reportUnusedDisableDirectives')!
}

// The rule itself reports nothing that reaches the output but through the postprocess.
fn (mut c Checker) lint_vue_comment_directive(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	vcd_options(c.rule_options(vue_comment_directive))!
	return []
}

// VcdEvent is a problem of the rule: a directive event (message_id disableBlock…clear) at ESLint's
// line and column, or an unused report (`report`).
struct VcdEvent {
	line       int
	column     int
	message_id string
	key        string
	rule       string
	report     Finding
}

// VcdParsed is parse(): the directive and its rules, each with the index (UTF-16, in the text
// without the description) where the search for it started.
struct VcdParsed {
	typ   string
	rules []VcdRule
}

struct VcdRule {
	id    string
	index int
}

fn vcd_is_space(u u16) bool {
	return is_js_space(rune(u))
}

// vcd_parse is parse(pattern, comment) for both patterns: `line` picks
// `^\s*(eslint-disable(?:-next)?-line)(?:\s+|$)`, else `^\s*(eslint-(?:en|dis)able)(?:\s+|$)`.
fn vcd_parse(value string, line bool) ?VcdParsed {
	all := utf16_units(value)
	// stripDirectiveComment: value.split(/\s-{2,}\s/u, 1)[0].
	mut text := all.clone()
	for i := 0; i < all.len; i++ {
		if !vcd_is_space(all[i]) {
			continue
		}
		mut j := i + 1
		for j < all.len && all[j] == `-` {
			j++
		}
		if j - (i + 1) >= 2 && j < all.len && vcd_is_space(all[j]) {
			text = all[..i].clone()
			break
		}
	}
	mut i := 0
	for i < text.len && vcd_is_space(text[i]) {
		i++
	}
	rest := text[i..]
	candidates := if line {
		['eslint-disable-next-line', 'eslint-disable-line']
	} else {
		['eslint-disable', 'eslint-enable']
	}
	mut typ := ''
	for cand in candidates {
		units := utf16_units(cand)
		if rest.len >= units.len && rest[..units.len] == units {
			after := i + units.len
			// `(?:\s+|$)`
			if after == text.len || vcd_is_space(text[after]) {
				typ = cand
				break
			}
		}
	}
	if typ == '' {
		return none
	}
	mut start := i + typ.len
	for start < text.len && vcd_is_space(text[start]) {
		start++
	}
	// rulesRe = /([^\s,]+)[\s,]*/g from the end of the match; each rule's index is where its
	// search started.
	mut found := []VcdRule{}
	mut pos := start
	for {
		mut k := pos
		for k < text.len && (vcd_is_space(text[k]) || text[k] == `,`) {
			k++
		}
		if k >= text.len {
			break
		}
		mut e := k
		for e < text.len && !vcd_is_space(text[e]) && text[e] != `,` {
			e++
		}
		found << VcdRule{
			id:    utf16_to_string(text[k..e])
			index: pos
		}
		for e < text.len && (vcd_is_space(text[e]) || text[e] == `,`) {
			e++
		}
		pos = e
	}
	return VcdParsed{
		typ:   typ
		rules: found
	}
}

fn utf16_to_string(units []u16) string {
	mut runes := []rune{cap: units.len}
	mut i := 0
	for i < units.len {
		u := units[i]
		if u >= 0xd800 && u < 0xdc00 && i + 1 < units.len && units[i + 1] >= 0xdc00
			&& units[i + 1] < 0xe000 {
			runes << rune(0x10000 + ((u32(u) - 0xd800) << 10) + (u32(units[i + 1]) - 0xdc00))
			i += 2
			continue
		}
		runes << rune(u)
		i++
	}
	return runes.string()
}

// vcd_key is locToKey.
fn vcd_key(line int, column int) string {
	return 'line:${line},column${column}'
}

// vcd_unused_report is reportUnused: a report on the comment, and its key.
fn (c &Checker) vcd_unused_report(comment vue.Token, kind string, mut events []VcdEvent) string {
	doc := c.vue.doc
	start := doc.loc(comment.start)
	events << VcdEvent{
		line:       start.line
		column:     start.column + 1
		message_id: 'unused'
		report:     Finding{
			stmt:       c.position_range(comment.start, comment.end)
			message_id: 'unused'
			data:       {
				'kind': kind
			}
		}
	}
	return vcd_key(start.line, start.column)
}

// vcd_unused_rules is reportUnusedRules: a report on the name of each rule (located by
// sourceCode.getLocFromIndex, with ESLint's own line breaks, from the comment's start plus 4, the
// length of `<!--`, also for a JavaScript comment), each with the key of its directive.
fn (c &Checker) vcd_unused_rules(comment vue.Token, kind string, directive_rules []VcdRule, mut events []VcdEvent) {
	doc := c.vue.doc
	comment_start := doc.utf16(comment.start) + 4
	for rule in directive_rules {
		start := doc.byte_offset(comment_start + rule.index)
		end := doc.byte_offset(comment_start + rule.index + utf16_units(rule.id).len)
		_, positions := offsets.utf16_positions(doc.src, [c.position_at(start)])
		at := positions[0]
		events << VcdEvent{
			line:       at.line
			column:     at.col
			message_id: 'unusedRule'
			// The key of the rule's directive is that of its report.
			key:        vcd_key(at.line, at.col - 1)
			report:     Finding{
				stmt:       c.position_range(start, end)
				message_id: 'unusedRule'
				data:       {
					'rule': rule.id
					'kind': kind
				}
				text_loc:   true
			}
		}
	}
}

// vcd_process_comment runs processBlock and processLine on a comment.
fn (c &Checker) vcd_process_comment(comment vue.Token, report_unused bool, mut events []VcdEvent) {
	doc := c.vue.doc
	start := doc.loc(comment.start)
	if parsed := vcd_parse(comment.value, false) {
		if parsed.typ == 'eslint-disable' {
			if parsed.rules.len > 0 {
				mut keys := []string{len: parsed.rules.len, init: '*'}
				if report_unused {
					first := events.len
					c.vcd_unused_rules(comment, parsed.typ, parsed.rules, mut events)
					for k in 0 .. parsed.rules.len {
						keys[k] = events[first + k].key
					}
				}
				for k, rule in parsed.rules {
					events << VcdEvent{
						line:       start.line
						column:     start.column + 1
						message_id: 'disableBlockRule'
						rule:       rule.id
						key:        keys[k]
					}
				}
			} else {
				key := if report_unused {
					c.vcd_unused_report(comment, parsed.typ, mut events)
				} else {
					''
				}
				events << VcdEvent{
					line:       start.line
					column:     start.column + 1
					message_id: 'disableBlock'
					key:        key
				}
			}
		} else {
			if parsed.rules.len > 0 {
				for rule in parsed.rules {
					events << VcdEvent{
						line:       start.line
						column:     start.column + 1
						message_id: 'enableBlockRule'
						rule:       rule.id
					}
				}
			} else {
				events << VcdEvent{
					line:       start.line
					column:     start.column + 1
					message_id: 'enableBlock'
				}
			}
		}
	}
	parsed := vcd_parse(comment.value, true) or { return }
	if start.line != doc.loc(comment.end).line {
		return
	}
	line := start.line + if parsed.typ == 'eslint-disable-line' { 0 } else { 1 }
	// column -1: ESLint's column 0, before every problem of the line.
	if parsed.rules.len > 0 {
		mut keys := []string{len: parsed.rules.len, init: ''}
		if report_unused {
			first := events.len
			c.vcd_unused_rules(comment, parsed.typ, parsed.rules, mut events)
			for k in 0 .. parsed.rules.len {
				keys[k] = events[first + k].key
			}
		}
		for k, rule in parsed.rules {
			events << VcdEvent{
				line:       line
				column:     0
				message_id: 'disableLineRule'
				rule:       rule.id
				key:        keys[k]
			}
			events << VcdEvent{
				line:       line + 1
				column:     0
				message_id: 'enableLineRule'
				rule:       rule.id
			}
		}
	} else {
		key := if report_unused {
			c.vcd_unused_report(comment, parsed.typ, mut events)
		} else {
			''
		}
		events << VcdEvent{
			line:       line
			column:     0
			message_id: 'disableLine'
			key:        key
		}
		events << VcdEvent{
			line:       line + 1
			column:     0
			message_id: 'enableLine'
		}
	}
}

// vcd_events are the problems the rule reports, in its order: the directives of every comment of
// the document and a clear mark at the end of the template (when there is one), then again the
// directives of the top-level comments (outside every top-level element) and a clear mark at the
// end of each top-level element.
fn (c &Checker) vcd_events(report_unused bool) []VcdEvent {
	doc := c.vue.doc
	mut events := []VcdEvent{}
	if doc.template_body >= 0 {
		for comment in doc.comments {
			c.vcd_process_comment(comment, report_unused, mut events)
		}
		_, body_end := c.vue_vnode_range(doc.template_body)
		end := doc.loc(body_end)
		events << VcdEvent{
			line:       end.line
			column:     end.column + 1
			message_id: 'clear'
		}
	}
	elements := doc.nodes[0].children.filter(doc.nodes[it].typ == .v_element)
	for comment in doc.comments {
		if elements.all(comment.end <= doc.nodes[it].start || doc.nodes[it].end <= comment.start) {
			c.vcd_process_comment(comment, report_unused, mut events)
		}
	}
	for element in elements {
		_, element_end := c.vue_vnode_range(element)
		end := doc.loc(element_end)
		events << VcdEvent{
			line:       end.line
			column:     end.column + 1
			message_id: 'clear'
		}
	}
	return events
}

// VcdItem is a message the postprocess walks: an event of the rule (`event` >= 0) or a finding of
// another rule.
struct VcdItem {
	line    int
	column  int
	event   int = -1
	finding int = -1
}

// vue_finding_positions are the line and column ESLint gives each finding of the .vue file (as
// vue_report_positions prints them).
fn (c &Checker) vue_finding_positions(findings []Finding) []offsets.DisplayPos {
	doc := c.vue.doc
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
		} else if f.stmt.row < 0 {
			out << offsets.DisplayPos{
				line: 0
				col:  doc.loc(f.stmt.start_byte).column + 1
			}
		} else {
			loc := doc.loc(f.stmt.start_byte)
			out << offsets.DisplayPos{
				line: loc.line
				col:  loc.column + 1
			}
		}
	}
	return out
}

// vue_comment_directive_postprocess is the processor's postprocess on the findings of the file
// (sorted, after the script's own directive comments): the findings in a disabled area go, and with
// reportUnusedDisableDirectives the reports of the disable directives that suppressed nothing come
// in, at their places.
fn (mut c Checker) vue_comment_directive_postprocess(findings []Finding, setting RuleSetting) ![]Finding {
	if !c.is_vue() {
		return findings
	}
	report_unused := vcd_options(setting.options)!
	events := c.vcd_events(report_unused)
	positions := c.vue_finding_positions(findings)
	// The problems by (line, column), stable: the rule reports first (in its Program listener), so
	// at one position its events come before the other rules' findings.
	mut items := []VcdItem{cap: events.len + findings.len}
	for k, e in events {
		items << VcdItem{
			line:   e.line
			column: e.column
			event:  k
		}
	}
	for k, p in positions {
		items << VcdItem{
			line:    p.line
			column:  p.col
			finding: k
		}
	}
	vcd_stable_sort(mut items)
	mut block_all := map[string]bool{}
	mut line_all := map[string]bool{}
	mut block_rules := map[string][]string{}
	mut line_rules := map[string][]string{}
	mut used := map[string]bool{}
	mut unused_keys := []string{}
	mut unused_reports := map[string]VcdItem{}
	mut kept := []VcdItem{}
	for item in items {
		if item.event >= 0 {
			e := events[item.event]
			match e.message_id {
				'disableBlock' {
					block_all[e.key] = true
				}
				'disableLine' {
					line_all[e.key] = true
				}
				'enableBlock' {
					block_all.clear()
				}
				'enableLine' {
					line_all.clear()
				}
				'disableBlockRule' {
					block_rules[e.rule] << e.key
				}
				'disableLineRule' {
					line_rules[e.rule] << e.key
				}
				'enableBlockRule' {
					block_rules.delete(e.rule)
				}
				'enableLineRule' {
					line_rules.delete(e.rule)
				}
				'clear' {
					block_all.clear()
					line_all.clear()
					block_rules.clear()
					line_rules.clear()
				}
				else {
					// An unused report, by the key of its place (messageToKey).
					key := vcd_key(e.line, e.column - 1)
					if key !in unused_reports {
						unused_keys << key
					}
					unused_reports[key] = item
				}
			}
			continue
		}
		f := findings[item.finding]
		mut keys := []string{}
		keys << block_all.keys()
		keys << line_all.keys()
		rule_id := f.eslint_id()
		if rule_id != '' {
			keys << block_rules[rule_id] or { []string{} }
			keys << line_rules[rule_id] or { []string{} }
		}
		if keys.len > 0 {
			for k in keys {
				used[k] = true
			}
			continue
		}
		kept << item
	}
	if unused_reports.len > 0 {
		for key in unused_keys {
			if key !in used {
				kept << unused_reports[key]
			}
		}
		vcd_stable_sort(mut kept)
	}
	mut out := []Finding{cap: kept.len}
	for item in kept {
		if item.event >= 0 {
			out << Finding{
				...events[item.event].report
				rule:     vue_comment_directive
				severity: setting.severity
			}
		} else {
			out << findings[item.finding]
		}
	}
	return out
}

// vcd_stable_sort sorts by line and column, keeping the order of the equal ones.
fn vcd_stable_sort(mut items []VcdItem) {
	mut order := []int{len: items.len, init: index}
	order.sort_with_compare(fn [items] (a &int, b &int) int {
		x := items[*a]
		y := items[*b]
		if x.line != y.line {
			return if x.line < y.line { -1 } else { 1 }
		}
		if x.column != y.column {
			return if x.column < y.column { -1 } else { 1 }
		}
		return *a - *b
	})
	sorted := order.map(items[it])
	items = sorted.clone()
}
