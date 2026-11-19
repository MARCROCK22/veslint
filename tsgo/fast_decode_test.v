module tsgo

import json2

// The fast decoding of the answers (fast_decode.v) gives what json2 gives, or fails and leaves the
// answer to json2.

fn same_as_json2[T](payload string, fast fn (string) !T) {
	value := fast(payload) or { panic('the fast decoding failed on ${payload}: ${err}') }
	want := json2.decode[T](payload) or { panic(err) }
	assert value.str() == want.str(), payload
}

fn test_types_as_json2() {
	same_as_json2[[]TypeResponse]('[{"id":87,"flags":1024,"objectFlags":0,"isTupleType":false,"value":"Hola \\"V\\" \\\\ \\/ \\n\\t\\r\\b\\f \\u00e9 \\ud83d\\ude00 é","isThisType":false},null,{"id":14,"flags":4,"objectFlags":0,"isTupleType":false,"value":null,"isThisType":false,"intrinsicName":"string"}]',
		fast_types)
	// Numbers are parsed as json2 parses them; a BigInt is a string.
	for value in ['1.5', '-0', '1e+21', '5e-324', '123456789012345680000', '"-123"', 'true', 'false',
		'"NaN"'] {
		same_as_json2[TypeResponse]('{"id":3,"flags":256,"value":${value}}', fast_type)
	}
	// What the client does not keep is skipped, whatever it holds; spaces anywhere.
	same_as_json2[TypeResponse](' { "id" : 9 , "texts" : [ "a]\\"}" , "" ] , "typeParameters":[1,2],"x":{"a":[{"b":null}],"c":-1.5e3},"elementFlags":[1,8],"fixedLength":0,"readonly":true,"target":4,"aliasTypeArguments":[5],"symbol":{"id":12345678901234,"file":"n1"},"aliasSymbol":{"id":7},"checkType":2,"extendsType":3,"isTupleType":true,"objectFlags":4294967295 } ',
		fast_type)
	same_as_json2[[]TypeResponse]('[]', fast_types)
	same_as_json2[TypeResponse]('{}', fast_type)
}

fn test_symbols_as_json2() {
	same_as_json2[[]SymbolResponse]('[{"reference":{"kind":0,"file":{"fileName":"/p/a.ts","path":"/p/a.ts","contentHash":"h","parseOptionsKey":"k","scriptKind":3,"nodeId":"n1"},"id":5},"name":"x","flags":2,"checkFlags":0,"declarations":["1.2./p/a.ts","3.4./p/a.ts"],"valueDeclaration":"1.2./p/a.ts","parent":{"id":4,"file":"n1"},"exportSymbol":{"id":6}},null,{"reference":{"kind":1,"snapshot":2,"project":"/p/tsconfig.json","id":18446744073},"name":"__type","flags":2048,"checkFlags":8}]',
		fast_symbols)
	same_as_json2[SymbolResponse]('{"reference":{"kind":1,"snapshot":1,"id":3},"name":"\\u2028","flags":4,"checkFlags":0}',
		fast_symbol)
}

fn test_signatures_as_json2() {
	same_as_json2[[]SignatureResponse]('[{"id":1,"flags":0,"declaration":"1.2./p/a.ts","typeParameters":[3,4],"parameters":[{"id":1,"file":"n1"},{"id":2}],"thisParameter":{"id":9,"file":"n2"},"target":7},{"id":2,"flags":4}]',
		fast_signatures)
	same_as_json2[SignatureResponse]('{"id":1,"flags":0}', fast_signature)
}

// What the fast decoding does not read goes to json2, which gives the same as if it were alone.
fn test_unusual_answers_go_to_json2() {
	for payload in ['{"id":1e3,"flags":0}', '{"id":1,"flags":0,"value":[1]}',
		'{"id":1,"flags":0,"intrinsicName":"\\ud800"}', '{"id":1,"flags":0}x', '{"id":1,"flags":-1}',
		'{"id":12345678901234567890,"flags":0}', '{"\\u0069d":1,"flags":0}'] {
		if _ := fast_type(payload) {
			assert false, 'the fast decoding read ${payload}'
		}
		fallback := checked_decode[TypeResponse]('test', payload, fast_type) or { TypeResponse{} }
		want := json2.decode[TypeResponse](payload) or { TypeResponse{} }
		assert fallback.str() == want.str(), payload
	}
}
