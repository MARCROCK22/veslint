module rules

import json2
import os

// The cases come from tools/gen_inline_config_cases.mjs: what ESLint's parser of configuration
// comments makes of the text of a `/* eslint … */` comment (the rules in order, each with its
// value; an object is written as {"$keys": [[key, value, own]…]}), or the message of its error.

// inline_value_form writes a value read from a comment as the cases do.
fn inline_value_form(value json2.Any) json2.Any {
	if value is []json2.Any {
		return json2.Any(value.map(inline_value_form(it)))
	}
	if value is map[string]json2.Any {
		mut keys := []json2.Any{}
		for key in js_object_keys(value) {
			keys << json2.Any([json2.Any(key), inline_value_form(value[key] or {
				json2.Any(json2.null)
			}), json2.Any(true)])
		}
		return json2.Any({
			'\$keys': json2.Any(keys)
		})
	}
	if json_is_number(value) {
		number := json_number(value)
		if number != number || number - number != 0 {
			return json2.Any({
				'\$js': json2.Any(if number != number {
					'NaN'
				} else if number > 0 {
					'Infinity'
				} else {
					'-Infinity'
				})
			})
		}
	}
	return value
}

// levn_stand_in turns the values of a case that JSON does not have into what veslint has in their
// place (see levn.v): a regular expression is an object without properties, and undefined is null
// in a list and no property in an object.
fn levn_stand_in(value json2.Any) json2.Any {
	if value is []json2.Any {
		return json2.Any(value.map(levn_stand_in(it)))
	}
	if value is map[string]json2.Any {
		if special := value['\$js'] {
			text := special.str()
			if text == 'undefined' {
				return json2.Any(json2.null)
			}
			if text.starts_with('/') {
				return json2.Any({
					'\$keys': json2.Any([]json2.Any{})
				})
			}
			return value
		}
		mut keys := []json2.Any{}
		for item in value['\$keys'] or { json2.Any([]json2.Any{}) }.as_array() {
			entry := item.as_array()
			if js_json_stringify(entry[1]) == '{"\$js":"undefined"}' {
				continue
			}
			keys << json2.Any([entry[0], levn_stand_in(entry[1]), entry[2]])
		}
		return json2.Any({
			'\$keys': json2.Any(keys)
		})
	}
	return value
}

fn test_inline_rules_are_read_like_eslint() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'inline_config_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut checked := 0
	mut dates := 0
	mut wrong := []string{}
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		text := entry['text'] or { panic('no text') }.str()
		expected := if message := entry['error'] {
			'error: ${message.str()}'
		} else {
			// The rules are a list of [id, value, own]: a list for levn_stand_in too.
			js_json_stringify(levn_stand_in(entry['rules'] or { panic('no rules') }))
		}
		// A `#…#` that V8 reads as a date: veslint does not read dates.
		if expected.contains('"date ') {
			dates++
			continue
		}
		mut got := ''
		if ids, values := parse_inline_rules(text) {
			mut read := []json2.Any{}
			for i, id in ids {
				read << json2.Any([json2.Any(id), inline_value_form(values[i]), json2.Any(true)])
			}
			got = js_json_stringify(json2.Any(read))
		} else {
			got = 'error: ${err.msg()}'
		}
		if got != expected {
			wrong << '${json2.encode(text)}\n  got    ${got}\n  ESLint ${expected}'
		}
		checked++
	}
	if wrong.len > 0 {
		assert false, '${wrong.len} differences:\n' + wrong.join('\n')
	}
	assert checked >= 100
	assert dates == 1
}
