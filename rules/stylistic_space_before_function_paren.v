module rules

import estree
import time
import x.json2

// Port of the `@stylistic/space-before-function-paren` rule of @stylistic/eslint-plugin 5.10.0,
// with its options (`"always"`, the default, `"never"`, or an object with `anonymous`, `named`,
// `asyncArrow` and `catch`, each `"always"`, `"never"` or `"ignore"`) and its fixes.

const ssbfp_messages = {
	'unexpectedSpace': 'Unexpected space before function parentheses.'
	'missingSpace':    'Missing space before function parentheses.'
}

struct SsbfpOptions {
	async_arrow string
	anonymous   string
	named       string
	catch_      string
}

fn ssbfp_options(given []json2.Any) !SsbfpOptions {
	options := sty_options(given, [json2.Any('always')])
	if options.len > 0 {
		value := options[0]
		if value is string {
			return SsbfpOptions{
				async_arrow: value
				anonymous:   value
				named:       value
				catch_:      value
			}
		}
	}
	config := sty_option_object(options, 0)
	option := fn [config] (key string) string {
		value := config[key] or { return 'always' }
		if value is string {
			return value
		}
		return 'always'
	}
	return SsbfpOptions{
		async_arrow: option('asyncArrow')
		anonymous:   option('anonymous')
		named:       option('named')
		catch_:      option('catch')
	}
}

fn (mut c Checker) lint_stylistic_space_before_function_paren(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := ssbfp_options(c.rule_options(stylistic_space_before_function_paren))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.arrow_function_expression, .function_declaration, .function_expression,
			.ts_empty_body_function_expression, .ts_declare_function {
				stats.checked++
				c.ssbfp_check_function(t, tokens, node, options, mut findings)
			}
			.catch_clause {
				stats.checked++
				if t.node(node, .param) == none || options.catch_ == 'ignore' {
					continue
				}
				right := c.ssbfp_first_opening_paren(t, tokens, node) or { continue }
				left := tokens.before(right.start, false) or { continue }
				c.ssbfp_check_space(tokens, left, right, options.catch_, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ssbfp_first_opening_paren is getFirstToken(node, isOpeningParenToken).
fn (c &Checker) ssbfp_first_opening_paren(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	for token in tokens.inside(t.nodes[node].start, t.nodes[node].end, false) {
		if c.token_is(token, '(') {
			return token
		}
	}
	return none
}

// ssbfp_is_named_function ports isNamedFunction.
fn ssbfp_is_named_function(t &estree.EsTree, node int) bool {
	if _ := t.node(node, .id) {
		return true
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.method_definition, .ts_abstract_method_definition {
			true
		}
		.property {
			kind := t.string_of(parent, .kind) or { '' }
			kind in ['get', 'set'] || (t.flag(parent, .method) or { false })
		}
		else {
			false
		}
	}
}

// ssbfp_config ports getConfigForFunction.
fn (c &Checker) ssbfp_config(t &estree.EsTree, tokens &SourceTokens, node int, options SsbfpOptions) string {
	if t.typ(node) == .arrow_function_expression {
		if t.flag(node, .async) or { false } {
			if second := un_first_token(t, tokens, node, 1) {
				if c.token_is(second, '(') {
					return options.async_arrow
				}
			}
		}
	} else if ssbfp_is_named_function(t, node) {
		return options.named
	} else if !(t.flag(node, .generator) or { false }) {
		return options.anonymous
	}
	return 'ignore'
}

// ssbfp_check_function ports checkFunction.
fn (c &Checker) ssbfp_check_function(t &estree.EsTree, tokens &SourceTokens, node int, options SsbfpOptions, mut findings []Finding) {
	config := c.ssbfp_config(t, tokens, node, options)
	if config == 'ignore' {
		return
	}
	type_parameters := t.node(node, .type_parameters) or { -1 }
	has_id := t.node(node, .id) != none
	if config == 'always' && type_parameters >= 0 && !has_id {
		return
	}
	mut left := SourceToken{}
	mut right := SourceToken{}
	if type_parameters >= 0 {
		left = un_last_token(t, tokens, type_parameters) or { return }
		right = tokens.after(left.end, false) or { return }
	} else {
		right = c.ssbfp_first_opening_paren(t, tokens, node) or { return }
		left = tokens.before(right.start, false) or { return }
	}
	c.ssbfp_check_space(tokens, left, right, config, mut findings)
}

// ssbfp_check_space ports checkSpace.
fn (c &Checker) ssbfp_check_space(tokens &SourceTokens, left SourceToken, right SourceToken, option string, mut findings []Finding) {
	has_spacing := tokens.is_space_between(left.end, right.start)
	if has_spacing && option == 'never' {
		comments := tokens.comments_before(right.start)
		// No fix when a line comment is between the tokens.
		has_line_comment := comments.any(it.kind == .line_comment)
		mut text := ''
		for comment in comments {
			text += c.token_text(comment)
		}
		findings << Finding{
			stmt:       c.position_range(left.end, right.start)
			message_id: 'unexpectedSpace'
			has_fix:    !has_line_comment
			fix:        if has_line_comment {
				Fix{}
			} else {
				fix_replace_range(left.end, right.start, text)
			}
		}
	} else if !has_spacing && option == 'always' {
		findings << Finding{
			stmt:       c.position_range(right.start, right.end)
			message_id: 'missingSpace'
			has_fix:    true
			fix:        fix_replace_range(left.end, left.end, ' ')
		}
	}
}
