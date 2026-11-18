module rules

import postcss
import svelte

// Port of the `svelte/no-unused-svelte-ignore` rule of eslint-plugin-svelte 3.24.1, in part: a
// `svelte-ignore` comment (a script comment or an HTML comment) without a code is reported
// (missingCode). Not ported: `unused`, a code no warning of the Svelte compiler uses, which needs
// the compiler's warnings (shared/svelte-compile-warns runs `compile()`; to come with
// svelte/valid-compile): those cases are in tests/upstream/known.txt.

const snusi_messages = {
	'unused':      'svelte-ignore comment is used, but not warned'
	'missingCode': 'svelte-ignore comment must include the code'
}

// snusi_code_list is the text after SVELTE_IGNORE_PATTERN (/^\s*svelte-ignore\s+/) of a comment's
// text, none when it does not match.
fn snusi_code_list(s string) ?string {
	u := postcss.units(s)
	mut i := 0
	for i < u.len && postcss.is_js_space(u[i]) {
		i++
	}
	keyword := postcss.units('svelte-ignore')
	if i + keyword.len > u.len || u[i..i + keyword.len] != keyword {
		return none
	}
	i += keyword.len
	if i >= u.len || !postcss.is_js_space(u[i]) {
		return none
	}
	for i < u.len && postcss.is_js_space(u[i]) {
		i++
	}
	return postcss.text(u[i..])
}

// snusi_missing_code is hasMissingCodeIgnore: nothing but parenthetical notes (/\([^)]*\)/gu) and
// spaces.
fn snusi_missing_code(code_list string) bool {
	mut out := []u8{}
	mut i := 0
	for i < code_list.len {
		if code_list[i] == `(` {
			close := code_list.index_after(')', i + 1) or { -1 }
			if close >= 0 {
				i = close + 1
				continue
			}
		}
		out << code_list[i]
		i++
	}
	return postcss.js_trim(out.bytestr()) == ''
}

fn (mut c Checker) lint_svelte_no_unused_svelte_ignore(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut items := []svelte.Token{}
	for comment in doc.comments {
		code_list := snusi_code_list(comment.value) or { continue }
		if snusi_missing_code(code_list) {
			items << comment
		}
	}
	for token in doc.tokens {
		if token.typ != 'HTMLComment' || token.value.len < 7 {
			continue
		}
		code_list := snusi_code_list(token.value[4..token.value.len - 3]) or { continue }
		if snusi_missing_code(code_list) {
			items << token
		}
	}
	mut findings := []Finding{}
	for t in items {
		findings << c.sv_report(sv_token_loc_start(t), sv_token_loc_end(t), 'missingCode', {})
	}
	return findings
}
