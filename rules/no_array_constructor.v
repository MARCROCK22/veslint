module rules

import time
import treesitter { named_children, node_end, node_field, node_kind, node_start, position_of }

// Port of the `no-array-constructor` rule of typescript-eslint 8.62.0 (it has no options), with
// its fix.

const nac_messages = {
	'useLiteral': 'The array literal notation [] is preferable.'
}

fn (mut c Checker) lint_no_array_constructor(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// CallExpression (not a tagged template nor `import()`) and NewExpression.
	for node in c.nodes_of_kinds(root, ['call_expression', 'new_expression'], []) {
		is_call := node_kind(node) == 'call_expression'
		if is_call && precedence_is_import_call(node) {
			continue
		}
		args := if is_call {
			call_arguments(node) or { continue }
		} else if list := node_field(node, 'arguments') {
			named_children(list)
		} else {
			[]C.TSNode{}
		}
		callee := unwrap_parens(node_field(node, if is_call { 'function' } else { 'constructor' }) or {
			continue
		})
		checked++
		// Not one argument, the callee is the identifier `Array` and there are no type arguments.
		if args.len == 1 || node_kind(callee) != 'identifier' || c.identifier_name(callee) != 'Array' {
			continue
		}
		if _ := node_field(node, 'type_arguments') {
			continue
		}
		text := c.nac_arguments_text(node, callee)
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'useLiteral'
			has_fix:    true
			fix:        fix_replace_range(node_start(node), c.tokens.last_end(node_end(node)),
				'[${text}]')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nac_arguments_text ports getArgumentsText: the source between the first `(` after the callee
// and the last token of the call, if that one is a `)`; '' otherwise.
fn (mut c Checker) nac_arguments_text(node C.TSNode, callee C.TSNode) string {
	last := c.last_token(node) or { return '' }
	if !c.token_is(last, ')') {
		return ''
	}
	tokens := c.source_tokens(node)
	mut offset := node_end(callee)
	for {
		token := tokens.after(offset, false) or { return '' }
		if token.start == last.start {
			return ''
		}
		if c.token_is(token, '(') {
			return c.src[token.end..last.start]
		}
		offset = token.end
	}
	return ''
}
