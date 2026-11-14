module rules

import json2
import os

// The cases come from tools/gen_html_entities.mjs: inputs with what decodeHTMLAttribute of the
// `entities` package gives for them (tests/html_attribute_cases.json).

fn test_html_decode_attribute_matches_entities() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'html_attribute_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut failures := []string{}
	cases := (data['cases'] or { panic('no cases') }).as_array()
	for item in cases {
		values := item.as_array()
		got := html_decode_attribute(values[0].str())
		if got != values[1].str() {
			failures << '${json2.encode(values[0].str())}: ${json2.encode(got)}, entities ${json2.encode(values[1].str())}'
		}
	}
	assert failures == []
	assert cases.len > 20000
}
