module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `prefer-object-spread` rule of ESLint 10.6.0, with its fix (it has no options).

const pos_messages = {
	'useSpreadMessage':  'Use an object spread instead of `Object.assign` eg: `{ ...foo }`.'
	'useLiteralMessage': 'Use an object literal instead of `Object.assign`. eg: `{ foo: bar }`.'
}

fn (mut c Checker) lint_prefer_object_spread(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	trace := {
		'Object': EsTrace{
			children: {
				'assign': EsTrace{
					call: true
				}
			}
		}
	}
	for traced in c.es_global_references(root, trace) {
		call := traced.node
		stats.checked++
		args := (call_arguments(call) or { continue }).filter(node_kind(it) != 'comment')
		if args.len == 0 || node_kind(unwrap_parens(args[0])) != 'object'
			|| args.any(node_kind(it) == 'spread_element') {
			continue
		}
		if args.len > 1 && args.any(node_kind(unwrap_parens(it)) == 'object'
			&& named_children(unwrap_parens(it)).any(es_accessor_kind(it) in ['get', 'set'])) {
			continue
		}
		has_fix, fix := c.pos_fix(root, call, args)
		findings << Finding{
			stmt:       position_of(call)
			message_id: if args.len == 1 { 'useLiteralMessage' } else { 'useSpreadMessage' }
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn pos_is_space(b u8) bool {
	return b in [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
}

// pos_needs_parens ports needsParens: an object literal in the place of the call would start a
// statement or be read otherwise.
fn (mut c Checker) pos_needs_parens(call C.TSNode) bool {
	parent := cti_estree_parent(call) or { return false }
	match node_kind(parent) {
		'variable_declarator', 'array', 'return_statement', 'call_expression', 'pair' {
			return false
		}
		'arguments' {
			holder := node_parent(parent) or { return false }
			if node_kind(holder) == 'call_expression' {
				return false
			}
			return !c.es_is_parenthesised(call)
		}
		'assignment_expression' {
			left := node_field(parent, 'left') or { return false }
			return node_key(unwrap_parens(left)) == node_key(call) && !c.es_is_parenthesised(call)
		}
		else {
			return !c.es_is_parenthesised(call)
		}
	}
}

// pos_fix ports defineFixer: `{ ...a, b: 1 }` from `Object.assign({}, a, { b: 1 })`.
fn (mut c Checker) pos_fix(root C.TSNode, call C.TSNode, args []C.TSNode) (bool, Fix) {
	tokens := c.source_tokens(root)
	callee := node_field(call, 'function') or { return false, Fix{} }
	mut left_paren := tokens.after(c.es_end(callee), false) or { return false, Fix{} }
	for c.src[left_paren.start..left_paren.end] != '(' {
		left_paren = tokens.after(left_paren.end, false) or { return false, Fix{} }
	}
	right_paren := tokens.before(c.es_end(call), false) or { return false, Fix{} }
	mut fixes := []Fix{}
	fixes << fix_remove_range(node_start(call), left_paren.start)
	parens := c.pos_needs_parens(call)
	fixes << fix_replace_range(left_paren.start, left_paren.end, if parens { '({' } else { '{' })
	fixes << fix_replace_range(right_paren.start, right_paren.end, if parens { '})' } else { '}' })
	for arg_raw in args {
		arg := unwrap_parens(arg_raw)
		// getParenTokens: the first and last tokens of the argument and the parentheses around it.
		mut list := []SourceToken{}
		list << (tokens.after(node_start(arg), false) or { return false, Fix{} })
		list << (tokens.before(c.es_end(arg), false) or { return false, Fix{} })
		mut left_next := tokens.before(node_start(arg), false) or { return false, Fix{} }
		mut right_next := tokens.after(c.es_end(arg), false) or { return false, Fix{} }
		for left_next.start > left_paren.start && c.src[left_next.start..left_next.end] == '('
			&& c.src[right_next.start..right_next.end] == ')' {
			list << left_next
			list << right_next
			left_next = tokens.before(left_next.start, false) or { break }
			right_next = tokens.after(right_next.end, false) or { break }
		}
		list.sort(a.start < b.start)
		left := list[0]
		right := list.last()
		inner := list[1..list.len - 1]
		if node_kind(arg) == 'object' {
			closing := tokens.before(c.es_end(arg), false) or { return false, Fix{} }
			maybe_trailing := tokens.before(closing.start, false) or { return false, Fix{} }
			for t in inner {
				fixes << fix_remove_range(t.start, t.end)
			}
			mut left_end := left.end
			for left_end < c.src.len && pos_is_space(c.src[left_end]) {
				left_end++
			}
			mut right_start := right.start
			before_right := tokens.before(right.start, true) or { right }
			if before_right.kind != .line_comment {
				for right_start > 0 && pos_is_space(c.src[right_start - 1]) {
					right_start--
				}
			}
			if right_start < left_end {
				right_start = left_end
			}
			fixes << fix_remove_range(left.start, left_end)
			fixes << fix_remove_range(right_start, right.end)
			properties := named_children(arg).filter(node_kind(it) != 'comment')
			if comma := tokens.after(right.end, false) {
				if (properties.len == 0 || c.src[maybe_trailing.start..maybe_trailing.end] == ',')
					&& c.src[comma.start..comma.end] == ',' {
					fixes << fix_remove_range(comma.start, comma.end)
				}
			}
		} else {
			needs := node_kind(arg) in ['assignment_expression', 'augmented_assignment_expression',
				'arrow_function', 'ternary_expression'] && !c.es_is_parenthesised(arg)
			if needs {
				fixes << fix_insert_at(left.start, '...(')
				fixes << fix_insert_at(right.end, ')')
			} else {
				fixes << fix_insert_at(left.start, '...')
			}
		}
	}
	has_fix, fix := c.merge_fixes(fixes) or { return false, Fix{} }
	return has_fix, fix
}
