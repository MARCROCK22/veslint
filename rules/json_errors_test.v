module rules

import json2
import os

// The cases come from tools/gen_json_error_cases.mjs: the message of the error V8 throws from
// `JSON.parse(text)`, or '' for valid JSON.
fn test_v8_json_error_matches_v8() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'json_error_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut checked := 0
	mut wrong := []string{}
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		text := entry['text'] or { panic('no text') }.str()
		expected := entry['message'] or { panic('no message') }.str()
		got := v8_json_error(text)
		if got != expected {
			wrong << 'JSON.parse(${json2.encode(text)}): got `${got}`, V8 gives `${expected}`'
		}
		checked++
	}
	assert wrong == []string{}
	assert checked >= 75
}
