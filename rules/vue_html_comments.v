module rules

// lib/utils/html-comments.ts of eslint-plugin-vue 10.12.1 (prefix `vhc_`): the HTML comments of
// the template split into their parts (`<!--`, the decoration of the `exceptions`, the value, the
// closing decoration and `-->`), for the html-comment-* rules. Offsets are bytes of the file.

// VhcPart is a token of a parsed comment: [start, end). `present` is false for a missing one.
struct VhcPart {
	present bool
	start   int
	end     int
}

struct VhcComment {
	open             VhcPart
	open_decoration  VhcPart
	value            VhcPart
	close_decoration VhcPart
	close            VhcPart
}

// vhc_open_decoration is getOpenDecoration: the longest run of one exception at the start.
fn vhc_open_decoration(contents string, exceptions []string) string {
	mut decoration := ''
	for exception in exceptions {
		mut index := 0
		if exception.len > 0 {
			for contents[index..].starts_with(exception) {
				index += exception.len
			}
		}
		if utf16_units(decoration).len < utf16_units(contents[..index]).len {
			decoration = contents[..index]
		}
	}
	return decoration
}

// vhc_close_decoration is getCloseDecoration: the longest run of one exception at the end.
fn vhc_close_decoration(contents string, exceptions []string) string {
	mut decoration := ''
	for exception in exceptions {
		mut index := contents.len
		if exception.len > 0 {
			for index >= exception.len && contents[..index].ends_with(exception) {
				index -= exception.len
			}
		}
		if utf16_units(decoration).len < utf16_units(contents[index..]).len {
			decoration = contents[index..]
		}
	}
	return decoration
}

// vhc_first_non_space is `text.search(/\S/)` in bytes, -1 for none.
fn vhc_first_non_space(text string) int {
	mut i := 0
	for r in text.runes() {
		if !is_js_space(r) {
			return i
		}
		i += r.length_in_bytes()
	}
	return -1
}

// vhc_last_non_space_end is the end of the last non-space character (`search(/\S\s*$/) + 1`),
// -1 for none.
fn vhc_last_non_space_end(text string) int {
	runes := text.runes()
	mut end := text.len
	for k := runes.len - 1; k >= 0; k-- {
		if !is_js_space(runes[k]) {
			return end
		}
		end -= runes[k].length_in_bytes()
	}
	return -1
}

// vhc_parse is parseHTMLComment of an HTMLComment token, none when it is not a normal comment.
fn (c &Checker) vhc_parse(start int, end int, exceptions []string) ?VhcComment {
	text := c.src[start..end]
	if !text.starts_with('<!--') || !text.ends_with('-->') || text.len < 7 {
		return none
	}
	mut value := text[4..text.len - 3]
	open_decoration := vhc_open_decoration(value, exceptions)
	value = value[open_decoration.len..]
	first := vhc_first_non_space(value)
	before_space := if first >= 0 { value[..first] } else { value }
	value = value[before_space.len..]
	close_decoration := vhc_close_decoration(value, exceptions)
	if close_decoration != '' {
		value = value[..value.len - close_decoration.len]
	}
	last := vhc_last_non_space_end(value)
	after_space := if last >= 0 { value[last..] } else { value }
	if after_space != '' {
		value = value[..value.len - after_space.len]
	}
	mut index := start
	open := VhcPart{true, index, index + 4}
	index += 4
	mut od := VhcPart{}
	if open_decoration != '' {
		od = VhcPart{true, index, index + open_decoration.len}
		index += open_decoration.len
	}
	index += before_space.len
	mut v := VhcPart{}
	if value != '' {
		v = VhcPart{true, index, index + value.len}
		index += value.len
	}
	index += after_space.len
	mut cd := VhcPart{}
	if close_decoration != '' {
		cd = VhcPart{true, index, index + close_decoration.len}
		index += close_decoration.len
	}
	return VhcComment{
		open:             open
		open_decoration:  od
		value:            v
		close_decoration: cd
		close:            VhcPart{true, index, index + 3}
	}
}

// vhc_comments is defineVisitor: the parsed HTML comments of the template (without the
// `eslint-disable`/`eslint-enable` directives unless `include_directives`, never the IE
// conditional comments); none for a file without a template or with an invalid end.
fn (c &Checker) vhc_comments(exceptions []string, include_directives bool) []VhcComment {
	mut out := []VhcComment{}
	if !c.vue_has_template() || c.vue_has_invalid_eof() {
		return out
	}
	doc := c.vue.doc
	body := doc.template_body
	if body < 0 {
		return out
	}
	body_start := doc.nodes[body].start
	body_end := doc.nodes[body].end
	for comment in doc.comments {
		if comment.typ != 'HTMLComment' || comment.start < body_start || comment.end > body_end {
			continue
		}
		value := comment.value
		if !include_directives && vhc_is_directive(value) {
			continue
		}
		if value.starts_with('[if') && value.len > 3 && is_js_space(value[3..].runes()[0]) {
			continue
		}
		if value.ends_with('[endif]') {
			continue
		}
		if parsed := c.vhc_parse(comment.start, comment.end, exceptions) {
			out << parsed
		}
	}
	return out
}

// vhc_is_directive is `/^\s*eslint-(?:en|dis)able/`.
fn vhc_is_directive(value string) bool {
	first := vhc_first_non_space(value)
	if first < 0 {
		return false
	}
	rest := value[first..]
	return rest.starts_with('eslint-enable') || rest.starts_with('eslint-disable')
}

// VhcLines are ESLint's lines of the file (getLocFromIndex): the offsets where they start.
struct VhcLines {
	starts []int
}

// vhc_lines breaks the file into ESLint's lines (`\r\n`, `\n`, `\r`, U+2028, U+2029).
fn (c &Checker) vhc_lines() VhcLines {
	src := c.src
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
	return VhcLines{
		starts: starts
	}
}

// vhc_line is the line (from 1) of an offset, as getLocFromIndex gives it.
fn vhc_line(lines &VhcLines, offset int) int {
	mut lo := 0
	mut hi := lines.starts.len
	for lo < hi {
		mid := (lo + hi) / 2
		if lines.starts[mid] <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// vhc_report is a report whose `loc` goes from one offset to another (getLocFromIndex).
fn (c &Checker) vhc_report(start int, end int, message_id string, data map[string]string) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       data
		text_loc:   true
	}
}
