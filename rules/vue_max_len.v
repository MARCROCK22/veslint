module rules

import json2
import jsregexp
import offsets
import time
import treesitter { node_kind }

// Port of the `vue/max-len` rule of eslint-plugin-vue 10.12.1 (options: the code length and the
// tab width as numbers, then an object with `code`, `template`, `comments`, `tabWidth`,
// `ignorePattern`, `ignoreComments`, `ignoreTrailingComments`, `ignoreUrls`, `ignoreStrings`,
// `ignoreTemplateLiterals`, `ignoreRegExpLiterals`, `ignoreHTMLAttributeValues`,
// `ignoreHTMLTextContents`): ESLint core's max-len on the lines of the script and of the template
// of a .vue file (and of a .ts file). Its reports are located by line and column (the limit and
// the length of the line, tabs counted to the next tab stop): Finding.line_loc.

const vmaxlen_messages = {
	'max':        'This line has a length of {{lineLength}}. Maximum allowed is {{maxLength}}.'
	'maxComment': 'This line has a comment length of {{lineLength}}. Maximum allowed is {{maxCommentLength}}.'
}

struct VmaxlenOptions {
	code              int = 80
	template          int
	comments          int
	tab_width         int = 2
	ignore_pattern    ?jsregexp.JsRegex
	ignore_comments   bool
	ignore_trailing   bool
	ignore_urls       bool
	ignore_strings    bool
	ignore_templates  bool
	ignore_regexps    bool
	ignore_attributes bool
	ignore_texts      bool
}

fn vmaxlen_int(value json2.Any, key string) !int {
	if value is f64 && value == f64(int(value)) && value >= 0 {
		return int(value)
	}
	if value is i64 && value >= 0 {
		return int(value)
	}
	if value is int && value >= 0 {
		return value
	}
	return error('option `${key}` of `${vue_max_len}` must be an integer of at least 0')
}

fn vmaxlen_options(options []json2.Any) !VmaxlenOptions {
	// The options object is the last option; the code length and the tab width may be the
	// first and the second as numbers.
	mut values := map[string]json2.Any{}
	if options.len > 0 && options.last() is map[string]json2.Any {
		values = options.last().as_map().clone()
	}
	known := ['code', 'template', 'comments', 'tabWidth', 'ignorePattern', 'ignoreComments',
		'ignoreTrailingComments', 'ignoreUrls', 'ignoreStrings', 'ignoreTemplateLiterals',
		'ignoreRegExpLiterals', 'ignoreHTMLAttributeValues', 'ignoreHTMLTextContents']
	for key, _ in values {
		if key !in known {
			return error('unknown option `${key}` of `${vue_max_len}`')
		}
	}
	if options.len > 0 && options[0] !is map[string]json2.Any {
		values['code'] = options[0]
	}
	if options.len > 1 && options[1] !is map[string]json2.Any {
		values['tabWidth'] = options[1]
	}
	flag := fn [values] (key string) !bool {
		value := values[key] or { return false }
		if value !is bool {
			return error('option `${key}` of `${vue_max_len}` must be true or false')
		}
		return value as bool
	}
	code := if v := values['code'] { vmaxlen_int(v, 'code')! } else { 80 }
	mut pattern := ?jsregexp.JsRegex(none)
	if v := values['ignorePattern'] {
		if v !is string {
			return error('option `ignorePattern` of `${vue_max_len}` must be a text')
		}
		text := v as string
		if text != '' {
			pattern = jsregexp.js_regex_new(text, 'u')!
		}
	}
	ignore_comments := flag('ignoreComments')!
	return VmaxlenOptions{
		code:              code
		template:          if v := values['template'] { vmaxlen_int(v, 'template')! } else { code }
		comments:          if v := values['comments'] { vmaxlen_int(v, 'comments')! } else { 0 }
		tab_width:         if v := values['tabWidth'] { vmaxlen_int(v, 'tabWidth')! } else { 2 }
		ignore_pattern:    pattern
		ignore_comments:   ignore_comments
		ignore_trailing:   flag('ignoreTrailingComments')! || ignore_comments
		ignore_urls:       flag('ignoreUrls')!
		ignore_strings:    flag('ignoreStrings')!
		ignore_templates:  flag('ignoreTemplateLiterals')!
		ignore_regexps:    flag('ignoreRegExpLiterals')!
		ignore_attributes: flag('ignoreHTMLAttributeValues')!
		ignore_texts:      flag('ignoreHTMLTextContents')!
	}
}

// VmaxlenComment is a comment's `loc`: lines from 1, UTF-16 columns from 0.
struct VmaxlenComment {
	start_line   int
	start_column int
	end_line     int
	end_column   int
}

// vmaxlen_length is computeLineLength: the code points of the line, a tab counted up to the next
// tab stop (its offset is a UTF-16 one, as RegExp.exec's index).
fn vmaxlen_length(line string, tab_width int) int {
	mut extra := 0
	mut offset := 0
	mut count := 0
	for r in line.runes() {
		if r == `\t` {
			total := offset + extra
			previous := if tab_width != 0 { total % tab_width } else { 0 }
			extra += tab_width - previous - 1
		}
		offset += if r > 0xffff { 2 } else { 1 }
		count++
	}
	return count + extra
}

// vmaxlen_slice is `line.slice(0, column)` (UTF-16 units).
fn vmaxlen_slice(line string, column int) string {
	units := utf16_units(line)
	return utf16_to_string(units[..if column < units.len { column } else { units.len }])
}

fn vmaxlen_is_trailing(line string, line_number int, c VmaxlenComment) bool {
	return c.start_line == line_number && line_number <= c.end_line
		&& (c.end_line > line_number || c.end_column == utf16_units(line).len)
}

fn vmaxlen_is_full_line(line string, line_number int, c VmaxlenComment) bool {
	first_on_line := js_trim(vmaxlen_slice(line, c.start_column)) == ''
	return (c.start_line < line_number || (c.start_line == line_number && first_on_line))
		&& (c.end_line > line_number || (c.end_line == line_number
			&& c.end_column == utf16_units(line).len))
}

// vmaxlen_strip is stripTrailingComment: the line before the comment, without the white space at
// its end.
fn vmaxlen_strip(line string, c VmaxlenComment) string {
	s := vmaxlen_slice(line, c.start_column)
	return s[..vu4_trim_end_offset(s, s.len)]
}

// vmaxlen_line_starts are where ESLint's lines start (sourceCode.lines: broken by CRLF, LF, CR,
// U+2028 and U+2029).
fn vmaxlen_line_starts(src string) []int {
	mut starts := [0]
	mut pos := 0
	for pos < src.len {
		b := src[pos]
		mut n := 0
		if b == `\n` {
			n = 1
		} else if b == `\r` {
			n = if pos + 1 < src.len && src[pos + 1] == `\n` { 2 } else { 1 }
		} else if b == 0xE2 && pos + 2 < src.len && src[pos + 1] == 0x80
			&& (src[pos + 2] == 0xA8 || src[pos + 2] == 0xA9) {
			n = 3
		}
		if n == 0 {
			pos++
			continue
		}
		pos += n
		starts << pos
	}
	return starts
}

// VmaxlenLines tells the lines of tokens and comments: vue-eslint-parser's (broken by LF only) in
// a .vue file, ESLint's in a .ts file.
struct VmaxlenLines {
	vue    bool
	starts offsets.LineStarts
}

fn (c &Checker) vmaxlen_line(l &VmaxlenLines, offset int) int {
	return if l.vue { c.vue.doc.loc(offset).line } else { l.starts.line_index(offset) + 1 }
}

fn (c &Checker) vmaxlen_comment(l &VmaxlenLines, start int, end int) VmaxlenComment {
	if l.vue {
		s := c.vue.doc.loc(start)
		e := c.vue.doc.loc(end)
		return VmaxlenComment{s.line, s.column, e.line, e.column}
	}
	return VmaxlenComment{
		start_line:   l.starts.line_index(start) + 1
		start_column: utf16_column(c.src, start)
		end_line:     l.starts.line_index(end) + 1
		end_column:   utf16_column(c.src, end)
	}
}

// vmaxlen_mark marks the lines from the one of `start` to the one of `end` (groupByLineNumber).
fn (c &Checker) vmaxlen_mark(l &VmaxlenLines, start int, end int, mut lines map[int]bool) {
	for line in c.vmaxlen_line(l, start) .. c.vmaxlen_line(l, end) + 1 {
		lines[line] = true
	}
}

// vmaxlen_svelte_range is the script's range of lines of a .svelte file: from the first to the last
// of svelte-eslint-parser's tokens and comments of the whole file ([] without any).
fn (c &Checker) vmaxlen_svelte_range(l &VmaxlenLines) []int {
	tokens := c.svelte.doc.tokens
	comments := c.svelte.doc.comments
	if tokens.len > 0 {
		first := c.vmaxlen_line(l, sv_token_loc_start(tokens[0]))
		last := c.vmaxlen_line(l, sv_token_loc_end(tokens.last()))
		if comments.len > 0 {
			first_comment := c.vmaxlen_line(l, sv_token_loc_start(comments[0]))
			last_comment := c.vmaxlen_line(l, sv_token_loc_end(comments.last()))
			return [if first < first_comment { first } else { first_comment },
				if last > last_comment { last } else { last_comment }]
		}
		return [first, last]
	}
	if comments.len > 0 {
		return [c.vmaxlen_line(l, sv_token_loc_start(comments[0])),
			c.vmaxlen_line(l, sv_token_loc_end(comments.last()))]
	}
	return []
}

fn (mut c Checker) lint_vue_max_len(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	stats.checked++
	o := vmaxlen_options(c.rule_options(vue_max_len))!
	l := VmaxlenLines{
		vue:    c.is_vue()
		starts: offsets.line_starts(c.src)
	}
	source := c.source_tokens(root)
	script_tokens := source.tokens
	script_comments := source.comments
	has_template := c.vue_has_template()
	mut template_start, mut template_end := 0, 0
	if has_template {
		body := &c.vue.doc.nodes[c.vue.doc.template_body]
		template_start, template_end = body.start, body.end
	}
	template_first := has_template && template_start < c.vue.doc.script.program_start
	// The lines with strings, template literals, regular expressions, HTML texts, attribute values.
	mut strings := map[int]bool{}
	mut templates := map[int]bool{}
	mut regexps := map[int]bool{}
	mut texts := map[int]bool{}
	mut attributes := map[int]bool{}
	// A .svelte file: svelte-eslint-parser's tokens of the whole file (the markup's, the script's and
	// the template expressions', HTML comments among them) are `sourceCode.ast.tokens`.
	if c.is_svelte() {
		for token in c.svelte.doc.tokens {
			start, end := sv_token_loc_start(token), sv_token_loc_end(token)
			match token.typ {
				'String' { c.vmaxlen_mark(&l, start, end, mut strings) }
				'Template' { c.vmaxlen_mark(&l, start, end, mut templates) }
				'RegularExpression' { c.vmaxlen_mark(&l, start, end, mut regexps) }
				'HTMLText' { c.vmaxlen_mark(&l, start, end, mut texts) }
				else {}
			}
		}
	}
	for token in script_tokens {
		if c.is_svelte() {
			break
		}
		match token.kind {
			.string_ { c.vmaxlen_mark(&l, token.start, token.end, mut strings) }
			.template { c.vmaxlen_mark(&l, token.start, token.end, mut templates) }
			.regular_expression { c.vmaxlen_mark(&l, token.start, token.end, mut regexps) }
			// A JSX attribute's string (the node before it is the JSXAttribute).
			.jsx_text {
				if node_kind(token.node) == 'string' {
					c.vmaxlen_mark(&l, token.start, token.end, mut strings)
				}
			}
			else {}
		}
	}
	mut template_comments := []VmaxlenComment{}
	if has_template {
		for token in c.vue_tokens_with_comments_in(template_start, template_end) {
			match token.typ {
				'String' { c.vmaxlen_mark(&l, token.start, token.end, mut strings) }
				'Template' { c.vmaxlen_mark(&l, token.start, token.end, mut templates) }
				'RegularExpression' { c.vmaxlen_mark(&l, token.start, token.end, mut regexps) }
				'HTMLText' { c.vmaxlen_mark(&l, token.start, token.end, mut texts) }
				else {}
			}
		}
		for comment in c.vue.doc.comments {
			if comment.start >= template_start && comment.end <= template_end {
				template_comments << c.vmaxlen_comment(&l, comment.start, comment.end)
			}
		}
		for i in c.vue_template_vnodes() {
			node := &c.vue.doc.nodes[i]
			if node.typ == .v_literal && node.parent >= 0 && !c.vue.doc.nodes[node.parent].directive {
				c.vmaxlen_mark(&l, node.start, node.end, mut attributes)
			}
		}
	}
	// The comments of each line, in the order of `comments`.
	mut by_line := map[int][]VmaxlenComment{}
	if o.ignore_comments || o.comments != 0 || o.ignore_trailing {
		mut comments := []VmaxlenComment{}
		script := if c.is_svelte() {
			c.svelte.doc.comments.map(c.vmaxlen_comment(&l, sv_token_loc_start(it), sv_token_loc_end(it)))
		} else {
			script_comments.map(c.vmaxlen_comment(&l, it.start, it.end))
		}
		if template_first {
			comments << template_comments
			comments << script
		} else {
			comments << script
			comments << template_comments
		}
		for comment in comments {
			for line in comment.start_line .. comment.end_line + 1 {
				by_line[line] << comment
			}
		}
	}
	mut script_range := []int{}
	if c.is_svelte() {
		script_range = c.vmaxlen_svelte_range(&l)
	} else if script_tokens.len > 0 {
		first := c.vmaxlen_line(&l, script_tokens[0].start)
		last := c.vmaxlen_line(&l, script_tokens.last().end)
		if script_comments.len > 0 {
			first_comment := c.vmaxlen_line(&l, script_comments[0].start)
			last_comment := c.vmaxlen_line(&l, script_comments.last().end)
			script_range = [if first < first_comment { first } else { first_comment },
				if last > last_comment { last } else { last_comment }]
		} else {
			script_range = [first, last]
		}
	} else if script_comments.len > 0 {
		script_range = [c.vmaxlen_line(&l, script_comments[0].start),
			c.vmaxlen_line(&l, script_comments.last().end)]
	}
	mut template_range := []int{}
	if has_template {
		template_range = [c.vmaxlen_line(&l, template_start), c.vmaxlen_line(&l, template_end)]
	}
	url := jsregexp.js_regex_new('[^:/?#]:\\/\\/[^?#]', 'u')!
	mut findings := []Finding{}
	// The lines of the file: for a .svelte file, not those of the template part of its lint code
	// that follows the file in the source text (file_text).
	file_text := c.file_text()
	starts := vmaxlen_line_starts(file_text)
	for i, line_start in starts {
		line_number := i + 1
		mut line_end := file_text.len
		if i + 1 < starts.len {
			// The line without the line break before the next one.
			line_end = starts[i + 1]
			last := file_text[line_end - 1]
			if last == `\n` {
				line_end -= if line_end - 2 >= line_start && file_text[line_end - 2] == `\r` {
					2
				} else {
					1
				}
			} else if last == `\r` {
				line_end--
			} else {
				line_end -= 3
			}
		}
		line := file_text[line_start..line_end]
		in_script := script_range.len > 0 && script_range[0] <= line_number
			&& line_number <= script_range[1]
		in_template := template_range.len > 0 && template_range[0] <= line_number
			&& line_number <= template_range[1]
		if (!in_script && !in_template) || (o.ignore_strings && line_number in strings)
			|| (o.ignore_templates && line_number in templates)
			|| (o.ignore_regexps && line_number in regexps)
			|| (o.ignore_attributes && line_number in attributes)
			|| (o.ignore_texts && line_number in texts) {
			continue
		}
		mut is_comment_line := false
		mut text := line
		if comments := by_line[line_number] {
			mut list := comments.clone()
			mut comment := list.pop()
			if vmaxlen_is_full_line(line, line_number, comment) {
				is_comment_line = true
			} else if o.ignore_trailing && vmaxlen_is_trailing(line, line_number, comment) {
				text = vmaxlen_strip(line, comment)
				// Several trailing comments: the loop strips the second one while it is trailing
				// (JavaScript's `comment` is not taken again in it).
				if list.len > 0 {
					comment = list.pop()
					for vmaxlen_is_trailing(text, line_number, comment) {
						stripped := vmaxlen_strip(text, comment)
						if stripped == text {
							break
						}
						text = stripped
					}
				}
			}
		}
		if pattern := o.ignore_pattern {
			if vue_regexp_test(&pattern, text) {
				continue
			}
		}
		if (o.ignore_urls && vue_regexp_test(&url, text)) || (is_comment_line && o.ignore_comments) {
			continue
		}
		max_length := if in_script && in_template {
			if o.code > o.template { o.code } else { o.template }
		} else if in_script {
			o.code
		} else {
			o.template
		}
		line_length := vmaxlen_length(text, o.tab_width)
		mut message_id := ''
		mut limit := 0
		if is_comment_line && o.comments != 0 {
			if line_length > o.comments {
				message_id = 'maxComment'
				limit = o.comments
			}
		} else if line_length > max_length {
			message_id = 'max'
			limit = max_length
		}
		if message_id == '' {
			continue
		}
		mut data := {
			'lineLength': line_length.str()
		}
		data[if message_id == 'max' { 'maxLength' } else { 'maxCommentLength' }] = limit.str()
		findings << Finding{
			stmt:             c.position_range(line_start, line_end)
			message_id:       message_id
			data:             data
			line_loc:         true
			fixed_line:       line_number
			fixed_column:     limit + 1
			fixed_end_line:   line_number
			fixed_end_column: line_length + 1
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
