module rules

import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-script-url` rule of ESLint 10.6.0 (it has no options).

const nsu_messages = {
	'unexpectedScriptURL': 'Script URL is a form of eval.'
}

fn (mut c Checker) lint_no_script_url(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['string', 'template_string'], []) {
		stats.checked++
		if node_kind(node) == 'template_string' {
			// Not the template of a TaggedTemplateExpression.
			if parent := node_parent(node) {
				if node_kind(parent) == 'call_expression' {
					if args := node_field(parent, 'arguments') {
						if node_key(args) == node_key(node) {
							continue
						}
					}
				}
			}
		}
		value := c.es_static_string_value(node) or { continue }
		if value.to_lower().starts_with('javascript:') {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpectedScriptURL'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
