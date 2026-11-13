module rules

import time
import treesitter { named_children, node_field, node_kind, node_start }

// Port of the `no-empty-static-block` rule of ESLint 10.6.0, with its suggestion (it has no
// options).

const nesb_messages = {
	'unexpected':     'Unexpected empty static block.'
	'suggestComment': 'Add comment inside empty static block.'
}

fn (mut c Checker) lint_no_empty_static_block(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['class_static_block'], []) {
		body := node_field(node, 'body') or { continue }
		stats.checked++
		// An empty body without comments (the comments before its closing brace).
		// The braces of the body: tree-sitter may put a comment that follows it inside it.
		open := node_start(body) + 1
		close := c.es_end(body) - 1
		if named_children(body).filter(node_kind(it) != 'comment').len > 0
			|| c.source_tokens(root).comments_inside(open, close).len > 0 {
			continue
		}
		_, suggestion := c.suggestion('suggestComment', map[string]string{}, [
			fix_replace_range(open, close, ' /* empty */ '),
		])!
		findings << Finding{
			stmt:        c.position_at(node_start(body))
			message_id:  'unexpected'
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
