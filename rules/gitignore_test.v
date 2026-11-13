module rules

import json2
import os

// tests/gitignore_cases.json (tools/gen_gitignore_cases.mjs) has what the `ignore` package answers
// for lists of gitignore patterns and a set of paths; gitignore.v must answer the same.
fn test_gitignore_matches_the_ignore_package() {
	text := os.read_file(os.join_path(@VMODROOT, 'tests/gitignore_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](text) or { panic(err) }).as_map()
	paths := data['paths'] or { panic('no paths') }.as_array().map(it.str())
	mut failures := []string{}
	cases := data['cases'] or { panic('no cases') }.as_array()
	for entry in cases {
		item := entry.as_map()
		patterns := item['patterns'] or { panic('no patterns') }.as_array().map(it.str())
		ignore_case := (item['ignorecase'] or { json2.Any(false) }).bool()
		want := item['ignored'] or { panic('no ignored') }.as_array().map(it.str())
		mut matcher := new_gitignore(patterns, ignore_case)
		got := paths.filter(matcher.ignores(it))
		if got != want {
			failures << '${patterns} (ignorecase ${ignore_case}): ${got}, ignore has ${want}'
		}
	}
	assert failures.len == 0, '${failures.len} of ${cases.len} cases differ:\n${failures[..if failures.len > 10 {
		10
	} else {
		failures.len
	}].join('\n')}'
}
