// V bug: x.json2 rejects a JSON string with an escaped lone surrogate ("Expected a trail surrogate
// after a head surrogate"). The JSON grammar (RFC 8259) allows any \uXXXX escape, and JSON.parse
// gives a string with that code unit; as WTF-8 (V strings of JavaScript text) "\ud800" is ED A0 80.
// Found in veslint's reading of an ESLint configuration: the `alphabet` option of
// eslint-plugin-perfectionist's tests has lone surrogates, and the configuration was refused.
// expected: ['eda080', '61edb08062']
import x.json2

fn main() {
	value := json2.decode[json2.Any]('["\\ud800", "a\\udc00b"]') or {
		println('error: ${err.msg().all_before('\n')}')
		return
	}
	println(value.as_array().map(it.str().bytes().hex()))
}
