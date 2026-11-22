module rules

import estree
import time
import x.json2

// Port of the `@stylistic/dot-location` rule of @stylistic/eslint-plugin 6.0.1, with its option
// (`"property"`, the default since 6.0.0, or `"object"`) and its fixes.

const sdl_messages = {
	'expectedDotAfterObject':    'Expected dot to be on same line as object.'
	'expectedDotBeforeProperty': 'Expected dot to be on same line as property.'
}

fn sdl_options(given []json2.Any) !bool {
	options := sty_options(given, [json2.Any('property')])
	return sty_option_string(options, 0, 'property') == 'object'
}

fn (mut c Checker) lint_stylistic_dot_location(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	on_object := sdl_options(c.rule_options(stylistic_dot_location))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		// getProperty
		property := match t.typ(node) {
			.member_expression {
				// obj['foo']
				if t.flag(node, .computed) or { false } {
					continue
				}
				t.node(node, .property) or { continue }
			}
			.meta_property, .jsx_member_expression {
				t.node(node, .property) or { continue }
			}
			.ts_qualified_name {
				t.node(node, .right) or { continue }
			}
			.ts_import_type {
				t.node(node, .qualifier) or { continue }
			}
			else {
				continue
			}
		}
		stats.checked++
		c.sdl_check(t, tokens, property, on_object, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sdl_check ports checkDotLocation.
fn (c &Checker) sdl_check(t &estree.EsTree, tokens &SourceTokens, property int, on_object bool, mut findings []Finding) ! {
	dot := tokens.before(t.nodes[property].start, false) or { return }
	dot_value := c.token_text(dot)
	if on_object {
		// The object can be parenthesized: the parentheses are not part of it.
		before := tokens.before(dot.start, false) or { return }
		if !sty_same_line(t, before, dot) {
			inserted := if dot_value.starts_with('.') && before.kind == .numeric
				&& un_is_decimal_integer(c.token_text(before)) {
				' ${dot_value}'
			} else {
				dot_value
			}
			has_fix, fix := c.merge_fixes([fix_insert_at(before.end, inserted),
				fix_remove_range(dot.start, dot.end)])!
			findings << Finding{
				stmt:       c.position_range(dot.start, dot.end)
				message_id: 'expectedDotAfterObject'
				has_fix:    has_fix
				fix:        fix
			}
		}
	} else if !sty_same_line_offsets(t, dot.end, t.nodes[property].start) {
		has_fix, fix := c.merge_fixes([fix_remove_range(dot.start, dot.end),
			fix_insert_at(t.nodes[property].start, dot_value)])!
		findings << Finding{
			stmt:       c.position_range(dot.start, dot.end)
			message_id: 'expectedDotBeforeProperty'
			has_fix:    has_fix
			fix:        fix
		}
	}
}
