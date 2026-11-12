module rules

// Expected values computed with requiresQuoting of @typescript-eslint/type-utils 8.62.0 on
// TypeScript 6.0.3 (the result is the same with the ES2022 target and with the default one).
struct RequiresQuotingCase {
	name     string
	expected bool
}

const requires_quoting_cases = [
	RequiresQuotingCase{'', true},
	RequiresQuotingCase{'a', false},
	RequiresQuotingCase{'A1', false},
	RequiresQuotingCase{'_', false},
	RequiresQuotingCase{'$', false},
	RequiresQuotingCase{'__proto__', false},
	RequiresQuotingCase{'1x', true},
	RequiresQuotingCase{'a-b', true},
	RequiresQuotingCase{'a b', true},
	RequiresQuotingCase{"it's", true},
	RequiresQuotingCase{'é', false},
	RequiresQuotingCase{'日本', false},
	RequiresQuotingCase{'ªb', false},
	// U+00B7 continues an identifier but does not start one.
	RequiresQuotingCase{'·x', true},
	RequiresQuotingCase{'x·y', false},
	// So does the zero-width joiner.
	RequiresQuotingCase{'a‍b', false},
	RequiresQuotingCase{'‍a', true},
	// Outside the BMP: two surrogates for charCodeAt, never identifier characters, even when the
	// code point is a letter.
	RequiresQuotingCase{'🎉', true},
	RequiresQuotingCase{'a🎉', true},
	RequiresQuotingCase{'𝒜', true},
	// A combining mark.
	RequiresQuotingCase{'à', false},
	RequiresQuotingCase{'̀a', true},
	RequiresQuotingCase{'ǅ', false},
	RequiresQuotingCase{'ⅳ', false},
	RequiresQuotingCase{'x‿', false},
	RequiresQuotingCase{'℘', false},
	RequiresQuotingCase{'a b', true},
	RequiresQuotingCase{'π', false},
	RequiresQuotingCase{'new\nline', true},
	RequiresQuotingCase{'x￿', true},
	RequiresQuotingCase{'Ａ', false},
	RequiresQuotingCase{'a.b', true},
	RequiresQuotingCase{'a1_$', false},
	RequiresQuotingCase{'$1', false},
	RequiresQuotingCase{'9', true},
	RequiresQuotingCase{'ℂ', false},
	RequiresQuotingCase{'ᢅ', false},
]

fn test_requires_quoting() {
	for case in requires_quoting_cases {
		assert requires_quoting(case.name) == case.expected, 'requires_quoting(${case.name.bytes().hex()})'
	}
}

// The code units above ASCII that TypeScript 6.0.3's isIdentifierStart and isIdentifierPart accept
// with the ESNext target: 48983 and 50691.
fn test_identifier_tables() {
	mut starts := 0
	mut parts := 0
	for code in u32(128) .. u32(0x10000) {
		if ts_is_identifier_start(code) {
			starts++
		}
		if ts_is_identifier_part(code) {
			parts++
		}
	}
	assert starts == 48983
	assert parts == 50691
	// ASCII: letters, `$` and `_` start an identifier; digits only continue it.
	for code in u32(0) .. u32(128) {
		letter := (code >= `a` && code <= `z`) || (code >= `A` && code <= `Z`) || code == `$`
			|| code == `_`
		assert ts_is_identifier_start(code) == letter
		assert ts_is_identifier_part(code) == (letter || (code >= `0` && code <= `9`))
	}
}
