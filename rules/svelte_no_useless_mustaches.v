module rules

import estree
import json2

// Port of the `svelte/no-useless-mustaches` rule of eslint-plugin-svelte 3.24.1: a text mustache
// tag whose expression is a string literal (or a template literal without expressions) could be
// plain text; the fix writes the text (with HTML entities for `<`, `>` or the attribute's quote)
// when it has no comment, no escape and no white space at its ends. Options ignoreIncludesComment
// and ignoreStringEscape.

const snum_messages = {
	'unexpected': 'Unexpected mustache interpolation with a string literal value.'
}

struct SnumOptions {
	ignore_comment bool
	ignore_escape  bool
}

fn snum_options(options []json2.Any) !SnumOptions {
	o := option_object(svelte_no_useless_mustaches, options, ['ignoreIncludesComment',
		'ignoreStringEscape'])!
	return SnumOptions{
		ignore_comment: o.bool_value('ignoreIncludesComment')!
		ignore_escape:  o.bool_value('ignoreStringEscape')!
	}
}

// snum_strip_quotes is stripQuotes: the text without its quotes ("…", '…' or `…`), none when it
// has none.
fn snum_strip_quotes(text string) ?string {
	if text.len >= 1 && text[0] in [`"`, `'`, `\``] && text.ends_with(text[0..1]) {
		// text.slice(1, -1) of a one-character text is ''.
		return if text.len >= 2 { text[1..text.len - 1] } else { '' }
	}
	return none
}

// snum_unescape is text.replace(/\\([\s\S])/g, '$1').
fn snum_unescape(text string) string {
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		if text[i] == `\\` && i + 1 < text.len {
			i++
		}
		out << text[i]
		i++
	}
	return out.bytestr()
}

fn (mut c Checker) lint_svelte_no_useless_mustaches(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := snum_options(c.rule_options(svelte_no_useless_mustaches))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	es := &doc.es
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.mustache_tag) {
		n := doc.nodes[i]
		if n.kind == 'raw' || n.expression.idx < 0 || !n.expression.es {
			continue
		}
		expression := n.expression.idx
		mut str_value := ''
		mut raw_value := ''
		is_template := es.nodes[expression].typ == .template_literal
		if es.nodes[expression].typ == .literal {
			value := es.get(expression, .value)
			if value !is string {
				continue
			}
			str_value = value as string
			text := c.sv_es_text(expression)
			raw_value = if text.len >= 2 { text[1..text.len - 1] } else { '' }
		} else if is_template {
			if (es.list(expression, .expressions) or { []int{} }).len > 0 {
				continue
			}
			quasis := es.list(expression, .quasis) or { continue }
			value := es.get(quasis[0], .value)
			if value !is estree.TemplateValue {
				continue
			}
			template := value as estree.TemplateValue
			str_value = template.cooked
			raw_value = template.raw
		} else {
			continue
		}
		has_comment := c.sv_tokens_in(n.start, n.end, true).any(sv_is_comment(it))
		if options.ignore_comment && has_comment {
			continue
		}
		if is_template && (raw_value.contains('\n') || raw_value.contains('\r')) {
			continue
		}
		if raw_value.contains('{') {
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
		if options.ignore_escape && has_escape {
			continue
		}
		mut finding := c.sv_report_snode(i, 'unexpected', {})
		if fix := c.snum_fix(i, has_comment || has_escape) {
			has_fix, merged := c.merge_fixes(fix)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     merged
			}
		}
		findings << finding
	}
	return findings
}

// snum_fix is the rule's fix: none when it gives null.
fn (c &Checker) snum_fix(i int, blocked bool) ?[]Fix {
	if blocked {
		return none
	}
	doc := c.svelte.doc
	n := doc.nodes[i]
	text := snum_strip_quotes(c.sv_es_text(n.expression.idx))?
	if text.contains('\n') {
		return none
	}
	if text.len > 0 {
		first := text.runes()[0]
		last := text.runes().last()
		if is_js_space(first) || is_js_space(last) {
			return none
		}
	}
	unescaped := snum_unescape(text)
	parent := doc.nodes[n.parent]
	if parent.typ in [.attribute, .style_directive] {
		_, key_end := c.sv_ref_range(parent.key)
		div := c.sv_text(key_end, doc.nodes[parent.values[0]].start)
		if div.ends_with('"') {
			return [Fix{
				start: n.start
				end:   n.end
				text:  unescaped.replace('"', '&quot;')
			}]
		}
		if div.ends_with("'") {
			return [Fix{
				start: n.start
				end:   n.end
				text:  unescaped.replace("'", '&apos;')
			}]
		}
		first_value := doc.nodes[parent.values[0]]
		last_value := doc.nodes[parent.values.last()]
		return [Fix{
			start: first_value.start
			end:   first_value.start
			text:  '"'
		}, Fix{
			start: n.start
			end:   n.end
			text:  unescaped.replace('"', '&quot;')
		}, Fix{
			start: last_value.end
			end:   last_value.end
			text:  '"'
		}]
	}
	return [Fix{
		start: n.start
		end:   n.end
		text:  unescaped.replace('<', '&lt;').replace('>', '&gt;')
	}]
}
