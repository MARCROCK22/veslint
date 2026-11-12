module tsgo

import json2

// PROMPT.md §3.3: a `null` inside an array of responses decodes as a struct with zero values, which
// is_null() recognizes.
fn test_null_elements_decode_as_null() {
	types := json2.decode[[]TypeResponse]('[{"id":87,"flags":1024,"objectFlags":0,"value":"Hola Vlang","isThisType":false},null,{"id":14,"flags":32,"value":null,"intrinsicName":"string"}]') or {
		panic(err)
	}
	assert types.len == 3
	assert !types[0].is_null()
	assert types[0].id == 87
	assert types[1].is_null()
	assert types[2].intrinsic_name == 'string'
	symbols := json2.decode[[]SymbolResponse]('[{"id":1,"project":"/p/tsconfig.json","name":"default","flags":48,"checkFlags":0},null]') or {
		panic(err)
	}
	assert symbols.len == 2
	assert !symbols[0].is_null()
	assert symbols[0].name == 'default'
	assert symbols[1].is_null()
}

fn test_null_payloads() {
	assert is_null_payload('null')
	assert is_null_payload('')
	assert is_null_payload(' null\n')
	assert !is_null_payload('{"id":1}')
}
