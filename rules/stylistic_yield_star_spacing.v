module rules

import estree
import time
import x.json2

// Port of the `@stylistic/yield-star-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// option (`"before"`, `"after"`, the default, `"both"`, `"neither"`, or an object with `before`
// and `after`) and its fixes.

const sysp_messages = {
	'missingBefore':    'Missing space before *.'
	'missingAfter':     'Missing space after *.'
	'unexpectedBefore': 'Unexpected space before *.'
	'unexpectedAfter':  'Unexpected space after *.'
}

// SyspMode is the spacing asked on each side of the `*`; none when an object option leaves the
// side out (`undefined`: never equal to isSpaceBetween, so always reported as unexpected).
struct SyspMode {
	before ?bool
	after  ?bool
}

fn sysp_options(given []json2.Any) !SyspMode {
	options := sty_options(given, [json2.Any('after')])
	config := if options.len > 0 { options[0] } else { json2.Any(json2.Null{}) }
	if config is map[string]json2.Any {
		return SyspMode{
			before: sty_option_bool(config, 'before')
			after:  sty_option_bool(config, 'after')
		}
	}
	return match sty_option_string(options, 0, '') {
		'before' { SyspMode{true, false} }
		'both' { SyspMode{true, true} }
		'neither' { SyspMode{false, false} }
		else { SyspMode{false, true} }
	}
}

fn (mut c Checker) lint_stylistic_yield_star_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mode := sysp_options(c.rule_options(stylistic_yield_star_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if t.typ(node) != .yield_expression || !(t.flag(node, .delegate) or { false }) {
			continue
		}
		stats.checked++
		yield_token := un_first_token(t, tokens, node, 0) or { continue }
		star_token := un_first_token(t, tokens, node, 1) or { continue }
		next_token := un_first_token(t, tokens, node, 2) or { continue }
		c.sysp_check(t, tokens, 'before', mode.before, yield_token, star_token, mut findings)
		c.sysp_check(t, tokens, 'after', mode.after, star_token, next_token, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sysp_check ports checkSpacing.
fn (c &Checker) sysp_check(t &estree.EsTree, tokens &SourceTokens, side string, mode ?bool, left SourceToken, right SourceToken, mut findings []Finding) {
	spaced := tokens.is_space_between(left.end, right.start)
	if wanted := mode {
		if spaced == wanted {
			return
		}
	}
	space_required := mode or { false }
	after := c.token_text(left) == '*'
	node := if after { left } else { right }
	message_id := if space_required {
		if side == 'before' { 'missingBefore' } else { 'missingAfter' }
	} else {
		if side == 'before' { 'unexpectedBefore' } else { 'unexpectedAfter' }
	}
	fix := if space_required {
		if after { fix_insert_at(node.end, ' ') } else { fix_insert_at(node.start, ' ') }
	} else {
		fix_remove_range(left.end, right.start)
	}
	findings << Finding{
		stmt:       c.position_range(node.start, node.end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}
