module rules

import estree
import json2

// Ports of the `array-bracket-newline` and `array-element-newline` rules of
// @stylistic/eslint-plugin 6.0.1, with their options and fixes, for vue/array-bracket-newline and
// vue/array-element-newline (vue_wrap.v), which have them as their bases and not as rules of their
// own. With `c.vue_wrap_core` they give what ESLint core's give: array-bracket-newline closes an
// ArrayPattern at its last token whatever its type annotation, and array-element-newline has no
// `consistent` in an object option.

const sabn_messages = {
	'unexpectedOpeningLinebreak': "There should be no linebreak after '['."
	'unexpectedClosingLinebreak': "There should be no linebreak before ']'."
	'missingOpeningLinebreak':    "A linebreak is required after '['."
	'missingClosingLinebreak':    "A linebreak is required before ']'."
}

const saen_messages = {
	'unexpectedLineBreak': 'There should be no linebreak here.'
	'missingLineBreak':    'There should be a linebreak after this element.'
}

struct SaNewlineOption {
	consistent bool
	multiline  bool
	min_items  int // max_i32 for Number.POSITIVE_INFINITY
}

// sabn_option ports array-bracket-newline's normalizeOptionValue.
fn sabn_option(option json2.Any) SaNewlineOption {
	if option is string && option != '' {
		return match option {
			'consistent' {
				SaNewlineOption{
					consistent: true
					min_items:  max_i32
				}
			}
			'always' { SaNewlineOption{} }
			else {
				SaNewlineOption{
					min_items: max_i32
				}
			}
		}
	}
	if option is map[string]json2.Any {
		min := option['minItems'] or { json2.Any(json2.Null{}) }
		if min is f64 && min == 0 {
			return SaNewlineOption{}
		}
		return SaNewlineOption{
			multiline: sty_option_bool(option, 'multiline') or { false }
			min_items: sa_min_items(min)
		}
	}
	return SaNewlineOption{
		multiline: true
		min_items: max_i32
	}
}

// sa_min_items is `option.minItems || Number.POSITIVE_INFINITY`.
fn sa_min_items(value json2.Any) int {
	if value is f64 && value != 0 {
		return int(value)
	}
	if value is i64 && value != 0 {
		return int(value)
	}
	return max_i32
}

fn (mut c Checker) lint_stylistic_array_bracket_newline(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	mut findings := []Finding{}
	given := c.rule_options(vue_wrap_array_bracket_newline)
	option := sabn_option(if given.len > 0 { given[0] } else { json2.Any(json2.Null{}) })
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) !in [.array_expression, .array_pattern] {
			continue
		}
		node := step.node
		stats.checked++
		elements := t.list(node, .elements) or { []int{} }
		open := tokens.after(t.nodes[node].start, false) or { continue }
		mut close := tokens.before(t.nodes[node].end, false) or { continue }
		if !c.vue_wrap_core && t.typ(node) == .array_pattern {
			if annotation := t.node(node, .type_annotation) {
				close = tokens.before(t.nodes[annotation].start, false) or { continue }
			}
		}
		first_any := tokens.after(open.end, true) or { continue }
		last_any := tokens.before(close.start, true) or { continue }
		first := tokens.after(open.end, false) or { continue }
		last := tokens.before(close.start, false) or { continue }
		needs := elements.len >= option.min_items
			|| (option.multiline && elements.len > 0 && !sty_same_line(t, last_any, first_any))
			|| (elements.len == 0 && first_any.kind == .block_comment
				&& !sty_same_line(t, last_any, first_any) && first_any.start == last_any.start)
			|| (option.consistent && !sty_same_line(t, open, first))
		if needs {
			if sty_same_line(t, open, first) {
				findings << sa_report(c, open, 'missingOpeningLinebreak', fix_insert_at(open.end,
					'\n'))
			}
			if sty_same_line(t, last, close) {
				findings << sa_report(c, close, 'missingClosingLinebreak', fix_insert_at(close.start,
					'\n'))
			}
		} else {
			if !sty_same_line(t, open, first) {
				next := tokens.after(open.end, true) or { continue }
				findings << if next.is_comment() {
					Finding{
						stmt:       c.position_range(open.start, open.end)
						message_id: 'unexpectedOpeningLinebreak'
					}
				} else {
					sa_report(c, open, 'unexpectedOpeningLinebreak', fix_remove_range(open.end,
						next.start))
				}
			}
			if !sty_same_line(t, last, close) {
				previous := tokens.before(close.start, true) or { continue }
				findings << if previous.is_comment() {
					Finding{
						stmt:       c.position_range(close.start, close.end)
						message_id: 'unexpectedClosingLinebreak'
					}
				} else {
					sa_report(c, close, 'unexpectedClosingLinebreak', fix_remove_range(previous.end,
						close.start))
				}
			}
		}
	}
	return findings
}

fn sa_report(c &Checker, token SourceToken, message_id string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(token.start, token.end)
		message_id: message_id
		has_fix:    true
		fix:        fix
	}
}

// saen_option ports array-element-newline's normalizeOptionValue (`consistent` in an object only
// in ESLint Stylistic's).
fn saen_option(provided json2.Any, core bool) SaNewlineOption {
	if provided is map[string]json2.Any {
		min := provided['minItems'] or { json2.Any(json2.Null{}) }
		if (min is f64 && min == 0) || (min is i64 && min == 0) {
			return SaNewlineOption{}
		}
		return SaNewlineOption{
			consistent: !core && (sty_option_bool(provided, 'consistent') or { false })
			multiline:  sty_option_bool(provided, 'multiline') or { false }
			min_items:  sa_min_items(min)
		}
	}
	option := if provided is string && provided != '' { provided } else { 'always' }
	return match option {
		'never' {
			SaNewlineOption{
				min_items: max_i32
			}
		}
		'consistent' {
			SaNewlineOption{
				consistent: true
				min_items:  max_i32
			}
		}
		else { SaNewlineOption{} }
	}
}

// saen_options ports normalizeOptions: per node type, none for a type an object of types omits.
fn saen_options(given []json2.Any, core bool) (?SaNewlineOption, ?SaNewlineOption) {
	value := if given.len > 0 { given[0] } else { json2.Any(json2.Null{}) }
	if value is map[string]json2.Any {
		expression := value['ArrayExpression'] or { json2.Any(json2.Null{}) }
		pattern := value['ArrayPattern'] or { json2.Any(json2.Null{}) }
		if sa_truthy(expression) || sa_truthy(pattern) {
			e := if sa_truthy(expression) {
				?SaNewlineOption(saen_option(expression, core))
			} else {
				none
			}
			p := if sa_truthy(pattern) {
				?SaNewlineOption(saen_option(pattern, core))
			} else {
				none
			}
			return e, p
		}
	}
	option := saen_option(value, core)
	return option, option
}

fn sa_truthy(value json2.Any) bool {
	return match value {
		json2.Null { false }
		string { value != '' }
		bool { value }
		f64 { value != 0 }
		else { true }
	}
}

fn (mut c Checker) lint_stylistic_array_element_newline(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	mut findings := []Finding{}
	expression_option, pattern_option := saen_options(c.rule_options(vue_wrap_array_element_newline),
		c.vue_wrap_core)
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) !in [.array_expression, .array_pattern] {
			continue
		}
		node := step.node
		option := if t.typ(node) == .array_expression { expression_option } else { pattern_option }
		o := option or { continue }
		stats.checked++
		c.saen_check(t, tokens, node, o, mut findings)
	}
	return findings
}

// saen_pair is the comma between two elements and the tokens around it.
struct SaenPair {
	last_of_previous SourceToken
	first_of_current SourceToken
}

fn (c &Checker) saen_pairs(t &estree.EsTree, tokens &SourceTokens, elements []int) []?SaenPair {
	mut out := []?SaenPair{}
	for i, element in elements {
		if i == 0 || element < 0 || elements[i - 1] < 0 {
			out << ?SaenPair(none)
			continue
		}
		mut comma := ?SourceToken(none)
		for token in tokens.inside(t.nodes[elements[i - 1]].end, t.nodes[element].start, false) {
			if c.token_is(token, ',') {
				comma = token
				break
			}
		}
		cm := comma or {
			out << ?SaenPair(none)
			continue
		}
		before := tokens.before(cm.start, false) or {
			out << ?SaenPair(none)
			continue
		}
		after := tokens.after(cm.end, false) or {
			out << ?SaenPair(none)
			continue
		}
		out << SaenPair{before, after}
	}
	return out
}

fn (c &Checker) saen_check(t &estree.EsTree, tokens &SourceTokens, node int, o SaNewlineOption, mut findings []Finding) {
	elements := t.list(node, .elements) or { []int{} }
	mut element_break := false
	if o.multiline {
		for element in elements {
			if element >= 0 && !sty_same_line_offsets(t, t.nodes[element].start, t.nodes[element].end) {
				element_break = true
				break
			}
		}
	}
	pairs := c.saen_pairs(t, tokens, elements)
	mut breaks := 0
	for pair in pairs {
		p := pair or { continue }
		if !sty_same_line(t, p.last_of_previous, p.first_of_current) {
			breaks++
		}
	}
	needs := elements.len >= o.min_items || (o.multiline && element_break)
		|| (o.consistent && breaks > 0 && breaks < elements.len)
	for pair in pairs {
		p := pair or { continue }
		token := p.first_of_current
		same := sty_same_line(t, p.last_of_previous, token)
		before := tokens.before(token.start, true) or { continue }
		if needs {
			if same {
				findings << Finding{
					stmt:       c.position_range(before.end, token.start)
					message_id: 'missingLineBreak'
					has_fix:    true
					fix:        fix_replace_range(before.end, token.start, '\n')
				}
			}
		} else if !same {
			mut fix := ?Fix(none)
			if !before.is_comment() {
				if !sty_same_line(t, before, token) {
					fix = fix_replace_range(before.end, token.start, ' ')
				} else if two := tokens.before(before.start, true) {
					if !two.is_comment() {
						fix = fix_replace_range(two.end, before.start, '')
					}
				}
			}
			findings << Finding{
				stmt:       c.position_range(before.end, token.start)
				message_id: 'unexpectedLineBreak'
				has_fix:    fix != none
				fix:        fix or { Fix{} }
			}
		}
	}
}
