module treesitter

import os
import rand

// The incremental parse (Parser.reparse, TreeCache) must give the tree a parse from scratch gives,
// for any edit.

fn edited_tree(p &Parser, old_src string, src string) (&C.TSTree, &C.TSTree) {
	old := p.parse(old_src) or { panic(err) }
	again, _ := p.reparse(old, old_src, src) or { panic(err) }
	fresh := p.parse(src) or { panic(err) }
	return again, fresh
}

fn assert_same_tree(p &Parser, old_src string, src string) {
	again, fresh := edited_tree(p, old_src, src)
	defer {
		tree_delete(again)
		tree_delete(fresh)
	}
	assert trees_differ(again, fresh) == -1, '${old_src.str()} -> ${src.str()}'
}

fn test_reparse_small_edits() {
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	cases := [
		['const a = 1;\n', 'const a = 1;\n// edit\n'],
		['const a = 1;\n', 'const ab = 1;\n'],
		['const a = 1;\nlet b = 2;\n', 'let b = 2;\n'],
		['f(a, b);\n', 'f(a, b\n'], // into a syntax error
		['f(a, b\n', 'f(a, b);\n'], // out of it
		['const s = "é";\n', 'const s = "ü";\n'], // the same first byte of two characters
		['const s = "😀";\n', 'const s = "😁";\n'],
		['a;\r\nb;\r\n', 'a;\r\nc;\r\nb;\r\n'],
		['a;\rb;\n', 'a;\r\rb;\n'],
		['const t = `a\${b}c`;\n', 'const t = `a\${b}c\${d}`;\n'],
		['/* a */ x;\n', '/* a x;\n'],
		['x;', ''],
		['', 'x;'],
		['class A { m() {} }\n', 'class A { m() {} n() {} }\n'],
		['let x = a < b;\n', 'let x = a < b > (c);\n'],
	]
	for c in cases {
		assert_same_tree(p, c[0], c[1])
	}
}

// tree-sitter's incremental parse reads the `}` of a function and a line `-1;` far after the
// edit as a subtraction from a function expression; a parse from scratch reads a declaration and a
// statement: the edit is parsed from scratch.
fn test_reparse_distrusts_a_change_away_from_the_edit() {
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	src := os.read_file(os.join_path(@VMODROOT, 'tests', 'rules', 'unicorn', 'prefer-native-coercion-functions',
		'cases.ts')) or { panic(err) }
	at := src.index('const f2') or { panic('no f2') }
	edited := src[..at] + '// note\n' + src[at..]
	old := p.parse(src) or { panic(err) }
	again, how := p.reparse(old, src, edited) or { panic(err) }
	fresh := p.parse(edited) or { panic(err) }
	defer {
		tree_delete(again)
		tree_delete(fresh)
	}
	assert how == .fresh
	assert trees_differ(again, fresh) == -1
}

// An edit inside a statement of a file without errors is parsed incrementally.
fn test_reparse_is_incremental_for_an_edit_in_a_statement() {
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	src := 'const a = 1;\nfunction f(x: number) {\n  return x + 1;\n}\nconst b = f(a);\n'
	edited := src.replace('x + 1', 'x + 12')
	old := p.parse(src) or { panic(err) }
	again, how := p.reparse(old, src, edited) or { panic(err) }
	fresh := p.parse(edited) or { panic(err) }
	defer {
		tree_delete(again)
		tree_delete(fresh)
	}
	assert how == .incremental
	assert trees_differ(again, fresh) == -1
}

fn test_reparse_equal_text_keeps_the_tree() {
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	src := 'const a = 1;\n'
	old := p.parse(src) or { panic(err) }
	again, how := p.reparse(old, src, src.clone()) or { panic(err) }
	defer {
		tree_delete(again)
	}
	assert voidptr(again) == voidptr(old)
	assert how == .same
}

fn test_tree_cache_reuses_and_forgets() {
	p := new_parser() or { panic(err) }
	tsx := new_tsx_parser() or { panic(err) }
	defer {
		p.close()
		tsx.close()
	}
	mut cache := new_tree_cache()
	defer {
		cache.clear()
	}
	first := cache.parse(p, 'a.ts', 'let a = 1;\n') or { panic(err) }
	assert cache.owns(first)
	same := cache.parse(p, 'a.ts', 'let a = 1;\n') or { panic(err) }
	assert voidptr(same) == voidptr(first)
	edited := cache.parse(p, 'a.ts', 'let a = 12;\n') or { panic(err) }
	assert !cache.owns(first) || voidptr(edited) == voidptr(first)
	assert cache.owns(edited)
	// Another language: parsed from scratch.
	other := cache.parse(tsx, 'a.ts', 'let a = <b/>;\n') or { panic(err) }
	assert voidptr(C.ts_tree_language(other)) == voidptr(tsx.lang)
	for i in 0 .. tree_cache_size + 2 {
		cache.parse(p, 'f${i}.ts', 'x;') or { panic(err) }
	}
	assert cache.entries.len == tree_cache_size
	assert 'a.ts' !in cache.entries
	cache.forget('f${tree_cache_size + 1}.ts')
	assert cache.entries.len == tree_cache_size - 1
}

const edit_snippets = ['\n', '\r\n', '\r', ' ', ';', '{', '}', '(', ')', '[', ']', '`', '\${',
	'"', "'", '/*', '*/', '//', '<', '>', '=>', 'é', 'ü', '😀', '\u2028', 'await ', 'async ',
	'yield ', 'const x = 1;\n', '<T>', 'as const', 'function f() {', 'class A {', 'type T = A | B;\n',
	'/re/g', 'x', '0', '.', '?.', 'if (a) b\n', '#!/x\n', 'import x from "y";\n', 'export ', '@d ',
	'enum E { A }', 'declare ', 'interface I {}', '<div>{a}</div>', '\\', '\t']

// char_start is `at` moved back to the start of its UTF-8 character.
fn char_start(src string, at int) int {
	mut i := if at > src.len { src.len } else { at }
	for i > 0 && i < src.len && (src[i] & 0xC0) == 0x80 {
		i--
	}
	return i
}

// random_edit is `src` with a random edit: an insertion, a deletion or a replacement, of a snippet
// or of a piece of the text itself, at character boundaries.
fn random_edit(src string) string {
	at := char_start(src, if src.len == 0 { 0 } else { rand.intn(src.len + 1) or { 0 } })
	max_len := if src.len - at < 1 { 1 } else { src.len - at }
	span := char_start(src, at + rand.intn(if max_len > 40 { 40 } else { max_len }) or { 0 }) - at
	end := if span < 0 { at } else { at + span }
	insert := match rand.intn(3) or { 0 } {
		0 {
			edit_snippets[rand.intn(edit_snippets.len) or { 0 }]
		}
		1 {
			from := char_start(src, rand.intn(src.len + 1) or { 0 })
			to := char_start(src, from + (rand.intn(60) or { 0 }))
			if to > from { src[from..to] } else { '' }
		}
		else {
			''
		}
	}
	return match rand.intn(3) or { 0 } {
		0 { src[..at] + insert + src[at..] }
		1 { src[..at] + src[end..] }
		else { src[..at] + insert + src[end..] }
	}
}

// line_edit is `src` with an edit of a line, which often leaves it without syntax errors: a line
// inserted (a comment, an empty one, a copy of another), deleted, a space at its end or a letter
// in its first word.
fn line_edit(src string) string {
	sep := if src.contains('\r\n') { '\r\n' } else { '\n' }
	mut lines := src.split(sep)
	i := rand.intn(lines.len) or { 0 }
	match rand.intn(6) or { 0 } {
		0 {
			lines.insert(i, '// note')
		}
		1 {
			lines.delete(i)
		}
		2 {
			lines.insert(i, lines[rand.intn(lines.len) or { 0 }])
		}
		3 {
			lines[i] = lines[i] + ' '
		}
		4 {
			lines.insert(i, '')
		}
		else {
			line := lines[i]
			mut j := 0
			for j < line.len && !line[j].is_letter() {
				j++
			}
			if j < line.len {
				lines[i] = line[..j + 1] + 'q' + line[j + 1..]
			}
		}
	}
	return lines.join(sep)
}

// Random edits of every TypeScript fixture of tests/, one after the other from the tree of the
// last edit, each compared with a parse from scratch.
fn test_reparse_random_edits_of_the_fixtures() {
	p := new_parser() or { panic(err) }
	tsx := new_tsx_parser() or { panic(err) }
	defer {
		p.close()
		tsx.close()
	}
	rand.seed([u32(7), 11])
	root := os.join_path(@VMODROOT, 'tests')
	mut files := os.walk_ext(root, '.ts')
	files << os.walk_ext(root, '.tsx')
	files.sort()
	assert files.len > 100
	mut edits := 0
	mut outcomes := [3]int{}
	mut failures := []string{}
	for path in files {
		original := os.read_file(path) or { continue }
		if original.len > 200_000 {
			continue
		}
		parser := if path.ends_with('.tsx') { tsx } else { p }
		mut src := original
		mut tree := parser.parse(src) or { panic(err) }
		for _ in 0 .. 5 {
			next := if (rand.intn(2) or { 0 }) == 0 { random_edit(src) } else { line_edit(src) }
			again, how := parser.reparse(tree, src, next) or { panic(err) }
			tree = again
			outcomes[int(how)]++
			src = next
			fresh := parser.parse(src) or { panic(err) }
			at := trees_differ(tree, fresh)
			tree_delete(fresh)
			edits++
			if at >= 0 && failures.len < 10 {
				failures << '${path}: differs at byte ${at} after an edit'
			}
		}
		tree_delete(tree)
	}
	assert edits > 1000
	assert failures.len == 0, failures.join('\n')
	// Both ways are tested: incrementally (the line edits often keep the file without errors) and
	// from scratch.
	assert outcomes[int(Reparse.incremental)] > edits / 10, '${outcomes}'
	assert outcomes[int(Reparse.fresh)] > edits / 10, '${outcomes}'
}
