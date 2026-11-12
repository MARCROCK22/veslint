module rules

// The message of the SyntaxError V8 (the engine ESLint runs on) throws from `JSON.parse(text)`,
// for the error ESLint prints when a `/* eslint … */` comment cannot be read ("Failed to parse
// JSON from '…': <that message>"). It follows V8's JsonParser: the same order of checks, the
// position of the unexpected token in UTF-16 units, and for an unexpected character the text
// itself or ten characters of context around it.

const json_max_context = 10
const json_min_length_for_context = 2 * json_max_context + 1

struct JsonErrorParser {
	src []u16
mut:
	pos   int
	error string
}

// v8_json_error is the message of `JSON.parse(text)`'s error, or '' when the text is valid JSON.
fn v8_json_error(text string) string {
	mut p := JsonErrorParser{
		src: utf16_units(text)
	}
	if p.value() {
		p.skip_space()
		if p.pos < p.src.len {
			// The only message whose position does not say "in JSON".
			p.error = 'Unexpected non-whitespace character after JSON' +
				p.location().all_after(' in JSON')
		}
	}
	return p.error
}

fn (p &JsonErrorParser) at() u16 {
	return if p.pos < p.src.len { p.src[p.pos] } else { u16(0) }
}

fn (mut p JsonErrorParser) skip_space() {
	for p.pos < p.src.len && p.src[p.pos] in [u16(` `), `\t`, `\n`, `\r`] {
		p.pos++
	}
}

// location is the " in JSON at position N (line L column C)" of an error at the cursor.
fn (p &JsonErrorParser) location() string {
	mut line := 1
	mut line_start := 0
	mut i := 0
	for i < p.pos {
		if p.src[i] == `\r` {
			if i + 1 < p.pos && p.src[i + 1] == `\n` {
				i++
			}
			line++
			line_start = i + 1
		} else if p.src[i] == `\n` {
			line++
			line_start = i + 1
		}
		i++
	}
	return ' in JSON at position ${p.pos} (line ${line} column ${p.pos - line_start + 1})'
}

// fail records an error with its own message at the cursor.
fn (mut p JsonErrorParser) fail(message string) bool {
	if p.error == '' {
		p.error = message + p.location()
	}
	return false
}

// unexpected records the error for a token nothing expects (LookUpErrorMessageForJsonToken).
fn (mut p JsonErrorParser) unexpected() bool {
	if p.error != '' {
		return false
	}
	if p.pos >= p.src.len {
		p.error = 'Unexpected end of JSON input'
		return false
	}
	ch := p.src[p.pos]
	if ch == `"` {
		p.error = 'Unexpected string' + p.location()
		return false
	}
	if ch == `-` || (ch >= `0` && ch <= `9`) {
		p.error = 'Unexpected number' + p.location()
		return false
	}
	source := stv_units_string(p.src)
	if source in ['NaN', 'Infinity', 'undefined', '[object Object]'] {
		p.error = '"${source}" is not valid JSON'
		return false
	}
	token := stv_units_string([ch])
	if p.src.len < json_min_length_for_context {
		p.error = "Unexpected token '${token}', \"${stv_units_string(p.src)}\" is not valid JSON"
		return false
	}
	if p.pos < json_max_context {
		context := stv_units_string(p.src[..p.pos + json_max_context])
		p.error = "Unexpected token '${token}', \"${context}\"... is not valid JSON"
	} else if p.pos < p.src.len - json_max_context {
		context := stv_units_string(p.src[p.pos - json_max_context..p.pos + json_max_context])
		p.error = "Unexpected token '${token}', ...\"${context}\"... is not valid JSON"
	} else {
		context := stv_units_string(p.src[p.pos - json_max_context..])
		p.error = "Unexpected token '${token}', ...\"${context}\" is not valid JSON"
	}
	return false
}

fn (mut p JsonErrorParser) value() bool {
	p.skip_space()
	ch := p.at()
	if p.pos >= p.src.len {
		return p.unexpected()
	}
	if ch == `"` {
		return p.string()
	}
	if ch == `-` || (ch >= `0` && ch <= `9`) {
		return p.number()
	}
	if ch == `{` {
		p.pos++
		p.skip_space()
		if p.at() == `}` && p.pos < p.src.len {
			p.pos++
			return true
		}
		mut first := true
		for {
			p.skip_space()
			if p.pos >= p.src.len || p.at() != `"` {
				return p.fail(if first {
					"Expected property name or '}'"
				} else {
					'Expected double-quoted property name'
				})
			}
			first = false
			if !p.string() {
				return false
			}
			p.skip_space()
			if p.pos >= p.src.len || p.at() != `:` {
				return p.fail("Expected ':' after property name")
			}
			p.pos++
			if !p.value() {
				return false
			}
			p.skip_space()
			if p.pos < p.src.len && p.at() == `,` {
				p.pos++
				continue
			}
			if p.pos < p.src.len && p.at() == `}` {
				p.pos++
				return true
			}
			return p.fail("Expected ',' or '}' after property value")
		}
	}
	if ch == `[` {
		p.pos++
		p.skip_space()
		if p.at() == `]` && p.pos < p.src.len {
			p.pos++
			return true
		}
		for {
			if !p.value() {
				return false
			}
			p.skip_space()
			if p.pos < p.src.len && p.at() == `,` {
				p.pos++
				continue
			}
			if p.pos < p.src.len && p.at() == `]` {
				p.pos++
				return true
			}
			return p.fail("Expected ',' or ']' after array element")
		}
	}
	for word in ['true', 'false', 'null'] {
		if ch == word[0] {
			for expected in word.bytes() {
				if p.pos >= p.src.len || p.src[p.pos] != expected {
					return p.unexpected()
				}
				p.pos++
			}
			return true
		}
	}
	return p.unexpected()
}

fn (mut p JsonErrorParser) string() bool {
	p.pos++
	for {
		if p.pos >= p.src.len {
			return p.fail('Unterminated string')
		}
		ch := p.src[p.pos]
		if ch == `"` {
			p.pos++
			return true
		}
		if ch < 0x20 {
			return p.fail('Bad control character in string literal')
		}
		if ch != `\\` {
			p.pos++
			continue
		}
		p.pos++
		if p.pos >= p.src.len {
			return p.fail('Unterminated string')
		}
		escape := p.src[p.pos]
		if escape == `u` {
			for i in 1 .. 5 {
				if p.pos + i >= p.src.len || regexp_hex_value(u32(p.src[p.pos + i])) < 0 {
					p.pos += i
					return p.fail('Bad Unicode escape')
				}
			}
			p.pos += 5
			continue
		}
		if escape !in [u16(`"`), `\\`, `/`, `b`, `f`, `n`, `r`, `t`] {
			return p.fail('Bad escaped character')
		}
		p.pos++
	}
	return false
}

fn (mut p JsonErrorParser) digits() int {
	start := p.pos
	for p.pos < p.src.len && p.src[p.pos] >= `0` && p.src[p.pos] <= `9` {
		p.pos++
	}
	return p.pos - start
}

fn (mut p JsonErrorParser) number() bool {
	if p.at() == `-` {
		p.pos++
		if p.pos >= p.src.len || !(p.at() >= `0` && p.at() <= `9`) {
			return p.fail('No number after minus sign')
		}
	}
	if p.at() == `0` {
		p.pos++
		if p.pos < p.src.len && p.at() >= `0` && p.at() <= `9` {
			return p.unexpected()
		}
	} else {
		p.digits()
	}
	if p.pos < p.src.len && p.at() == `.` {
		p.pos++
		if p.digits() == 0 {
			return p.fail('Unterminated fractional number')
		}
	}
	if p.pos < p.src.len && p.at() in [u16(`e`), `E`] {
		p.pos++
		if p.pos < p.src.len && p.at() in [u16(`+`), `-`] {
			p.pos++
		}
		if p.digits() == 0 {
			return p.fail('Exponent part is missing a number')
		}
	}
	return true
}
