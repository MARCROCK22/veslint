module rules

import time
import treesitter { position_of }

// Port of the `no-loss-of-precision` rule of ESLint 10.6.0 (it has no options).

const nlop_messages = {
	'noLossOfPrecision': 'This number literal will lose precision at runtime.'
}

fn (mut c Checker) lint_no_loss_of_precision(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['number'], []) {
		raw := c.text(node)
		if raw.ends_with('n') {
			continue
		}
		stats.checked++
		value := number_literal_value(raw) or { continue }
		if value == 0 || !nlop_loses_precision(raw, value) {
			continue
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'noLossOfPrecision'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// NlopNotation is a number as its significant digits and the power of ten of the first one.
struct NlopNotation {
	coefficient string
	magnitude   int
}

fn nlop_loses_precision(raw string, value f64) bool {
	lower := raw.to_lower()
	if lower.starts_with('0x') || lower.starts_with('0b') || lower.starts_with('0o')
		|| (raw.len > 1 && raw[0] == `0` && raw[1..].bytes().all(it >= `0` && it <= `7`)) {
		// notBaseTenLosesPrecision: the digits of the value in its base end the literal.
		upper := raw.replace('_', '').to_upper()
		base := if upper.starts_with('0B') {
			2
		} else if upper.starts_with('0X') {
			16
		} else {
			8
		}
		digits := stv_number_to_string(value, JsAny{
			kind:   .number_
			number: f64(base)
		}) or { return false }
		return !upper.ends_with(digits.to_upper())
	}
	// baseTenLosesPrecision.
	written := nlop_notation(raw.replace('_', '').to_lower(), false)
	precision := written.coefficient.len
	if precision > 100 {
		return true
	}
	stored_text := stv_to_precision(value, f64(precision)) or { return false }
	stored := nlop_notation(stored_text, true)
	return written.magnitude != stored.magnitude || written.coefficient != stored.coefficient
}

fn nlop_trim_leading_zeros(s string) string {
	for i in 0 .. s.len {
		if s[i] != `0` {
			return s[i..]
		}
	}
	return s
}

fn nlop_trim_trailing_zeros(s string) string {
	for i := s.len - 1; i >= 0; i-- {
		if s[i] != `0` {
			return s[..i + 1]
		}
	}
	return s
}

// nlop_notation ports convertNumberToScientificNotation.
fn nlop_notation(number string, parse_as_float bool) NlopNotation {
	parts := number.split('e')
	coefficient := parts[0]
	mut notation := NlopNotation{}
	if parse_as_float || number.contains('.') {
		trimmed := nlop_trim_leading_zeros(coefficient)
		dot := trimmed.index('.') or { -1 }
		notation = match dot {
			0 {
				significant := nlop_trim_leading_zeros(trimmed[1..])
				NlopNotation{significant, significant.len - trimmed.len}
			}
			-1 {
				NlopNotation{trimmed, trimmed.len - 1}
			}
			else {
				NlopNotation{trimmed.replace('.', ''), dot - 1}
			}
		}
	} else {
		trimmed := nlop_trim_leading_zeros(coefficient)
		notation = NlopNotation{nlop_trim_trailing_zeros(trimmed), trimmed.len - 1}
	}
	if parts.len > 1 {
		notation = NlopNotation{notation.coefficient, notation.magnitude + parts[1].trim_left('+').int()}
	}
	return notation
}
