module rules

import time

// Port of the `unicorn/no-zero-fractions` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const unzf_messages = {
	'zero-fraction': "Don't use a zero fraction in the number."
	'dangling-dot':  "Don't use a dangling dot in the number."
}

// un_is_decimal_integer ports isDecimalInteger of utils/numeric.js:
// /^(?:0|0[0-7]*[89]\d*|[1-9](?:_?\d)*)$/u.
fn un_is_decimal_integer(text string) bool {
	if text == '0' {
		return true
	}
	if text.len == 0 {
		return false
	}
	if text[0] == `0` {
		// `0[0-7]*[89]\d*`
		mut i := 1
		for i < text.len && text[i] >= `0` && text[i] <= `7` {
			i++
		}
		if i >= text.len || text[i] !in [`8`, `9`] {
			return false
		}
		return text[i + 1..].bytes().all(it.is_digit())
	}
	if text[0] < `1` || text[0] > `9` {
		return false
	}
	// `[1-9](?:_?\d)*`
	mut i := 1
	for i < text.len {
		if text[i] == `_` {
			i++
		}
		if i >= text.len || !text[i].is_digit() {
			return false
		}
		i++
	}
	return true
}

fn (mut c Checker) lint_unicorn_no_zero_fractions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .literal || t.get(node, .value) !is f64 {
			continue
		}
		stats.checked++
		raw := un_raw(t, node)
		// `^(?<before>[\d_]*)(?<dotAndFractions>\.[\d_]*)(?<after>.*)$`
		mut i := 0
		for i < raw.len && (raw[i].is_digit() || raw[i] == `_`) {
			i++
		}
		if i >= raw.len || raw[i] != `.` {
			continue
		}
		before := raw[..i]
		mut j := i + 1
		for j < raw.len && (raw[j].is_digit() || raw[j] == `_`) {
			j++
		}
		dot_and_fractions := raw[i..j]
		after := raw[j..]
		// `.replaceAll(/[.0_]+$/g, '')`
		mut k := dot_and_fractions.len
		for k > 0 && dot_and_fractions[k - 1] in [`.`, `0`, `_`] {
			k--
		}
		mut formatted := before + dot_and_fractions[..k]
		if formatted == '' {
			formatted = '0'
		}
		formatted += after
		if formatted == raw {
			continue
		}
		end := t.nodes[node].start + before.len + dot_and_fractions.len
		start := end - (raw.len - formatted.len)
		mut fixed := formatted
		parent := t.nodes[node].parent
		if t.typ(parent) == .member_expression && t.node(parent, .object) or { -1 } == node
			&& un_is_decimal_integer(formatted) && !c.un_is_parenthesized(t, tokens, node) {
			fixed = '(${fixed})'
			if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), fixed) {
				fixed = ';${fixed}'
			}
		}
		mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)]
		fixes << c.un_fix_space_around_keyword(t, tokens, node)
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			stmt:       c.position_range(start, end)
			message_id: if dot_and_fractions == '.' { 'dangling-dot' } else { 'zero-fraction' }
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
