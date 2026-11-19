module rules

import jsregexp
import offsets
import treesitter { Ident, node_end, node_start }

// The shared code of the rules of @eslint-community/eslint-plugin-eslint-comments 4.8.1
// (lib/internal/*.js), as they run in ESLint 10.15.0:
//   - getDisabledArea (lib/internal/disabled-area.js) takes the directives of
//     sourceCode.getDisableDirectives() (DisabledAreaForLanguagePlugin, since ESLint's SourceCode
//     has it): ESLint's own reading of the comments (ec_disabled_area);
//   - getAllDirectiveComments (lib/internal/get-all-directive-comments.js) parses every comment
//     with the plugin's own parser (getAllDirectiveCommentsFromAllComments, since ESLint's
//     SourceCode has getAllComments): ec_directive_comments;
//   - toForceLocation and toRuleIdLocation (lib/internal/utils.js): ec_force_location and
//     ec_rule_id_location, whose column -1 puts a report before the comment, where no directive of
//     the comment itself hides it;
//   - no-restricted-disable matches the rule ids with the `ignore` package 7.0.14 (EcIgnore).
// The comments are those ESLint reads directives in (rules/directives.v); a column here is
// ESLint's `loc` column, from 0, in UTF-16 units.

// EcComment is a comment: its text without `//` or `/*` and `*/` (comment.value) and its loc.
struct EcComment {
	start      int // bytes
	end        int
	is_line    bool
	value      string
	line       int // from 1
	column     int // from 0, in UTF-16 units
	end_line   int
	end_column int
}

// EcLoc is the `loc` of a report: a column from 0 (-1 before the line), and the bytes of the text
// it stands for (veslint's place of the report on its line).
struct EcLoc {
	line       int
	column     int
	end_line   int
	end_column int
	start_byte int
	end_byte   int
}

// ec_comments are the comments of the file, in order, as ESLint's SourceCode gives them.
fn (mut c Checker) ec_comments(root C.TSNode) []EcComment {
	lines := offsets.line_starts(c.src)
	mut out := []EcComment{}
	for node in c.nodes_of_kind(root, c'comment') {
		text := c.text(node)
		is_line := text.starts_with('//')
		if !is_line && (text.len < 4 || !text.starts_with('/*') || !text.ends_with('*/')) {
			continue
		}
		start := node_start(node)
		end := node_end(node)
		line, column := c.line_column(lines, start)
		end_line, end_column := c.line_column(lines, end)
		out << EcComment{
			start:      start
			end:        end
			is_line:    is_line
			value:      if is_line { text[2..] } else { text[2..text.len - 2] }
			line:       line
			column:     column - 1
			end_line:   end_line
			end_column: end_column - 1
		}
	}
	return out
}

// ec_force_location ports toForceLocation: the comment's loc with its start at column -1 of its
// line.
fn ec_force_location(comment EcComment) EcLoc {
	return EcLoc{
		line:       comment.line
		column:     -1
		end_line:   comment.end_line
		end_column: comment.end_column
		start_byte: comment.start
		end_byte:   comment.end
	}
}

// ec_comment_location is the comment's loc.
fn ec_comment_location(comment EcComment) EcLoc {
	return EcLoc{
		line:       comment.line
		column:     comment.column
		end_line:   comment.end_line
		end_column: comment.end_column
		start_byte: comment.start
		end_byte:   comment.end
	}
}

// ec_value_lines ports `comment.value.match(LINE_PATTERN)`, LINE_PATTERN being
// /[^\r\n  ]*(?:\r\n|[\r\n  ]|$)/gu: the lines of the value with their line
// break, and an empty one at its end; each with its byte offset in the value.
fn ec_value_lines(value string) ([]string, []int) {
	mut lines := []string{}
	mut starts := []int{}
	mut pos := 0
	for {
		mut i := pos
		mut found := false
		for i < value.len {
			if value[i] == `\n` || value[i] == `\r` {
				found = true
				break
			}
			// U+2028 and U+2029: E2 80 A8 and E2 80 A9.
			if value[i] == 0xe2 && i + 2 < value.len && value[i + 1] == 0x80
				&& value[i + 2] in [u8(0xa8), 0xa9] {
				found = true
				break
			}
			i++
		}
		if !found {
			lines << value[pos..]
			starts << pos
			if pos < value.len {
				// The match ends at the end of the value; the next one is the empty one there.
				lines << ''
				starts << value.len
			}
			return lines, starts
		}
		mut end := i + 1
		if value[i] == `\r` && end < value.len && value[end] == `\n` {
			end++
		} else if value[i] == 0xe2 {
			end = i + 3
		}
		lines << value[pos..end]
		starts << pos
		pos = end
	}
	return lines, starts
}

// ec_find_rule_id ports `ruleIdPattern.exec(line)` for
// new RegExp(`([\s,]|^)${escapeStringRegexp(ruleId)}(?:[\s,]|$)`, "u"): the UTF-16 index of the
// match, the length of its first group and the byte offset of the rule id in the line.
fn ec_find_rule_id(line string, rule_id string) ?(int, int, int) {
	runes := line.runes()
	id := rule_id.runes()
	mut utf16_index := 0
	mut byte_index := 0
	for p in 0 .. runes.len + 1 {
		// `[\s,]` first, then `^`.
		if p < runes.len && ec_is_delimiter(runes[p]) && ec_id_at(runes, id, p + 1) {
			return utf16_index, 1, byte_index + runes[p].str().len
		}
		if p == 0 && ec_id_at(runes, id, 0) {
			return 0, 0, 0
		}
		if p < runes.len {
			utf16_index += if runes[p] > 0xffff { 2 } else { 1 }
			byte_index += runes[p].str().len
		}
	}
	return none
}

fn ec_is_delimiter(r rune) bool {
	return r == `,` || is_js_space(r)
}

// ec_id_at tells whether the rule id is at `at`, followed by a delimiter or the end.
fn ec_id_at(runes []rune, id []rune, at int) bool {
	if at + id.len > runes.len {
		return false
	}
	for k in 0 .. id.len {
		if runes[at + k] != id[k] {
			return false
		}
	}
	after := at + id.len
	return after == runes.len || ec_is_delimiter(runes[after])
}

// ec_rule_id_location ports toRuleIdLocation: where the rule id is written in the comment, the
// comment's loc when it is not there, and the force location without a rule id.
fn ec_rule_id_location(comment EcComment, rule_id ?string) EcLoc {
	id := rule_id or { return ec_force_location(comment) }
	lines, starts := ec_value_lines(comment.value)
	for i, line in lines {
		index, group, at := ec_find_rule_id(line, id) or { continue }
		length := utf16_length_of(id)
		// The value starts after `//` or `/*`: 2 bytes.
		start_byte := comment.start + 2 + starts[i] + at
		if i == 0 {
			column := 2 + comment.column + index + group
			return EcLoc{
				line:       comment.line
				column:     column
				end_line:   comment.line
				end_column: column + length
				start_byte: start_byte
				end_byte:   start_byte + id.len
			}
		}
		return EcLoc{
			line:       comment.line + i
			column:     index + group
			end_line:   comment.line + i
			end_column: index + group + length
			start_byte: start_byte
			end_byte:   start_byte + id.len
		}
	}
	return ec_comment_location(comment)
}

// utf16_length_of is the length of a text in UTF-16 units.
fn utf16_length_of(s string) int {
	mut n := 0
	for r in s.runes() {
		n += if r > 0xffff { 2 } else { 1 }
	}
	return n
}

// ec_finding is a report at a loc.
fn ec_finding(loc EcLoc, message_id string, data map[string]string) Finding {
	return Finding{
		stmt:             Ident{
			start_byte: loc.start_byte
			end_byte:   loc.end_byte
		}
		message_id:       message_id
		data:             data
		line_loc:         true
		fixed_line:       loc.line
		fixed_column:     loc.column + 1
		fixed_end_line:   loc.end_line
		fixed_end_column: loc.end_column + 1
	}
}

// EcDirective is a directive comment as the plugin's parser reads it (parseDirectiveText):
// `description` is none without a ` -- ` in the comment.
struct EcDirective {
	kind        string
	value       string
	description ?string
	eslint      bool
	comment     EcComment
}

const ec_eslint_kinds = ['eslint', 'eslint-env', 'eslint-enable', 'eslint-disable',
	'eslint-disable-line', 'eslint-disable-next-line', 'exported', 'global', 'globals']

// ec_divide ports divideDirectiveComment: `value.split(/\s-{2,}\s/u)`, its first part trimmed and
// the second (up to the next separator) as the description.
fn ec_divide(value string) (string, ?string) {
	runes := value.runes()
	first_start, first_end := ec_separator(runes, 0) or { return js_trim(value), none }
	text := js_trim(runes[..first_start].string())
	second_start, _ := ec_separator(runes, first_end) or { runes.len, 0 }
	return text, js_trim(runes[first_end..second_start].string())
}

// ec_separator is the next match of /\s-{2,}\s/ from `from`: its start and its end.
fn ec_separator(runes []rune, from int) ?(int, int) {
	for i := from; i < runes.len; i++ {
		if !is_js_space(runes[i]) {
			continue
		}
		mut j := i + 1
		for j < runes.len && runes[j] == `-` {
			j++
		}
		if j - i > 2 && j < runes.len && is_js_space(runes[j]) {
			return i, j + 1
		}
	}
	return none
}

// ec_starts_with_directive tells whether the text starts with the directive and white space or
// its end after it.
fn ec_starts_with_directive(text string, directive string) bool {
	if !text.starts_with(directive) {
		return false
	}
	rest := text[directive.len..]
	return rest == '' || is_js_space(rest.runes()[0])
}

// ec_parse_directive_text ports parseDirectiveText: DIRECTIVE_PATTERN
// (/^(eslint(?:-env|-enable|-disable(?:(?:-next)?-line)?)?|exported|globals?)(?:\s|$)/u), then the
// additional directives in their order.
fn ec_parse_directive_text(value string, additional []string) ?EcDirective {
	text, description := ec_divide(value)
	mut kind := ''
	mut eslint := false
	mut found := false
	for label in ec_eslint_kinds {
		if ec_starts_with_directive(text, label) {
			kind = label
			eslint = true
			found = true
			break
		}
	}
	if !found {
		for directive in additional {
			if ec_starts_with_directive(text, directive) {
				kind = directive
				found = true
				break
			}
		}
	}
	if !found {
		return none
	}
	return EcDirective{
		kind:        kind
		value:       js_trim(text[kind.len..])
		description: description
		eslint:      eslint
	}
}

// ec_directive_comments ports getAllDirectiveCommentsFromAllComments with parseDirectiveComment:
// the directive comments of the file; a line comment only for `eslint-disable-line`,
// `eslint-disable-next-line` and the additional directives, and an `eslint-disable-line` only on
// one line.
fn (mut c Checker) ec_directive_comments(root C.TSNode, additional []string) []EcDirective {
	mut out := []EcDirective{}
	for comment in c.ec_comments(root) {
		parsed := ec_parse_directive_text(comment.value, additional) or { continue }
		line_supported := parsed.kind in additional
			|| parsed.kind in ['eslint-disable-line', 'eslint-disable-next-line']
		if comment.is_line && !line_supported {
			continue
		}
		if parsed.kind == 'eslint-disable-line' && comment.line != comment.end_line {
			continue
		}
		out << EcDirective{
			...parsed
			comment: comment
		}
	}
	return out
}

// EcArea is an area a disable directive makes (DisabledArea#areas): `rule_id` is none for every
// rule, and `end` none while no directive closes it. `comment` is the index of its comment.
struct EcArea {
	comment int
	rule_id ?string
	kind    string // 'block' or 'line'
	start   EcPos
mut:
	end ?EcPos
}

// EcPos is a place: a line from 1 and a column from 0 (-1 before the line).
struct EcPos {
	line   int
	column int
}

// ec_lte ports utils.lte.
fn ec_lte(a EcPos, b EcPos) bool {
	return a.line < b.line || (a.line == b.line && a.column <= b.column)
}

// EcRuleComment is a directive about a rule (or every rule): an `eslint-enable` that closes no
// area, or a disable of one already disabled there.
struct EcRuleComment {
	comment int
	rule_id ?string
}

// EcDisabledArea ports DisabledAreaForLanguagePlugin. `related_comments` are the keys of
// numberOfRelatedDisableDirectives, in order, and `related_counts` their values.
struct EcDisabledArea {
mut:
	comments                     []EcComment
	areas                        []EcArea
	duplicate_disable_directives []EcRuleComment
	unused_enable_directives     []EcRuleComment
	related_comments             []int
	related_counts               []int
}

fn ec_same_rule(a ?string, b ?string) bool {
	if x := a {
		if y := b {
			return x == y
		}
		return false
	}
	return b == none
}

// get_area ports _getArea.
fn (d &EcDisabledArea) get_area(rule_id ?string, location EcPos) bool {
	for i := d.areas.len - 1; i >= 0; i-- {
		area := d.areas[i]
		if (area.rule_id == none || ec_same_rule(area.rule_id, rule_id))
			&& ec_lte(area.start, location) {
			if end := area.end {
				if !ec_lte(location, end) {
					continue
				}
			}
			return true
		}
	}
	return false
}

// disable ports _disable.
fn (mut d EcDisabledArea) disable(comment int, location EcPos, rule_ids []string, has_ids bool, kind string) {
	if has_ids {
		for id in rule_ids {
			if d.get_area(id, location) {
				d.duplicate_disable_directives << EcRuleComment{comment, id}
			}
			d.areas << EcArea{
				comment: comment
				rule_id: id
				kind:    kind
				start:   location
			}
		}
	} else {
		if d.get_area(none, location) {
			d.duplicate_disable_directives << EcRuleComment{comment, none}
		}
		d.areas << EcArea{
			comment: comment
			kind:    kind
			start:   location
		}
	}
}

// enable ports _enable.
fn (mut d EcDisabledArea) enable(comment int, location EcPos, rule_ids []string, has_ids bool, kind string) {
	mut related := []int{}
	if has_ids {
		for id in rule_ids {
			mut used := false
			for i := d.areas.len - 1; i >= 0; i-- {
				area := d.areas[i]
				if area.end == none && area.kind == kind && ec_same_rule(area.rule_id, id) {
					if area.comment !in related {
						related << area.comment
					}
					d.areas[i].end = location
					used = true
				}
			}
			if !used {
				d.unused_enable_directives << EcRuleComment{comment, id}
			}
		}
	} else {
		mut used := false
		for i := d.areas.len - 1; i >= 0; i-- {
			area := d.areas[i]
			if area.end == none && area.kind == kind {
				if area.comment !in related {
					related << area.comment
				}
				d.areas[i].end = location
				used = true
			}
		}
		if !used {
			d.unused_enable_directives << EcRuleComment{comment, none}
		}
	}
	// A Map: setting a key again keeps its place.
	at := d.related_comments.index(comment)
	if at >= 0 {
		d.related_counts[at] = related.len
	} else {
		d.related_comments << comment
		d.related_counts << related.len
	}
}

// ec_split_rule_ids ports `value.split(/[\s,]+/u)`.
fn ec_split_rule_ids(value string) []string {
	mut out := []string{}
	mut current := []rune{}
	mut in_delimiter := false
	for r in value.runes() {
		if ec_is_delimiter(r) {
			if !in_delimiter {
				out << current.string()
				current.clear()
				in_delimiter = true
			}
			continue
		}
		in_delimiter = false
		current << r
	}
	out << current.string()
	return out
}

// ec_disabled_area ports getDisabledArea: the directives of sourceCode.getDisableDirectives() of
// ESLint 10.15.0 (getInlineConfigNodes with ConfigCommentParser#parseDirective: the justification
// after the first ` -- ` left out; a line comment only for `eslint-disable-line` and
// `eslint-disable-next-line`; an `eslint-disable-line` on more than one line is not a directive),
// whatever rules they name.
fn (mut c Checker) ec_disabled_area(root C.TSNode) EcDisabledArea {
	mut d := EcDisabledArea{
		comments: c.ec_comments(root)
	}
	for i, comment in d.comments {
		label, value, _ := parse_directive(comment.value) or { continue }
		if comment.is_line && label !in ['eslint-disable-line', 'eslint-disable-next-line'] {
			continue
		}
		if label == 'eslint-disable-line' && comment.line != comment.end_line {
			continue
		}
		has_ids := value != ''
		rule_ids := if has_ids { ec_split_rule_ids(value) } else { []string{} }
		match label {
			'eslint-disable' {
				d.disable(i, EcPos{comment.line, comment.column}, rule_ids, has_ids, 'block')
			}
			'eslint-enable' {
				d.enable(i, EcPos{comment.line, comment.column}, rule_ids, has_ids, 'block')
			}
			'eslint-disable-line' {
				d.disable(i, EcPos{comment.line, 0}, rule_ids, has_ids, 'line')
				d.enable(i, EcPos{comment.line + 1, -1}, rule_ids, has_ids, 'line')
			}
			'eslint-disable-next-line' {
				d.disable(i, EcPos{comment.line + 1, 0}, rule_ids, has_ids, 'line')
				d.enable(i, EcPos{comment.line + 2, -1}, rule_ids, has_ids, 'line')
			}
			else {}
		}
	}
	return d
}

// The `ignore` package 7.0.14 (node-ignore), as no-restricted-disable uses it: `ignore()`
// (ignoreCase, the default), `add(pattern)` and `ignores(path)`. Each pattern becomes a regular
// expression the way the package makes it (makeRegexPrefix, then _make for the mode `regex`), run
// by jsregexp; the texts are UTF-16 units, as in JavaScript.

const ec_placeholder = u16(0)
const ec_trailing_wildcard = u16(0xe000)
const ec_trailing_doublestar = u16(0xe001)

// EcIgnoreRule is an IgnoreRule.
struct EcIgnoreRule {
	negative      bool
	basename_only bool
	regex         jsregexp.JsRegex
}

// EcIgnore is an Ignore with its RuleManager.
struct EcIgnore {
mut:
	rules          []EcIgnoreRule
	basename_count int
}

fn ec_u(s string) []u16 {
	return utf16_units(s)
}

fn ec_has(units []u16, needle string) bool {
	n := ec_u(needle)
	if n.len == 0 {
		return true
	}
	for i := 0; i + n.len <= units.len; i++ {
		if units[i..i + n.len] == n {
			return true
		}
	}
	return false
}

// EcMatch is a match of a regular expression: its start and end, and its groups (empty when the
// group did not take part).
struct EcMatch {
	start  int
	end    int
	groups [][]u16
}

fn ec_group(m EcMatch, i int) []u16 {
	return if i < m.groups.len { m.groups[i] } else { []u16{} }
}

// ec_replace ports `text.replace(regex, replacer)`: every match with `global`, else the first.
fn ec_replace(text []u16, source string, global bool, replacer fn (EcMatch, []u16) []u16) ![]u16 {
	re := jsregexp.js_regex_new(source, '')!
	mut out := []u16{}
	mut pos := 0
	mut last := 0
	for pos <= text.len {
		found, start, end, slots := re.exec(text, pos)!
		if !found {
			break
		}
		mut groups := [][]u16{}
		for g := 1; 2 * g + 1 < slots.len; g++ {
			if slots[2 * g] < 0 {
				groups << []u16{}
			} else {
				groups << text[slots[2 * g]..slots[2 * g + 1]].clone()
			}
		}
		out << text[last..start]
		out << replacer(EcMatch{start, end, groups}, text)
		last = end
		if !global {
			break
		}
		pos = if end == start { end + 1 } else { end }
	}
	out << text[last..]
	return out
}

fn ec_test(source string, text []u16) !bool {
	re := jsregexp.js_regex_new(source, '')!
	return re.test(text)!
}

fn ec_escape_member(ch u16) []u16 {
	return if ch in ec_u('\\]^-[') { [u16(`\\`), ch] } else { [ch] }
}

// ec_class_source ports classSource.
fn ec_class_source(negated bool, body []u16) ![]u16 {
	if negated {
		mut out := ec_u('[^\\/')
		out << body
		out << u16(`]`)
		return out
	}
	mut source := [u16(`[`)]
	source << body
	source << u16(`]`)
	re := jsregexp.js_regex_new(utf16_to_string(source), '')!
	if re.test(ec_u('/'))! {
		mut out := ec_u('(?!\\/)')
		out << source
		return out
	}
	return source
}

const ec_posix_classes = {
	'alnum':  '0-9A-Za-z'
	'alpha':  'A-Za-z'
	'blank':  ' \\t'
	'cntrl':  '\\x00-\\x1f\\x7f'
	'digit':  '0-9'
	'graph':  '!-.0-~'
	'lower':  'a-z'
	'print':  ' -.0-~'
	'punct':  '!-.:-@\\[-`{-~'
	'space':  ' \\t\\n\\r'
	'upper':  'A-Z'
	'xdigit': '0-9A-Fa-f'
}

// ec_scan_bracket ports scanBracket: whether a bracket expression starts at `start`, its end and
// its source.
fn ec_scan_bracket(pattern []u16, start int) !(bool, int, []u16) {
	length := pattern.len
	mut index := start + 1
	mut negated := false
	if index < length && (pattern[index] == `!` || pattern[index] == `^`) {
		negated = true
		index++
	}
	mut body := []u16{}
	mut prev := []u16{}
	for {
		if index >= length {
			return false, 0, []u16{}
		}
		ch := pattern[index]
		if ch == `\\` {
			if index + 1 >= length {
				return false, 0, []u16{}
			}
			escaped := pattern[index + 1]
			body << ec_escape_member(escaped)
			prev = [escaped]
			index++
		} else if ch == `-` && prev.len > 0 && index + 1 < length && pattern[index + 1] != `]` {
			index++
			mut to := pattern[index]
			mut has_to := true
			if to == `\\` {
				index++
				if index < length {
					to = pattern[index]
				} else {
					has_to = false
				}
			}
			// `prev <= to`, two strings (`undefined` past the end of the pattern: false).
			if has_to && prev[0] <= to {
				body << u16(`-`)
				body << ec_escape_member(to)
			}
			prev = []u16{}
		} else if ch == `[` && index + 1 < length && pattern[index + 1] == `:` {
			name_start := index + 2
			mut end := name_start
			for end < length && pattern[end] != `]` {
				end++
			}
			if end == length {
				return false, 0, []u16{}
			}
			if end > name_start && pattern[end - 1] == `:` {
				name := utf16_to_string(pattern[name_start..end - 1])
				class := ec_posix_classes[name] or { return false, 0, []u16{} }
				body << ec_u(class)
				prev = []u16{}
				index = end
			} else {
				body << ec_escape_member(`[`)
				prev = [u16(`[`)]
				index = name_start - 2
			}
		} else {
			body << ec_escape_member(ch)
			prev = [ch]
		}
		index++
		if index < length && pattern[index] == `]` {
			return true, index, ec_class_source(negated, body)!
		}
	}
	return false, 0, []u16{}
}

fn ec_is_reserved(ch u16) bool {
	return ch == ec_placeholder || ch == ec_trailing_wildcard || ch == ec_trailing_doublestar
}

// ec_hold ports `hold` of extractBrackets: a placeholder for a source.
fn ec_hold(mut sources [][]u16, mut out []u16, source []u16) {
	out << ec_placeholder
	out << ec_u(sources.len.str())
	out << ec_placeholder
	sources << source
}

// ec_extract_brackets ports extractBrackets: the pattern with a placeholder for each escaped
// character and bracket expression, and their sources.
fn ec_extract_brackets(pattern []u16) !([]u16, [][]u16) {
	mut sources := [][]u16{}
	mut out := []u16{}
	length := pattern.len
	mut index := 0
	for index < length {
		ch := pattern[index]
		if ch == `\\` {
			if index + 1 >= length || (pattern[index + 1] == `/` && index + 2 == length) {
				ec_hold(mut sources, mut out, ec_u('[]'))
			} else {
				escaped := pattern[index + 1]
				if escaped == `*` || escaped == `[` || escaped == ` ` {
					out << pattern[index..index + 2]
				} else if escaped in ec_u('.*+?()[]{}^$|\\/') {
					ec_hold(mut sources, mut out, [u16(`\\`), escaped])
				} else if ec_is_reserved(escaped) {
					ec_hold(mut sources, mut out, [u16(`[`), escaped, u16(`]`)])
				} else {
					ec_hold(mut sources, mut out, [escaped])
				}
			}
			index += 2
		} else if ec_is_reserved(ch) {
			ec_hold(mut sources, mut out, [u16(`[`), ch, u16(`]`)])
			index++
		} else if ch == `[` {
			ok, end, source := ec_scan_bracket(pattern, index)!
			if !ok {
				ec_hold(mut sources, mut out, ec_u('[]'))
				index = length
			} else {
				ec_hold(mut sources, mut out, source)
				index = end + 1
			}
		} else {
			out << ch
			index++
		}
	}
	return out, sources
}

fn ec_backslash_space(m EcMatch, _ []u16) []u16 {
	run := ec_group(m, 0)
	if ec_group(m, 1).len > 0 {
		mut out := run[..run.len - run.len % 2].clone()
		out << u16(` `)
		return out
	}
	return run
}

fn ec_globstar_three(m EcMatch, _ []u16) []u16 {
	mut out := ec_group(m, 0)
	out << ec_u('**')
	return out
}

fn ec_escape_meta(m EcMatch, text []u16) []u16 {
	mut out := [u16(`\\`)]
	out << text[m.start..m.end]
	return out
}

fn ec_question(_ EcMatch, _ []u16) []u16 {
	return ec_u('[^/]')
}

fn ec_caret(_ EcMatch, _ []u16) []u16 {
	return ec_u('^')
}

fn ec_slash(_ EcMatch, _ []u16) []u16 {
	return ec_u('\\/')
}

fn ec_leading_globstar(_ EcMatch, _ []u16) []u16 {
	return ec_u('^(?:.*\\/)?')
}

fn ec_middle_globstar(m EcMatch, text []u16) []u16 {
	index := m.start
	if index + 6 < text.len {
		return if text[index + 6..] == ec_u('\\/') {
			ec_u('(?:\\/[^\\/]+)+')
		} else {
			ec_u('(?:\\/[^\\/]+)*')
		}
	}
	mut out := ec_u('\\/')
	out << ec_trailing_doublestar
	return out
}

fn ec_middle_wildcard(m EcMatch, _ []u16) []u16 {
	mut out := ec_group(m, 0)
	out << ec_u('[^\\/]*')
	return out
}

fn ec_end_wildcard(m EcMatch, text []u16) []u16 {
	if ec_group(m, 1).len == 0 {
		mut out := ec_group(m, 0)
		out << ec_trailing_wildcard
		return out
	}
	return text[m.start..m.end]
}

fn ec_backslash(_ EcMatch, _ []u16) []u16 {
	return ec_u('\\')
}

fn ec_bracket_range(m EcMatch, _ []u16) []u16 {
	mut out := ec_u('\\[')
	out << ec_group(m, 0)
	out << ec_group(m, 1)
	return out
}

fn ec_trailing_wildcard_source(m EcMatch, _ []u16) []u16 {
	p1 := ec_group(m, 0)
	mut out := []u16{}
	if p1.len > 0 {
		out << p1
		out << ec_u('[^/]+')
	} else {
		out << ec_u('[^/]*')
	}
	out << ec_u('(?=$|\\/$)')
	return out
}

fn ec_trailing_doublestar_source(_ EcMatch, _ []u16) []u16 {
	return ec_u('.+(?=$|\\/$)')
}

// EcReplacer is one of REPLACERS that is a regular expression: its source, whether it is global,
// the text the source must have for it to run (`required`), and its replacer.
struct EcReplacer {
	source   string
	global   bool
	required string
	replacer fn (EcMatch, []u16) []u16 = unsafe { nil }
}

// ec_replace_with runs a replacer as makeRegexPrefix does: when the text has `required` and the
// regular expression matches it.
fn ec_replace_with(s []u16, r EcReplacer) ![]u16 {
	if r.required != '' && !ec_has(s, r.required) {
		return s
	}
	if !ec_test(r.source, s)! {
		return s
	}
	return ec_replace(s, r.source, r.global, r.replacer)!
}

// ec_make_regex_prefix ports makeRegexPrefix and its REPLACERS.
fn ec_make_regex_prefix(original []u16) ![]u16 {
	mut pattern := original.clone()
	// REGEX_ANCHORED_GLOBSTAR: /^\/\*{2,}$/
	if pattern.len >= 3 && pattern[0] == `/` && pattern[1..].all(it == `*`) {
		pattern = ec_u('**')
	}
	source, sources := ec_extract_brackets(pattern)!
	mut s := source.clone()
	s = ec_replace_with(s, EcReplacer{r'(\\+)( ?)', true, '\\ ', ec_backslash_space})!
	s = ec_replace_with(s, EcReplacer{r'(^|\/)\*{3,}(?=\/|$)', true, '*', ec_globstar_three})!
	s = ec_replace_with(s, EcReplacer{r'[\\$.|*+(){^]', true, '', ec_escape_meta})!
	s = ec_replace_with(s, EcReplacer{r'(?!\\)\?', true, '?', ec_question})!
	s = ec_replace_with(s, EcReplacer{r'^\/', false, '/', ec_caret})!
	s = ec_replace_with(s, EcReplacer{r'\/', true, '/', ec_slash})!
	s = ec_replace_with(s, EcReplacer{r'^\^*(?:\\\*\\\*\\\/)+', false, '*', ec_leading_globstar})!
	// The start, or after a slash when the pattern has no slash but at its end
	// (REGEX_INNER_SLASH: /\/(?!$)/).
	if s.len > 0 && s[0] != `^` {
		mut inner := false
		for i, ch in pattern {
			if ch == `/` && i != pattern.len - 1 {
				inner = true
				break
			}
		}
		mut anchored := ec_u(if inner { '^' } else { '(?:^|\\/)' })
		anchored << s
		s = anchored.clone()
	}
	s = ec_replace_with(s, EcReplacer{r'\\\/\\\*\\\*(?=\\\/|$)', true, '*', ec_middle_globstar})!
	s = ec_replace_with(s, EcReplacer{r'(^|[^\\]+)(\\\*)+(?=.+)', true, '*', ec_middle_wildcard})!
	s = ec_replace_with(s, EcReplacer{r'(^|[^\\])((?:\\\\)*)\\\*$', false, '*', ec_end_wildcard})!
	s = ec_replace_with(s, EcReplacer{r'\\\\\\(?=[$.|*+(){^])', true, '\\\\', ec_backslash})!
	s = ec_replace_with(s, EcReplacer{r'\\\\', true, '\\\\', ec_backslash})!
	s = ec_replace_with(s, EcReplacer{r'\\\[([^\]/]*?)($|\])', true, '[', ec_bracket_range})!
	// The end.
	if s.len > 0 {
		last := s[s.len - 1]
		if last != ec_trailing_wildcard && last != ec_trailing_doublestar {
			s << ec_u(if last == `/` { '$' } else { '(?=$|\\/$)' })
		}
	}
	if sources.len == 0 {
		return s
	}
	// REGEX_RESTORE_PLACEHOLDER: /\u0000(\d+)\u0000/g
	return ec_replace(s, r'\u0000(\d+)\u0000', true, fn [sources] (m EcMatch, _ []u16) []u16 {
		return sources[utf16_to_string(ec_group(m, 0)).int()]
	})!
}

// EcPinToken is a token of pinWildcards: a wildcard, a single, or a boundary.
struct EcPinToken {
	wildcard    bool
	is_boundary bool
	text        []u16
}

const ec_wildcard = '[^\\/]*'

// ec_pin_wildcards ports pinWildcards: each wildcard but the last of a run stops before the
// separator that follows it.
fn ec_pin_wildcards(source []u16) []u16 {
	wildcard := ec_u(ec_wildcard)
	if !ec_has(source, ec_wildcard) {
		return source
	}
	mut tokens := []EcPinToken{}
	length := source.len
	mut index := 0
	for index < length {
		ch := source[index]
		if index + wildcard.len <= length && source[index..index + wildcard.len] == wildcard {
			tokens << EcPinToken{
				wildcard: true
			}
			index += wildcard.len
		} else if ch == `[` {
			mut end := index + 1
			if end < length && source[end] == `^` {
				end++
			}
			if end < length && source[end] == `]` {
				end++
			}
			for end < length && source[end] != `]` {
				end += if source[end] == `\\` { 2 } else { 1 }
			}
			end++
			tokens << EcPinToken{
				text: source[index..ec_min(end, length)]
			}
			index = end
		} else if ch == `\\` {
			tokens << EcPinToken{
				text: source[index..ec_min(index + 2, length)]
			}
			index += 2
		} else if ch == `(` {
			mut depth := 0
			mut end := index
			for {
				if end < length && source[end] == `\\` {
					end++
				} else if end < length && source[end] == `(` {
					depth++
				} else if end < length && source[end] == `)` {
					depth--
				}
				end++
				if !(end < length && depth > 0) {
					break
				}
			}
			if end < length && source[end] in ec_u('*+?') {
				end++
			}
			tokens << EcPinToken{
				is_boundary: true
				text:        source[index..ec_min(end, length)]
			}
			index = end
		} else if ch == `^` || ch == `$` {
			tokens << EcPinToken{
				is_boundary: true
				text:        [ch]
			}
			index++
		} else {
			tokens << EcPinToken{
				text: [ch]
			}
			index++
		}
	}
	mut out := []u16{}
	mut run := []EcPinToken{}
	for token in tokens {
		if token.is_boundary {
			ec_flush(mut out, run)
			run.clear()
			out << token.text
			continue
		}
		run << token
	}
	ec_flush(mut out, run)
	return out
}

fn ec_min(a int, b int) int {
	return if a < b { a } else { b }
}

// ec_flush ports `flush` of pinWildcards.
fn ec_flush(mut out []u16, run []EcPinToken) {
	mut last_wildcard := -1
	for at, token in run {
		if token.wildcard {
			last_wildcard = at
		}
	}
	for at, token in run {
		if !token.wildcard {
			out << token.text
			continue
		}
		if at == last_wildcard {
			out << ec_u(ec_wildcard)
			continue
		}
		// separatorAfter: the singles up to the next wildcard.
		mut separator := []u16{}
		for index := at + 1; index < run.len && !run[index].wildcard; index++ {
			separator << run[index].text
		}
		out << ec_u('(?:(?!')
		out << separator
		out << ec_u(')[^\\/])*')
	}
}

// ec_trim_end ports trimEnd.
fn ec_trim_end(body []u16) []u16 {
	mut end := body.len
	for end > 0 && (body[end - 1] == `\r` || body[end - 1] == `\n`) {
		end--
	}
	line_end := end
	for end > 0 && body[end - 1] == ` ` {
		end--
	}
	if end == line_end {
		return body[..end].clone()
	}
	mut backslashes := 0
	for backslashes < end && body[end - backslashes - 1] == `\\` {
		backslashes++
	}
	if backslashes % 2 == 1 {
		mut out := body[..end - 1].clone()
		out << u16(` `)
		return out
	}
	return body[..end].clone()
}

// add ports Ignore#add with a string: its lines (split at /\r?\n/, the empty ones left out), each a
// rule (checkPattern, createRule).
fn (mut ig EcIgnore) add(pattern string) ! {
	for line in pattern.split('\n') {
		text := if line.ends_with('\r') { line[..line.len - 1] } else { line }
		if text == '' {
			continue
		}
		units := ec_u(text)
		// REGEX_INVALID_TRAILING_BACKSLASH: /(?:[^\\]|^)\\$/
		if units[units.len - 1] == `\\` && (units.len == 1 || units[units.len - 2] != `\\`) {
			continue
		}
		mut body := if units[0] == 0xfeff { units[1..].clone() } else { units.clone() }
		if body.len > 0 && body[0] == `#` {
			continue
		}
		mut negative := false
		if body.len > 0 && body[0] == `!` {
			negative = true
			body = body[1..].clone()
		}
		if body.len > 0 && body[body.len - 1] in [u16(` `), `\r`, `\n`] {
			body = ec_trim_end(body)
		}
		if body.len == 0 {
			continue
		}
		// /^\\!/ and /^\\#/
		if body.len >= 2 && body[0] == `\\` && body[1] in [u16(`!`), `#`] {
			body = body[1..].clone()
		}
		prefix := ec_make_regex_prefix(body)!
		// _make for MODE_IGNORE: REGEX_REPLACE_TRAILING_WILDCARD (/(^|\\\/)?$/), then
		// REGEX_REPLACE_TRAILING_DOUBLESTAR (/$/).
		mut source := ec_replace(prefix, r'(^|\\\/)?$', false, ec_trailing_wildcard_source)!
		source = ec_replace(source, r'$', false, ec_trailing_doublestar_source)!
		regex := jsregexp.js_regex_new(utf16_to_string(ec_pin_wildcards(source)), 'i')!
		slash := body.index(`/`)
		basename_only := slash < 0 || slash == body.len - 1
		ig.rules << EcIgnoreRule{
			negative:      negative
			basename_only: basename_only
			regex:         regex
		}
		if basename_only {
			ig.basename_count++
		}
	}
}

// ec_basename_of ports basenameOf.
fn ec_basename_of(path []u16) []u16 {
	end := path.len - 1
	from := if path[end] == `/` { end - 1 } else { end }
	for i := from; i >= 0; i-- {
		if path[i] == `/` {
			return path[i + 1..]
		}
	}
	return path
}

// ec_parent_of ports parentOf.
fn ec_parent_of(path []u16) []u16 {
	if path[0] == `/` || ec_has(path, '//') {
		mut slices := [][]u16{}
		mut current := []u16{}
		for ch in path {
			if ch == `/` {
				if current.len > 0 {
					slices << current.clone()
				}
				current.clear()
			} else {
				current << ch
			}
		}
		if current.len > 0 {
			slices << current.clone()
		}
		if slices.len > 0 {
			slices.pop()
		}
		mut out := []u16{}
		for i, slice in slices {
			if i > 0 {
				out << u16(`/`)
			}
			out << slice
		}
		if slices.len > 0 {
			out << u16(`/`)
		}
		return out
	}
	end := path.len - 1
	from := if path[end] == `/` { end - 1 } else { end }
	for i := from; i >= 0; i-- {
		if path[i] == `/` {
			return path[..i + 1]
		}
	}
	return []u16{}
}

// test ports RuleManager#test for the mode `regex`: whether the path is ignored, and whether it is
// unignored.
fn (ig &EcIgnore) test(path []u16) !(bool, bool) {
	shortcut := ig.basename_count * 2 >= ig.rules.len
	basename := if shortcut { ec_basename_of(path) } else { path }
	for i := ig.rules.len - 1; i >= 0; i-- {
		rule := ig.rules[i]
		if rule.regex.test(if shortcut && rule.basename_only { basename } else { path })! {
			return !rule.negative, rule.negative
		}
	}
	return false, false
}

// t ports Ignore#_t: a path whose parent directory is ignored is ignored.
fn (ig &EcIgnore) t(path []u16) !(bool, bool) {
	parent := ec_parent_of(path)
	if parent.len > 0 {
		ignored, unignored := ig.t(parent)!
		if ignored {
			return ignored, unignored
		}
	}
	return ig.test(path)!
}

// ignores ports Ignore#ignores, with checkPath: a path that is empty or not relative throws, as
// in the package (and ESLint stops on the error).
fn (ig &EcIgnore) ignores(path string) !bool {
	units := ec_u(path)
	if units.len == 0 {
		return error('TypeError: path must not be empty')
	}
	// isNotRelative
	not_relative := units[0] == `/` || (units[0] == `.` && (units.len == 1 || units[1] == `/`
		|| (units[1] == `.` && (units.len == 2 || units[2] == `/`))))
	if not_relative {
		return error('RangeError: path should be a `path.relative()`d string, but got "${path}"')
	}
	ignored, _ := ig.t(units)!
	return ignored
}
