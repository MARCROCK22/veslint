module rules

import estree
import time
import x.json2

// Port of the `@stylistic/space-before-blocks` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`"always"`, the default, `"never"`, or an object with `keywords`, `functions`,
// `classes` and `modules`, each `"always"`, `"never"` or `"off"`) and its fixes.

const ssbb_messages = {
	'unexpectedSpace': 'Unexpected space before opening brace.'
	'missingSpace':    'Missing space before opening brace.'
}

// SsbbSpacing is what a kind of block asks: `always`, `never`, or neither (`off`).
struct SsbbSpacing {
	always bool
	never  bool
}

struct SsbbOptions {
	functions SsbbSpacing
	keywords  SsbbSpacing
	classes   SsbbSpacing
	modules   SsbbSpacing
}

fn ssbb_options(given []json2.Any) !SsbbOptions {
	options := sty_options(given, [json2.Any('always')])
	config := if options.len > 0 { options[0] } else { json2.Any(json2.Null{}) }
	if config is map[string]json2.Any {
		// categoryConfig: `{ functions: 'always', keywords: 'always', classes: 'always', modules:
		// 'always', ...config }`
		spacing := fn [config] (key string) SsbbSpacing {
			value := sty_option_string([config[key] or { json2.Any('always') }], 0, '')
			return SsbbSpacing{value == 'always', value == 'never'}
		}
		return SsbbOptions{
			functions: spacing('functions')
			keywords:  spacing('keywords')
			classes:   spacing('classes')
			modules:   spacing('modules')
		}
	}
	never := config is string && config == 'never'
	spacing := SsbbSpacing{!never, never}
	return SsbbOptions{spacing, spacing, spacing, spacing}
}

fn (mut c Checker) lint_stylistic_space_before_blocks(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := ssbb_options(c.rule_options(stylistic_space_before_blocks))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.block_statement, .class_body, .ts_enum_body, .ts_interface_body, .ts_module_block {
				stats.checked++
				c.ssbb_check(t, tokens, node, t.nodes[node].start, t.nodes[node].end, options, mut
					findings)
			}
			.switch_statement {
				stats.checked++
				cases := t.list(node, .cases) or { []int{} }
				opening_brace := if cases.len > 0 {
					tokens.before(t.nodes[cases[0]].start, false) or { continue }
				} else {
					// getLastToken(node, 1)
					last := un_last_token(t, tokens, node) or { continue }
					tokens.before(last.start, false) or { continue }
				}
				c.ssbb_check(t, tokens, -1, opening_brace.start, opening_brace.end, options, mut
					findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ssbb_is_function_body ports isFunctionBody: a block that is the body of a function (`node` is -1
// for a token).
fn ssbb_is_function_body(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .block_statement {
		return false
	}
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) in [.arrow_function_expression, .function_declaration,
		.function_expression] && (t.node(parent, .body) or { -1 }) == node
}

// ssbb_is_conflicted ports isConflicted: the spacing is checked by `arrow-spacing`,
// `keyword-spacing` (not that of a class body, as `class{}`) or `switch-colon-spacing`.
fn (c &Checker) ssbb_is_conflicted(t &estree.EsTree, tokens &SourceTokens, preceding SourceToken, node int) bool {
	if c.token_is(preceding, '=>') {
		return true
	}
	if preceding.kind == .keyword && !ssbb_is_function_body(t, node)
		&& (node < 0 || t.typ(node) != .class_body) {
		return true
	}
	if c.token_is(preceding, ':') && node >= 0 {
		parent := t.nodes[node].parent
		if parent >= 0 && t.typ(parent) == .switch_case {
			colon := c.sscs_colon_token(t, tokens, parent) or { return false }
			return colon.start == preceding.start
		}
	}
	return false
}

// ssbb_check ports checkPrecedingSpace for a node (`node` >= 0) or the `{` token of a switch
// statement (`node` is -1), from `start` to `end`.
fn (c &Checker) ssbb_check(t &estree.EsTree, tokens &SourceTokens, node int, start int, end int, options SsbbOptions, mut findings []Finding) {
	preceding := tokens.before(start, false) or { return }
	if c.ssbb_is_conflicted(t, tokens, preceding, node)
		|| !sty_same_line_offsets(t, preceding.end, start) {
		return
	}
	has_space := tokens.is_space_between(preceding.end, start)
	spacing := if ssbb_is_function_body(t, node) {
		options.functions
	} else if node >= 0 && t.typ(node) in [.class_body, .ts_enum_body, .ts_interface_body] {
		options.classes
	} else if node >= 0 && t.typ(node) == .ts_module_block {
		options.modules
	} else {
		options.keywords
	}
	if spacing.always && !has_space {
		findings << Finding{
			stmt:       c.position_range(start, end)
			message_id: 'missingSpace'
			has_fix:    true
			fix:        fix_insert_at(start, ' ')
		}
	} else if spacing.never && has_space {
		findings << Finding{
			stmt:       c.position_range(start, end)
			message_id: 'unexpectedSpace'
			has_fix:    true
			fix:        fix_remove_range(preceding.end, start)
		}
	}
}
