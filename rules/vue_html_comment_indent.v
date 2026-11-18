module rules

import json2
import time

// Port of the `vue/html-comment-indent` rule of eslint-plugin-vue 10.12.1 (option: the size of an
// indentation, 2 by default, or "tab"): the lines of a multi-line HTML comment of the template
// are indented one level more than the line of its `<!--`, and its `-->` on a line of its own as
// much as that line, with the fixes that reindent them.

const vue_html_comment_indent_messages = {
	'unexpectedBaseIndentation':      'Expected base point indentation of {{expected}}, but found {{actual}}.'
	'missingBaseIndentation':         'Expected base point indentation of {{expected}}, but not found.'
	'unexpectedIndentationCharacter': 'Expected {{expected}} character, but found {{actual}} character.'
	'unexpectedIndentation':          'Expected indentation of {{expected}} but found {{actual}}.'
	'unexpectedRelativeIndentation':  'Expected relative indentation of {{expected}} but found {{actual}}.'
}

struct VhciOptions {
	indent_char string
	indent_text string
}

fn vue_html_comment_indent_options(options []json2.Any) !VhciOptions {
	mut indent_char := ' '
	mut size := 2
	if options.len > 0 {
		value := options[0]
		if value is string {
			if value == 'tab' {
				indent_char = '\t'
				size = 1
			}
		} else {
			n := json_number(value)
			if n == f64(i64(n)) && n >= -9007199254740991 && n <= 9007199254740991 {
				size = int(n)
			}
		}
	}
	return VhciOptions{
		indent_char: indent_char
		indent_text: indent_char.repeat(if size > 0 { size } else { 0 })
	}
}

// vhci_unit is toUnit.
fn vhci_unit(ch string) string {
	return match ch {
		'\t' { 'tab' }
		' ' { 'space' }
		else { js_json_stringify(json2.Any(ch)) }
	}
}

// vhci_display is toDisplay.
fn vhci_display(s string, unit_char string) string {
	if unit_char != '' && s.len == 0 {
		return '0 ${vhci_unit(unit_char)}s'
	}
	if s.len > 0 && (s[0] == ` ` || s[0] == `\t`) && s.bytes().all(it == s[0]) {
		return '${s.len} ${vhci_unit(s[0].ascii_str())}${if s.len == 1 { '' } else { 's' }}'
	}
	return js_json_stringify(json2.Any(s))
}

struct VhciCtx {
	o     VhciOptions
	lines VhcLines
}

// vhci_line_text is sourceCode.lines[line - 1].
fn (c &Checker) vhci_line_text(ctx &VhciCtx, line int) (int, string) {
	start := ctx.lines.starts[line - 1]
	mut end := if line < ctx.lines.starts.len { ctx.lines.starts[line] } else { c.src.len }
	// Without its line break.
	if line < ctx.lines.starts.len {
		if end - start >= 2 && c.src[end - 2] == `\r` && c.src[end - 1] == `\n` {
			end -= 2
		} else if end - start >= 1 && (c.src[end - 1] == `\n` || c.src[end - 1] == `\r`) {
			end--
		} else if end - start >= 3 {
			end -= 3 // U+2028 or U+2029
		}
	}
	return start, c.src[start..end]
}

// vhci_indent is getLineIndentText: the line up to its first non-space character.
fn (c &Checker) vhci_indent(ctx &VhciCtx, line int) string {
	_, text := c.vhci_line_text(ctx, line)
	index := vhc_first_non_space(text)
	return if index >= 0 { text[..index] } else { text[..if text.len > 0 { text.len - 1 } else { 0 }] }
}

fn (mut c Checker) lint_vue_html_comment_indent(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	o := vue_html_comment_indent_options(c.rule_options(vue_html_comment_indent))!
	mut findings := []Finding{}
	comments := c.vhc_comments([], true)
	if comments.len == 0 {
		return findings
	}
	ctx := VhciCtx{
		o:     o
		lines: c.vhc_lines()
	}
	for comment in comments {
		stats.checked++
		base := c.vhci_indent(ctx, vhc_line(ctx.lines, comment.open.start))
		mut end_line := 0
		if comment.value.present {
			start_line := vhc_line(ctx.lines, comment.value.start)
			end_line = vhc_line(ctx.lines, comment.value.end)
			check_start := if vhc_line(ctx.lines, comment.open.end) == start_line {
				start_line + 1
			} else {
				start_line
			}
			for line in check_start .. end_line + 1 {
				c.vhci_validate(ctx, line, base, 1, mut findings)
			}
		} else {
			end_line = vhc_line(ctx.lines, comment.open.end)
		}
		close_line := vhc_line(ctx.lines, comment.close.start)
		if end_line < close_line {
			c.vhci_validate(ctx, close_line, base, 0, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vhci_validate is validateIndentForLine.
fn (c &Checker) vhci_validate(ctx &VhciCtx, line int, base string, offset int, mut findings []Finding) {
	line_start, text := c.vhci_line_text(ctx, line)
	if js_trim(text) == '' {
		return
	}
	actual := c.vhci_indent(ctx, line)
	expected_offset := ctx.o.indent_text.repeat(offset)
	expected := base + expected_offset
	fix := fix_replace_range(line_start, line_start + actual.len, expected)
	if base != '' && (utf16_units(actual).len < utf16_units(base).len || !actual.starts_with(base)) {
		base_units := utf16_units(base).len
		actual_units := utf16_units(actual)
		actual_prefix := utf16_to_string(actual_units[..if base_units < actual_units.len {
			base_units
		} else {
			actual_units.len
		}])
		findings << c.with_fixes(c.vhc_report(line_start, line_start + actual.len, if actual != '' {
			'unexpectedBaseIndentation'
		} else {
			'missingBaseIndentation'
		}, {
			'expected': vhci_display(base, '')
			'actual':   vhci_display(actual_prefix, '')
		}), [fix]) or { return }
		return
	}
	actual_offset := actual[base.len..]
	mut at := line_start + base.len
	for r in actual_offset.runes() {
		ch := r.str()
		if ch != ctx.o.indent_char {
			findings << c.with_fixes(c.vhc_report(at, at + ch.len, 'unexpectedIndentationCharacter',
				{
				'expected': vhci_unit(ctx.o.indent_char)
				'actual':   vhci_unit(ch)
			}), [fix]) or { return }
			return
		}
		at += ch.len
	}
	if utf16_units(actual_offset).len != utf16_units(expected_offset).len {
		findings << c.with_fixes(c.vhc_report(line_start + base.len, line_start + actual.len,
			if base != '' { 'unexpectedRelativeIndentation' } else { 'unexpectedIndentation' }, {
			'expected': vhci_display(expected_offset, ctx.o.indent_char)
			'actual':   vhci_display(actual_offset, ctx.o.indent_char)
		}), [fix]) or { return }
	}
}
