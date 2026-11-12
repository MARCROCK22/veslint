module rules

import math

// Expected values computed with Node (String(eval(literal)) and eval of each string).

fn test_js_number_string() {
	cases := {
		'16':                              '16'
		'0x10':                            '16'
		'0X1F':                            '31'
		'0o17':                            '15'
		'0b101':                           '5'
		'017':                             '15'
		'019':                             '19'
		'1.50':                            '1.5'
		'.5':                              '0.5'
		'1.':                              '1'
		'1e3':                             '1000'
		'1e21':                            '1e+21'
		'1e+21':                           '1e+21'
		'1e-7':                            '1e-7'
		'1.5e-7':                          '1.5e-7'
		'0.000001':                        '0.000001'
		'123456789012345680000':           '123456789012345680000'
		'9007199254740993':                '9007199254740992'
		'1_000_000':                       '1000000'
		'0x1_0':                           '16'
		'1e400':                           'Infinity'
		'5e-324':                          '5e-324'
		'0':                               '0'
		'0.0':                             '0'
		'100':                             '100'
		'1n':                              '1'
		'0x10n':                           '16'
		'123456789012345678901234567890n': '123456789012345678901234567890'
	}
	for text, want in cases {
		got := js_number_string(text) or { '<none>' }
		assert got == want, '${text}: ${got} != ${want}'
	}
}

// Number::toString of values no literal token has: negatives, NaN and the infinities.
fn test_js_number_to_string() {
	cases := {
		'-1':                     js_number_to_string(-1)
		'-2.5':                   js_number_to_string(-2.5)
		'-1e+21':                 js_number_to_string(-1e21)
		'-1e-7':                  js_number_to_string(-1e-7)
		'-0.5':                   js_number_to_string(-0.5)
		'-123456789012345680000': js_number_to_string(-123456789012345680000.0)
		'-5e-324':                js_number_to_string(-5e-324)
		'0':                      js_number_to_string(-0.0)
		'NaN':                    js_number_to_string(math.nan())
		'Infinity':               js_number_to_string(math.inf(1))
		'-Infinity':              js_number_to_string(math.inf(-1))
	}
	for want, got in cases {
		assert got == want, '${got} != ${want}'
	}
}

fn test_cooked_string() {
	assert cooked_string('a\\tb', false) or { '' } == 'a\tb'
	assert cooked_string('\\x41\\u0042\\u{43}', false) or { '' } == 'ABC'
	assert cooked_string('\\uD83D\\uDE00', false) or { '' } == '😀'
	assert cooked_string("\\'", false) or { '' } == "'"
	assert cooked_string('l\\\n', false) or { '' } == 'l'
	assert cooked_string('\\a', false) or { '' } == 'a'
	assert cooked_string('\\0', false) or { '' } == [u8(0)].bytestr()
	assert cooked_string('c\r\nd', true) or { '' } == 'c\nd'
	assert cooked_string('plain', false) or { '' } == 'plain'
	assert cooked_string('é\\é', false) or { '' } == 'éé'
}

fn test_cooked_string_invalid() {
	for raw in ['\\1', '\\01', '\\uD83D', '\\uDE00', '\\u{110000}', '\\x4', '\\u{}', 'fin\\'] {
		if got := cooked_string(raw, false) {
			assert false, '${raw}: expected none, got ${got}'
		}
	}
}
