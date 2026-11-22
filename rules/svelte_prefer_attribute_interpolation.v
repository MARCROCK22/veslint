module rules

import estree

// Port of the `svelte/prefer-attribute-interpolation` rule of eslint-plugin-svelte 3.24.1: an
// attribute whose one value is a template literal with expressions could be written as text with
// mustache tags; not when the tag has a comment, or a quasi has a line break, a `{` or an escape
// that matters.

const spai_messages = {
	'unexpected': 'Prefer attribute interpolation over a template literal.'
}

// spai_has_useful_escape is hasUsefulStringEscape.
fn spai_has_useful_escape(raw string, cooked string) bool {
	if raw == cooked {
		return false
	}
	chars := raw.runes()
	mut k := 0
	for k < chars.len {
		if chars[k] == `\\` {
			k++
			if k >= chars.len || chars[k] in [`n`, `r`, `v`, `t`, `b`, `f`, `u`, `x`] {
				return true
			}
		}
		k++
	}
	return false
}

fn (mut c Checker) lint_svelte_prefer_attribute_interpolation(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	es := &doc.es
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.attribute) {
		n := doc.nodes[i]
		if n.values.len != 1 {
			continue
		}
		value := n.values[0]
		v := doc.nodes[value]
		if v.typ != .mustache_tag || !v.expression.es || v.expression.idx < 0
			|| es.nodes[v.expression.idx].typ != .template_literal
			|| (es.list(v.expression.idx, .expressions) or { []int{} }).len == 0 {
			continue
		}
		if c.sv_tokens_in(v.start, v.end, true).any(sv_is_comment(it)) {
			continue
		}
		mut useless := false
		for quasi in es.list(v.expression.idx, .quasis) or { []int{} } {
			tv := es.get(quasi, .value)
			if tv !is estree.TemplateValue {
				continue
			}
			t := tv as estree.TemplateValue
			cooked := if t.has_cooked { t.cooked } else { t.raw }
			if t.raw.contains('\n') || t.raw.contains('\r') || t.raw.contains('{')
				|| spai_has_useful_escape(t.raw, cooked) {
				useless = true
				break
			}
		}
		if useless {
			continue
		}
		findings << c.sv_report_snode(value, 'unexpected', {})
	}
	return findings
}
