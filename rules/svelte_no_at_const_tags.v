module rules

// Port of the `svelte/no-at-const-tags` rule of eslint-plugin-svelte 3.24.1 (Svelte 5.56 and
// later, in runes mode): `{@const x = …}` should be the declaration tag `{const x = $derived(…)}`;
// the fix removes the `@` and wraps the initializer in `$derived(…)` unless it is one already.

const snact_messages = {
	'unexpected': 'Use `{const ...}` declaration tag instead of legacy `{@const ...}`.'
}

fn (mut c Checker) lint_svelte_no_at_const_tags(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() || !c.sv_runes() {
		return []
	}
	doc := c.svelte.doc
	es := &doc.es
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.const_tag) {
		n := doc.nodes[i]
		mut finding := c.sv_report_snode(i, 'unexpected', {})
		// /^\{(\s*)@const\b/ on the tag's text.
		text := c.sv_text(n.start, n.end)
		mut k := 1
		for k < text.len {
			r := text[k..].runes()[0]
			if !is_js_space(r) {
				break
			}
			k += r.str().len
		}
		rest := text[k..]
		if text.starts_with('{') && rest.starts_with('@const')
			&& (rest.len == 6 || !sv_is_word_char(rest[6])) {
			at := n.start + k
			mut fixes := [Fix{
				start: at
				end:   at + 1
			}]
			if n.declarations.len > 0 {
				if init := es.node(n.declarations[0], .init) {
					callee := es.node(init, .callee) or { -1 }
					derived := es.nodes[init].typ == .call_expression && callee >= 0
						&& es.nodes[callee].typ == .identifier
						&& (es.string_of(callee, .name) or { '' }) == '\$derived'
					if !derived {
						fixes << Fix{
							start: es.nodes[init].start
							end:   es.nodes[init].start
							text:  '\$derived('
						}
						fixes << Fix{
							start: es.nodes[init].end
							end:   es.nodes[init].end
							text:  ')'
						}
					}
				}
			}
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	return findings
}

// sv_is_word_char is \w: an ASCII letter, digit or `_`.
fn sv_is_word_char(b u8) bool {
	return b.is_letter() || b.is_digit() || b == `_`
}
