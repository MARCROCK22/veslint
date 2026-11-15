module rules

import estree
import time

// Port of the `@stylistic/type-generic-spacing` rule of @stylistic/eslint-plugin 5.10.0 (no
// options), with its fixes.

const stgs_messages = {
	'genericSpacingMismatch': 'Generic spaces mismatch'
}

// The parents of a type parameter declaration that may have a space before it.
const stgs_preserve_prefix_space_before_generic = [estree.NodeType.ts_call_signature_declaration,
	.arrow_function_expression, .ts_function_type, .ts_constructor_type, .function_expression,
	.class_expression]

fn (mut c Checker) lint_stylistic_type_generic_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.ts_type_parameter_instantiation {
				stats.checked++
				c.stgs_check_params(t, tokens, node, mut findings)
			}
			.ts_type_parameter_declaration {
				stats.checked++
				parent := t.nodes[node].parent
				if parent < 0 || t.typ(parent) !in stgs_preserve_prefix_space_before_generic {
					start := t.nodes[node].start
					space_start := stgs_trailing_space_start(c.src, start)
					if space_start < start {
						findings << Finding{
							stmt:       c.position_range(start, t.nodes[node].end)
							message_id: 'genericSpacingMismatch'
							has_fix:    true
							fix:        fix_remove_range(space_start, start)
						}
					}
				}
				c.stgs_check_params(t, tokens, node, mut findings)
			}
			.ts_type_parameter {
				stats.checked++
				c.stgs_check_default(t, node, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// stgs_trailing_space_start is where the whitespace (JavaScript's `\s`) that ends at `end`
// starts: `text.slice(0, end).match(/(\s+)$/)`.
fn stgs_trailing_space_start(src string, end int) int {
	mut start := end
	for start > 0 {
		mut previous := start - 1
		for previous > 0 && src[previous] & 0xc0 == 0x80 {
			previous--
		}
		runes := src[previous..start].runes()
		if runes.len != 1 || !is_js_space(runes[0]) {
			break
		}
		start = previous
	}
	return start
}

// stgs_check_params ports the checkBracketSpacing of the params of a type parameter instantiation
// or declaration.
fn (c &Checker) stgs_check_params(t &estree.EsTree, tokens &SourceTokens, node int, mut findings []Finding) {
	params := t.list(node, .params) or { return }
	if params.len == 0 {
		return
	}
	if open := tokens.before(t.nodes[params[0]].start, false) {
		if first := tokens.after(open.end, false) {
			c.stgs_remove_space_between(open.end, first.start, mut findings)
		}
	}
	if close := tokens.after(t.nodes[params.last()].end, false) {
		if last := tokens.before(close.start, false) {
			c.stgs_remove_space_between(last.end, close.start, mut findings)
		}
	}
}

// stgs_remove_space_between ports removeSpaceBetween for what ends at `left_end` and what starts
// at `right_start`.
fn (c &Checker) stgs_remove_space_between(left_end int, right_start int, mut findings []Finding) {
	if left_end > right_start {
		return
	}
	between := c.src[left_end..right_start]
	if !between.runes().any(is_js_space(it)) || between.starts_with('\r')
		|| between.starts_with('\n') {
		return
	}
	findings << Finding{
		stmt:       c.position_range(left_end, right_start)
		message_id: 'genericSpacingMismatch'
		has_fix:    true
		fix:        fix_remove_range(left_end, right_start)
	}
}

// stgs_check_default ports the check of TSTypeParameter: one space around the `=` of a default.
fn (c &Checker) stgs_check_default(t &estree.EsTree, node int, mut findings []Finding) {
	default_node := t.node(node, .default_) or { return }
	end_node := t.node(node, .constraint) or { t.node(node, .name) or { return } }
	from := t.nodes[end_node].end
	to := t.nodes[default_node].start
	if from > to {
		return
	}
	span := c.src[from..to]
	if stgs_has_spaced_equal(span) {
		return
	}
	findings << Finding{
		stmt:       c.position_range(from, to)
		message_id: 'genericSpacingMismatch'
		has_fix:    true
		fix:        fix_replace_range(from, to, stgs_replace_equal(span))
	}
}

// stgs_has_spaced_equal is `/(?:^|[^ ]) = (?:$|[^ ])/.test(span)`.
fn stgs_has_spaced_equal(span string) bool {
	for i := 0; i + 3 <= span.len; i++ {
		if span[i..i + 3] == ' = ' && (i == 0 || span[i - 1] != ` `)
			&& (i + 3 == span.len || span[i + 3] != ` `) {
			return true
		}
	}
	return false
}

// stgs_replace_equal is `span.replace(/\s*=\s*/, ' = ')`: the first `=` and the whitespace around
// it.
fn stgs_replace_equal(span string) string {
	equal := span.index('=') or { return span }
	start := stgs_trailing_space_start(span, equal)
	mut end := equal + 1
	for end < span.len {
		length := utf8_char_len(span[end])
		if end + length > span.len {
			break
		}
		runes := span[end..end + length].runes()
		if runes.len != 1 || !is_js_space(runes[0]) {
			break
		}
		end += length
	}
	return span[..start] + ' = ' + span[end..]
}
