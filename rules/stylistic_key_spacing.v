module rules

import estree
import math
import time
import x.json2

// Port of the `@stylistic/key-spacing` rule of @stylistic/eslint-plugin 5.10.0, with its options
// (`beforeColon`, `afterColon`, `mode`, `align` as a string or an object, `singleLine`,
// `multiLine` and `ignoredNodes`) and its fixes: the spaces around the colon of the properties of
// objects and object patterns and of import attributes, and before and after the type annotation
// of the properties of type literals, interfaces and classes.

const sks_messages = {
	'extraKey':     "Extra space after {{computed}}key '{{key}}'."
	'extraValue':   "Extra space before value for {{computed}}key '{{key}}'."
	'missingKey':   "Missing space after {{computed}}key '{{key}}'."
	'missingValue': "Missing space before value for {{computed}}key '{{key}}'."
}

// SksAlign is an alignment configuration of initOptions. `on` is '' and the numbers NaN for what
// is `undefined` (an `align` object of `multiLine` is taken as it is given).
struct SksAlign {
	on     string
	mode   string
	before f64
	after  f64
}

// SksLine is the result of initOptionProperty: beforeColon and afterColon are numbers (0 or 1).
struct SksLine {
	mode      string
	before    f64
	after     f64
	has_align bool
	align     SksAlign
}

struct SksOptions {
	// raw is the option object, which the listeners of type annotations read themselves.
	raw       map[string]json2.Any
	multi     SksLine
	single    SksLine
	has_align bool
	align     SksAlign
	ignored   []string
}

fn sks_options(given []json2.Any) !SksOptions {
	options := sty_options(given, [json2.Any(map[string]json2.Any{})])
	raw := sty_option_object(options, 0)
	mut ignored := []string{}
	if value := raw['ignoredNodes'] {
		if value is []json2.Any {
			for item in value {
				ignored << item.str()
			}
		}
	}
	multi_from := sty_option_object([raw['multiLine'] or { json2.Any(raw) }], 0)
	single_from := sty_option_object([raw['singleLine'] or { json2.Any(raw) }], 0)
	multi := sks_init_option_property(multi_from)
	single := sks_init_option_property(single_from)
	if align := raw['align'] {
		if align is map[string]json2.Any {
			from := sks_init_option_property(align)
			return SksOptions{
				raw:       raw
				multi:     multi
				single:    single
				has_align: true
				align:     SksAlign{
					on:     sks_truthy_string(align, 'on') or { 'colon' }
					mode:   sks_truthy_string(align, 'mode') or { 'strict' }
					before: from.before
					after:  from.after
				}
				ignored:   ignored
			}
		}
	}
	return SksOptions{
		raw:       raw
		multi:     multi
		single:    single
		has_align: multi.has_align
		align:     SksAlign{
			on:     multi.align.on
			mode:   if multi.align.mode != '' { multi.align.mode } else { multi.mode }
			before: multi.align.before
			after:  multi.align.after
		}
		ignored:   ignored
	}
}

// sks_init_option_property ports initOptionProperty.
fn sks_init_option_property(from map[string]json2.Any) SksLine {
	mode := sks_truthy_string(from, 'mode') or { 'strict' }
	before := sks_number(from, 'beforeColon', 0)
	after := sks_number(from, 'afterColon', 1)
	align := from['align'] or { return SksLine{
		mode:   mode
		before: before
		after:  after
	} }
	if align is map[string]json2.Any {
		return SksLine{
			mode:      mode
			before:    before
			after:     after
			has_align: true
			align:     SksAlign{
				on:     sks_truthy_string(align, 'on') or { '' }
				mode:   sks_truthy_string(align, 'mode') or { '' }
				before: sks_number(align, 'beforeColon', math.nan())
				after:  sks_number(align, 'afterColon', math.nan())
			}
		}
	}
	return SksLine{
		mode:      mode
		before:    before
		after:     after
		has_align: true
		align:     SksAlign{
			on:     align.str()
			mode:   mode
			before: before
			after:  after
		}
	}
}

// sks_truthy_string is `object[key]` when it is a non-empty string.
fn sks_truthy_string(object map[string]json2.Any, key string) ?string {
	value := object[key] or { return none }
	if value is string && value != '' {
		return value
	}
	return none
}

// sks_number is `+object[key]` for a boolean, `fallback` when it is not given.
fn sks_number(object map[string]json2.Any, key string, fallback f64) f64 {
	value := object[key] or { return fallback }
	if value is bool {
		return if value { 1 } else { 0 }
	}
	return fallback
}

// sks_raw_bool is `object[key] ?? fallback` for a boolean option.
fn sks_raw_bool(object map[string]json2.Any, key string, fallback bool) bool {
	return sty_option_bool(object, key) or { fallback }
}

// sks_raw_string is `object[key]` when it is a string.
fn sks_raw_string(object map[string]json2.Any, key string) ?string {
	value := object[key] or { return none }
	if value is string {
		return value
	}
	return none
}

// sks_raw_object is `object[key]` when it is an object.
fn sks_raw_object(object map[string]json2.Any, key string) ?map[string]json2.Any {
	value := object[key] or { return none }
	if value is map[string]json2.Any {
		return value
	}
	return none
}

struct SksCtx {
	t       &estree.EsTree
	tokens  &SourceTokens
	options SksOptions
}

fn (mut c Checker) lint_stylistic_key_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sks_options(c.rule_options(stylistic_key_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	ctx := SksCtx{
		t:       t
		tokens:  c.un_tokens(t)
		options: options
	}
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		typ := t.typ(node)
		if typ in [.ts_type_literal, .ts_interface_body, .class_body] {
			stats.checked++
			c.sks_validate_body(ctx, node, mut findings)
			continue
		}
		if options.has_align {
			match typ {
				.object_expression {
					stats.checked++
					if 'ObjectExpression' in options.ignored {
						continue
					}
					properties := t.list(node, .properties) or { []int{} }
					if sks_is_single_line(t, node) {
						c.sks_verify_list_spacing(ctx, properties.filter(sks_is_key_value(t, it)),
							options.single, mut findings)
					} else {
						c.sks_verify_alignment(ctx, properties, mut findings)
					}
				}
				.import_declaration, .export_named_declaration, .export_all_declaration {
					stats.checked++
					c.sks_verify_import_attributes(ctx, node, mut findings)
				}
				else {}
			}
			continue
		}
		match typ {
			.property {
				stats.checked++
				parent := t.nodes[node].parent
				line := if sks_is_single_line(t, parent) { options.single } else { options.multi }
				c.sks_verify_spacing(ctx, node, line.before, line.after, line.mode, mut findings)
			}
			.import_attribute {
				stats.checked++
				parent := t.nodes[node].parent
				line := if c.sks_single_line_import_attributes(ctx, parent) {
					options.single
				} else {
					options.multi
				}
				c.sks_verify_spacing(ctx, node, line.before, line.after, line.mode, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sks_is_single_line ports isSingleLine: the node starts and ends on the same line.
fn sks_is_single_line(t &estree.EsTree, node int) bool {
	return sty_same_line_offsets(t, t.nodes[node].start, t.nodes[node].end)
}

// sks_single_line_import_attributes ports isSingleLineImportAttributes for a declaration.
fn (c &Checker) sks_single_line_import_attributes(ctx SksCtx, node int) bool {
	attributes := ctx.t.list(node, .attributes) or { return false }
	if attributes.len == 0 {
		return false
	}
	opening := c.sks_token_before(ctx.tokens, ctx.t.nodes[attributes[0]].start, '{') or {
		return false
	}
	closing := c.sks_token_after(ctx.tokens, ctx.t.nodes[attributes.last()].end, '}') or {
		return false
	}
	return sty_same_line(ctx.t, closing, opening)
}

// sks_token_before ports getTokenBefore(offset, is<punctuator>Token).
fn (c &Checker) sks_token_before(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset) - 1; i >= 0; i-- {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

// sks_token_after ports getTokenAfter(what ends at offset, is<punctuator>Token).
fn (c &Checker) sks_token_after(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset); i < tokens.tokens.len; i++ {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

// sks_is_key_value ports isKeyValueProperty.
fn sks_is_key_value(t &estree.EsTree, property int) bool {
	typ := t.typ(property)
	if typ == .import_attribute {
		return true
	}
	return !((t.flag(property, .method) or { false }) || (t.flag(property, .shorthand) or { false })
		|| (t.string_of(property, .kind) or { 'init' }) != 'init' || typ != .property)
}

// sks_next_colon ports getNextColon: the first `:` after the node.
fn (c &Checker) sks_next_colon(ctx SksCtx, node int) ?SourceToken {
	return c.sks_token_after(ctx.tokens, ctx.t.nodes[node].end, ':')
}

// sks_last_token_before_colon ports getLastTokenBeforeColon.
fn (c &Checker) sks_last_token_before_colon(ctx SksCtx, node int) ?SourceToken {
	colon := c.sks_next_colon(ctx, node)?
	return ctx.tokens.before(colon.start, false)
}

// sks_line ports `loc.start.line` / `loc.end.line` of an offset.
fn sks_line(t &estree.EsTree, offset int) int {
	line, _ := t.line_column(offset)
	return line
}

// sks_continues_property_group ports continuesPropertyGroup.
fn (c &Checker) sks_continues_property_group(ctx SksCtx, last_member int, candidate int) bool {
	t := ctx.t
	group_end_line := sks_line(t, t.nodes[last_member].start)
	mut candidate_start := t.nodes[candidate].start
	if sks_is_key_value(t, candidate) {
		key := t.node(candidate, .key) or { -1 }
		if key >= 0 {
			colon := c.sks_next_colon(ctx, key) or { return false }
			after := ctx.tokens.after(colon.end, false) or { return false }
			candidate_start = after.start
		}
	}
	candidate_line := sks_line(t, candidate_start)
	if candidate_line - group_end_line <= 1 {
		return true
	}
	return sks_comments_join(t, ctx.tokens.comments_before(t.nodes[candidate].start), group_end_line,
		candidate_line)
}

// sks_comments_join is the check of the leading comments of continuesPropertyGroup and
// continuesAlignGroup: the first one is adjacent to the end of the group, the last one to the
// candidate, and each one to the next.
fn sks_comments_join(t &estree.EsTree, comments []SourceToken, group_end_line int, candidate_line int) bool {
	if comments.len > 0 && sks_line(t, comments[0].start) - group_end_line <= 1
		&& candidate_line - sks_line(t, comments.last().end) <= 1 {
		for i in 1 .. comments.len {
			if sks_line(t, comments[i].start) - sks_line(t, comments[i - 1].end) > 1 {
				return false
			}
		}
		return true
	}
	return false
}

// sks_key ports getKey.
fn (c &Checker) sks_key(ctx SksCtx, property int) string {
	t := ctx.t
	key := t.node(property, .key) or { return 'null' }
	if t.typ(property) != .import_attribute && (t.flag(property, .computed) or { false }) {
		return c.un_text(t, key)
	}
	if t.typ(property) == .import_attribute {
		if t.typ(key) == .identifier {
			return t.string_of(key, .name) or { 'null' }
		}
		return es_tree_static_string_value(t, key) or { 'null' }
	}
	return es_tree_static_property_name(t, property) or { 'null' }
}

// sks_is_js_whitespace is `\s` of a regular expression.
fn sks_is_js_whitespace(r rune) bool {
	return r in [` `, `\t`, `\n`, `\v`, `\f`, `\r`, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f,
		0x3000, 0xfeff] || (r >= 0x2000 && r <= 0x200a)
}

// sks_property_whitespace ports getPropertyWhitespace: `/(\s*):(\s*)/u` on the text between the
// key and the value.
fn (c &Checker) sks_property_whitespace(ctx SksCtx, property int) ?(string, string) {
	key := ctx.t.node(property, .key)?
	value := ctx.t.node(property, .value)?
	start := ctx.t.nodes[key].end
	end := ctx.t.nodes[value].start
	if start >= end {
		return none
	}
	text := c.src[start..end]
	mut run_start := 0
	mut i := 0
	for i < text.len {
		if text[i] == `:` {
			mut j := i + 1
			for j < text.len {
				r, n := sks_rune_at(text, j)
				if !sks_is_js_whitespace(r) {
					break
				}
				j += n
			}
			return text[run_start..i], text[i + 1..j]
		}
		r, n := sks_rune_at(text, i)
		i += n
		if !sks_is_js_whitespace(r) {
			run_start = i
		}
	}
	return none
}

// sks_rune_at decodes the code point at a byte offset of a string, with its length in bytes.
fn sks_rune_at(text string, i int) (rune, int) {
	c := text[i]
	n := if c >= 0xf0 {
		4
	} else if c >= 0xe0 {
		3
	} else if c >= 0xc0 {
		2
	} else {
		1
	}
	if i + n > text.len {
		return rune(c), 1
	}
	return text[i..i + n].runes()[0], n
}

// sks_units is the length of a string in UTF-16 units.
fn sks_units(text string) int {
	mut units := 0
	for r in text.runes() {
		units += if r >= 0x10000 { 2 } else { 1 }
	}
	return units
}

// sks_forward_units is the byte offset `units` UTF-16 units after `offset`.
fn (c &Checker) sks_forward_units(offset int, units int) int {
	mut at := offset
	mut left := units
	for left > 0 && at < c.src.len {
		_, n := sks_rune_at(c.src, at)
		left -= if n == 4 { 2 } else { 1 }
		at += n
	}
	return at
}

// sks_back_units is the byte offset `units` UTF-16 units before `offset`.
fn (c &Checker) sks_back_units(offset int, units int) int {
	mut at := offset
	mut left := units
	for left > 0 && at > 0 {
		at--
		for at > 0 && c.src[at] & 0xc0 == 0x80 {
			at--
		}
		left -= if c.src[at] >= 0xf0 { 2 } else { 1 }
	}
	return at
}

// sks_report ports report: spacing on one side of the colon of a key-value property.
fn (c &Checker) sks_report(ctx SksCtx, property int, side string, whitespace string, expected f64, mode string, mut findings []Finding) {
	t := ctx.t
	diff := f64(sks_units(whitespace)) - expected
	expected_truthy := expected != 0 && !math.is_nan(expected)
	if !(((diff != 0 && !math.is_nan(diff)) && mode == 'strict') || (diff < 0 && mode == 'minimum')
		|| (diff > 0 && !expected_truthy && mode == 'minimum')) {
		return
	}
	if expected_truthy && (whitespace.contains('\n') || whitespace.contains('\r')
		|| whitespace.contains(' ') || whitespace.contains(' ')) {
		return
	}
	key := t.node(property, .key) or { return }
	next_colon := c.sks_next_colon(ctx, key) or { return }
	before_colon := ctx.tokens.before(next_colon.start, true) or { return }
	after_colon := ctx.tokens.after(next_colon.end, true) or { return }
	is_key_side := side == 'key'
	is_extra := diff > 0
	diff_abs := int(math.abs(diff))
	mut start := 0
	mut end := 0
	mut fix := Fix{}
	if is_extra {
		start = if is_key_side { before_colon.end } else { next_colon.start }
		end = if is_key_side { next_colon.start } else { after_colon.start }
		fix = if is_key_side {
			fix_remove_range(before_colon.end, c.sks_forward_units(before_colon.end, diff_abs))
		} else {
			fix_remove_range(c.sks_back_units(after_colon.start, diff_abs), after_colon.start)
		}
	} else {
		missing := if is_key_side { before_colon } else { after_colon }
		start = missing.start
		end = missing.end
		fix = if is_key_side {
			fix_insert_at(before_colon.end, ' '.repeat(diff_abs))
		} else {
			fix_insert_at(after_colon.start, ' '.repeat(diff_abs))
		}
	}
	message_id := if is_extra {
		if is_key_side { 'extraKey' } else { 'extraValue' }
	} else {
		if is_key_side { 'missingKey' } else { 'missingValue' }
	}
	computed := t.typ(property) != .import_attribute && (t.flag(property, .computed) or { false })
	findings << Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       {
			'computed': if computed { 'computed ' } else { '' }
			'key':      c.sks_key(ctx, property)
		}
		has_fix:    true
		fix:        fix
	}
}

// sks_key_width ports getKeyWidth.
fn (c &Checker) sks_key_width(ctx SksCtx, property int) int {
	start := un_first_token(ctx.t, ctx.tokens, property, 0) or { return 0 }
	key := ctx.t.node(property, .key) or { return 0 }
	end := c.sks_last_token_before_colon(ctx, key) or { return 0 }
	if end.end <= start.start {
		return 0
	}
	return sty_string_length(c.src[start.start..end.end])
}

// sks_create_groups ports createGroups.
fn (c &Checker) sks_create_groups(ctx SksCtx, properties []int) [][]int {
	if properties.len == 1 {
		return [properties]
	}
	mut groups := [][]int{}
	groups << []int{}
	for property in properties {
		last := groups.len - 1
		if groups[last].len == 0 || c.sks_continues_property_group(ctx, groups[last].last(), property) {
			groups[last] << property
		} else {
			groups << [property]
		}
	}
	return groups
}

// sks_verify_group_alignment ports verifyGroupAlignment.
fn (c &Checker) sks_verify_group_alignment(ctx SksCtx, properties []int, mut findings []Finding) {
	options := ctx.options
	widths := properties.map(c.sks_key_width(ctx, it))
	align := options.align.on
	mut target := math.inf(-1)
	for width in widths {
		target = math.max(target, f64(width))
	}
	mut before := options.multi.before
	mut after := options.multi.after
	mut mode := options.align.mode
	if properties.len > 1 {
		before = options.align.before
		after = options.align.after
		mode = options.align.mode
	}
	target += if align == 'colon' { before } else { after }
	for i, property in properties {
		before_ws, after_ws := c.sks_property_whitespace(ctx, property) or { continue }
		width := f64(widths[i])
		if align == 'value' {
			c.sks_report(ctx, property, 'key', before_ws, before, mode, mut findings)
			c.sks_report(ctx, property, 'value', after_ws, target - width, mode, mut findings)
		} else {
			c.sks_report(ctx, property, 'key', before_ws, target - width, mode, mut findings)
			c.sks_report(ctx, property, 'value', after_ws, after, mode, mut findings)
		}
	}
}

// sks_verify_spacing ports verifySpacing.
fn (c &Checker) sks_verify_spacing(ctx SksCtx, node int, before f64, after f64, mode string, mut findings []Finding) {
	parent := ctx.t.nodes[node].parent
	if parent >= 0 && ctx.t.typ(parent).type_name() in ctx.options.ignored {
		return
	}
	before_ws, after_ws := c.sks_property_whitespace(ctx, node) or { return }
	c.sks_report(ctx, node, 'key', before_ws, before, mode, mut findings)
	c.sks_report(ctx, node, 'value', after_ws, after, mode, mut findings)
}

// sks_verify_list_spacing ports verifyListSpacing.
fn (c &Checker) sks_verify_list_spacing(ctx SksCtx, properties []int, line SksLine, mut findings []Finding) {
	for property in properties {
		c.sks_verify_spacing(ctx, property, line.before, line.after, line.mode, mut findings)
	}
}

// sks_verify_alignment ports verifyAlignment.
fn (c &Checker) sks_verify_alignment(ctx SksCtx, properties []int, mut findings []Finding) {
	t := ctx.t
	for group in c.sks_create_groups(ctx, properties) {
		key_values := group.filter(sks_is_key_value(t, it))
		if key_values.len > 0 && sty_same_line_offsets(t, t.nodes[key_values.last()].end,
			t.nodes[key_values[0]].start) {
			c.sks_verify_list_spacing(ctx, key_values, ctx.options.multi, mut findings)
		} else {
			c.sks_verify_group_alignment(ctx, key_values, mut findings)
		}
	}
}

// sks_verify_import_attributes ports verifyImportAttributes.
fn (c &Checker) sks_verify_import_attributes(ctx SksCtx, node int, mut findings []Finding) {
	if ctx.t.typ(node).type_name() in ctx.options.ignored {
		return
	}
	attributes := ctx.t.list(node, .attributes) or { return }
	if attributes.len == 0 {
		return
	}
	if c.sks_single_line_import_attributes(ctx, node) {
		c.sks_verify_list_spacing(ctx, attributes, ctx.options.single, mut findings)
	} else {
		c.sks_verify_alignment(ctx, attributes, mut findings)
	}
}

// sks_adjusted_column ports adjustedColumn: the graphemes from the start of the line to the
// offset.
fn (c &Checker) sks_adjusted_column(offset int) int {
	mut start := offset
	for start > 0 {
		b := c.src[start - 1]
		if b == `\n` || b == `\r` || (b in [u8(0xa8), 0xa9] && start >= 3
			&& c.src[start - 3] == 0xe2 && c.src[start - 2] == 0x80) {
			break
		}
		start--
	}
	return sty_string_length(c.src[start..offset])
}

// sks_is_key_type_node ports isKeyTypeNode.
fn sks_is_key_type_node(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.ts_property_signature, .ts_index_signature, .property_definition]
		&& t.node(node, .type_annotation) != none
}

// sks_is_applicable ports isApplicable.
fn sks_is_applicable(t &estree.EsTree, node int) bool {
	if !sks_is_key_type_node(t, node) {
		return false
	}
	annotation := t.node(node, .type_annotation) or { return false }
	return sty_same_line_offsets(t, t.nodes[node].end, t.nodes[annotation].start)
}

// sks_key_text ports getKeyText.
fn (c &Checker) sks_key_text(ctx SksCtx, node int) string {
	t := ctx.t
	if t.typ(node) != .ts_index_signature {
		key := t.node(node, .key) or { return '' }
		return c.un_text(t, key)
	}
	parameters := t.list(node, .parameters) or { []int{} }
	if parameters.len == 0 {
		return ''
	}
	bracket := c.sks_token_after(ctx.tokens, t.nodes[parameters.last()].end, ']') or { return '' }
	return c.src[t.nodes[node].start..bracket.end]
}

// sks_key_end ports getKeyLocEnd (as an offset).
fn (c &Checker) sks_key_end(ctx SksCtx, node int) ?int {
	t := ctx.t
	target := if t.typ(node) != .ts_index_signature {
		t.node(node, .key)?
	} else {
		parameters := t.list(node, .parameters)?
		if parameters.len == 0 {
			return none
		}
		parameters.last()
	}
	token := c.sks_last_token_before_colon(ctx, target)?
	return token.end
}

fn (c &Checker) sks_type_report(ctx SksCtx, node int, message_id string, fix Fix, mut findings []Finding) {
	findings << Finding{
		stmt:       c.position_range(ctx.t.nodes[node].start, ctx.t.nodes[node].end)
		message_id: message_id
		data:       {
			'computed': ''
			'key':      c.sks_key_text(ctx, node)
		}
		has_fix:    true
		fix:        fix
	}
}

// sks_column is `loc.column` of an offset.
fn sks_column(t &estree.EsTree, offset int) int {
	_, column := t.line_column(offset)
	return column
}

// sks_check_before_colon ports checkBeforeColon.
fn (c &Checker) sks_check_before_colon(ctx SksCtx, node int, expected int, mode string, mut findings []Finding) {
	t := ctx.t
	annotation := t.node(node, .type_annotation) or { return }
	key_end := c.sks_key_end(ctx, node) or { return }
	difference := sks_column(t, t.nodes[annotation].start) - sks_column(t, key_end) - expected
	if !(if mode == 'strict' { difference != 0 } else { difference < 0 }) {
		return
	}
	at := t.nodes[annotation].start
	fix := if difference > 0 {
		fix_remove_range(c.sks_back_units(at, difference), at)
	} else {
		fix_insert_at(at, ' '.repeat(-difference))
	}
	c.sks_type_report(ctx, node, if difference > 0 { 'extraKey' } else { 'missingKey' }, fix, mut
		findings)
}

// sks_check_after_colon ports checkAfterColon.
fn (c &Checker) sks_check_after_colon(ctx SksCtx, node int, expected int, mode string, mut findings []Finding) {
	t := ctx.t
	annotation := t.node(node, .type_annotation) or { return }
	colon := un_first_token(t, ctx.tokens, annotation, 0) or { return }
	after := ctx.tokens.after(colon.end, true) or { return }
	difference := sks_column(t, after.start) - sks_column(t, colon.start) - 1 - expected
	if !(if mode == 'strict' { difference != 0 } else { difference < 0 }) {
		return
	}
	fix := if difference > 0 {
		fix_remove_range(colon.end, c.sks_forward_units(colon.end, difference))
	} else {
		fix_insert_at(colon.end, ' '.repeat(-difference))
	}
	c.sks_type_report(ctx, node, if difference > 0 { 'extraValue' } else { 'missingValue' }, fix, mut
		findings)
}

// sks_continues_align_group ports continuesAlignGroup.
fn sks_continues_align_group(ctx SksCtx, last_member int, candidate int) bool {
	t := ctx.t
	group_end_line := sks_line(t, t.nodes[last_member].start)
	value := if sks_is_key_type_node(t, candidate) {
		t.node(candidate, .type_annotation) or { candidate }
	} else {
		candidate
	}
	candidate_line := sks_line(t, t.nodes[value].start)
	if candidate_line == group_end_line {
		return false
	}
	if candidate_line - group_end_line == 1 {
		return true
	}
	return sks_comments_join(t, ctx.tokens.comments_before(t.nodes[candidate].start), group_end_line,
		candidate_line)
}

// sks_multi_align is `options.multiLine.align` when it is an object.
fn sks_multi_align(options map[string]json2.Any) ?map[string]json2.Any {
	multi := sks_raw_object(options, 'multiLine')?
	return sks_raw_object(multi, 'align')
}

// sks_multi_align_string is `options.multiLine.align` when it is a string.
fn sks_multi_align_string(options map[string]json2.Any) ?string {
	multi := sks_raw_object(options, 'multiLine')?
	return sks_raw_string(multi, 'align')
}

// sks_check_align_group ports checkAlignGroup.
fn (c &Checker) sks_check_align_group(ctx SksCtx, group []int, mut findings []Finding) {
	t := ctx.t
	options := ctx.options.raw
	align_object := sks_raw_object(options, 'align')
	multi := sks_raw_object(options, 'multiLine')
	multi_align := sks_multi_align(options)
	mut align := 'colon'
	mut before := false
	mut after := true
	mut mode := 'strict'
	if a := align_object {
		align = sks_raw_string(a, 'on') or { 'colon' }
		before = sks_raw_bool(a, 'beforeColon', false)
		after = sks_raw_bool(a, 'afterColon', true)
		mode = sks_raw_string(a, 'mode') or { 'strict' }
	} else {
		if ma := multi_align {
			align = sks_raw_string(ma, 'on') or { 'colon' }
		} else {
			align = sks_multi_align_string(options) or {
				sks_raw_string(options, 'align') or { 'colon' }
			}
		}
		if m := multi {
			if ma := multi_align {
				before = sks_raw_bool(ma, 'beforeColon', false)
				after = sks_raw_bool(ma, 'afterColon', true)
				mode = sks_raw_string(ma, 'mode') or { sks_raw_string(m, 'mode') or { 'strict' } }
			} else {
				before = sks_raw_bool(m, 'beforeColon', false)
				after = sks_raw_bool(m, 'afterColon', true)
				mode = sks_raw_string(m, 'mode') or { 'strict' }
			}
		} else {
			before = sks_raw_bool(options, 'beforeColon', false)
			after = sks_raw_bool(options, 'afterColon', true)
			mode = sks_raw_string(options, 'mode') or { 'strict' }
		}
	}
	expected_before := if before { 1 } else { 0 }
	expected_after := if after { 1 } else { 0 }
	mut align_column := 0
	for node in group {
		if !sks_is_key_type_node(t, node) {
			continue
		}
		key_end := c.sks_key_end(ctx, node) or { continue }
		column := c.sks_adjusted_column(key_end)
		candidate := if align == 'colon' {
			column + expected_before
		} else {
			column + 1 + expected_after + expected_before
		}
		if candidate > align_column {
			align_column = candidate
		}
	}
	for node in group {
		if !sks_is_applicable(t, node) {
			continue
		}
		annotation := t.node(node, .type_annotation) or { continue }
		to_check := if align == 'colon' {
			annotation
		} else {
			t.node(annotation, .type_annotation) or { continue }
		}
		at := t.nodes[to_check].start
		difference := c.sks_adjusted_column(at) - align_column
		if difference != 0 {
			message_id := if difference > 0 {
				if align == 'colon' { 'extraKey' } else { 'extraValue' }
			} else {
				if align == 'colon' { 'missingKey' } else { 'missingValue' }
			}
			fix := if difference > 0 {
				fix_remove_range(c.sks_back_units(at, difference), at)
			} else {
				fix_insert_at(at, ' '.repeat(-difference))
			}
			c.sks_type_report(ctx, node, message_id, fix, mut findings)
		}
		if align == 'colon' {
			c.sks_check_after_colon(ctx, node, expected_after, mode, mut findings)
		} else {
			c.sks_check_before_colon(ctx, node, expected_before, mode, mut findings)
		}
	}
}

// sks_check_individual_node ports checkIndividualNode.
fn (c &Checker) sks_check_individual_node(ctx SksCtx, node int, single_line bool, mut findings []Finding) {
	options := ctx.options.raw
	// The singleLine or multiLine object when it is given, else the options themselves.
	source := sks_raw_object(options, if single_line { 'singleLine' } else { 'multiLine' }) or {
		options
	}
	before := sks_raw_bool(source, 'beforeColon', false)
	after := sks_raw_bool(source, 'afterColon', true)
	mode := sks_raw_string(source, 'mode') or { 'strict' }
	if sks_is_applicable(ctx.t, node) {
		c.sks_check_before_colon(ctx, node, if before { 1 } else { 0 }, mode, mut findings)
		c.sks_check_after_colon(ctx, node, if after { 1 } else { 0 }, mode, mut findings)
	}
}

// sks_validate_body ports validateBody.
fn (c &Checker) sks_validate_body(ctx SksCtx, body int, mut findings []Finding) {
	t := ctx.t
	if t.typ(body).type_name() in ctx.options.ignored {
		return
	}
	members := if t.typ(body) == .ts_type_literal {
		t.list(body, .members) or { []int{} }
	} else {
		t.list(body, .body) or { []int{} }
	}
	mut align_groups := [][]int{}
	mut unaligned := []int{}
	raw := ctx.options.raw
	mut multi_align := false
	if m := sks_raw_object(raw, 'multiLine') {
		multi_align = 'align' in m
	}
	if 'align' in raw || multi_align {
		align_groups << []int{}
		mut prev_node := -1
		for node in members {
			current := align_groups.len - 1
			mut prev_aligned := if align_groups[current].len > 0 {
				align_groups[current].last()
			} else {
				-1
			}
			if prev_aligned != prev_node {
				prev_aligned = -1
			}
			if prev_aligned >= 0 && sks_continues_align_group(ctx, prev_aligned, node) {
				align_groups[current] << node
			} else if prev_node >= 0
				&& sks_line(t, t.nodes[prev_node].start) == sks_line(t, t.nodes[node].start) {
				if prev_aligned >= 0 {
					unaligned << prev_aligned
					align_groups[current].delete_last()
				}
				unaligned << node
			} else {
				align_groups << [node]
			}
			prev_node = node
		}
		for group in align_groups {
			if group.len == 1 {
				unaligned << group[0]
			}
		}
		align_groups = align_groups.filter(it.len >= 2)
	} else {
		unaligned = members.clone()
	}
	for group in align_groups {
		c.sks_check_align_group(ctx, group, mut findings)
	}
	single_line := sks_is_single_line(t, body)
	for node in unaligned {
		c.sks_check_individual_node(ctx, node, single_line, mut findings)
	}
}
