module rules

import estree
import time
import x.json2

// Port of the `@stylistic/array-bracket-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`"always"` or `"never"`, the default, and the exceptions `singleValue`,
// `objectsInArrays` and `arraysInArrays`) and its fixes.

const sabs_messages = {
	'unexpectedSpaceAfter':  "There should be no space after '{{tokenValue}}'."
	'unexpectedSpaceBefore': "There should be no space before '{{tokenValue}}'."
	'missingSpaceAfter':     "A space is required after '{{tokenValue}}'."
	'missingSpaceBefore':    "A space is required before '{{tokenValue}}'."
}

struct SabsOptions {
	spaced                     bool
	single_element_exception   bool
	objects_in_arrays_exception bool
	arrays_in_arrays_exception bool
}

fn sabs_options(given []json2.Any) !SabsOptions {
	options := sty_options(given, [json2.Any('never')])
	spaced := sty_option_string(options, 0, '') == 'always'
	// isOptionSet: `context.options[1][option] === !spaced` (the options as given).
	exceptions := sty_option_object(given, 1)
	is_set := fn [exceptions, spaced] (option string) bool {
		value := sty_option_bool(exceptions, option) or { return false }
		return value == !spaced
	}
	return SabsOptions{
		spaced:                      spaced
		single_element_exception:    is_set('singleValue')
		objects_in_arrays_exception: is_set('objectsInArrays')
		arrays_in_arrays_exception:  is_set('arraysInArrays')
	}
}

fn (mut c Checker) lint_stylistic_array_bracket_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sabs_options(c.rule_options(stylistic_array_bracket_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if !t.visits(node) {
			continue
		}
		if t.typ(node) !in [.array_pattern, .array_expression] {
			continue
		}
		stats.checked++
		c.sabs_validate(t, tokens, node, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn sabs_is_object_type(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.object_expression, .object_pattern]
}

fn sabs_is_array_type(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.array_expression, .array_pattern]
}

// sabs_validate ports validateArraySpacing.
fn (c &Checker) sabs_validate(t &estree.EsTree, tokens &SourceTokens, node int, options SabsOptions, mut findings []Finding) {
	elements := t.list(node, .elements) or { []int{} }
	if options.spaced && elements.len == 0 {
		return
	}
	first := un_first_token(t, tokens, node, 0) or { return }
	second := un_first_token(t, tokens, node, 1) or { return }
	mut last := un_last_token(t, tokens, node) or { return }
	if t.typ(node) == .array_pattern {
		if annotation := t.node(node, .type_annotation) {
			last = tokens.before(t.nodes[annotation].start, false) or { return }
		}
	}
	penultimate := tokens.before(last.start, false) or { return }
	first_element := if elements.len > 0 { elements[0] } else { -1 }
	last_element := if elements.len > 0 { elements.last() } else { -1 }
	opening_must_be_spaced := if (first_element >= 0 && options.objects_in_arrays_exception
		&& sabs_is_object_type(t, first_element)) || (first_element >= 0
		&& options.arrays_in_arrays_exception && sabs_is_array_type(t, first_element))
		|| (options.single_element_exception && elements.len == 1) {
		!options.spaced
	} else {
		options.spaced
	}
	closing_must_be_spaced := if (last_element >= 0 && options.objects_in_arrays_exception
		&& sabs_is_object_type(t, last_element)) || (last_element >= 0
		&& options.arrays_in_arrays_exception && sabs_is_array_type(t, last_element))
		|| (options.single_element_exception && elements.len == 1) {
		!options.spaced
	} else {
		options.spaced
	}
	if sty_same_line(t, first, second) {
		spaced := tokens.is_space_between(first.end, second.start)
		if opening_must_be_spaced && !spaced {
			findings << c.sabs_report(first.start, first.end, 'missingSpaceAfter', c.token_text(first),
				fix_replace_range(first.end, first.end, ' '))
		}
		if !opening_must_be_spaced && spaced {
			next := tokens.after(first.end, false) or { return }
			findings << c.sabs_report(first.end, next.start, 'unexpectedSpaceAfter', c.token_text(first),
				fix_remove_range(first.end, next.start))
		}
	}
	if first.start != penultimate.start && sty_same_line(t, penultimate, last) {
		spaced := tokens.is_space_between(penultimate.end, last.start)
		if closing_must_be_spaced && !spaced {
			findings << c.sabs_report(last.start, last.end, 'missingSpaceBefore', c.token_text(last),
				fix_replace_range(last.start, last.start, ' '))
		}
		if !closing_must_be_spaced && spaced {
			previous := tokens.before(last.start, false) or { return }
			findings << c.sabs_report(previous.end, last.start, 'unexpectedSpaceBefore', c.token_text(last),
				fix_remove_range(previous.end, last.start))
		}
	}
}

fn (c &Checker) sabs_report(start int, end int, message_id string, token_value string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       {
			'tokenValue': token_value
		}
		has_fix:    true
		fix:        fix
	}
}
