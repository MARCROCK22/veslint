module jsregexp

// Expected results computed with Node 26 (V8) and @eslint-community/regexpp 4.12.2: validity in
// each mode and, for valid patterns, the top-level structure (c<hex code point>, s = ^, e = $,
// o = other).
struct RegexpCase {
	pattern string
	mode    string
	valid   bool
	alts    string
}

const regexp_cases = [
	RegexpCase{'a', '-', true, 'c61'},
	RegexpCase{'a', 'u', true, 'c61'},
	RegexpCase{'a', 'v', true, 'c61'},
	RegexpCase{'', '-', true, ''},
	RegexpCase{'', 'u', true, ''},
	RegexpCase{'', 'v', true, ''},
	RegexpCase{'(?<a>x)|(?<a>y)', '-', true, 'o|o'},
	RegexpCase{'(?<a>x)|(?<a>y)', 'u', true, 'o|o'},
	RegexpCase{'(?<a>x)|(?<a>y)', 'v', true, 'o|o'},
	RegexpCase{'(?<a>x)(?<a>y)', '-', false, ''},
	RegexpCase{'(?<a>x)(?<a>y)', 'u', false, ''},
	RegexpCase{'(?<a>x)(?<a>y)', 'v', false, ''},
	RegexpCase{'((?<a>x)|(?<a>y))(?<a>z)', '-', false, ''},
	RegexpCase{'((?<a>x)|(?<a>y))(?<a>z)', 'u', false, ''},
	RegexpCase{'((?<a>x)|(?<a>y))(?<a>z)', 'v', false, ''},
	RegexpCase{'(?:(?<a>x)|(?<b>y))|(?<a>z)', '-', true, 'o|o'},
	RegexpCase{'(?:(?<a>x)|(?<b>y))|(?<a>z)', 'u', true, 'o|o'},
	RegexpCase{'(?:(?<a>x)|(?<b>y))|(?<a>z)', 'v', true, 'o|o'},
	RegexpCase{'(?<a>(?<a>x))', '-', false, ''},
	RegexpCase{'(?<a>(?<a>x))', 'u', false, ''},
	RegexpCase{'(?<a>(?<a>x))', 'v', false, ''},
	RegexpCase{'\\k<a>(?<a>x)', '-', true, 'o.o'},
	RegexpCase{'\\k<a>(?<a>x)', 'u', true, 'o.o'},
	RegexpCase{'\\k<a>(?<a>x)', 'v', true, 'o.o'},
	RegexpCase{'\\k<a>', '-', true, 'c6b.c3c.c61.c3e'},
	RegexpCase{'\\k<a>', 'u', false, ''},
	RegexpCase{'\\k<a>', 'v', false, ''},
	RegexpCase{'(?<𝒜>x)', '-', true, 'o'},
	RegexpCase{'(?<𝒜>x)', 'u', true, 'o'},
	RegexpCase{'(?<𝒜>x)', 'v', true, 'o'},
	RegexpCase{'(?<\\uD835\\uDC9C>x)', '-', true, 'o'},
	RegexpCase{'(?<\\uD835\\uDC9C>x)', 'u', true, 'o'},
	RegexpCase{'(?<\\uD835\\uDC9C>x)', 'v', true, 'o'},
	RegexpCase{'(?<\\u{1d49c}>x)', '-', true, 'o'},
	RegexpCase{'(?<\\u{1d49c}>x)', 'u', true, 'o'},
	RegexpCase{'(?<\\u{1d49c}>x)', 'v', true, 'o'},
	RegexpCase{'(?<a\\u200c>x)', '-', true, 'o'},
	RegexpCase{'(?<a\\u200c>x)', 'u', true, 'o'},
	RegexpCase{'(?<a\\u200c>x)', 'v', true, 'o'},
	RegexpCase{'(?<\$>x)', '-', true, 'o'},
	RegexpCase{'(?<\$>x)', 'u', true, 'o'},
	RegexpCase{'(?<\$>x)', 'v', true, 'o'},
	RegexpCase{'(?<1>x)', '-', false, ''},
	RegexpCase{'(?<1>x)', 'u', false, ''},
	RegexpCase{'(?<1>x)', 'v', false, ''},
	RegexpCase{'[\\c]', '-', true, 'o'},
	RegexpCase{'[\\c]', 'u', false, ''},
	RegexpCase{'[\\c]', 'v', false, ''},
	RegexpCase{'\\c', '-', true, 'c5c.c63'},
	RegexpCase{'\\c', 'u', false, ''},
	RegexpCase{'\\c', 'v', false, ''},
	RegexpCase{'[\\c1]', '-', true, 'o'},
	RegexpCase{'[\\c1]', 'u', false, ''},
	RegexpCase{'[\\c1]', 'v', false, ''},
	RegexpCase{'\\c1', '-', true, 'c5c.c63.c31'},
	RegexpCase{'\\c1', 'u', false, ''},
	RegexpCase{'\\c1', 'v', false, ''},
	RegexpCase{'[a-\\d]', '-', true, 'o'},
	RegexpCase{'[a-\\d]', 'u', false, ''},
	RegexpCase{'[a-\\d]', 'v', false, ''},
	RegexpCase{'[\\w-\\d]', '-', true, 'o'},
	RegexpCase{'[\\w-\\d]', 'u', false, ''},
	RegexpCase{'[\\w-\\d]', 'v', false, ''},
	RegexpCase{'(?i:a)', '-', true, 'o'},
	RegexpCase{'(?i:a)', 'u', true, 'o'},
	RegexpCase{'(?i:a)', 'v', true, 'o'},
	RegexpCase{'(?-i:a)', '-', true, 'o'},
	RegexpCase{'(?-i:a)', 'u', true, 'o'},
	RegexpCase{'(?-i:a)', 'v', true, 'o'},
	RegexpCase{'(?i-s:a)', '-', true, 'o'},
	RegexpCase{'(?i-s:a)', 'u', true, 'o'},
	RegexpCase{'(?i-s:a)', 'v', true, 'o'},
	RegexpCase{'(?-:a)', '-', false, ''},
	RegexpCase{'(?-:a)', 'u', false, ''},
	RegexpCase{'(?-:a)', 'v', false, ''},
	RegexpCase{'(?ii:a)', '-', false, ''},
	RegexpCase{'(?ii:a)', 'u', false, ''},
	RegexpCase{'(?ii:a)', 'v', false, ''},
	RegexpCase{'(?i-i:a)', '-', false, ''},
	RegexpCase{'(?i-i:a)', 'u', false, ''},
	RegexpCase{'(?i-i:a)', 'v', false, ''},
	RegexpCase{'(?x:a)', '-', false, ''},
	RegexpCase{'(?x:a)', 'u', false, ''},
	RegexpCase{'(?x:a)', 'v', false, ''},
	RegexpCase{'(?<=a)+', '-', false, ''},
	RegexpCase{'(?<=a)+', 'u', false, ''},
	RegexpCase{'(?<=a)+', 'v', false, ''},
	RegexpCase{'(?=a)?', '-', true, 'o'},
	RegexpCase{'(?=a)?', 'u', false, ''},
	RegexpCase{'(?=a)?', 'v', false, ''},
	RegexpCase{'(?=a){2,1}', '-', false, ''},
	RegexpCase{'(?=a){2,1}', 'u', false, ''},
	RegexpCase{'(?=a){2,1}', 'v', false, ''},
	RegexpCase{'a{2,1}', '-', false, ''},
	RegexpCase{'a{2,1}', 'u', false, ''},
	RegexpCase{'a{2,1}', 'v', false, ''},
	RegexpCase{'a{,1}', '-', true, 'c61.c7b.c2c.c31.c7d'},
	RegexpCase{'a{,1}', 'u', false, ''},
	RegexpCase{'a{,1}', 'v', false, ''},
	RegexpCase{'a{1', '-', true, 'c61.c7b.c31'},
	RegexpCase{'a{1', 'u', false, ''},
	RegexpCase{'a{1', 'v', false, ''},
	RegexpCase{'{1}', '-', false, ''},
	RegexpCase{'{1}', 'u', false, ''},
	RegexpCase{'{1}', 'v', false, ''},
	RegexpCase{'{', '-', true, 'c7b'},
	RegexpCase{'{', 'u', false, ''},
	RegexpCase{'{', 'v', false, ''},
	RegexpCase{'}', '-', true, 'c7d'},
	RegexpCase{'}', 'u', false, ''},
	RegexpCase{'}', 'v', false, ''},
	RegexpCase{']', '-', true, 'c5d'},
	RegexpCase{']', 'u', false, ''},
	RegexpCase{']', 'v', false, ''},
	RegexpCase{'a**', '-', false, ''},
	RegexpCase{'a**', 'u', false, ''},
	RegexpCase{'a**', 'v', false, ''},
	RegexpCase{'\\b*', '-', false, ''},
	RegexpCase{'\\b*', 'u', false, ''},
	RegexpCase{'\\b*', 'v', false, ''},
	RegexpCase{'^*', '-', false, ''},
	RegexpCase{'^*', 'u', false, ''},
	RegexpCase{'^*', 'v', false, ''},
	RegexpCase{'\$?', '-', false, ''},
	RegexpCase{'\$?', 'u', false, ''},
	RegexpCase{'\$?', 'v', false, ''},
	RegexpCase{'[]', '-', true, 'o'},
	RegexpCase{'[]', 'u', true, 'o'},
	RegexpCase{'[]', 'v', true, 'o'},
	RegexpCase{'[^]', '-', true, 'o'},
	RegexpCase{'[^]', 'u', true, 'o'},
	RegexpCase{'[^]', 'v', true, 'o'},
	RegexpCase{'[]]', '-', true, 'o.c5d'},
	RegexpCase{'[]]', 'u', false, ''},
	RegexpCase{'[]]', 'v', false, ''},
	RegexpCase{'\\1(a)', '-', true, 'o.o'},
	RegexpCase{'\\1(a)', 'u', true, 'o.o'},
	RegexpCase{'\\1(a)', 'v', true, 'o.o'},
	RegexpCase{'(a)\\2', '-', true, 'o.c2'},
	RegexpCase{'(a)\\2', 'u', false, ''},
	RegexpCase{'(a)\\2', 'v', false, ''},
	RegexpCase{'\\10', '-', true, 'c8'},
	RegexpCase{'\\10', 'u', false, ''},
	RegexpCase{'\\10', 'v', false, ''},
	RegexpCase{'\\00', '-', true, 'c0'},
	RegexpCase{'\\00', 'u', false, ''},
	RegexpCase{'\\00', 'v', false, ''},
	RegexpCase{'\\400', '-', true, 'c20.c30'},
	RegexpCase{'\\400', 'u', false, ''},
	RegexpCase{'\\400', 'v', false, ''},
	RegexpCase{'\\378', '-', true, 'c1f.c38'},
	RegexpCase{'\\378', 'u', false, ''},
	RegexpCase{'\\378', 'v', false, ''},
	RegexpCase{'[\\8]', '-', true, 'o'},
	RegexpCase{'[\\8]', 'u', false, ''},
	RegexpCase{'[\\8]', 'v', false, ''},
	RegexpCase{'[\\08]', '-', true, 'o'},
	RegexpCase{'[\\08]', 'u', false, ''},
	RegexpCase{'[\\08]', 'v', false, ''},
	RegexpCase{'\\x', '-', true, 'c78'},
	RegexpCase{'\\x', 'u', false, ''},
	RegexpCase{'\\x', 'v', false, ''},
	RegexpCase{'\\xg1', '-', true, 'c78.c67.c31'},
	RegexpCase{'\\xg1', 'u', false, ''},
	RegexpCase{'\\xg1', 'v', false, ''},
	RegexpCase{'\\u', '-', true, 'c75'},
	RegexpCase{'\\u', 'u', false, ''},
	RegexpCase{'\\u', 'v', false, ''},
	RegexpCase{'\\u{1}', '-', true, 'o'},
	RegexpCase{'\\u{1}', 'u', true, 'c1'},
	RegexpCase{'\\u{1}', 'v', true, 'c1'},
	RegexpCase{'\\uD83D\\uDE00', '-', true, 'cd83d.cde00'},
	RegexpCase{'\\uD83D\\uDE00', 'u', true, 'c1f600'},
	RegexpCase{'\\uD83D\\uDE00', 'v', true, 'c1f600'},
	RegexpCase{'[😀-😁]', '-', false, ''},
	RegexpCase{'[😀-😁]', 'u', true, 'o'},
	RegexpCase{'[😀-😁]', 'v', true, 'o'},
	RegexpCase{'[😁-😀]', '-', false, ''},
	RegexpCase{'[😁-😀]', 'u', false, ''},
	RegexpCase{'[😁-😀]', 'v', false, ''},
	RegexpCase{'[z-a]', '-', false, ''},
	RegexpCase{'[z-a]', 'u', false, ''},
	RegexpCase{'[z-a]', 'v', false, ''},
	RegexpCase{'\\p{L}', '-', true, 'c70.c7b.c4c.c7d'},
	RegexpCase{'\\p{L}', 'u', true, 'o'},
	RegexpCase{'\\p{L}', 'v', true, 'o'},
	RegexpCase{'\\p{Lu}', '-', true, 'c70.c7b.c4c.c75.c7d'},
	RegexpCase{'\\p{Lu}', 'u', true, 'o'},
	RegexpCase{'\\p{Lu}', 'v', true, 'o'},
	RegexpCase{'\\p{General_Category=Lu}', '-', true, 'c70.c7b.c47.c65.c6e.c65.c72.c61.c6c.c5f.c43.c61.c74.c65.c67.c6f.c72.c79.c3d.c4c.c75.c7d'},
	RegexpCase{'\\p{General_Category=Lu}', 'u', true, 'o'},
	RegexpCase{'\\p{General_Category=Lu}', 'v', true, 'o'},
	RegexpCase{'\\p{sc=Grek}', '-', true, 'c70.c7b.c73.c63.c3d.c47.c72.c65.c6b.c7d'},
	RegexpCase{'\\p{sc=Grek}', 'u', true, 'o'},
	RegexpCase{'\\p{sc=Grek}', 'v', true, 'o'},
	RegexpCase{'\\p{Script_Extensions=Latin}', '-', true, 'c70.c7b.c53.c63.c72.c69.c70.c74.c5f.c45.c78.c74.c65.c6e.c73.c69.c6f.c6e.c73.c3d.c4c.c61.c74.c69.c6e.c7d'},
	RegexpCase{'\\p{Script_Extensions=Latin}', 'u', true, 'o'},
	RegexpCase{'\\p{Script_Extensions=Latin}', 'v', true, 'o'},
	RegexpCase{'\\p{Block=Basic}', '-', true, 'c70.c7b.c42.c6c.c6f.c63.c6b.c3d.c42.c61.c73.c69.c63.c7d'},
	RegexpCase{'\\p{Block=Basic}', 'u', false, ''},
	RegexpCase{'\\p{Block=Basic}', 'v', false, ''},
	RegexpCase{'\\p{Foo}', '-', true, 'c70.c7b.c46.c6f.c6f.c7d'},
	RegexpCase{'\\p{Foo}', 'u', false, ''},
	RegexpCase{'\\p{Foo}', 'v', false, ''},
	RegexpCase{'\\P{L}', '-', true, 'c50.c7b.c4c.c7d'},
	RegexpCase{'\\P{L}', 'u', true, 'o'},
	RegexpCase{'\\P{L}', 'v', true, 'o'},
	RegexpCase{'\\p{RGI_Emoji}', '-', true, 'c70.c7b.c52.c47.c49.c5f.c45.c6d.c6f.c6a.c69.c7d'},
	RegexpCase{'\\p{RGI_Emoji}', 'u', false, ''},
	RegexpCase{'\\p{RGI_Emoji}', 'v', true, 'o'},
	RegexpCase{'[^\\p{RGI_Emoji}]', '-', true, 'o'},
	RegexpCase{'[^\\p{RGI_Emoji}]', 'u', false, ''},
	RegexpCase{'[^\\p{RGI_Emoji}]', 'v', false, ''},
	RegexpCase{'[\\q{a|bc}--\\q{bc}]', '-', false, ''},
	RegexpCase{'[\\q{a|bc}--\\q{bc}]', 'u', false, ''},
	RegexpCase{'[\\q{a|bc}--\\q{bc}]', 'v', true, 'o'},
	RegexpCase{'[^\\q{a|bc}]', '-', true, 'o'},
	RegexpCase{'[^\\q{a|bc}]', 'u', false, ''},
	RegexpCase{'[^\\q{a|bc}]', 'v', false, ''},
	RegexpCase{'[^\\q{a}]', '-', true, 'o'},
	RegexpCase{'[^\\q{a}]', 'u', false, ''},
	RegexpCase{'[^\\q{a}]', 'v', true, 'o'},
	RegexpCase{'[a&&b&&c]', '-', true, 'o'},
	RegexpCase{'[a&&b&&c]', 'u', true, 'o'},
	RegexpCase{'[a&&b&&c]', 'v', true, 'o'},
	RegexpCase{'[a&&b--c]', '-', false, ''},
	RegexpCase{'[a&&b--c]', 'u', false, ''},
	RegexpCase{'[a&&b--c]', 'v', false, ''},
	RegexpCase{'[a&&&b]', '-', true, 'o'},
	RegexpCase{'[a&&&b]', 'u', true, 'o'},
	RegexpCase{'[a&&&b]', 'v', false, ''},
	RegexpCase{'[!!]', '-', true, 'o'},
	RegexpCase{'[!!]', 'u', true, 'o'},
	RegexpCase{'[!!]', 'v', false, ''},
	RegexpCase{'[(]', '-', true, 'o'},
	RegexpCase{'[(]', 'u', true, 'o'},
	RegexpCase{'[(]', 'v', false, ''},
	RegexpCase{'[a[b]c]', '-', true, 'o.c63.c5d'},
	RegexpCase{'[a[b]c]', 'u', false, ''},
	RegexpCase{'[a[b]c]', 'v', true, 'o'},
	RegexpCase{'\\-', '-', true, 'c2d'},
	RegexpCase{'\\-', 'u', false, ''},
	RegexpCase{'\\-', 'v', false, ''},
	RegexpCase{'[\\-]', '-', true, 'o'},
	RegexpCase{'[\\-]', 'u', true, 'o'},
	RegexpCase{'[\\-]', 'v', true, 'o'},
	RegexpCase{'\\/', '-', true, 'c2f'},
	RegexpCase{'\\/', 'u', true, 'c2f'},
	RegexpCase{'\\/', 'v', true, 'c2f'},
	RegexpCase{'^ab\$', '-', true, 's.c61.c62.e'},
	RegexpCase{'^ab\$', 'u', true, 's.c61.c62.e'},
	RegexpCase{'^ab\$', 'v', true, 's.c61.c62.e'},
	RegexpCase{'^a', '-', true, 's.c61'},
	RegexpCase{'^a', 'u', true, 's.c61'},
	RegexpCase{'^a', 'v', true, 's.c61'},
	RegexpCase{'a\$', '-', true, 'c61.e'},
	RegexpCase{'a\$', 'u', true, 'c61.e'},
	RegexpCase{'a\$', 'v', true, 'c61.e'},
	RegexpCase{'a\\\$', '-', true, 'c61.c24'},
	RegexpCase{'a\\\$', 'u', true, 'c61.c24'},
	RegexpCase{'a\\\$', 'v', true, 'c61.c24'},
	RegexpCase{'ab|c', '-', true, 'c61.c62|c63'},
	RegexpCase{'ab|c', 'u', true, 'c61.c62|c63'},
	RegexpCase{'ab|c', 'v', true, 'c61.c62|c63'},
	RegexpCase{'a(b)c', '-', true, 'c61.o.c63'},
	RegexpCase{'a(b)c', 'u', true, 'c61.o.c63'},
	RegexpCase{'a(b)c', 'v', true, 'c61.o.c63'},
	RegexpCase{'\\n\\t\\0', '-', true, 'ca.c9.c0'},
	RegexpCase{'\\n\\t\\0', 'u', true, 'ca.c9.c0'},
	RegexpCase{'\\n\\t\\0', 'v', true, 'ca.c9.c0'},
	RegexpCase{'\\u{61}b', '-', true, 'o.c62'},
	RegexpCase{'\\u{61}b', 'u', true, 'c61.c62'},
	RegexpCase{'\\u{61}b', 'v', true, 'c61.c62'},
	RegexpCase{'é😀', '-', true, 'ce9.cd83d.cde00'},
	RegexpCase{'é😀', 'u', true, 'ce9.c1f600'},
	RegexpCase{'é😀', 'v', true, 'ce9.c1f600'},
]

struct RegexpSourceCase {
	pattern string
	source  string
}

const regexp_source_cases = [
	RegexpSourceCase{'a/b', 'a\\/b'},
	RegexpSourceCase{'[/]', '[/]'},
	RegexpSourceCase{'[a]/', '[a]\\/'},
	RegexpSourceCase{'a\\/b', 'a\\/b'},
	RegexpSourceCase{'a\nb', 'a\\nb'},
	RegexpSourceCase{'a\\\nb', 'a\\nb'},
	RegexpSourceCase{'', '(?:)'},
	RegexpSourceCase{'a b', 'a\\u2028b'},
	RegexpSourceCase{'\\[/]', '\\[\\/]'},
	RegexpSourceCase{'[\\]/]', '[\\]/]'},
]

fn regexp_test_units(s string) []u16 {
	return utf16_units(s)
}

fn regexp_test_encode(p RegexpPattern) string {
	mut alts := []string{}
	for alt in p.alternatives {
		mut els := []string{}
		for e in alt {
			els << match e.kind {
				.character { 'c' + e.value.hex() }
				.assertion_start { 's' }
				.assertion_end { 'e' }
				.other { 'o' }
			}
		}
		alts << els.join('.')
	}
	return alts.join('|')
}

fn test_regexp_parse() {
	for t in regexp_cases {
		mode := match t.mode {
			'u' { RegexpMode.unicode }
			'v' { RegexpMode.unicode_sets }
			else { RegexpMode.annex_b }
		}
		got := regexp_parse(regexp_test_units(t.pattern), mode)
		assert got.valid == t.valid, '${t.pattern} (${t.mode})'
		if got.valid {
			assert regexp_test_encode(got) == t.alts, '${t.pattern} (${t.mode})'
		}
	}
}

fn test_regexp_new() {
	for t in regexp_source_cases {
		re := regexp_new(regexp_test_units(t.pattern), '') or { panic(t.pattern) }
		assert re.source == regexp_test_units(t.source), t.pattern
	}
	assert (regexp_new(regexp_test_units('a'), 'yg') or { panic('yg') }).flags == 'gy'
	assert (regexp_new(regexp_test_units('a'), 'dgimsuy') or { panic('all') }).flags == 'dgimsuy'
	assert regexp_new(regexp_test_units('a'), 'gg') == none
	assert regexp_new(regexp_test_units('a'), 'uv') == none
	assert regexp_new(regexp_test_units('a'), 'x') == none
	assert regexp_new(regexp_test_units('('), '') == none
}
