module rules

import estree
import time
import x.json2

// Port of the `@stylistic/object-property-newline` rule of @stylistic/eslint-plugin 6.0.1, with its
// option `allowAllPropertiesOnSameLine` and its fixes: each property of an object, a type literal
// or an interface body on a line of its own.

const sopn_messages = {
	'propertiesOnNewlineAll': "Object properties must go on a new line if they aren't all on the same line."
	'propertiesOnNewline':    'Object properties must go on a new line.'
}

fn sopn_options(given []json2.Any) !bool {
	options := sty_options(given, [
		json2.Any({
			'allowAllPropertiesOnSameLine': json2.Any(false)
		}),
	])
	return sty_option_bool(sty_option_object(options, 0), 'allowAllPropertiesOnSameLine') or {
		false
	}
}

fn (mut c Checker) lint_stylistic_object_property_newline(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	allow_same_line := sopn_options(c.rule_options(stylistic_object_property_newline))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		children := match t.typ(node) {
			.object_expression { t.list(node, .properties) or { []int{} } }
			.ts_type_literal { t.list(node, .members) or { []int{} } }
			.ts_interface_body { t.list(node, .body) or { []int{} } }
			else { continue }
		}
		stats.checked++
		c.sopn_check(t, tokens, children, allow_same_line, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sopn_check ports check.
fn (c &Checker) sopn_check(t &estree.EsTree, tokens &SourceTokens, children []int, allow_same_line bool, mut findings []Finding) {
	if allow_same_line && children.len > 1 {
		first := un_first_token(t, tokens, children[0], 0) or { return }
		last := un_last_token(t, tokens, children.last()) or { return }
		if sty_same_line(t, first, last) {
			return
		}
	}
	message_id := if allow_same_line { 'propertiesOnNewlineAll' } else { 'propertiesOnNewline' }
	for i in 1 .. children.len {
		last_of_previous := un_last_token(t, tokens, children[i - 1]) or { continue }
		first_of_current := un_first_token(t, tokens, children[i], 0) or { continue }
		if !sty_same_line(t, last_of_previous, first_of_current) {
			continue
		}
		before := tokens.before(first_of_current.start, false) or { continue }
		// The fix is null when there is more than white space (a comment) after the comma.
		has_fix := js_trim(c.src[before.end..first_of_current.start]) == ''
		findings << Finding{
			stmt:       c.position_range(first_of_current.start, first_of_current.end)
			message_id: message_id
			has_fix:    has_fix
			fix:        if has_fix {
				fix_replace_range(before.end, first_of_current.start, '\n')
			} else {
				Fix{}
			}
		}
	}
}
