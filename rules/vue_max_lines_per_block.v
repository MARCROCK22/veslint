module rules

import json2
import time

// Port of the `vue/max-lines-per-block` rule of eslint-plugin-vue 10.12.1 (options `template`,
// `script`, `style`: the maximum lines of each top-level block, its tags left out; and
// `skipBlankLines`): a block with more lines.

const vue_max_lines_per_block_messages = {
	'tooManyLines': 'Block has too many lines ({{lineCount}}). Maximum allowed is {{limit}}.'
}

struct VueMaxLinesOptions {
	limits           map[string]f64
	skip_blank_lines bool
}

fn vue_max_lines_per_block_options(options []json2.Any) !VueMaxLinesOptions {
	o := option_object(vue_max_lines_per_block, options, ['style', 'template', 'script',
		'skipBlankLines'])!
	mut limits := map[string]f64{}
	for key in ['template', 'script', 'style'] {
		value := o.values[key] or { continue }
		if value !is f64 && value !is int && value !is i64 {
			return error('option `${key}` of `${vue_max_lines_per_block}` must be an integer')
		}
		// `if (!limits[block.name])`: 0 is no limit.
		if value.f64() != 0 {
			limits[key] = value.f64()
		}
	}
	return VueMaxLinesOptions{
		limits:           limits
		skip_blank_lines: o.bool_value('skipBlankLines')!
	}
}

fn (mut c Checker) lint_vue_max_lines_per_block(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() || c.vue_has_invalid_eof() {
		return []
	}
	sw := time.new_stopwatch()
	o := vue_max_lines_per_block_options(c.rule_options(vue_max_lines_per_block))!
	mut findings := []Finding{}
	doc := c.vue.doc
	for block in doc.nodes[0].children {
		node := &doc.nodes[block]
		if node.typ != .v_element {
			continue
		}
		limit := o.limits[node.name] or { continue }
		stats.checked++
		// The start tag and the end tag are supposed to take one line each.
		mut line_count := doc.loc(node.end).line - doc.loc(node.start).line - 1
		if o.skip_blank_lines {
			line_count -= vue_split_lines(doc.src[node.start..node.end]).filter(js_trim(it) == '').len
		}
		if f64(line_count) > limit {
			findings << c.vue_report_vnode(block, 'tooManyLines', {
				'limit':     js_number_to_string(limit)
				'lineCount': line_count.str()
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_split_lines ports SourceCode.splitLines: the lines of a text, broken at CRLF, CR, LF, U+2028
// and U+2029.
fn vue_split_lines(text string) []string {
	mut lines := []string{}
	mut start := 0
	mut i := 0
	for i < text.len {
		b := text[i]
		if b == `\r` {
			lines << text[start..i]
			i += if i + 1 < text.len && text[i + 1] == `\n` { 2 } else { 1 }
			start = i
			continue
		}
		if b == `\n` {
			lines << text[start..i]
			i++
			start = i
			continue
		}
		if b == 0xE2 && i + 2 < text.len && text[i + 1] == 0x80 && text[i + 2] in [
			u8(0xA8),
			0xA9,
		] {
			lines << text[start..i]
			i += 3
			start = i
			continue
		}
		i++
	}
	lines << text[start..]
	return lines
}
