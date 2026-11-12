module rules

import json2
import os

// The cases come from tools/gen_package_pattern_cases.mjs: for the `package` of a type specifier,
// the pattern typescript-eslint makes of it, and what `new RegExp(pattern).test(text)` gives in V8
// for each text (`1` or `0`, or `?` where V8 answers two ways), or that V8 rejects the pattern.
fn test_package_patterns_match_like_v8() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'package_pattern_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	texts := data['texts'] or { panic('no texts') }.as_array().map(it.str())
	mut checked := 0
	mut rejected := 0
	mut wrong := []string{}
	mut unsupported := []string{}
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		package_name := entry['package'] or { panic('no package') }.str()
		pattern := entry['pattern'] or { panic('no pattern') }.str()
		assert package_pattern(package_name) == pattern
		if 'error' in entry {
			rejected++
			if _ := regexp_compile_annex_b(utf16_units(pattern)) {
				wrong << '/${pattern}/ should be invalid'
			}
			continue
		}
		matches := entry['matches'] or { panic('no matches') }.str()
		assert matches.len == texts.len
		prog := regexp_compile_annex_b(utf16_units(pattern)) or {
			if err.msg().contains('a backreference that ignores case') {
				unsupported << pattern
			} else {
				wrong << '/${pattern}/ does not compile: ${err.msg()}'
			}
			continue
		}
		for i, text in texts {
			if matches[i] == `?` {
				continue
			}
			got := regexp_test_annex_b(prog, utf16_units(text)) or {
				wrong << '/${pattern}/ on ${json2.encode(text)}: ${err.msg()}'
				continue
			}
			if got != (matches[i] == `1`) {
				wrong << '/${pattern}/ on ${json2.encode(text)}: got ${got}'
			}
			checked++
		}
	}
	if wrong.len > 0 {
		assert false, '${wrong.len} differences; the first ones:\n' + wrong#[..12].join('\n')
	}
	assert checked >= 40000
	assert rejected >= 100
	// The one thing of these patterns veslint does not match: a backreference inside a group with
	// the `i` flag (the matcher compares it as the `u` mode does). It says so.
	assert unsupported == ['(?i:(a)\\1)|(?i:(a)\\1)']
}

// A name of a package is a pattern without anchors, as typescript-eslint has it; with a scope, the
// name of its @types package counts too.
fn test_package_pattern_of_a_name() {
	assert package_pattern('fake-pkg') == 'fake-pkg|fake-pkg'
	assert package_pattern('@scope/name') == '@scope/name|scope__name'
	assert package_pattern('@/name') == '@/name|@/name'
	prog := regexp_compile_annex_b(utf16_units(package_pattern('@scope/name'))) or { panic(err) }
	assert regexp_test_annex_b(prog, utf16_units('@types/scope__name/index.d.ts')) or { panic(err) }
	assert regexp_test_annex_b(prog, utf16_units('@scope/name/lib/a.d.ts')) or { panic(err) }
	assert !(regexp_test_annex_b(prog, utf16_units('@scope/other/lib/a.d.ts')) or { panic(err) })
}
