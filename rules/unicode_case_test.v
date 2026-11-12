module rules

import json2
import os

// The cases come from tools/gen_unicode_case.mjs: what toUpperCase and toLowerCase give in V8
// for each string, as UTF-16 units.
fn test_case_conversions_match_v8() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'unicode_case_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut checked := 0
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		units := case_units(entry['units'] or { panic('no units') })
		upper := case_units(entry['upper'] or { panic('no upper') })
		lower := case_units(entry['lower'] or { panic('no lower') })
		assert js_to_upper(units) == upper, 'toUpperCase of ${units}'
		assert js_to_lower(units) == lower, 'toLowerCase of ${units}'
		checked++
	}
	assert checked >= 650
}

fn case_units(value json2.Any) []u16 {
	return value.as_array().map(u16(it.int()))
}

fn test_one_unit_of_a_pair_is_not_converted() {
	// U+10400 has a lower case, but not each half of it: `name[0].toLowerCase()`.
	deseret := utf16_units('\U00010400')
	assert js_to_lower(deseret) == utf16_units('\U00010428')
	assert js_to_lower(deseret[..1]) == deseret[..1]
	assert js_to_upper(deseret[1..]) == deseret[1..]
}
