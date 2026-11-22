module rules

import json2
import time

// Port of the `vue/padding-line-between-tags` rule of eslint-plugin-vue 10.12.1 (option: a list of
// `{blankLine, prev, next}`, the last matching one applies; selectors `*`, a name, and
// `:single-line` / `:multi-line`): between an element of the template and its next sibling
// element, a blank line expected ("always", fixed by line breaks after the element), not
// expected ("never", fixed by dropping the blank lines between them) or as between the first
// pair of the parent ("consistent").

const vplbt_messages = {
	'never':  'Unexpected blank line before this tag.'
	'always': 'Expected blank line before this tag.'
}

struct VplbtConfigure {
	blank_line string
	prev       string
	next       string
}

fn vplbt_options(options []json2.Any) ![]VplbtConfigure {
	if options.len == 0 {
		return [VplbtConfigure{'always', '*', '*'}]
	}
	list := options[0]
	if list !is []json2.Any {
		return error('the option of `${vue_padding_line_between_tags}` must be a list')
	}
	mut out := []VplbtConfigure{}
	for item in list.as_array() {
		o := option_object(vue_padding_line_between_tags, [item], ['blankLine', 'prev', 'next'])!
		prev := o.values['prev'] or { return error('`prev` is required') }
		next := o.values['next'] or { return error('`next` is required') }
		if prev !is string || next !is string {
			return error('`prev` and `next` of `${vue_padding_line_between_tags}` must be texts')
		}
		out << VplbtConfigure{
			blank_line: o.string_value('blankLine', ['always', 'never', 'consistent'])!
			prev:       prev as string
			next:       next as string
		}
	}
	return out
}

// vplbt_end_tag is `element.endTag || element.startTag`.
fn (c &Checker) vplbt_end_tag(element int) int {
	el := &c.vue.doc.nodes[element]
	return if el.end_tag >= 0 { el.end_tag } else { el.start_tag }
}

fn (c &Checker) vplbt_single_line(element int) bool {
	el := &c.vue.doc.nodes[element]
	return c.vu4_line(c.vue.doc.nodes[el.start_tag].start) == c.vu4_line(c.vue.doc.nodes[c.vplbt_end_tag(element)].end)
}

// vplbt_matches is isSelectorMatchingTag.
fn (c &Checker) vplbt_matches(selector string, element int) bool {
	name := c.vue.doc.nodes[element].name
	colon := selector.last_index(':') or { -1 }
	if colon > 0 {
		pseudo := selector[colon..]
		tag := selector[..colon]
		tag_match := tag == '*' || name == tag
		if pseudo == ':single-line' {
			return tag_match && c.vplbt_single_line(element)
		}
		if pseudo == ':multi-line' {
			return tag_match && !c.vplbt_single_line(element)
		}
	}
	return selector == '*' || name == selector
}

// vplbt_blank is /^\s*$/.test(line).
fn vplbt_blank(line string) bool {
	return line.runes().all(is_js_space(it))
}

// vplbt_leading_space is /^\s*/.exec(line)[0].
fn vplbt_leading_space(line string) string {
	runes := line.runes()
	mut k := 0
	for k < runes.len && is_js_space(runes[k]) {
		k++
	}
	return runes[..k].string()
}

fn (mut c Checker) lint_vue_padding_line_between_tags(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	configures := vplbt_options(c.rule_options(vue_padding_line_between_tags))!
	mut findings := []Finding{}
	mut lines := []string{}
	mut has_lines := false
	mut first_consistent := map[int]string{}
	for block in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[block]
		if node.typ != .v_element || node.parent < 0 || c.vue.doc.nodes[node.parent].parent < 0 {
			continue
		}
		stats.checked++
		end_tag := c.vue.doc.nodes[c.vplbt_end_tag(block)]
		mut sibling := -1
		for s in c.vue.doc.nodes[node.parent].children {
			sn := &c.vue.doc.nodes[s]
			if sn.typ == .v_element && s != block && sn.start >= end_tag.end {
				sibling = s
				break
			}
		}
		if sibling < 0 {
			continue
		}
		mut configure := ?VplbtConfigure(none)
		for k := configures.len - 1; k >= 0; k-- {
			if c.vplbt_matches(configures[k].prev, block) && c.vplbt_matches(configures[k].next, sibling) {
				configure = configures[k]
				break
			}
		}
		conf := configure or { continue }
		sib := c.vue.doc.nodes[sibling]
		diff := c.vu4_line(sib.start) - c.vu4_line(end_tag.end)
		mut blank_line := conf.blank_line
		if blank_line == 'consistent' {
			first := first_consistent[node.parent] or {
				first_consistent[node.parent] = if diff > 1 { 'always' } else { 'never' }
				continue
			}
			blank_line = first
		}
		if !has_lines {
			lines = un_source_lines(c.vue.doc.src)
			has_lines = true
		}
		if blank_line == 'always' {
			if diff == 1 {
				findings << c.with_fixes(c.vue_report_vnode(sibling, 'always', map[string]string{}),
					[fix_insert_at(node.end, '\n')])!
			} else if diff == 0 {
				line := lines[c.vu4_line(end_tag.start) - 1] or { '' }
				findings << c.with_fixes(c.vue_report_vnode(sibling, 'always', map[string]string{}),
					[fix_insert_at(end_tag.end, '\n\n' + vplbt_leading_space(line))])!
			}
			continue
		}
		if diff <= 1 {
			continue
		}
		mut only_text := true
		for k := c.vu4_line(end_tag.start); only_text && k < c.vu4_line(sib.start) - 1; k++ {
			only_text = !vplbt_blank(lines[k] or { '' })
		}
		if only_text {
			continue
		}
		mut between := un_source_lines(c.vue_text(end_tag.end, sib.start))
		mut text := '\n' + between.pop()
		for k := between.len - 1; k >= 0; k-- {
			if !vplbt_blank(between[k]) {
				text = '${if k == 0 { '' } else { '\n' }}${between[k]}${text}'
			}
		}
		findings << c.with_fixes(c.vue_report_vnode(sibling, 'never', map[string]string{}),
			[fix_replace_range(end_tag.end, sib.start, text)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
