module rules

import time
import tsgo { TypeResponse }
import treesitter { node_field, node_kind, node_start, nodes_of_kind, position_of }

// Port of the `no-array-delete` rule of typescript-eslint 8.62.0 (it has no options), with its
// `useSplice` suggestion.

const nad_messages = {
	'noArrayDelete': 'Using the `delete` operator with an array expression is unsafe.'
	'useSplice':     'Use `array.splice()` instead.'
}

fn (mut c Checker) lint_no_array_delete(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// `UnaryExpression[operator="delete"]` whose argument is a MemberExpression (not an optional
	// chain): its object is checked.
	mut deletes := []C.TSNode{}
	mut objects := []C.TSNode{}
	mut members := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'unary_expression') {
		if operator_of(node) != 'delete' {
			continue
		}
		argument := unwrap_parens(node_field(node, 'argument') or { continue })
		if estree_type(argument) != 'MemberExpression' {
			continue
		}
		object := node_field(argument, 'object') or { continue }
		deletes << node
		objects << unwrap_parens(object)
		members << argument
	}
	c.resolve_spans(objects.map(node_span(it)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, node in deletes {
		t := c.node_type(objects[i]) or { continue }
		if c.nad_is_underlying_type_array(c.constrained(t)!)! {
			_, suggestion := c.suggestion('useSplice', map[string]string{}, [
				c.nad_use_splice(node, members[i], objects[i]),
			])!
			findings << Finding{
				stmt:        position_of(node)
				message_id:  'noArrayDelete'
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += deletes.len
	return findings
}

// nad_use_splice ports the fixer of the `useSplice` suggestion: `delete a[k]` becomes
// `a.splice(k, 1)`, after the comments that were inside the expression.
fn (c &Checker) nad_use_splice(node C.TSNode, member C.TSNode, object C.TSNode) Fix {
	property := unwrap_parens(node_field(member, 'index') or {
		node_field(member, 'property') or { member }
	})
	raw_key := c.text(property)
	key := if node_kind(property) == 'sequence_expression' { '(${raw_key})' } else { raw_key }
	mut text := '${c.text(object)}.splice(${key}, 1)'
	comments := nodes_of_kind(node, c'comment')
	if comments.len > 0 {
		indentation := ' '.repeat(utf16_column(c.src, node_start(node)))
		text = comments.map(c.text(it)).join('\n${indentation}') + '\n${indentation}${text}'
	}
	return fix_replace(node, text)
}

// nad_is_underlying_type_array ports isUnderlyingTypeArray: an array or a tuple; a union if all its
// parts are; an intersection if any part is.
fn (mut c Checker) nad_is_underlying_type_array(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if !c.is_array(part)! && !c.is_tuple(part)! {
				return false
			}
		}
		return true
	}
	if t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.is_array(part)! || c.is_tuple(part)! {
				return true
			}
		}
		return false
	}
	return c.is_array(t)! || c.is_tuple(t)!
}
