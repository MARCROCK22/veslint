module rules

import estree
import math
import math.big
import time

// Port of the `unicorn/prefer-bigint-literals` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix and its suggestion.

const upbl_messages = {
	'prefer-bigint-literals/error':      'Prefer using bigint literal over `BigInt(…)`.'
	'prefer-bigint-literals/suggestion': 'Replace with {{replacement}}.'
}

// UpblReplacement is what getReplacement gives: the literal, whether it is only a suggestion, and
// the sign of its value.
struct UpblReplacement {
	suggestion bool
	text       string
	negative   bool
	zero       bool
}

// upbl_string_bigint ports `BigInt(text)` of a string (StringToBigInt): none when it throws.
fn upbl_string_bigint(text string) ?big.Integer {
	s := js_trim(text)
	if s == '' {
		return big.integer_from_int(0)
	}
	lower := s.to_lower()
	for prefix, base in {
		'0x': u32(16)
		'0o': 8
		'0b': 2
	} {
		if lower.starts_with(prefix) {
			digits := lower[2..]
			valid := match prefix {
				'0x' { digits.bytes().all(it.is_digit() || (it >= `a` && it <= `f`)) }
				'0o' { digits.bytes().all(it >= `0` && it <= `7`) }
				else { digits.bytes().all(it in [`0`, `1`]) }
			}
			if digits == '' || !valid {
				return none
			}
			return big.integer_from_radix(digits, base) or { return none }
		}
	}
	mut digits := s
	mut negative := false
	if s[0] in [`+`, `-`] {
		negative = s[0] == `-`
		digits = s[1..]
	}
	if digits == '' || !digits.bytes().all(it.is_digit()) {
		return none
	}
	value := big.integer_from_string(digits) or { return none }
	return if negative { value.neg() } else { value }
}

// upbl_is_bigint_literal_text ports isBigIntLiteralText: /^(?:0|[1-9]\d*)$/u.
fn upbl_is_bigint_literal_text(text string) bool {
	if text == '0' {
		return true
	}
	return text.len > 0 && text[0] >= `1` && text[0] <= `9` && text.bytes().all(it.is_digit())
}

// upbl_can_use_prefixed_raw ports canUsePrefixedRaw: `0b1`, `0o7`, `0xf` whose digits are the
// canonical ones of the value.
fn upbl_can_use_prefixed_raw(raw string, value big.Integer) bool {
	for prefix, base in {
		'0b': u32(2)
		'0o': 8
		'0x': 16
	} {
		if raw.starts_with(prefix) {
			return raw[2..] == value.radix_str(base)
		}
	}
	return false
}

// upbl_integer is the exact integer of a double that is an integer.
fn upbl_integer(v f64) big.Integer {
	if v == 0 {
		return big.integer_from_int(0)
	}
	bits := math.f64_bits(math.abs(v))
	exponent := int((bits >> 52) & 0x7ff)
	mut mantissa := bits & ((u64(1) << 52) - 1)
	mut shift := exponent - 1075
	if exponent == 0 {
		shift = -1074
	} else {
		mantissa |= u64(1) << 52
	}
	mut out := big.integer_from_u64(mantissa)
	if shift >= 0 {
		out = out.left_shift(u32(shift))
	} else {
		out = big.integer_from_u64(mantissa >> u32(-shift))
	}
	return out
}

// upbl_can_use_raw ports canUseNumericLiteralRaw.
fn upbl_can_use_raw(raw_text string, value f64) bool {
	raw := raw_text.replace('_', '').to_lower()
	if raw.contains('.') {
		return false
	}
	// `1e+21` is also how `String()` prints the value, but `1e+21n` is not a bigint literal.
	return upbl_can_use_prefixed_raw(raw, upbl_integer(value))
		|| (!raw.contains('e') && raw == js_number_to_string(value))
}

// upbl_replacement ports getReplacement.
fn upbl_replacement(t &estree.EsTree, from int) ?UpblReplacement {
	if string_value := un_static_string_value(t, from) {
		bigint := upbl_string_bigint(string_value)?
		mut text := js_trim(string_value)
		if text.starts_with('+') {
			text = js_trim(text[1..])
		}
		// A bigint literal can not have leading zeros, `00001n` is a syntax error.
		if !upbl_is_bigint_literal_text(text) && !upbl_can_use_prefixed_raw(text.to_lower(), bigint) {
			text = bigint.str()
		}
		return UpblReplacement{
			suggestion: string_value.contains('+')
			text:       '${text}n'
			negative:   bigint.signum < 0
			zero:       bigint.signum == 0
		}
	}
	mut node := from
	mut suggestion := false
	mut negated := false
	for t.typ(node) == .unary_expression && (t.flag(node, .prefix) or { false }) {
		operator := t.string_of(node, .operator) or { '' }
		if operator == '+' {
			suggestion = true
		} else if operator == '-' {
			negated = !negated
		} else {
			return none
		}
		node = t.node(node, .argument) or { return none }
	}
	if t.typ(node) != .literal {
		return none
	}
	value := t.get(node, .value)
	if value !is f64 {
		return none
	}
	number := value as f64
	if math.is_nan(number) || math.is_inf(number, 0) || math.trunc(number) != number {
		return none
	}
	integer := upbl_integer(number)
	raw := un_raw(t, node)
	mut text := ''
	if upbl_can_use_raw(raw, number) {
		text = '${raw}n'
	} else {
		text = '${integer.str()}n'
		suggestion = true
	}
	zero := number == 0
	if negated && !zero {
		text = '-${text}'
	}
	return UpblReplacement{
		suggestion: suggestion
		text:       text
		negative:   negated && !zero
		zero:       zero
	}
}

fn (mut c Checker) lint_unicorn_prefer_bigint_literals(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_call(t, node, names: ['BigInt'], arguments_length: 1, optional: false) {
			continue
		}
		argument := (t.list(node, .arguments) or { continue })[0]
		replacement := upbl_replacement(t, argument) or { continue }
		mut text := replacement.text
		if !c.un_is_parenthesized(t, tokens, node) && replacement.negative {
			text = '(${text})'
			if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), text) {
				text = ';${text}'
			}
		}
		fix := fix_replace_range(t.nodes[node].start, t.nodes[node].end, text)
		if replacement.suggestion
			|| tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len > 0 {
			findings << Finding{
				stmt:        c.es_tree_position(t, node)
				message_id:  'prefer-bigint-literals/error'
				suggestions: [
					Suggestion{
						message_id: 'prefer-bigint-literals/suggestion'
						data:       {
							'replacement': if replacement.text.runes().len < 20 {
								'`${replacement.text}`'
							} else {
								'a bigint literal'
							}
						}
						fix:        fix
					},
				]
			}
		} else {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'prefer-bigint-literals/error'
				has_fix:    true
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
