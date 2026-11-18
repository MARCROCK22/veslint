module rules

import estree
import json2
import time

// Port of the `vue/padding-lines-in-component-definition` rule of eslint-plugin-vue 10.12.1
// (option "always", the default, "never", or `{betweenOptions, withinOption,
// groupSingleLineProperties}`): blank lines between the options of a Vue object (or of
// defineOptions) and between the items of an option (and of defineProps and defineEmits), with
// the fixes that add or remove them.

const vue_padding_lines_in_component_definition_messages = {
	'never':                     'Unexpected blank line before this definition.'
	'always':                    'Expected blank line before this definition.'
	'groupSingleLineProperties': 'Unexpected blank line between single line properties.'
}

fn vue_padding_lines_in_component_definition_options(options []json2.Any) !json2.Any {
	if options.len == 0 {
		return json2.Any('always')
	}
	value := options[0]
	if value is string || value is map[string]json2.Any {
		return value
	}
	return error('the option of `${vue_padding_lines_in_component_definition}` must be a string or an object')
}

// vplicd_parse_option is parseOption: a string option is the same for every key; an object's is
// its property (null when it has none).
fn vplicd_parse_option(option json2.Any, key string) json2.Any {
	if option is string {
		return option
	}
	if option is map[string]json2.Any {
		return option[key] or { json2.null }
	}
	return json2.null
}

// vplicd_truthy is JavaScript's truthiness of an option.
fn vplicd_truthy(option json2.Any) bool {
	return match option {
		string { option != '' }
		bool { option }
		map[string]json2.Any { true }
		[]json2.Any { true }
		else { false }
	}
}

fn vplicd_is_string(option json2.Any, s string) bool {
	return option is string && option == s
}

fn (mut c Checker) lint_vue_padding_lines_in_component_definition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := vue_padding_lines_in_component_definition_options(c.rule_options(vue_padding_lines_in_component_definition))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	group := if vplicd_is_string(options, 'always') {
		true
	} else if vplicd_is_string(options, 'never') {
		false
	} else {
		vplicd_truthy(vplicd_parse_option(options, 'groupSingleLineProperties'))
	}
	mut ctx := VplicdCtx{
		t:      t
		tokens: tokens
		group:  group
	}
	for obj in s.objects_of(vue_all_object_types) {
		stats.checked++
		c.vplicd_verify(mut ctx, t.list(obj, .properties) or { []int{} }, vplicd_parse_option(options,
			'betweenOptions'), vplicd_parse_option(options, 'withinOption'))
	}
	within := vplicd_parse_option(options, 'withinOption')
	for m in c.vue_macros(t) {
		if m.name in ['defineProps', 'defineEmits'] {
			list := if m.name == 'defineProps' {
				c.vue_define_props(root, t, m.call, abs_path, false, mut stats)
			} else {
				c.vue_define_emits(root, t, m.call)
			}
			nodes := list.filter(it.kind != .infer_type && it.node >= 0
				&& t.typ(it.node) in [.property, .spread_element]).map(it.node)
			key := if m.name == 'defineProps' { 'props' } else { 'emits' }
			option := if vplicd_truthy(within) { vplicd_parse_option(within, key) } else { within }
			if !vplicd_truthy(option) {
				continue
			}
			c.vplicd_verify(mut ctx, nodes, vplicd_parse_option(option, 'betweenItems'),
				vplicd_parse_option(option, 'withinEach'))
		} else if m.name == 'defineOptions' {
			args := t.list(m.call, .arguments) or { []int{} }
			if args.len == 0 || t.typ(args[0]) != .object_expression {
				continue
			}
			c.vplicd_verify(mut ctx, t.list(args[0], .properties) or { []int{} }, vplicd_parse_option(options,
				'betweenOptions'), within)
		}
	}
	findings << ctx.findings
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

struct VplicdCtx {
	t      &estree.EsTree
	tokens &SourceTokens
	group  bool
mut:
	findings []Finding
}

fn (c &Checker) vplicd_verify(mut ctx VplicdCtx, properties []int, option json2.Any, next_option json2.Any) {
	t := ctx.t
	for i, current in properties {
		if i + 1 < properties.len && !vplicd_is_string(option, 'ignore') {
			next := properties[i + 1]
			before_next := ctx.tokens.before(t.nodes[next].start, true) or { SourceToken{} }
			is_comment := before_next.is_comment()
			report_start := if is_comment { before_next.start } else { t.nodes[next].start }
			report_end := if is_comment { before_next.end } else { t.nodes[next].end }
			report_line, _ := t.line_column(report_start)
			current_end_line, _ := t.line_column(t.nodes[current].end)
			range := report_line - current_end_line
			if ctx.group && vplicd_single_line(t, current) && vplicd_single_line(t, next) {
				if range > 1 {
					ctx.findings << c.with_fixes(c.vplicd_finding(report_start, report_end,
						'groupSingleLineProperties'), [
						c.vplicd_replace_lines(ctx, current, report_start),
					]) or { c.vplicd_finding(report_start, report_end, 'groupSingleLineProperties') }
				}
				// The grouped single-line properties are not checked further, nor their options.
				continue
			}
			if range <= 1 && vplicd_is_string(option, 'always') {
				ctx.findings << c.with_fixes(c.vplicd_finding(report_start, report_end,
					'always'), [c.vplicd_insert_lines(ctx, current, report_start, range)]) or {
					c.vplicd_finding(report_start, report_end, 'always')
				}
			} else if range > 1 && vplicd_is_string(option, 'never') {
				ctx.findings << c.with_fixes(c.vplicd_finding(report_start, report_end,
					'never'), [c.vplicd_replace_lines(ctx, current, report_start)]) or {
					c.vplicd_finding(report_start, report_end, 'never')
				}
			}
		}
		if !vplicd_truthy(next_option) || t.typ(current) != .property {
			continue
		}
		name := vue_static_property_name(t, current) or { continue }
		if name == '' {
			continue
		}
		property_option := vplicd_parse_option(next_option, name)
		if !vplicd_truthy(property_option) {
			continue
		}
		value := vue_property_value(t, current)
		if value < 0 || t.typ(value) != .object_expression {
			continue
		}
		c.vplicd_verify(mut ctx, t.list(value, .properties) or { []int{} }, vplicd_parse_option(property_option,
			'betweenItems'), vplicd_parse_option(property_option, 'withinEach'))
	}
}

fn (c &Checker) vplicd_finding(start int, end int, message_id string) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
	}
}

fn vplicd_single_line(t &estree.EsTree, node int) bool {
	start, _ := t.line_column(t.nodes[node].start)
	end, _ := t.line_column(t.nodes[node].end)
	return start == end
}

// vplicd_comma_after is getTokenAfter(node, isComma): the first comma token after the node.
fn (c &Checker) vplicd_comma_after(ctx &VplicdCtx, node int) ?SourceToken {
	mut offset := ctx.t.nodes[node].end
	for {
		token := ctx.tokens.after(offset, false)?
		if c.src[token.start..token.end] == ',' {
			return token
		}
		offset = token.end
	}
	return none
}

// vplicd_replace_lines is replaceLines: the padding between the comma after the property (or the
// property) and the next one becomes a line break and the last line of that padding.
fn (c &Checker) vplicd_replace_lines(ctx &VplicdCtx, current int, next_start int) Fix {
	start := if comma := c.vplicd_comma_after(ctx, current) {
		comma.end
	} else {
		ctx.t.nodes[current].end
	}
	padding := c.src[start..next_start]
	lines := vplicd_split_lines(padding)
	return fix_replace_range(start, next_start, '\n${lines.last()}')
}

// vplicd_insert_lines is insertLines.
fn (c &Checker) vplicd_insert_lines(ctx &VplicdCtx, current int, next_start int, range int) Fix {
	after := if comma := c.vplicd_comma_after(ctx, current) {
		comma.end
	} else {
		ctx.t.nodes[current].end
	}
	line_start := vx6_line_start_index(c.src, next_start)
	mut spaces_end := line_start
	for spaces_end < c.src.len {
		r := c.src[spaces_end..].runes()
		if r.len == 0 || !is_js_space(r[0]) || r[0] in [`\n`, `\r`, ` `, ` `] {
			break
		}
		spaces_end += r[0].length_in_bytes()
	}
	spaces := c.src[line_start..spaces_end]
	return fix_insert_at(after, if range == 0 { '\n\n${spaces}' } else { '\n' })
}

// vplicd_split_lines is `text.split(/\r\n|[\r\n  ]/u)`.
fn vplicd_split_lines(text string) []string {
	mut out := []string{}
	mut start := 0
	mut i := 0
	for i < text.len {
		if text[i] == `\r` && i + 1 < text.len && text[i + 1] == `\n` {
			out << text[start..i]
			i += 2
			start = i
		} else if text[i] == `\r` || text[i] == `\n` {
			out << text[start..i]
			i++
			start = i
		} else if i + 2 < text.len && text[i] == 0xE2 && text[i + 1] == 0x80
			&& (text[i + 2] == 0xA8 || text[i + 2] == 0xA9) {
			out << text[start..i]
			i += 3
			start = i
		} else {
			i++
		}
	}
	out << text[start..]
	return out
}
