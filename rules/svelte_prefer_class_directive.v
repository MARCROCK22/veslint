module rules

import json2

// Port of the `svelte/prefer-class-directive` rule of eslint-plugin-svelte 3.24.1: a mustache tag
// of the `class` attribute of an HTML element whose expression is a conditional choosing between
// (at most two) constant class names, one of them empty with prefer "empty" (the default), should
// be `class:name={condition}` directives; the fix writes them (when the class names are words that
// do not stick to the text around them).

const spcd_messages = {
	'unexpected': 'Unexpected class using the ternary operator.'
}

fn spcd_options(options []json2.Any) !bool {
	o := option_object(svelte_prefer_class_directive, options, ['prefer'])!
	return o.string_value('prefer', ['always', 'empty'])! != 'always'
}

// SpcdEntry is an entry of parseConditionalExpression's map: the test (negated or not) of the
// outermost conditional that leads to a class name, and that name.
struct SpcdEntry {
	not   bool
	node  int
	value string
}

// spcd_parse is parseConditionalExpression: the class names of each branch, in order; none when
// a branch is not a constant string.
fn (c &Checker) spcd_parse(node int) ?[]SpcdEntry {
	es := &c.svelte.doc.es
	test := es.node(node, .test)?
	mut out := []SpcdEntry{}
	for not in [false, true] {
		branch := es.node(node, if not { .alternate } else { .consequent })?
		if es.nodes[branch].typ == .conditional_expression {
			for sub in c.spcd_parse(branch)? {
				out << SpcdEntry{
					not:   not
					node:  test
					value: sub.value
				}
			}
		} else {
			out << SpcdEntry{
				not:   not
				node:  test
				value: c.sv_string_if_constant(branch)?
			}
		}
	}
	return out
}

// spcd_need_parentheses is needParentheses(node, 'not').
fn spcd_need_parentheses(typ string) bool {
	return typ in ['ArrowFunctionExpression', 'AssignmentExpression', 'BinaryExpression',
		'ConditionalExpression', 'LogicalExpression', 'SequenceExpression', 'UnaryExpression',
		'UpdateExpression']
}

// spcd_flip_operator rewrites the text between the operands of an equality: `==`/`===` become
// `!=`/`!==` (/[=](={1,2})/g), or the other way round (/!(={1,2})/g).
fn spcd_flip_operator(op string, to_not bool) string {
	mut out := []u8{cap: op.len + 1}
	mut i := 0
	for i < op.len {
		lead := if to_not { `=` } else { `!` }
		if op[i] == lead && i + 1 < op.len && op[i + 1] == `=` {
			n := if i + 2 < op.len && op[i + 2] == `=` { 2 } else { 1 }
			out << if to_not { `!` } else { `=` }
			out << op[i + 1..i + 1 + n].bytes()
			i += 1 + n
			continue
		}
		out << op[i]
		i++
	}
	return out.bytestr()
}

// spcd_expr_string is exprToString.
fn (c &Checker) spcd_expr_string(e SpcdEntry) string {
	doc := c.svelte.doc
	es := &doc.es
	mut text := c.sv_es_text(e.node)
	if !e.not {
		return text
	}
	typ := doc.es_type_name(e.node)
	if typ == 'BinaryExpression' {
		op := es.string_of(e.node, .operator) or { '' }
		if op in ['===', '==', '!==', '!='] {
			left := es.node(e.node, .left) or { -1 }
			right := es.node(e.node, .right) or { -1 }
			if left >= 0 && right >= 0 {
				between := c.sv_text(es.nodes[left].end, es.nodes[right].start)
				return c.sv_es_text(left) + spcd_flip_operator(between, op in ['===', '==']) +
					c.sv_es_text(right)
			}
		}
	} else if typ == 'UnaryExpression' {
		if (es.string_of(e.node, .operator) or { '' }) == '!' && (es.flag(e.node, .prefix) or { false }) {
			if argument := es.node(e.node, .argument) {
				return c.sv_es_text(argument)
			}
		}
	}
	if spcd_need_parentheses(typ) {
		text = '(${text})'
	}
	return '!${text}'
}

// spcd_strings is getStrings of a value of the attribute.
fn (c &Checker) spcd_strings(v int) ?[]string {
	doc := c.svelte.doc
	n := doc.nodes[v]
	if n.typ == .literal {
		return [n.value]
	}
	if n.expression.idx < 0 || !n.expression.es {
		return none
	}
	if doc.es.nodes[n.expression.idx].typ == .conditional_expression {
		return (c.spcd_parse(n.expression.idx)?).map(it.value)
	}
	return [c.sv_string_if_constant(n.expression.idx)?]
}

fn spcd_is_space_rune(s string, last bool) bool {
	runes := s.runes()
	return is_js_space(if last { runes.last() } else { runes[0] })
}

// spcd_ends_with_non_word is endsWithNonWord: the text before the value `index` (from it back)
// ends with white space, or there is none.
fn (c &Checker) spcd_ends_with_non_word(values []int, index int) bool {
	for i := index; i >= 0; i-- {
		strings := c.spcd_strings(values[i]) or { return false }
		for s in strings {
			if s != '' {
				return spcd_is_space_rune(s, true)
			}
		}
	}
	return true
}

// spcd_starts_with_non_word is startsWithNonWord: the text from the value `index` on starts with
// white space, or there is none.
fn (c &Checker) spcd_starts_with_non_word(values []int, index int) bool {
	for i := index; i < values.len; i++ {
		strings := c.spcd_strings(values[i]) or { return false }
		for s in strings {
			if s != '' {
				return spcd_is_space_rune(s, false)
			}
		}
	}
	return true
}

// spcd_trim is String.prototype.trim (trimStart, trimEnd with `start`, `end`).
fn spcd_trim(s string, start bool, end bool) string {
	runes := s.runes()
	mut a := 0
	mut b := runes.len
	if start {
		for a < b && is_js_space(runes[a]) {
			a++
		}
	}
	if end {
		for b > a && is_js_space(runes[b - 1]) {
			b--
		}
	}
	return runes[a..b].string()
}

// spcd_is_class_word is /^[\w-]*$/.
fn spcd_is_class_word(s string) bool {
	return s.bytes().all(sv_is_word_char(it) || it == `-`)
}

// spcd_fix is the rule's fix.
fn (c &Checker) spcd_fix(attr int, index int, entries []SpcdEntry) ![]Fix {
	doc := c.svelte.doc
	mut directives := []string{}
	mut space := ' '
	for e in entries {
		trimmed := spcd_trim(e.value, true, true)
		if trimmed != '' {
			directives << 'class:${trimmed}={${c.spcd_expr_string(e)}}'
		} else {
			space = e.value
		}
	}
	a := doc.nodes[attr]
	node := doc.nodes[a.values[index]]
	mut before := a.values[..index].clone()
	mut after := a.values[index + 1..].clone()
	mut buffer := []Fix{}
	for before.len > 0 {
		v := doc.nodes[before.last()]
		if v.typ == .literal {
			if spcd_trim(v.value, true, true) == '' {
				before.pop()
				buffer << Fix{
					start: v.start
					end:   v.end
				}
				continue
			}
			trimmed := spcd_trim(v.value, false, true)
			if trimmed != v.value {
				buffer << Fix{
					start: v.start
					end:   v.end
					text:  trimmed
				}
			}
		}
		break
	}
	for after.len > 0 {
		v := doc.nodes[after[0]]
		if v.typ == .literal {
			if spcd_trim(v.value, true, true) == '' {
				after.delete(0)
				buffer << Fix{
					start: v.start
					end:   v.end
				}
				continue
			}
			trimmed := spcd_trim(v.value, true, false)
			if trimmed != v.value {
				buffer << Fix{
					start: v.start
					end:   v.end
					text:  trimmed
				}
			}
		}
		break
	}
	if before.len == 0 && after.len == 0 {
		return [Fix{
			start: a.start
			end:   a.end
			text:  directives.join(' ')
		}]
	}
	mut fixes := buffer.clone()
	fixes << Fix{
		start: node.start
		end:   node.end
		text:  if before.len > 0 && after.len > 0 {
			if space == '' { ' ' } else { space }
		} else {
			''
		}
	}
	fixes << Fix{
		start: a.end
		end:   a.end
		text:  ' ${directives.join(' ')}'
	}
	return fixes
}

fn (mut c Checker) lint_svelte_prefer_class_directive(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	prefer_empty := spcd_options(c.rule_options(svelte_prefer_class_directive))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for attr in c.sv_snodes_of(.attribute) {
		a := doc.nodes[attr]
		tag := a.parent
		if tag < 0 || doc.nodes[tag].typ != .start_tag || c.sv_attribute_name(attr) != 'class'
			|| !c.sv_is_html_element_like(doc.nodes[tag].parent) {
			continue
		}
		for index, v in a.values {
			n := doc.nodes[v]
			if n.typ != .mustache_tag || !n.expression.es || n.expression.idx < 0
				|| doc.es.nodes[n.expression.idx].typ != .conditional_expression {
				continue
			}
			entries := c.spcd_parse(n.expression.idx) or { continue }
			if entries.len > 2 {
				continue
			}
			if prefer_empty && entries.all(spcd_trim(it.value, true, true) != '') {
				continue
			}
			prev_is_word := !c.spcd_starts_with_non_word(a.values, index + 1)
			next_is_word := !c.spcd_ends_with_non_word(a.values, index - 1)
			mut can_transform := true
			for e in entries {
				if e.value != '' {
					if !spcd_is_class_word(spcd_trim(e.value, true, true)) {
						can_transform = false
						break
					}
					if (!spcd_is_space_rune(e.value, false) && prev_is_word)
						|| (!spcd_is_space_rune(e.value, true) && next_is_word) {
						can_transform = false
						break
					}
				} else if prev_is_word && next_is_word {
					can_transform = false
					break
				}
			}
			if !can_transform {
				continue
			}
			has_fix, fix := c.merge_fixes(c.spcd_fix(attr, index, entries)!)!
			findings << Finding{
				...c.sv_report_snode(v, 'unexpected', {})
				has_fix: has_fix
				fix:     fix
			}
		}
	}
	return findings
}
