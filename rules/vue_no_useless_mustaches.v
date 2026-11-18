module rules

import estree
import json2
import time

// Port of the `vue/no-useless-mustaches` rule of eslint-plugin-vue 10.12.1 (options
// `ignoreIncludesComment`, `ignoreStringEscape`): a mustache of an element's content whose
// expression is a string literal (or a template literal without expressions), fixed to the text
// itself unless it holds a comment or a useful escape, starts or ends with white space, holds a
// line break, or the text would read otherwise in HTML (a `{{`, a character reference it would
// make or break).

const vnum_messages = {
	'unexpected': 'Unexpected mustache interpolation with a string literal value.'
}

struct VnumOptions {
	ignore_includes_comment bool
	ignore_string_escape    bool
}

fn vnum_options(options []json2.Any) !VnumOptions {
	o := option_object(vue_no_useless_mustaches, options, ['ignoreIncludesComment', 'ignoreStringEscape'])!
	return VnumOptions{
		ignore_includes_comment: o.bool_value('ignoreIncludesComment')!
		ignore_string_escape:    o.bool_value('ignoreStringEscape')!
	}
}

fn (mut c Checker) lint_vue_no_useless_mustaches(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnum_options(c.rule_options(vue_no_useless_mustaches))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_expression_container || node.parent < 0
			|| c.vue.doc.nodes[node.parent].typ != .v_element {
			continue
		}
		e := node.expression
		if e.kind != .estree {
			continue
		}
		stats.checked++
		t := c.vue_expr_es(e)
		if !vue_is_string_literal(t, e.node) {
			continue
		}
		str_value := vue_string_literal_value(t, e.node, false) or { continue }
		expr_start, expr_end := c.vue_expr_range(e)
		expr_text := c.vue_text(expr_start, expr_end)
		raw_value := if t.typ(e.node) == .literal {
			vu4_slice_units(expr_text, 1, -1)
		} else {
			quasis := t.list(e.node, .quasis) or { []int{} }
			v := t.get(quasis[0], .value)
			if v is estree.TemplateValue { v.raw } else { '' }
		}
		has_comment := c.vue_tokens_with_comments_in(node.start, node.end).any(it.typ in [
			'Block',
			'Line',
		])
		if opts.ignore_includes_comment && has_comment {
			continue
		}
		mut has_escape := false
		if raw_value != str_value {
			chars := raw_value.runes()
			mut k := 0
			for k < chars.len {
				if chars[k] == `\\` {
					k++
					if k >= chars.len || chars[k] in [`n`, `r`, `v`, `t`, `b`, `f`, `u`, `x`] {
						has_escape = true
						break
					}
				}
				k++
			}
		}
		if opts.ignore_string_escape && has_escape {
			continue
		}
		finding := c.vue_report_vnode(i, 'unexpected', map[string]string{})
		if has_comment || has_escape {
			findings << finding
			continue
		}
		text := vnum_strip_quotes_for_html(expr_text) or {
			findings << finding
			continue
		}
		if text.contains('\n') || vnum_starts_or_ends_with_space(text) {
			findings << finding
			continue
		}
		replacement := vnum_unescape(text.replace('<', '&lt;'))
		src := c.vue.doc.src
		char_before := if node.start > 0 { src[node.start - 1..node.start] } else { '' }
		char_after := if node.end < src.len { src[node.end..node.end + 1] } else { '' }
		can_start_mustache := '${char_before}${replacement}${char_after}'.contains('{{')
		joined := '${replacement}${char_after}'
		can_join_reference := vnum_is_after_reference_start(src, node.start) && joined.len > 0
			&& (joined[0].is_letter() || joined[0].is_digit() || joined[0] in [`_`, `#`, `;`])
		if can_start_mustache || can_join_reference || vnum_has_unsafe_reference(text) {
			findings << finding
			continue
		}
		findings << c.with_fixes(finding, [fix_replace_range(node.start, node.end, replacement)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnum_starts_or_ends_with_space is /^\s|\s$/u.test(text).
fn vnum_starts_or_ends_with_space(text string) bool {
	runes := text.runes()
	return runes.len > 0 && (is_js_space(runes[0]) || is_js_space(runes[runes.len - 1]))
}

// vnum_unescape is `.replaceAll(/\\([\S\s])/g, '$1')`: a backslash before a character is dropped.
fn vnum_unescape(text string) string {
	mut out := []u8{cap: text.len}
	mut k := 0
	for k < text.len {
		if text[k] == `\\` && k + 1 < text.len {
			k++
		}
		out << text[k]
		k++
	}
	return out.bytestr()
}

// vnum_reference_end is the end of a quote reference (&quot; &apos; &#123; &#x7b;, hex in lower
// case) at `at`, or -1.
fn vnum_quote_reference_end(text string, at int) int {
	if at >= text.len || text[at] != `&` {
		return -1
	}
	rest := text[at + 1..]
	if rest.starts_with('quot;') {
		return at + 6
	}
	if rest.starts_with('apos;') {
		return at + 6
	}
	if rest.len > 0 && rest[0] == `#` {
		mut k := 1
		if rest.len > 1 && rest[1] == `x` {
			k = 2
			start := k
			for k < rest.len && (rest[k].is_digit() || rest[k] in [`a`, `b`, `c`, `d`, `e`, `f`]) {
				k++
			}
			if k > start && k < rest.len && rest[k] == `;` {
				return at + 1 + k + 1
			}
		}
		k = 1
		start := k
		for k < rest.len && rest[k].is_digit() {
			k++
		}
		if k > start && k < rest.len && rest[k] == `;` {
			return at + 1 + k + 1
		}
	}
	return -1
}

// vnum_strip_quotes_for_html is stripQuotesForHTML: the text between the quotes (or quote
// references) that enclose it, or none.
fn vnum_strip_quotes_for_html(text string) ?string {
	if text.len > 0 && text[0] in [`"`, `'`, `\``] && text[0] == text[text.len - 1] {
		return vu4_slice_units(text, 1, -1)
	}
	// The opener: a quote reference or a quote.
	mut open_end := vnum_quote_reference_end(text, 0)
	if open_end < 0 {
		if text.len > 0 && text[0] in [`"`, `'`, `\``] {
			open_end = 1
		} else {
			return none
		}
	}
	// The closer: [\s\S]* is greedy, so the last place the rest is one quote or one reference.
	if text.len - 1 >= open_end && text[text.len - 1] in [`"`, `'`, `\``] {
		return text[open_end..text.len - 1]
	}
	if amp := text.last_index('&') {
		if amp >= open_end && vnum_quote_reference_end(text, amp) == text.len {
			return text[open_end..amp]
		}
	}
	return none
}

// vnum_is_after_reference_start is isAfterCharacterReferenceStart: the characters before
// `offset`, past a run of [\w#], are preceded by `&`.
fn vnum_is_after_reference_start(text string, offset int) bool {
	mut k := offset - 1
	for k >= 0 && (text[k].is_letter() || text[k].is_digit() || text[k] in [`_`, `#`]) {
		k--
	}
	return k >= 0 && text[k] == `&`
}

// vnum_reference_at: a character reference (/&(?:[a-z][\da-z]*|#\d+|#x[\da-f]+);/i) starts at `at`.
fn vnum_reference_at(text string, at int) bool {
	mut k := at + 1
	if k < text.len && text[k].is_letter() {
		k++
		for k < text.len && (text[k].is_letter() || text[k].is_digit()) {
			k++
		}
		return k < text.len && text[k] == `;`
	}
	if k < text.len && text[k] == `#` {
		k++
		start := k
		for k < text.len && text[k].is_digit() {
			k++
		}
		if k > start && k < text.len && text[k] == `;` {
			return true
		}
		k = start
		if k < text.len && text[k] in [`x`, `X`] {
			k++
			hex_start := k
			for k < text.len && text[k].is_hex_digit() {
				k++
			}
			return k > hex_start && k < text.len && text[k] == `;`
		}
	}
	return false
}

// vnum_has_unsafe_reference is hasUnsafeCharacterReference.
fn vnum_has_unsafe_reference(text string) bool {
	if !text.contains('&') {
		return false
	}
	mut incomplete := false
	for k := 0; k < text.len; k++ {
		if text[k] == `&` && !vnum_reference_at(text, k) {
			incomplete = true
		}
	}
	lower := text.to_lower()
	mut backslash := false
	for k := 0; k < lower.len; k++ {
		if lower[k] != `&` {
			continue
		}
		rest := lower[k + 1..]
		if rest.starts_with('bsol;') {
			backslash = true
			break
		}
		if rest.starts_with('#') {
			mut j := 1
			hex := rest.len > 1 && rest[1] == `x`
			if hex {
				j = 2
			}
			for j < rest.len && rest[j] == `0` {
				j++
			}
			want := if hex { '5c;' } else { '92;' }
			if rest[j..].starts_with(want) {
				backslash = true
				break
			}
		}
	}
	return text.contains('\\') || backslash || incomplete
}
