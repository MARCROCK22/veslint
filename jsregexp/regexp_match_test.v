module jsregexp

import json2
import os

// The cases come from tools/gen_regexp_match_cases.mjs: what `new RegExp(pattern, 'u').test(text)`
// gives in V8 for each pattern and text.
fn test_regexp_test_matches_v8() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'regexp_match_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut checked := 0
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		pattern := entry['pattern'] or { panic('no pattern') }.str()
		text := entry['text'] or { panic('no text') }.str()
		expected := entry['matches'] or { panic('no matches') }.bool()
		prog := regexp_compile(pattern) or { panic('/${pattern}/u does not compile: ${err.msg()}') }
		got := regexp_test(prog, text) or { panic('/${pattern}/u on `${text}`: ${err.msg()}') }
		assert got == expected, '/${pattern}/u on `${text}`'
		checked++
	}
	assert checked >= 5000
	for item in data['invalid'] or { panic('no invalid') }.as_array() {
		pattern := item.str()
		if _ := regexp_compile(pattern) {
			assert false, '/${pattern}/u should be invalid'
		} else {
			assert err.msg().starts_with('invalid regular expression'), pattern
		}
	}
}

fn test_regexp_test_gives_up_on_a_runaway_search() {
	prog := regexp_compile('^(a+)+$') or { panic(err) }
	if _ := regexp_test(prog, 'a'.repeat(40) + 'b') {
		assert false, 'expected the step limit'
	} else {
		assert err.msg().contains('takes too long')
	}
}
