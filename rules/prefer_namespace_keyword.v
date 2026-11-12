module rules

import time
import treesitter { node_field, node_kind, node_parent, node_start, position_of }

// Port of the `prefer-namespace-keyword` rule of typescript-eslint 8.62.0 (it has no options),
// with its fix.

const pnk_messages = {
	'useNamespace': "Use 'namespace' instead of 'module' to declare custom TypeScript modules."
}

fn (mut c Checker) lint_prefer_namespace_keyword(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// A TSModuleDeclaration whose id is not a Literal and whose token before the id is the
	// identifier `module`: `namespace X {}` is an internal_module, and `declare global {}` has no
	// module node (the token before `global` is `declare`).
	for node in c.nodes_of_kind(root, c'module') {
		name := node_field(node, 'name') or { continue }
		if node_kind(name) == 'string' {
			continue
		}
		checked++
		keyword := c.source_tokens(node).before(node_start(name), false) or { continue }
		if keyword.kind != .identifier || c.token_text(keyword) != 'module' {
			continue
		}
		// A declared module starts at its `declare`.
		parent := node_parent(node) or { node }
		reported := if node_kind(parent) == 'ambient_declaration' { parent } else { node }
		findings << Finding{
			stmt:       position_of(reported)
			message_id: 'useNamespace'
			has_fix:    true
			fix:        fix_replace_range(keyword.start, keyword.end, 'namespace')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
