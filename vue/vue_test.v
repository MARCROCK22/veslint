module vue

// Unit tests of the corners of vue-eslint-parser 10.4.2 that .claude/vue-parser-spec.md flags.
// tools/vue_parse_diff.mjs compares the whole output with the real parser; these pin the
// behaviours one by one.

fn parse(src string) &Document {
	return parse_sfc(src) or { panic(err) }
}

fn token_strings(d &Document) []string {
	return d.tokens.map('${it.typ} ${it.value}')
}

fn find_token(d &Document, typ string) Token {
	for t in d.tokens {
		if t.typ == typ {
			return t
		}
	}
	panic('no ${typ} token')
}

fn first_element(d &Document, name string) int {
	for i, n in d.nodes {
		if n.typ == .v_element && n.name == name {
			return i
		}
	}
	return -1
}

fn attribute(d &Document, element int, i int) VNode {
	return d.nodes[d.nodes[d.nodes[element].start_tag].attributes[i]]
}

fn error_codes(d &Document) []string {
	return d.errors.map(if it.code != '' { it.code } else { it.message })
}

// ---- Tokenizer ----

fn test_crlf_is_one_line_break_and_a_gap() {
	src := '<template>\r\n  <a>x</a>\r\n</template>'
	d := parse(src)
	assert d.line_terminators == [12, 24]
	ws := d.tokens.filter(it.typ == 'HTMLWhitespace')[0]
	assert ws.value == '\n  '
	assert ws.start == 10 && ws.end == 14
	assert d.gaps == [11, 23]
	a := first_element(d, 'a')
	assert d.loc(d.nodes[a].start) == Loc{2, 2}
}

fn test_lone_cr_and_line_separator_do_not_break_lines() {
	d := parse('<template>a\rb c<b>x</b></template>')
	assert d.line_terminators.len == 0
	b := first_element(d, 'b')
	// `a`, CR, `b`, U+2028 (one UTF-16 unit, three bytes), `c`.
	assert d.loc(d.nodes[b].start) == Loc{1, 15}
	assert d.nodes[b].start == 17
	text := d.nodes[d.nodes[d.template_body].children[0]]
	assert text.text == 'a\nb c'
}

fn test_legacy_entity_without_semicolon_in_attribute_is_kept() {
	d := parse('<template><a title="&lt c &amp; &lt">x</a></template>')
	a := first_element(d, 'a')
	// The quirk: the name's second character decides, and it is always alphanumeric.
	assert d.nodes[attribute(d, a, 0).value].text == '&lt c & &lt'
	assert d.errors.len == 0
}

fn test_text_entity_without_semicolon_reports_at_last_letter() {
	src := '<template>&amp y</template>'
	d := parse(src)
	text := d.nodes[d.nodes[d.template_body].children[0]]
	assert text.text == '& y'
	assert d.errors.len == 1
	assert d.errors[0].code == 'missing-semicolon-after-character-reference'
	assert d.errors[0].index == src.index('amp') or { 0 } + 2
}

fn test_numeric_references() {
	d := parse('<template>&#0;&#x110000;&#xD800;&#128;&#65</template>')
	text := d.nodes[d.nodes[d.template_body].children[0]]
	assert text.text == '���€A'
	assert error_codes(d) == ['null-character-reference', 'character-reference-outside-unicode-range',
		'surrogate-character-reference', 'control-character-reference',
		'missing-semicolon-after-character-reference']
}

fn test_comment_values() {
	d := parse('<!-- a -- b --><!---><!-- x --!><?php x ?><!DOCTYPE html><![CDATA[x]]></ >')
	assert d.comments.map(it.value) == [' a -- b ', '', ' x ', '?php x ?', 'DOCTYPE html', '[CDATA[x]]',
		' ']
	assert d.comments.map(it.typ) == ['HTMLComment', 'HTMLComment', 'HTMLComment', 'HTMLBogusComment',
		'HTMLBogusComment', 'HTMLBogusComment', 'HTMLBogusComment']
	assert error_codes(d) == ['abrupt-closing-of-empty-comment', 'incorrectly-closed-comment',
		'unexpected-question-mark-instead-of-tag-name', 'cdata-in-html-content',
		'invalid-first-character-of-tag-name']
}

fn test_empty_end_tag_makes_no_token() {
	d := parse('<template>a</>b</template>')
	assert d.tokens.filter(it.typ == 'HTMLEndTagOpen').len == 1
	assert error_codes(d) == ['missing-end-tag-name']
}

fn test_input_stream_error_has_the_previous_location() {
	src := '<template>\n\x01</template>'
	d := parse(src)
	assert d.errors.len == 1
	e := d.errors[0]
	assert e.code == 'control-character-in-input-stream'
	assert e.index == 11
	// Reported before the tokenizer moved on: at the line break, on line 1.
	assert e.line == 1 && e.column == 10
}

// ---- Mustaches ----

fn test_mustache_runs_to_the_next_close_anywhere() {
	d := parse('<template><a>{{ x </a> y }}</template>')
	a := first_element(d, 'a')
	container := d.nodes[d.nodes[a].children[0]]
	assert container.typ == .v_expression_container
	assert container.expression.is_null()
	assert d.errors.len == 1 && d.errors[0].ts_message
}

fn test_empty_mustache_is_text_and_unclosed_is_an_error() {
	d := parse('<template>{{}} {{ a</template>')
	children := d.nodes[d.template_body].children
	assert children.len == 1
	assert d.nodes[children[0]].typ == .v_text
	assert d.nodes[children[0]].text == '{{}} {{ a'
	assert error_codes(d) == ['x-missing-interpolation-end']
	assert d.tokens.map(it.typ)[2..8] == ['VExpressionStart', 'VExpressionEnd', 'HTMLWhitespace',
		'VExpressionStart', 'HTMLWhitespace', 'HTMLText']
}

fn test_mustache_value_is_decoded() {
	src := '<template>{{ a &lt; b }}</template>'
	d := parse(src)
	assert d.tokens.map('${it.typ} ${it.value}')[2..7] == ['VExpressionStart {{', 'Identifier a',
		'Punctuator <', 'Identifier b', 'VExpressionEnd }}']
	lt := d.tokens.filter(it.typ == 'Punctuator' && it.value == '<')[0]
	assert src[lt.start..lt.end] == '&lt;'
}

// ---- Tree ----

fn test_implicitly_closed_elements() {
	d := parse('<template><p>one<div>two</div><ul><li>a<li>b</ul><dl><dt>t<dd>d</dl></template>')
	children := d.nodes[d.template_body].children.map(d.nodes[it].name)
	assert children == ['p', 'div', 'ul', 'dl']
	ul := first_element(d, 'ul')
	assert d.nodes[ul].children.map(d.nodes[it].name) == ['li', 'li']
	dl := first_element(d, 'dl')
	assert d.nodes[dl].children.map(d.nodes[it].name) == ['dt', 'dd']
}

fn test_attribute_and_end_tag_errors() {
	d := parse('<template><div a=1 A=2></div x="1"><span/></Span></template>')
	assert error_codes(d) == ['duplicate-attribute', 'end-tag-with-attributes',
		'non-void-html-element-start-tag-with-trailing-solidus', 'x-invalid-end-tag']
	div := first_element(d, 'div')
	end_tag := d.nodes[d.nodes[div].end_tag]
	assert d.src[end_tag.start..end_tag.end] == '</div x="1">'
}

fn test_names_are_case_sensitive_where_vue_says() {
	d := parse('<template><Br>x<P>y<div>z</div></P><svg viewbox="0"><foreignObject><b/></foreignObject></svg><SVG/></template>')
	br := first_element(d, 'br')
	// <Br> is not void: it holds what follows.
	assert d.nodes[br].children.len > 0
	svg := first_element(d, 'svg')
	assert d.nodes[svg].namespace == .svg
	assert d.nodes[attribute(d, svg, 0).key].name == 'viewBox'
	fo := first_element(d, 'foreignObject')
	assert d.nodes[fo].raw_name == 'foreignObject'
	b := first_element(d, 'b')
	assert d.nodes[b].namespace == .html
}

fn test_v_pre() {
	d := parse('<template><div v-pre :a="b">{{ raw }}</div>{{ c }}</template>')
	div := first_element(d, 'div')
	pre := attribute(d, div, 0)
	assert pre.directive
	assert d.nodes[d.nodes[pre.key].dir_name].name == 'pre'
	assert !attribute(d, div, 1).directive
	assert d.nodes[d.nodes[div].children[0]].typ == .v_text
	last := d.nodes[d.template_body].children.last()
	assert d.nodes[last].typ == .v_expression_container
}

fn test_top_level_self_closing_enables_expressions() {
	d := parse('<foo/>\n{{ top }}\n<docs :a="b">x</docs>')
	kinds := d.nodes[0].children.map(d.nodes[it].typ)
	assert kinds == [NodeType.v_element, .v_text, .v_expression_container, .v_text, .v_element]
	docs := first_element(d, 'docs')
	assert attribute(d, docs, 0).directive
}

fn test_template_body_is_the_first_template_if_html() {
	d := parse('<template lang="pug">div</template><template><a/></template>')
	assert d.template_body == -1
	d2 := parse('<template lang="html"><a/></template>')
	assert d2.template_body == d2.nodes[0].children[0]
}

fn test_comments_split_text() {
	d := parse('<template>a<!-- c -->b</template>')
	assert d.nodes[d.template_body].children.map(d.nodes[it].text) == ['a', 'b']
}

// ---- Directives ----

fn test_directive_keys() {
	src := '<template><a :fooBar="x" @Update:modelValue.Once="y" .foo="z" #default v-.a="w"/></template>'
	d := parse(src)
	a := first_element(d, 'a')
	bind := d.nodes[attribute(d, a, 0).key]
	assert d.nodes[bind.dir_name].name == 'bind' && d.nodes[bind.dir_name].raw_name == ':'
	assert d.nodes[bind.argument].name == 'foobar'
	assert d.nodes[bind.argument].raw_name == 'fooBar'
	on := d.nodes[attribute(d, a, 1).key]
	assert d.nodes[on.argument].name == 'update:modelvalue'
	assert on.modifiers.map(d.nodes[it].name) == ['once']
	prop := d.nodes[attribute(d, a, 2).key]
	assert prop.modifiers.len == 1
	m := d.nodes[prop.modifiers[0]]
	assert m.name == 'prop' && m.raw_name == '' && m.start == m.end
	slot := d.nodes[attribute(d, a, 3).key]
	assert d.nodes[slot.dir_name].name == 'slot'
	assert d.nodes[slot.argument].name == 'default'
	bad := d.nodes[attribute(d, a, 4).key]
	assert d.nodes[bad.dir_name].name == ''
	assert error_codes(d) == ['non-void-html-element-start-tag-with-trailing-solidus',
		"Unexpected token '.'"]
	// The `.prop` modifier has no token; `.`, `:`, `@`, `#` are punctuators.
	assert d.tokens.filter(it.typ == 'Punctuator').map(it.value)[..4] == [':', '"', '"', '@']
}

fn test_dynamic_argument() {
	d := parse('<template><a :[key]="v" :[a b]="1"/></template>')
	a := first_element(d, 'a')
	arg := d.nodes[d.nodes[attribute(d, a, 0).key].argument]
	assert arg.typ == .v_expression_container
	assert !arg.expression.is_null()
	assert error_codes(d).contains("Dynamic argument cannot contain the ' ' character.")
}

fn test_same_name_shorthand_has_no_tokens() {
	d := parse('<template><a :foo-bar/></template>')
	a := first_element(d, 'a')
	value := d.nodes[attribute(d, a, 0).value]
	assert value.typ == .v_expression_container
	assert d.references[value.references[0]].name == 'fooBar'
	assert !d.references[value.references[0]].has_kind
	assert d.tokens.filter(it.typ == 'Identifier').len == 0
}

fn test_failed_directive_keeps_the_literal_token() {
	d := parse('<template><a :x="a b"/></template>')
	assert d.tokens.filter(it.typ == 'HTMLLiteral').len == 1
	a := first_element(d, 'a')
	assert d.nodes[attribute(d, a, 0).value].expression.is_null()
}

// ---- Expressions ----

fn test_v_on_kinds() {
	d := parse('<template><a @a="go" @b="go()" @c="() => go()" @d="foo.bar[\'baz\'][0]" @e="a++; b()"/></template>')
	a := first_element(d, 'a')
	mut kinds := []string{}
	for i in 0 .. 5 {
		e := d.nodes[attribute(d, a, i).value].expression
		kinds << if e.kind == .vnode {
			d.nodes[e.node].typ.type_name()
		} else {
			d.snippets[e.snippet].es.typ(e.node).type_name()
		}
	}
	assert kinds == ['Identifier', 'VOnExpression', 'ArrowFunctionExpression', 'MemberExpression',
		'VOnExpression']
	assert d.snippets.map(it.code)[1] == 'void function(\$event){go()}'
}

fn test_v_for_wrappers_and_tokens() {
	d := parse('<template><a v-for="(v, k) in obj" :k="k"/><b v-for="x of xs"/></template>')
	codes := d.snippets.map(it.code)
	assert codes.contains('for(let [v, k] in obj);')
	assert codes.contains('for(let [x]of xs);')
	a := first_element(d, 'a')
	assert d.nodes[a].variables.map(d.variables[it].name) == ['v', 'k']
	// `:k` resolves to the v-for variable.
	kref := d.references[d.nodes[attribute(d, a, 1).value].references[0]]
	assert d.variables[kref.variable].name == 'k'
	values := d.tokens.map(it.value)
	assert values.contains('(') && values.contains(')')
	assert !values.contains('[')
}

fn test_filters() {
	d := parse("<template>{{ msg | cap('a') | low }}</template>")
	c := d.nodes[d.nodes[d.template_body].children[0]]
	seq := d.nodes[c.expression.node]
	assert seq.typ == .v_filter_sequence_expression
	assert seq.filters.map(d.nodes[it].callee_name) == ['cap', 'low']
	assert d.snippets.map(it.code) == ['0( msg )', '"cap"', "0('a') ", '"low"']
}

fn test_template_type_references() {
	d := parse('<template>{{ x as Foo }}</template>')
	c := d.nodes[d.nodes[d.template_body].children[0]]
	refs := c.references.map(d.references[it])
	assert refs.map(it.name) == ['x', 'Foo']
	assert refs[1].is_type_reference && !refs[1].is_value_reference
}

fn test_lib_globals_are_not_references() {
	// `Math` is a variable of the lib esnext; `Infinity` is not one of typescript-eslint's.
	d := parse('<template>{{ Math.max(a, Infinity) }}</template>')
	c := d.nodes[d.nodes[d.template_body].children[0]]
	assert c.references.map(d.references[it].name) == ['a', 'Infinity']
}

fn test_positions_are_bytes_and_columns_utf16() {
	src := '<template>é😀{{ x }}</template>'
	d := parse(src)
	c := d.nodes[d.nodes[d.template_body].children[1]]
	assert c.start == src.index('{{') or { 0 }
	// é is one unit, 😀 two.
	assert d.loc(c.start) == Loc{1, 13}
	assert d.utf16(c.start) == 13
}

fn test_expression_error_message_is_left_to_typescript() {
	d := parse('<template><a :x="foo."></a></template>')
	assert d.errors.len == 1
	e := d.errors[0]
	assert e.ts_message
	assert e.adjust_end >= 0
	assert d.snippets[e.snippet].code == '0(foo.)'
}

// ---- Script ----

const both = '<script lang="ts">\nexport default { name: \'Both\' };\nconst top = 1;\n</script>\n\n<script setup lang="ts">\nimport { ref } from \'vue\';\nconst count = ref(top);\n</script>\n<template><div>{{ count }}</div></template>'

fn test_script_setup_synthetic_code() {
	d := parse(both)
	s := d.script
	assert s.combined
	assert s.code == "\nexport default { name: 'Both' };\nconst top = 1;\n;\nimport { ref } from 'vue';\n;\n\n{\n\n;\n\nconst count = ref(top);\n;\n\n}\n"
	assert s.program_start == 18 && s.program_end == 153
	// `import` of the code is the `import` of the file.
	at := s.code.index('import') or { 0 }
	assert both[s.synthetic_to_file(at, false)..].starts_with('import')
	assert s.tokens[0].value == '<script>' && s.tokens.last().value == '</script>'
	assert s.lang == .ts
}

fn test_masked_script_keeps_offsets_and_lines() {
	d := parse(both)
	m := d.masked_script()
	assert m.len == both.len
	for i, ch in both {
		if ch == `\n` {
			assert m[i] == `\n`
		}
	}
	assert m.contains("export default { name: 'Both' };")
	assert !m.contains('<template>')
}

fn test_whitespace_script_starts_the_program_at_zero() {
	d := parse('<script lang="ts">\n  \n</script>\n<script setup lang="ts">\nconst a = 1\n</script>')
	assert d.script.program_start == 0
}

fn test_single_script_program_is_its_content() {
	src := '<script lang="ts">\nexport const a = 1\n</script>'
	d := parse(src)
	assert d.script.program_start == 18 && d.script.program_end == 38
	assert d.script.code == '\nexport const a = 1\n'
	assert d.script.synthetic_to_file(1, false) == 19
}

fn test_script_lang_decision() {
	assert parse('<template><a/></template>').script.lang == .none
	assert parse('<script></script>').script.lang == .js
	assert parse('<script>let a</script>').script.lang == .js
	assert parse('<script lang="tsx">let a</script>').script.lang == .tsx
	assert parse('<script>let a</script><script setup lang="ts">let b</script>').script.lang == .ts
}

fn test_generic_constraints() {
	assert generic_constraint('T', 'T extends string') == ' string'
	assert generic_constraint('U', 'U = number') == 'unknown'
	assert generic_constraint('V', 'V extends (a: T) => void = () => void') == ' (a: T) => void '
	assert generic_constraint('K', 'K extends keyof T /* c = */ = keyof T') == ' keyof T /* c = */ '
	d := parse('<script setup lang="ts" generic="T extends string">\nconst a = 1\n</script>')
	assert d.script.code == 'type T =  string;\n\nconst a = 1\n'
}

fn test_style_v_bind() {
	src := '<style>.a { color: v-bind(color); width: v-bind( "w.x" ) }</style>'
	d := parse(src)
	style := first_element(d, 'style')
	assert d.nodes[style].style
	kinds := d.nodes[style].children.map(d.nodes[it].typ)
	assert kinds == [NodeType.v_text, .v_expression_container, .v_text, .v_expression_container,
		.v_text]
	assert d.snippets.map(it.code) == ['0(color)', '0(w.x)']
}

// ---- Found by fuzzing against vue-eslint-parser ----

fn test_nul_in_a_directive_name() {
	// The name has U+FFFD (three bytes) where the source has NUL (one): the key is cut by code
	// point.
	d := parse('<template><a :cl\x00ass="x"></a></template>')
	a := first_element(d, 'a')
	key := d.nodes[attribute(d, a, 0).key]
	arg := d.nodes[key.argument]
	assert arg.raw_name == 'cl\x00ass'
	assert arg.name == 'cl�ass'
	assert d.src[arg.start..arg.end] == 'cl\x00ass'
}

fn test_stream_error_after_a_named_reference() {
	// `&amp;` moves the tokenizer's column without advance_location.
	d := parse('<&amp;￾')
	e := d.errors.filter(it.code == 'noncharacter-in-input-stream')[0]
	assert e.line == 1 && e.column == 5
}

fn test_identifier_characters_typescript_rejects() {
	d := parse('<template><a v-slot="a😀"></a>{{ b }}</template>')
	assert d.errors.len == 1
	assert d.errors[0].ts_message
	assert d.errors[0].message == 'Invalid character.'
}

// file_to_synthetic is the inverse of synthetic_to_file on the scripts, -1 out of them (the
// `export` a named export of a <script setup> loses, the tags), and synthetic_token_ends has the
// ends of the punctuators the code adds, where TypeScript's next node starts.
fn test_file_to_synthetic() {
	d := parse(both)
	s := d.script
	at := both.index('import') or { 0 }
	code_at := s.file_to_synthetic(at, false)
	assert s.code[code_at..].starts_with('import')
	assert s.synthetic_to_file(code_at, false) == at
	assert s.file_to_synthetic(both.index('<template>') or { 0 }, false) == -1
	// With two scripts, the named exports of the setup lose their `export`.
	setup := parse('<script lang="ts">\nexport default {}\n</script>\n<script setup lang="ts">\nexport const x = 1\n</script>')
	export_at := setup.src.last_index('export') or { 0 }
	assert setup.script.file_to_synthetic(export_at, false) == -1
	const_at := setup.src.index('const') or { 0 }
	assert setup.script.code[setup.script.file_to_synthetic(const_at, false)..].starts_with('const x')
	ends := s.synthetic_token_ends([])
	block := s.code.index('{\n\n;') or { 0 }
	assert block + 1 in ends
}

// With a generic, the code starts with the defines: the first statement's TypeScript node starts
// after their `;`, and an offset of the file maps past them.
fn test_file_to_synthetic_with_generic() {
	src := '<script setup lang="ts" generic="T extends string">\nconst a: T = 1 as T\n</script>'
	d := parse(src)
	s := d.script
	assert s.code.starts_with('type T'), s.code
	at := src.index('const') or { 0 }
	assert s.code[s.file_to_synthetic(at, false)..].starts_with('const a')
	defines := s.code.index(';\n') or { 0 }
	assert s.synthetic_token_ends([]) == [defines + 1], s.code
}

// A `//` comment that ends a script content ends there in the masked script, not in the end tag.
fn test_line_comment_ends_with_the_content() {
	src := '<script lang="ts">export default {} // c</script>\n<template><div/></template>'
	d := parse(src)
	assert d.script.comments.len == 1
	assert d.script.comments[0].end == (src.index('</script>') or { 0 })
	assert d.script.masked.len == src.len
}

// What marks the variables of a <script setup> as used by the template, in vue-eslint-parser's
// order: an element that is a component, a custom directive, a `ref`, and the references of the
// expressions that nothing in the template resolves (not those of a v-for).
fn test_template_uses() {
	d := parse('<script setup lang="ts" generic="T">\nconst a = 1\n</script>\n<template><my-comp v-focus ref="el" :x="a" /><div v-for="i in list">{{ i }}</div></template>')
	assert d.has_script_setup()
	assert d.script_setup_generic_names() == ['T']
	uses := d.template_uses().map('${it.kind}:${it.name}')
	assert uses == ['element:my-comp', 'component:v-focus', 'exact:el', 'exact:a', 'exact:list']
	assert !parse('<script lang="ts">\nconst a = 1\n</script>').has_script_setup()
}
