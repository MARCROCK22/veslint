module svelte

// Unit tests of the corners .claude/svelte-parser-spec.md flags (§14); the differential test
// (tools/svelte_parse_diff.mjs) checks everything against svelte-eslint-parser.

fn parse_ok(src string) &Document {
	doc := parse_svelte(src) or { panic(err) }
	if e := doc.error {
		panic('unexpected error: ${e.message}')
	}
	return doc
}

fn tokens_text(d &Document) []string {
	return d.tokens.map('${it.typ}:${it.value}')
}

fn test_blank_not_cut() {
	src := '<script lang="ts">\n\tlet a = 1;\r\n</script>\n<p>é{a}</p>\n'
	sc := split_document(src)
	assert sc.template.len == src.len
	assert sc.script_raw.len == src.len
	// Script contents are blanked in the template code, markup in the script code (byte per
	// byte; the JavaScript copy one space per UTF-16 unit).
	assert sc.template.contains('<script lang="ts">\n \r\n</script>') == false
	assert sc.script_raw.contains('\tlet a = 1;\r\n')
	assert u16_len_of(sc.script_u16) == new_text_index(src).u16_len
}

fn test_separator_trims_last_statement() {
	src := '<script lang="ts">\n  let a = 1\n</script>\n{a}\n'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	script := doc.nodes[doc.nodes[0].children[0]]
	st := doc.es.nodes[script.body[0]]
	// `let a = 1` without `;` takes the separator `\n;` in the pre-virtual code; it ends at `1`.
	assert src[st.start..st.end] == 'let a = 1'
	assert doc.pre.contains('let a = 1\n;')
	// The separator `;` is no token.
	assert !doc.tokens.any(it.value == ';')
}

fn test_parens_are_gap_tokens() {
	src := '<p>{(a)}</p>'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	toks := tokens_text(doc)
	assert 'Punctuator:(' in toks
	assert 'Punctuator:)' in toks
	m := doc.nodes[doc.nodes[doc.nodes[0].children[0]].children[0]]
	e := doc.es.nodes[m.expression.idx]
	assert src[e.start..e.end] == 'a'
}

fn test_trimmed_text_untrimmed_range() {
	src := '{#each [1] as x}\n  empty  \n{/each}'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	each := doc.nodes[doc.nodes[0].children[0]]
	text := doc.nodes[each.children[0]]
	assert text.value == 'empty'
	assert src[text.start..text.end] == '\n  empty  \n'
	assert 'MustacheKeyword:/each' in tokens_text(doc)
	assert 'MustacheKeyword:#each' in tokens_text(doc)
	assert 'Keyword:as' in tokens_text(doc)
}

fn test_implicitly_closed_end_tag() {
	src := '<div><p><b>x</b></div>'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	div := doc.nodes[doc.nodes[0].children[0]]
	p := doc.nodes[div.children[0]]
	// The end tag found by lastIndexOf("<") is the `</b>` of the child.
	et := doc.nodes[p.end_tag]
	assert src[et.start..et.end] == '</b>'
	assert doc.tokens.filter(it.typ == 'HTMLIdentifier' && it.value == 'b').len == 3
}

fn test_start_tag_comments() {
	src := '<div // line\n /* block */ class="a">{#if a}<span /* in block */ />{/if}</div>'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	assert doc.comments.map(it.value) == [' line', ' block ']
	// The comment in the start tag of an element inside a block becomes one-character tokens.
	assert doc.tokens.any(it.typ == 'Identifier' && it.value == 'i')
}

fn test_shorthand_attribute_identifiers() {
	src := '<script lang="ts">let n = 1;</script><b {n}></b>'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	b := doc.nodes[doc.nodes[0].children[1]]
	attr := doc.nodes[doc.nodes[b.start_tag].attributes[0]]
	assert attr.typ == .shorthand_attribute
	assert attr.key.es && attr.value_ref.es && attr.key.idx != attr.value_ref.idx
	assert doc.es.nodes[attr.key.idx].typ == .identifier
}

fn test_generics_extends_token() {
	src := '<script lang="ts" generics="T extends string">let a: T;</script>'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	g := doc.nodes[doc.nodes[doc.nodes[0].children[0]].start_tag].attributes[1]
	assert doc.nodes[g].typ == .generics_directive
	ext := doc.tokens.filter(it.value == 'extends')[0]
	assert ext.typ == 'Keyword'
	assert src[ext.start..ext.end] == 'extends'
	// Its loc is the one of the `=` of the virtual `type T =     string;`.
	assert ext.loc_start == ext.start + 1
	assert doc.pre.contains('type T  =      string;')
}

fn test_virtual_code() {
	src := '<script lang="ts">\n  let count = \$state(0);\n</script>\n<button on:click={handle}>{count}</button>\n'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	v := doc.virtual_code
	assert v.contains('declare function \$state<T>(initial: T): T;')
	assert v.contains('export function \$_render1(){')
	assert v.contains("import('svelte/elements').SvelteHTMLElements")
	assert v.contains('export { \$_svelteComponent')
	assert v.contains('export namespace SvelteEslintParserModuleMarker {}')
}

fn test_template_only_file_is_typescript() {
	mut doc := parse_ok('<p>{a}</p>')
	defer {
		doc.free()
	}
	assert doc.lang == ''
	assert doc.virtual_code.contains('export function \$_render')
	// No lang: the JavaScript blank line before the user's code.
	assert doc.parser_codes().len == 2
}

fn test_compiler_error() {
	doc := parse_svelte('<div>{a +}</div>') or { panic(err) }
	e := doc.error or { panic('no error') }
	assert e.message.ends_with('\nhttps://svelte.dev/e/js_parse_error')
	assert e.code == 'js_parse_error'
	doc2 := parse_svelte('<div>') or { panic(err) }
	e2 := doc2.error or { panic('no error') }
	assert e2.message == '`<div>` was left open\nhttps://svelte.dev/e/element_unclosed'
	assert e2.index == 0
}

fn test_scopes() {
	src := '<script lang="ts">\n  import { writable } from "svelte/store";\n  const s = writable(1);\n  let items = \$state([1]);\n</script>\n{#each items as item}{item}{\$s}{/each}\n'
	mut doc := parse_ok(src)
	defer {
		doc.free()
	}
	info := &doc.scope
	// The each block's function scope is registered to the SvelteEachBlock.
	mut each_scope := -1
	for k, s in info.scopes {
		if !s.block.es && doc.nodes[s.block.idx].typ == .each_block {
			each_scope = k
		}
	}
	assert each_scope > 0
	assert info.scopes[each_scope].typ == 'function'
	assert info.scopes[each_scope].variables.map(info.variables[it].name) == ['item']
	// `$s` reads the store `s`; `$state` is a Svelte global.
	mut store_refs := 0
	for r in info.references {
		name := doc.es.string_of(r.identifier, .name) or { '' }
		if name == '\$s' && r.resolved >= 0 && info.variables[r.resolved].name == 's' {
			store_refs++
		}
		if name == '\$state' {
			assert r.resolved >= 0 && info.variables[r.resolved].global
		}
	}
	assert store_refs == 1
}
