module rules

import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `no-object-constructor` rule of ESLint 10.6.0, with its suggestion (it has no
// options).

const nobc_messages = {
	'preferLiteral':            'The object literal notation {} is preferable.'
	'useLiteral':               "Replace with '{{replacement}}'."
	'useLiteralAfterSemicolon': "Replace with '{{replacement}}', add preceding semicolon."
}

fn (mut c Checker) lint_no_object_constructor(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['call_expression', 'new_expression'], []) {
		field := if node_kind(node) == 'call_expression' { 'function' } else { 'constructor' }
		callee := unwrap_parens(node_field(node, field) or { continue })
		if node_kind(callee) != 'identifier' || c.text(callee) != 'Object' {
			continue
		}
		// `Object?.()` is a CallExpression too (in a ChainExpression); a tagged template is not.
		if node_kind(node) == 'call_expression' {
			args_node := node_field(node, 'arguments') or { continue }
			if node_kind(args_node) != 'arguments' {
				continue
			}
		}
		args := (call_arguments(node) or { []C.TSNode{} }).filter(node_kind(it) != 'comment')
		if args.len > 0 {
			continue
		}
		stats.checked++
		tree := c.scope_tree(root)
		v := tree.find_variable(tree.get_scope(node), 'Object', -1)
		if v < 0 || tree.variables[v].identifiers.len > 0 {
			continue
		}
		tokens := c.source_tokens(root)
		mut parens := is_start_of_expression_statement(node)
		if !parens {
			if before := tokens.before(node_start(node), false) {
				parens = c.src[before.start..before.end] == '=>'
			}
		}
		mut replacement := '{}'
		mut text := '{}'
		mut message_id := 'useLiteral'
		if parens {
			replacement = '({})'
			text = '({})'
			if c.eslint_needs_preceding_semicolon(node, node_start(node)) {
				text = ';({})'
				message_id = 'useLiteralAfterSemicolon'
			}
		}
		_, suggestion := c.suggestion(message_id, {
			'replacement': replacement
		}, [fix_replace_range(node_start(node), c.es_end(node), text)])!
		findings << Finding{
			stmt:        position_of(node)
			message_id:  'preferLiteral'
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
