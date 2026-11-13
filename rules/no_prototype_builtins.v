module rules

import time
import treesitter { node_field, node_kind, node_start }

// Port of the `no-prototype-builtins` rule of ESLint 10.6.0, with its suggestion (it has no
// options).

const npb_messages = {
	'prototypeBuildIn':    "Do not access Object.prototype method '{{prop}}' from target object."
	'callObjectPrototype': 'Call Object.prototype.{{prop}} explicitly.'
}

fn (mut c Checker) lint_no_prototype_builtins(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['call_expression'], []) {
		args_node := node_field(node, 'arguments') or { continue }
		if node_kind(args_node) != 'arguments' {
			continue
		}
		callee := unwrap_parens(node_field(node, 'function') or { continue })
		if node_kind(callee) !in ['member_expression', 'subscript_expression'] {
			continue
		}
		stats.checked++
		name := c.es_static_property_name(callee) or { continue }
		if name !in ['hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable'] {
			continue
		}
		property := unwrap_parens(node_field(callee, if node_kind(callee) == 'subscript_expression' {
			'index'
		} else {
			'property'
		}) or { continue })
		data := {
			'prop': name
		}
		mut suggestions := []Suggestion{}
		if fixes := c.npb_fixes(root, node, callee, name) {
			_, suggestion := c.suggestion('callObjectPrototype', data, fixes)!
			suggestions << suggestion
		}
		findings << Finding{
			stmt:        c.position_at(node_start(property))
			message_id:  'prototypeBuildIn'
			data:        data
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// npb_after_optional ports isAfterOptional: an optional link in the chain of the call.
fn npb_after_optional(n C.TSNode) bool {
	mut node := n
	for is_chain_element(node) {
		if is_optional_element(node) {
			return true
		}
		node = chain_lhs(node) or { return false }
		if node_kind(node) == 'parenthesized_expression' {
			return false
		}
	}
	return false
}

// npb_fixes is the fix of the suggestion: `Object.prototype.x.call(object, …)`.
fn (mut c Checker) npb_fixes(root C.TSNode, call C.TSNode, callee C.TSNode, name string) ?[]Fix {
	if npb_after_optional(call) {
		return none
	}
	// A callee that is a ChainExpression of its own.
	raw_callee := node_field(call, 'function')?
	if estree_type(unwrap_parens(raw_callee)) == 'ChainExpression' {
		return none
	}
	tree := c.scope_tree(root)
	v := tree.find_variable(tree.get_scope(call), 'Object', -1)
	if v < 0 || tree.variables[v].scope != 0 || tree.variables[v].defs.len > 0 {
		return none
	}
	object := unwrap_parens(node_field(callee, 'object')?)
	mut object_text := c.es_text(object)
	if es_precedence(object) <= 0 {
		object_text = '(${object_text})'
	}
	tokens := c.source_tokens(root)
	mut open := tokens.after(c.es_end(raw_callee), false)?
	for c.src[open.start..open.end] != '(' {
		open = tokens.after(open.end, false)?
	}
	args := (call_arguments(call)?).filter(node_kind(it) != 'comment')
	delim := if args.len == 0 { '' } else { ', ' }
	return [
		fix_replace_range(node_start(callee), c.es_end(callee), 'Object.prototype.${name}.call'),
		fix_insert_at(open.end, object_text + delim),
	]
}
