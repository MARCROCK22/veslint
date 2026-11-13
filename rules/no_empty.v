module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-empty` rule of ESLint 10.6.0, with its option and its suggestion.

const ne_messages = {
	'unexpected':     'Empty {{type}} statement.'
	'suggestComment': 'Add comment inside empty {{type}} statement.'
}

// ne_not_block_parents are the parents of a statement_block that is not an ESTree
// BlockStatement (a StaticBlock, a TSModuleBlock) or that is the body of a function.
const ne_not_block_parents = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition', 'class_static_block',
	'module', 'internal_module', 'ambient_declaration']

// ne_allow_empty_catch reads allowEmptyCatch.
fn ne_allow_empty_catch(options []json2.Any) !bool {
	o := option_object(no_empty, options, ['allowEmptyCatch'])!
	return o.bool_value('allowEmptyCatch')!
}

fn (mut c Checker) lint_no_empty(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_empty_catch := ne_allow_empty_catch(c.rule_options(no_empty))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['statement_block', 'switch_statement'], []) {
		stats.checked++
		if node_kind(node) == 'statement_block' {
			// No statement and no comment inside.
			end := c.es_end(node)
			if named_children(node).filter(node_kind(it) != 'comment').len > 0
				|| c.source_tokens(root).comments_inside(node_start(node), end).len > 0 {
				continue
			}
			parent := node_parent(node) or { continue }
			if node_kind(parent) in ne_not_block_parents {
				continue
			}
			if allow_empty_catch && node_kind(parent) == 'catch_clause' {
				continue
			}
			data := {
				'type': 'block'
			}
			_, suggestion := c.suggestion('suggestComment', data, [
				fix_replace_range(node_start(node) + 1, end - 1, ' /* empty */ '),
			])!
			findings << Finding{
				stmt:        position_of(node)
				message_id:  'unexpected'
				data:        data
				suggestions: [suggestion]
			}
			continue
		}
		// A switch without cases nor comments between its braces.
		body := node_field(node, 'body') or { continue }
		body_end := c.es_end(body)
		if named_children(body).filter(node_kind(it) != 'comment').len > 0
			|| c.source_tokens(root).comments_inside(node_start(body), body_end).len > 0 {
			continue
		}
		data := {
			'type': 'switch'
		}
		_, suggestion := c.suggestion('suggestComment', data, [
			fix_replace_range(node_start(body) + 1, body_end - 1, ' /* empty */ '),
		])!
		findings << Finding{
			stmt:        c.position_at(node_start(body))
			message_id:  'unexpected'
			data:        data
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
