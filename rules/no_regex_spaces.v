module rules

import regexpp
import time
import treesitter { named_children, node_field, node_kind, node_start, position_of }

// Port of the `no-regex-spaces` rule of ESLint 10.6.0 (it has no options).

const nrs_messages = {
	'multipleSpaces': 'Spaces are hard to count. Use {{{length}}}.'
}

// nrs_spaces_pattern is ESLint's spacesPattern.
const nrs_spaces_pattern = '( {2,})(?: [+*{?]|[^+*{?]|$)'

fn (mut c Checker) lint_no_regex_spaces(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	spaces := regexp_compile(nrs_spaces_pattern)!
	for node in c.nodes_of_kinds(root, ['regex', 'call_expression', 'new_expression'], []) {
		stats.checked++
		if node_kind(node) == 'regex' {
			pattern, flags := c.es_regex_literal(node) or { continue }
			raw := stv_units_string(pattern)
			c.nrs_check(node, pattern, raw, node_start(node) + 1, flags, spaces, mut findings)
			continue
		}
		callee := node_field(node, if node_kind(node) == 'call_expression' {
			'function'
		} else {
			'constructor'
		}) or { continue }
		if node_kind(callee) != 'identifier' || c.text(callee) != 'RegExp' {
			continue
		}
		arguments := node_field(node, 'arguments') or { continue }
		if node_kind(arguments) != 'arguments' {
			continue
		}
		args := named_children(arguments).filter(node_kind(it) != 'comment').map(unwrap_parens(it))
		if args.len == 0 {
			continue
		}
		pattern := c.es_string_units(args[0]) or { continue }
		// The RegExp of the scope must be the global one (a variable without definitions).
		tree := c.scope_tree(root)
		v := tree.find_variable(tree.get_scope(node), 'RegExp', -1)
		if v >= 0 && tree.variables[v].defs.len > 0 {
			continue
		}
		mut flags := ''
		if args.len >= 2 {
			flag_units := c.es_string_units(args[1]) or { continue }
			flags = stv_units_string(flag_units)
		}
		text := c.text(args[0])
		raw := text[1..text.len - 1]
		c.nrs_check(node, pattern, raw, node_start(args[0]) + 1, flags, spaces, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nrs_check ports checkRegex: the first run of two or more spaces outside a character class.
fn (c &Checker) nrs_check(node C.TSNode, pattern []u16, raw string, raw_start int, flags string, spaces RegexpProgram, mut findings []Finding) {
	if !raw.contains('  ') {
		return
	}
	ast := regexpp.parse_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags),
		regexpp.Options{}) or { return }
	mut classes := [][]int{}
	for event in ast.visit_events() {
		if event.enter && ast.nodes[event.node].kind == .character_class {
			classes << [ast.nodes[event.node].start, ast.nodes[event.node].end]
		}
	}
	text := stv_units_string(pattern)
	runes := text.runes()
	mut from := 0
	for from <= runes.len {
		found, start, end, groups := regexp_exec(spaces, runes, from) or { return }
		if !found {
			return
		}
		index := utf16_units(runes[..start].string()).len
		length := groups[3] - groups[2]
		if classes.all(index < it[0] || it[1] <= index) {
			mut f := Finding{
				stmt:       position_of(node)
				message_id: 'multipleSpaces'
				data:       {
					'length': '${length}'
				}
			}
			if raw == text {
				at := raw_start + es_units_byte_offset(raw, index)
				f = Finding{
					...f
					has_fix: true
					fix:     Fix{at, at + length, ' {${length}}'}
				}
			}
			findings << f
			return
		}
		from = if end == start { end + 1 } else { end }
	}
}
