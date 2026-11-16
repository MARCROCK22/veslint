module rules

import estree
import time
import x.json2

// Port of the `@stylistic/type-generic-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`before` and `after`: the space before a type parameter declaration or instantiation and
// the one after it) and its fixes. The spaces around the `=` of a default of a type parameter
// moved to `@stylistic/space-infix-ops` in 6.0.

const stgs_messages = {
	'genericSpacingMismatch': 'Generic spaces mismatch'
}

// SKIP_BEFORE_CHECK: the parents of a type parameter declaration or instantiation whose space
// before it is not checked.
const stgs_skip_before_check = [estree.NodeType.ts_call_signature_declaration,
	.ts_construct_signature_declaration, .arrow_function_expression, .ts_function_type,
	.ts_constructor_type]

// SHOULD_CHECK_AFTER: the parents of a type parameter declaration or instantiation whose space
// after it is checked.
const stgs_should_check_after = [estree.NodeType.call_expression, .new_expression,
	.tagged_template_expression, .ts_call_signature_declaration, .ts_construct_signature_declaration,
	.ts_method_signature, .ts_function_type, .ts_constructor_type]

struct StgsOptions {
	before bool
	after  bool
}

fn stgs_options(given []json2.Any) !StgsOptions {
	options := sty_options(given, [
		json2.Any({
			'before': json2.Any(false)
			'after':  json2.Any(false)
		}),
	])
	object := sty_option_object(options, 0)
	return StgsOptions{
		before: sty_option_bool(object, 'before') or { false }
		after:  sty_option_bool(object, 'after') or { false }
	}
}

fn (mut c Checker) lint_stylistic_type_generic_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := stgs_options(c.rule_options(stylistic_type_generic_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.ts_type_parameter_instantiation, .ts_type_parameter_declaration {
				stats.checked++
				c.stgs_check_before(t, tokens, node, options, mut findings)
				c.stgs_check_after(t, tokens, node, options, mut findings)
				c.stgs_check_params(t, tokens, node, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// stgs_skip_before ports shouldSkipBeforeCheck.
fn stgs_skip_before(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	parent_type := t.typ(parent)
	if parent_type in stgs_skip_before_check {
		return true
	}
	// const foo = function <T>() {} and const foo = class <T> {}
	if parent_type in [.function_expression, .class_expression] {
		return (t.node(parent, .id) or { -1 }) < 0
	}
	return false
}

// stgs_check_before ports checkBefore.
fn (c &Checker) stgs_check_before(t &estree.EsTree, tokens &SourceTokens, node int, options StgsOptions, mut findings []Finding) {
	if stgs_skip_before(t, node) {
		return
	}
	start := t.nodes[node].start
	pre_token := tokens.before(start, true) or { return }
	has_space := pre_token.end != start
	if options.before == has_space {
		return
	}
	findings << Finding{
		stmt:       c.position_range(pre_token.end, start)
		message_id: 'genericSpacingMismatch'
		has_fix:    true
		fix:        if options.before {
			fix_insert_at(start, ' ')
		} else {
			fix_replace_range(pre_token.end, start, '')
		}
	}
}

// stgs_check_after ports checkAfter.
fn (c &Checker) stgs_check_after(t &estree.EsTree, tokens &SourceTokens, node int, options StgsOptions, mut findings []Finding) {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) !in stgs_should_check_after {
		return
	}
	end := t.nodes[node].end
	next_token := tokens.after(end, true) or { return }
	has_space := next_token.start != end
	if options.after == has_space {
		return
	}
	findings << Finding{
		stmt:       c.position_range(end, next_token.start)
		message_id: 'genericSpacingMismatch'
		has_fix:    true
		fix:        if options.after {
			fix_insert_at(end, ' ')
		} else {
			fix_replace_range(end, next_token.start, '')
		}
	}
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
